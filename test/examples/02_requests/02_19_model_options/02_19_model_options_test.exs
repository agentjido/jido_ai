defmodule JidoAI.Examples.ModelOptionsTest do
  use JidoAI.Examples.Case
  alias Jido.AI.Request

  for api <- [:native, :standalone], streaming? <- [true, false] do
    test "#{api} selects provider, options and events per call with streaming #{streaming?}", %{
      jido: jido
    } do
      {mock, context} =
        mock([
          %{reply: {:tools, [%{id: "base_one", name: "switch_probe", arguments: %{n: 1}}]}},
          %{reply: {:anthropic, {:tools, [%{id: "selected_two", name: "switch_probe", arguments: %{n: 2}}]}}},
          %{reply: {:text, "Done"}}
        ])

      base = provider_options(MockLLM.options(mock), "base")

      selected =
        MockLLM.options(mock, :anthropic)
        |> provider_options("selected")
        |> Keyword.put(:thinking, %{type: "enabled", budget_tokens: 1024})

      context = context |> put_in([:ai, :assistant, :options], base) |> Map.put(:anthropic_options, selected)
      {events, usage} = run_provider_switch(unquote(api), unquote(streaming?), jido, context, base)
      assert usage.total_tokens == 45
      labels = ["openai:gpt-4o-mini", "anthropic:claude-sonnet-4-5", "openai:gpt-4o-mini"]

      for kind <- [:llm_started, :llm_completed] do
        assert Enum.map(Enum.filter(events, &(&1.kind == kind)), & &1.data.model) == labels
      end

      assert Enum.count(events, &(&1.kind == :tool_completed)) == 2
      deltas = Enum.filter(events, &(&1.kind == :llm_delta))

      if unquote(streaming?),
        do: assert(MapSet.new(Enum.map(deltas, & &1.data.model)) == MapSet.new(labels)),
        else: assert(deltas == [])

      [first, middle, last] = MockLLM.report(mock).requests

      assert Enum.map([first, middle, last], & &1.path) == [
               "/v1/chat/completions",
               "/v1/messages",
               "/v1/chat/completions"
             ]

      assert Enum.map([first, middle, last], & &1.headers["x-provider-case"]) == ["base", "selected", "base"]
      assert middle.headers["x-api-key"] == "local-example-key"
      assert middle.body["thinking"] == %{"type" => "enabled", "budget_tokens" => 1024}
      assert middle.body["model"] == "claude-sonnet-4-5-20250929"
      for request <- [first, middle, last], do: assert(request.body["stream"] == unquote(streaming?))
      for request <- [first, last], do: refute(Map.has_key?(request.body, "thinking"))

      middle_results =
        for %{"content" => content} <- middle.body["messages"],
            is_list(content),
            entry <- content,
            entry["type"] == "tool_result",
            do: entry

      assert [%{"tool_use_id" => "base_one", "content" => first_result}] = middle_results
      assert Jason.decode!(first_result) == %{"ok" => true, "result" => %{"n" => 1}}
      tool_messages = Enum.filter(last.body["messages"], &(&1["role"] == "tool"))
      assert Enum.map(tool_messages, & &1["tool_call_id"]) == ["base_one", "selected_two"]

      assert Enum.map(tool_messages, &Jason.decode!(&1["content"])) == [
               %{"ok" => true, "result" => %{"n" => 1}},
               %{"ok" => true, "result" => %{"n" => 2}}
             ]

      assert_script_done(mock)
    end
  end

  defp provider_options(options, marker),
    do: Keyword.update!(options, :req_http_options, &Keyword.put(&1, :headers, [{"x-provider-case", marker}]))

  defp run_provider_switch(:native, streaming?, jido, context, _base) do
    module =
      if streaming?,
        do: JidoAI.Examples.ModelOptions.StreamSwitchAgent,
        else: JidoAI.Examples.ModelOptions.BufferedSwitchAgent

    server = start_agent(jido, module.new!())

    assert {:ok, request} =
             Request.create_and_send(server, "Work",
               signal_type: "ai.ask",
               source: "/examples/provider_switch",
               context: context,
               stream_to: self()
             )

    assert {:ok, "Done"} = Request.await(request)
    events = request |> Request.Stream.events(stream_event_timeout_ms: 2_000) |> Enum.to_list()
    record = Server.agent(server).state.requests[request.id]
    assert record.meta.model_calls == 3
    assert {:ok, %{live: nil}} = Jido.AI.Orchestration.snapshot(server)
    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    {events, record.meta.usage}
  end

  defp run_provider_switch(:standalone, streaming?, jido, context, base) do
    alias Jido.AI.Reasoning.ReAct

    config =
      ReAct.Config.new(%{
        model: MockLLM.model(),
        tools: [JidoAI.Examples.ModelOptions.SwitchProbe],
        streaming: streaming?,
        llm_opts: base,
        request_transformer: JidoAI.Examples.ModelOptions.Switch,
        token_secret: "provider-switch-test"
      })

    result = ReAct.run("Work", config, context: Map.put(context, :jido, jido))
    assert result.result == "Done"
    assert {:ok, saved, _} = ReAct.Token.decode_state(result.final_token, config)
    assert saved.checkpoint.runtime.model_calls == 3
    assert :ok = Jido.Action.validate_static_data(saved.checkpoint)
    {result.trace, result.usage}
  end
end
