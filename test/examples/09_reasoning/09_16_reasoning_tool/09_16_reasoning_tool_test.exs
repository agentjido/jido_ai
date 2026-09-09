defmodule JidoAI.Examples.ReasoningToolTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Request, ToolAdapter}
  alias Jido.AI.Actions.Reasoning.RunStrategy
  alias JidoAI.Examples.ReasoningTool, as: Example

  setup do
    old = Application.fetch_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{fast: MockLLM.model()})

    on_exit(fn ->
      case old do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)

    :ok
  end

  test "a raw reasoning Action is exported and called as a model tool", %{jido: jido} do
    {mock, context} =
      mock([Example.call(), %{reply: {:text, "Conclusion: Four"}}, %{reply: {:text, "Reviewed"}}])

    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)
    context = Map.merge(context, %{default_model: MockLLM.model(), jido: jido})
    assert {:ok, request} = submit(server, context)
    assert {:ok, "Reviewed"} = Request.await(request)
    [outer, inner, final] = MockLLM.report(mock).requests
    tool = hd(outer.body["tools"])["function"]
    assert tool["name"] == "reason"

    assert tool["parameters"]["properties"]["request_policy"] == %{
             "type" => "string",
             "description" => "Request policy"
           }

    refute "request_policy" in tool["parameters"]["required"]
    assert tool["parameters"]["properties"]["options"]["type"] == "object"
    assert List.last(inner.body["messages"])["content"] == "Explain this answer"
    result = final.body["messages"] |> Enum.find(&(&1["role"] == "tool"))
    assert result["tool_call_id"] == "reason-1"
    assert result["content"] =~ "Four"
    assert Server.agent(server).state.case_id == "case-16"
    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    assert_script_done(mock)
  end

  test "unknown atom labels fail preflight without allocating atoms", %{jido: jido} do
    unknown = "untrusted_reason_policy_#{System.unique_integer([:positive])}"
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
    {mock, context} = mock([Example.call(%{request_policy: unknown})])
    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)
    assert {:ok, request} = submit(server, context)
    assert {:error, _} = Request.await(request)
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
    assert length(MockLLM.report(mock).requests) == 1
    assert Server.agent(server).state.reply == nil
    assert_script_done(mock)
  end

  test "JSON export leaves the public atom schema and direct validation unchanged" do
    original = RunStrategy.schema()
    tool = ToolAdapter.from_action(RunStrategy)
    assert tool.parameter_schema["properties"]["request_policy"]["type"] == "string"
    assert RunStrategy.schema() == original

    for policy <- [:reject, :cancel, :unsupported_public_atom] do
      assert {:ok, %{request_policy: ^policy}} =
               RunStrategy.validate_params(%{
                 strategy: :cot,
                 prompt: "Explain",
                 request_policy: policy
               })
    end

    assert {:error, _} =
             RunStrategy.validate_params(%{
               strategy: :cot,
               prompt: "Explain",
               request_policy: "reject"
             })
  end

  test "all seven callable methods run as raw tools and retain their result envelopes", %{
    jido: jido
  } do
    methods = [
      {"cot", :cot, %{}},
      {"cod", :cod, %{}},
      {"aot", :aot, %{profile: "short"}},
      {"tot", :tot, %{branching_factor: 2, max_depth: 1}},
      {"got", :got, %{}},
      {"trm", :trm, %{max_supervision_steps: 1}},
      {"adaptive", :cot, %{available_strategies: ["cot"]}}
    ]

    script =
      Enum.flat_map(methods, fn {strategy, method, opts} ->
        [Example.call(Map.merge(%{strategy: strategy}, opts))] ++
          JidoAI.Examples.Adaptive.script(method) ++ [%{reply: {:text, "Reviewed"}}]
      end)

    {mock, context} = mock(script)
    context = Map.merge(context, %{default_model: MockLLM.model(), jido: jido})

    for {strategy, _method, _opts} <- methods do
      server = start_agent(jido, Example.Agent.new!())
      assert {:ok, request} = submit(server, context)
      assert {:ok, "Reviewed"} = Request.await(request)
      [tool] = Server.agent(server).state.requests[request.id].meta.tool_results
      assert {:ok, result, []} = tool.result
      assert Atom.to_string(result.strategy) == strategy
      assert result.status == :success and result.usage.total_tokens > 0
      assert result.output != nil
      assert runner_pids(jido) == []
    end

    assert length(MockLLM.report(mock).requests) == length(script)
    assert_script_done(mock)
  end

  test "native data Builder and source JSON retain the raw Action and live behavior", %{
    jido: jido
  } do
    assert {:ok, definition} = Example.definition()
    assert definition == Example.Agent.definition()
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
             Jido.AI.Authoring.Codec.decode(
               Example.base(),
               Jason.decode!(Jason.encode!(document)),
               registry
             )

    assert decoded == built and built == definition

    script = [
      Example.call(),
      %{reply: {:text, "Conclusion: Four"}},
      %{reply: {:text, "Reviewed"}}
    ]

    {mock, context} = mock(List.flatten(List.duplicate(script, 4)))
    context = Map.merge(context, %{default_model: MockLLM.model(), jido: jido})

    for value <- [Example.Agent.definition(), definition, built, decoded] do
      server = start_agent(jido, value)
      assert {:ok, request} = submit(server, context)
      assert {:ok, "Reviewed"} = Request.await(request)
      assert Server.agent(server).plugins == value.plugins
    end

    assert_script_done(mock)
  end

  test "the public Agent macro can use the same raw reasoning Action", %{jido: jido} do
    call = %{
      reply:
        {:tools,
         [
           %{
             id: "public",
             name: "reasoning_run_strategy",
             arguments: %{strategy: "cot", prompt: "Explain", request_policy: "reject"}
           }
         ]}
    }

    {mock, context} =
      mock([call, %{reply: {:text, "Conclusion: Four"}}, %{reply: {:text, "Reviewed"}}])

    server = start_agent(jido, Example.PublicAgent.new!())

    assert {:ok, request} =
             Example.PublicAgent.ask(server, "Review", context: Map.put(context, :jido, jido))

    assert {:ok, "Reviewed"} = Request.await(request)
    assert Server.agent(server).state.last_answer == "Reviewed"
    assert_script_done(mock)
  end

  test "nested raw reasoning calls use the outer quota and cannot bypass its limit", %{jido: jido} do
    alias Jido.AI.Quota.Store
    start_supervised!({Store, []})

    {mock, context} =
      mock([
        Example.call(),
        %{reply: {:text, "Conclusion: Four"}},
        %{reply: {:text, "Reviewed"}},
        Example.call()
      ])

    context = Map.merge(context, %{default_model: MockLLM.model(), jido: jido})

    for {scope, max, expected} <- [{"raw_allowed", 3, :success}, {"raw_denied", 1, :failure}] do
      base =
        Map.put(Example.base(), :plugins, [
          {Jido.AI.Plugins.Quota, [scope: scope, max_requests: max, into: :reply]}
        ])

      assert {:ok, definition} = Jido.AI.Authoring.lower(base, [Example.source()])
      server = start_agent(jido, definition)
      assert {:ok, request} = submit(server, context)

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

  test "cancelling the outer request stops a held nested provider and its private Agent", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        Example.call(),
        %{reply: {:wait, :nested, {:text, "Conclusion: Late"}}},
        %{reply: {:text, "Next"}}
      ])

    server = start_agent(jido, Example.Agent.new!())
    context = Map.merge(context, %{default_model: MockLLM.model(), jido: jido})
    assert {:ok, request} = submit(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :nested, provider}, 2_000
    assert [runner] = runner_pids(jido)
    pm = Process.monitor(provider)
    rm = Process.monitor(runner)
    assert :ok = Jido.AI.Session.cancel(request)
    assert {:error, :cancelled} = Request.await(request)
    assert_receive {:DOWN, ^pm, :process, ^provider, _}, 2_000
    assert_receive {:DOWN, ^rm, :process, ^runner, _}, 2_000
    assert {:ok, next} = submit(server, context)
    assert {:ok, "Next"} = Request.await(next)
    assert runner_pids(jido) == []
    assert_script_done(mock)
  end

  test "nested defaults and atom labels preserve open data and the original schema", %{jido: jido} do
    args = %{
      items: [%{label: "cancel", note: "Known label"}],
      extras: %{label: "reject", other: "Preserved"}
    }

    {mock, context} =
      mock([
        %{reply: {:tools, [%{id: "labels", name: "labels", arguments: args}]}},
        %{reply: {:text, "Reviewed"}}
      ])

    original = Example.Labels.schema()

    assert {:ok, definition} =
             Example.definition(%{
               tools: [%{name: "labels", target: Example.Labels, forward_context: [:observer]}]
             })

    server = start_agent(jido, definition)
    assert {:ok, request} = submit(server, context)
    assert {:ok, "Reviewed"} = Request.await(request)

    assert_receive {:labels_received,
                    %{
                      policy: :reject,
                      items: [%{label: :cancel}],
                      extras: %{"other" => "Preserved", label: :reject}
                    }}

    [wire, _] = MockLLM.report(mock).requests
    props = hd(wire.body["tools"])["function"]["parameters"]["properties"]
    assert props["policy"]["default"] == "reject"
    assert props["items"]["items"]["properties"]["label"]["type"] == "string"
    assert props["extras"]["additionalProperties"] == true
    strict = ToolAdapter.from_action(Example.Labels, strict: true)
    assert strict.parameter_schema["properties"]["extras"]["additionalProperties"] == false
    assert Example.Labels.schema() == original
    assert_script_done(mock)
  end

  test "a nested provider failure reaches the outer model as a canonical tool error", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        Example.call(),
        %{reply: {:error, 503, "Private nested provider detail"}},
        %{reply: {:text, "Reasoning was unavailable"}}
      ])

    server = start_agent(jido, Example.Agent.new!())
    context = Map.merge(context, %{default_model: MockLLM.model(), jido: jido})
    assert {:ok, request} = submit(server, context)
    assert {:ok, "Reasoning was unavailable"} = Request.await(request)
    [tool] = Server.agent(server).state.requests[request.id].meta.tool_results
    assert tool.status == :error
    assert {:error, error, []} = tool.result
    assert error.details.reason.strategy == :cot
    assert error.details.reason.status == :failure
    [_, _, wire] = MockLLM.report(mock).requests
    message = Enum.find(wire.body["messages"], &(&1["role"] == "tool"))
    payload = Jason.decode!(message["content"])
    assert payload["ok"] == false
    assert payload["error"]["details"]["tool_call_id"] == "reason-1"
    refute message["content"] =~ "Private nested provider detail"
    assert runner_pids(jido) == []
    assert_script_done(mock)
  end

  defp runner_pids(jido) do
    Jido.list_agents(jido)
    |> Enum.flat_map(fn {_id, pid} ->
      case Server.agent(pid).name do
        "jido_ai_internal_reasoning_runner" -> [pid]
        _ -> []
      end
    end)
  end

  defp atoms(value) when is_atom(value), do: [value]
  defp atoms(value) when is_list(value), do: Enum.flat_map(value, &atoms/1)
  defp atoms(value) when is_tuple(value), do: value |> Tuple.to_list() |> atoms()
  defp atoms(%_{}), do: []

  defp atoms(value) when is_map(value),
    do: Enum.flat_map(value, fn {k, v} -> atoms(k) ++ atoms(v) end)

  defp atoms(_), do: []

  defp submit(server, context),
    do:
      Request.create_and_send(server, "Review",
        signal_type: "case.review",
        source: "/examples/reasoning-tool",
        context: context
      )
end
