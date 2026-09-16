defmodule JidoAI.Examples.ReasoningToolTest do
  use JidoAI.Examples.Case
  alias Jido.AI.Request
  alias JidoAI.Examples.ReasoningTool, as: Example

  test "Builder and source JSON retain the raw tool and live behavior", %{jido: jido} do
    definition = Example.Agent.definition()
    attrs = definition |> Map.from_struct() |> Map.drop([:id, :state])
    assert {:ok, built} = attrs |> Jido.Agent.Builder.new() |> Jido.Agent.Builder.build()
    source = Example.source()

    registry =
      source
      |> Map.put(:routes, [])
      |> atoms()
      |> Kernel.++(profile_atoms(source))
      |> Enum.uniq()
      |> Map.new(&{"atoms/#{&1}", {:atom, &1}})
      |> Map.put("models/answer", {:value, source.models.answer.model})

    assert {:ok, document} = Jido.AI.Authoring.Codec.encode([source], registry)

    assert {:ok, decoded} =
             Jido.AI.Authoring.Codec.decode(Example.base(), Jason.decode!(Jason.encode!(document)), registry)

    assert decoded == built and built == definition
    script = [call(), %{reply: {:text, "Conclusion: Four"}}, %{reply: {:text, "Reviewed"}}]
    {mock, context} = mock(script ++ script)

    for value <- [built, decoded] do
      server = start_agent(jido, value)
      assert {:ok, request} = submit(server, bind(context, jido))
      assert {:ok, "Reviewed"} = Request.await(request)
    end

    assert_script_done(mock)
  end

  test "raw nested reasoning uses the outer quota", %{jido: jido} do
    alias Jido.AI.Quota.Store
    start_supervised!({Store, []})
    {mock, context} = mock([call(), %{reply: {:text, "Conclusion: Four"}}, %{reply: {:text, "Reviewed"}}, call()])

    for {scope, max, expected} <- [{"raw_allowed", 3, :success}, {"raw_denied", 1, :failure}] do
      base =
        Map.put(Example.base(), :plugins, [
          {Jido.AI.Plugins.Quota, [scope: scope, max_requests: max, into: :reply]}
        ])

      assert {:ok, definition} = Jido.AI.Authoring.lower(base, [Example.source()])
      server = start_agent(jido, definition)
      assert {:ok, request} = submit(server, bind(context, jido))

      if expected == :success do
        assert {:ok, "Reviewed"} = Request.await(request)
        assert %{requests: 3, total_tokens: 45} = Store.get(scope)
      else
        assert {:error, _} = Request.await(request)
        assert %{requests: 1, total_tokens: 15} = Store.get(scope)
        assert Server.agent(server).state.reply == nil
      end

      assert runner_pids(jido) == []
    end

    assert_script_done(mock)
  end

  test "the model submits only a prompt and receives the host-selected reasoning result", %{jido: jido} do
    {mock, context} = mock([call(), %{reply: {:text, "Conclusion: Four"}}, %{reply: {:text, "Reviewed"}}])
    server = start_agent(jido, Example.Agent.new!())
    assert {:ok, request} = submit(server, bind(context, jido))
    assert {:ok, "Reviewed"} = Request.await(request)
    [outer, inner, final] = MockLLM.report(mock).requests
    tool = hd(outer.body["tools"])["function"]
    assert tool["name"] == "reason"
    assert Map.keys(tool["parameters"]["properties"]) == ["prompt"]
    assert tool["parameters"]["required"] == ["prompt"]
    assert List.last(inner.body["messages"])["content"] == "Explain this answer"
    result = Enum.find(final.body["messages"], &(&1["role"] == "tool"))
    assert result["tool_call_id"] == "reason-1" and result["content"] =~ "Four"
    assert Server.agent(server).state.case_id == "case-16"
    assert runner_pids(jido) == []
    assert_script_done(mock)
  end

  test "the model cannot change host policy through tool input", %{jido: jido} do
    {mock, context} = mock([call(%{strategy: "cot"})])
    server = start_agent(jido, Example.Agent.new!())
    assert {:ok, request} = submit(server, bind(context, jido))
    assert {:error, _} = Request.await(request)
    assert Server.agent(server).state.reply == nil
    assert_script_done(mock)
  end

  test "cancellation stops nested work and the outer Agent can accept another request", %{jido: jido} do
    {mock, context} = mock([call(), %{reply: {:wait, :nested, {:text, "Conclusion: Late"}}}, %{reply: {:text, "Next"}}])
    server = start_agent(jido, Example.Agent.new!())
    context = bind(context, jido)
    assert {:ok, request} = submit(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :nested, provider}, 2_000
    assert [runner] = runner_pids(jido)
    refs = for pid <- [provider, runner], do: {Process.monitor(pid), pid}
    assert :ok = Jido.AI.Orchestration.cancel(request)
    assert {:error, :cancelled} = Request.await(request)
    for {ref, pid} <- refs, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 2_000)
    assert {:ok, next} = submit(server, context)
    assert {:ok, "Next"} = Request.await(next)
    assert runner_pids(jido) == []
    assert_script_done(mock)
  end

  test "provider failure reaches the outer model as a tool error", %{jido: jido} do
    {mock, context} =
      mock([call(), %{reply: {:error, 503, "Private provider detail"}}, %{reply: {:text, "Unavailable"}}])

    server = start_agent(jido, Example.Agent.new!())
    assert {:ok, request} = submit(server, bind(context, jido))
    assert {:ok, "Unavailable"} = Request.await(request)
    [_, _, wire] = MockLLM.report(mock).requests
    message = Enum.find(wire.body["messages"], &(&1["role"] == "tool"))
    assert Jason.decode!(message["content"])["ok"] == false
    refute message["content"] =~ "Private provider detail"
    assert runner_pids(jido) == []
    assert_script_done(mock)
  end

  defp call(extra \\ %{}),
    do: %{
      reply:
        {:tools, [%{id: "reason-1", name: "reason", arguments: Map.merge(%{prompt: "Explain this answer"}, extra)}]}
    }

  defp bind(context, jido) do
    profile =
      Jido.AI.Profile.new!(%{
        id: :review,
        model: MockLLM.model(),
        reasoning: :chain_of_thought,
        controls: %{timeout: 5_000},
        result: %{into: :answer}
      })

    Map.merge(context, %{
      jido: jido,
      jido_ai_callable_profile: profile,
      ai: Map.put(context.ai, :review, %{options: context.model_options})
    })
  end

  defp runner_pids(jido) do
    for {_id, pid} <- Jido.list_agents(jido), Server.agent(pid).name == "jido_ai_internal_reasoning_runner", do: pid
  end

  defp atoms(value) when is_atom(value), do: [value]
  defp atoms(value) when is_list(value), do: Enum.flat_map(value, &atoms/1)
  defp atoms(value) when is_tuple(value), do: value |> Tuple.to_list() |> atoms()
  defp atoms(%_{}), do: []
  defp atoms(value) when is_map(value), do: Enum.flat_map(value, fn {k, v} -> atoms(k) ++ atoms(v) end)
  defp atoms(_), do: []

  defp submit(server, context),
    do:
      Request.create_and_send(server, "Review",
        signal_type: "case.review",
        source: "/examples/reasoning-tool",
        context: context
      )
end
