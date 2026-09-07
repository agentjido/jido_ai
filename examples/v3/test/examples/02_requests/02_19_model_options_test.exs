defmodule JidoAI.Examples.ModelOptionsTest do
  use JidoAI.Examples.Case
  alias Jido.AI.Request
  alias JidoAI.Examples.RequestScope.Agent

  for api <- [:native, :standalone], streaming? <- [true, false] do
    @tag history_case: "HIST-01/runtime-routing"
    test "#{api} selects provider, options and events per call with streaming #{streaming?}", %{jido: jido} do
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

      assert_receive {:provider_tool, 1}
      assert_receive {:provider_tool, 2}
      for iteration <- 1..3, do: assert_receive({:provider_transform, ^iteration, _})
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
    assert {:ok, %{live: nil}} = Jido.AI.Session.snapshot(server)
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

  setup do
    old = Application.fetch_env(:jido_ai, :model_aliases)

    Application.put_env(:jido_ai, :model_aliases, %{
      example: MockLLM.model(),
      selected: MockLLM.model("gpt-4o")
    })

    on_exit(fn ->
      case old do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)
  end

  test "public request model forms change the wire request and leave the next default intact", %{
    jido: jido
  } do
    forms = [
      :selected,
      "openai:gpt-4o",
      {:openai, "gpt-4o", []},
      {:openai, id: "gpt-4o"},
      %{provider: :openai, id: "gpt-4o"},
      MockLLM.model("gpt-4o")
    ]

    {mock, context} = mock(List.duplicate(%{reply: {:text, "Done"}}, length(forms) + 1))
    server = start_agent(jido, Agent.new!())
    definition = Server.agent(server).plugins

    for model <- forms do
      assert {:ok, request} =
               Agent.ask(server, "Select", context: context, model: model, stream_to: self())

      assert {:ok, "Done"} = Request.await(request)
      events = request |> Request.Stream.events(stream_event_timeout_ms: 2_000) |> Enum.to_list()
      assert Enum.find(events, &(&1.kind == :llm_started)).data.model == "openai:gpt-4o"
    end

    assert {:ok, "Done"} = Agent.ask_sync(server, "Default", context: context)
    requests = MockLLM.report(mock).requests

    assert Enum.map(requests, & &1.body["model"]) ==
             List.duplicate("gpt-4o", length(forms)) ++ ["gpt-4o-mini"]

    assert Enum.any?(requests, &(&1.path == "/v1/responses"))
    assert Enum.any?(requests, &(&1.path == "/v1/chat/completions"))
    assert Server.agent(server).plugins == definition
    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    assert_script_done(mock)
  end

  test "known string model options reach the provider and do not replace the next defaults", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:text, "Custom"}}, %{reply: {:text, "Default"}}])

    context =
      update_in(
        context.ai.assistant.options,
        &Keyword.merge(&1, temperature: 0.7, max_tokens: 91)
      )

    server = start_agent(jido, Agent.new!())

    assert {:ok, "Custom"} =
             Agent.ask_sync(server, "Custom",
               context: context,
               llm_opts: %{
                 "temperature" => 0.3,
                 "max_tokens" => 53,
                 "provider_options" => %{"response_format" => %{type: "json_object"}}
               }
             )

    assert {:ok, "Default"} = Agent.ask_sync(server, "Default", context: context)
    [custom, default] = MockLLM.report(mock).requests
    assert custom.body["temperature"] == 0.3
    assert (custom.body["max_tokens"] || custom.body["max_completion_tokens"]) == 53
    assert custom.body["response_format"] == %{"type" => "json_object"}
    assert default.body["temperature"] == 0.7
    assert (default.body["max_tokens"] || default.body["max_completion_tokens"]) == 91
    assert_script_done(mock)
  end

  test "invalid option containers reject before admission and preserve the error event", %{
    jido: jido
  } do
    {mock, context} = mock([])
    server = start_agent(jido, Agent.new!())
    before = Server.snapshot(server)

    for {key, value} <- [
          llm_opts: :invalid,
          llm_opts: self(),
          req_http_options: :invalid,
          req_http_options: %{}
        ] do
      id = Jido.Signal.ID.generate!()
      opts = [{key, value}, context: context, request_id: id, stream_to: self()]
      assert {:error, error} = Agent.ask(server, "Invalid", opts)

      assert_receive {:jido_ai_request_event, %{request_id: ^id, method: :react, data: %{error: ^error}}}

      refute_receive {:jido_ai_request_event, %{request_id: ^id}}, 20
      assert Server.snapshot(server) == before
    end

    assert_script_done(mock)
  end

  test "a request model wins over declared routing and invalid models retain admission identity",
       %{
         jido: jido
       } do
    {mock, context} = mock([%{reply: {:text, "Selected"}}, %{reply: {:text, "Routed"}}])

    definition =
      JidoAI.Examples.PluginStack.definition(
        reasoning: :chain_of_thought,
        plugins: [{Jido.AI.Plugins.ModelRouting, [routes: %{"ai.cot.query" => :example}]}]
      )

    server = start_agent(jido, definition)
    opts = [signal_type: "ai.cot.query", source: "/examples/model_options", context: context]
    assert {:ok, first} = Request.create_and_send(server, "Select", [model: :selected] ++ opts)
    assert {:ok, "Selected"} = Request.await(first)
    assert {:ok, second} = Request.create_and_send(server, "Route", opts)
    assert {:ok, "Routed"} = Request.await(second)

    assert Enum.map(MockLLM.report(mock).requests, & &1.body["model"]) == [
             "gpt-4o",
             "gpt-4o-mini"
           ]

    before = Server.agent(server)

    for model <- [:missing_model_alias_for_example, false, self(), [:invalid]] do
      id = Jido.Signal.ID.generate!()

      assert {:error, error} =
               Request.create_and_send(
                 server,
                 "Invalid",
                 [model: model, request_id: id, stream_to: self()] ++ opts
               )

      assert_receive {:jido_ai_request_event, %{request_id: ^id, method: :chain_of_thought, data: %{error: ^error}}}

      assert Server.agent(server) == before
    end

    assert_script_done(mock)
  end

  test "native custom routes use the same request model binding", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Reviewed"}}])
    context = put_in(context.ai, %{review: %{options: MockLLM.options(mock)}})
    server = start_agent(jido, JidoAI.Examples.Admission.Agent.new!())

    assert {:ok, request} =
             Request.create_and_send(server, "Review",
               signal_type: "case.review",
               source: "/examples/model_options",
               context: context,
               model: :selected
             )

    assert {:ok, "Reviewed"} = Request.await(request)
    assert [wire] = MockLLM.report(mock).requests
    assert wire.body["model"] == "gpt-4o"
    assert Server.agent(server).state.requests[request.id].method == :chain_of_thought
    assert_script_done(mock)
  end

  test "HTTP options retain live callbacks outside portable request records", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Callback"}}])
    observer = self()

    callback = fn request ->
      send(observer, {:http_options_seen, request.url.host})
      Req.Request.put_header(request, "x-request-case", "scoped")
    end

    http = [
      retry: false,
      adapter: JidoAI.Examples.ModelOptions.HttpAdapter,
      finch_private: [example_callback: callback]
    ]

    server = start_agent(jido, Agent.new!())

    assert {:ok, request} =
             Agent.ask(server, "Callback", context: context, req_http_options: http)

    assert {:ok, "Callback"} = Request.await(request)
    assert_receive {:http_options_seen, "127.0.0.1"}
    assert [wire] = MockLLM.report(mock).requests
    assert wire.headers["x-request-case"] == "scoped"
    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    assert_script_done(mock)
  end

  test "streamed model overrides retain selected model labels and actual headers", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, ["Scoped ", "stream"]}}])
    module = JidoAI.Examples.PublicAgent.StreamAgent
    server = start_agent(jido, module.new!())

    assert {:ok, %{request: request, events: events}} =
             module.ask_stream(server, "Stream",
               context: context,
               model: :selected,
               llm_opts: %{"temperature" => 0.4},
               req_http_options: [retry: false, headers: [{"x-stream-case", "scoped"}]]
             )

    assert {:ok, "Scoped stream"} = Request.await(request)
    events = Enum.to_list(events)
    assert Enum.find(events, &(&1.kind == :llm_started)).data.model == "openai:gpt-4o"
    deltas = Enum.filter(events, &(&1.kind == :llm_delta))
    assert deltas != []
    assert Enum.all?(deltas, &(&1.data.model == "openai:gpt-4o"))
    assert [wire] = MockLLM.report(mock).requests
    assert wire.path == "/v1/chat/completions"
    assert wire.body["stream"] == true
    assert wire.body["temperature"] == 0.4
    assert wire.headers["x-stream-case"] == "scoped"
    assert_script_done(mock)
  end

  test "a model override can execute a real tool round through buffered Responses", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:tools, [%{id: "echo", name: "scope_echo", arguments: %{value: 7}}]}},
        %{reply: {:text, "Seven"}}
      ])

    module = JidoAI.Examples.RequestScope.TwoTurns
    server = start_agent(jido, module.new!())
    assert {:ok, request} = module.ask(server, "Echo", context: context, model: "openai:gpt-4o")
    assert {:ok, "Seven"} = Request.await(request)
    assert [first, second] = MockLLM.report(mock).requests
    assert first.path == "/v1/responses" and second.path == "/v1/responses"
    output = Enum.find(second.body["input"], &(&1["type"] == "function_call_output"))
    assert output["call_id"] == "echo"
    assert Jason.decode!(output["output"]) == %{"ok" => true, "result" => %{"value" => 7}}
    meta = Server.agent(server).state.requests[request.id].meta
    assert meta.model_calls == 2 and meta.tool_calls == 1 and meta.usage.total_tokens == 30
    assert_script_done(mock)
  end

  test "a model override validates a typed object through buffered Responses", %{jido: jido} do
    {mock, context} = mock([%{reply: {:object, %{answer: "Typed"}}}])
    module = JidoAI.Examples.PublicAgent.ObjectAgent
    server = start_agent(jido, module.new!())
    assert {:ok, request} = module.ask(server, "Object", context: context, model: "openai:gpt-4o")
    assert {:ok, %{answer: "Typed"}} = Request.await(request)
    assert [wire] = MockLLM.report(mock).requests
    assert wire.path == "/v1/responses"
    assert %{"name" => name, "type" => "function"} = wire.body["tool_choice"]
    tool = Enum.find(wire.body["tools"], &(&1["name"] == name))
    assert tool["parameters"]["properties"]["answer"]["type"] == "string"
    assert Server.agent(server).state.requests[request.id].meta.usage.total_tokens == 15
    assert_script_done(mock)
  end

  test "empty overrides retain declared models and options", %{jido: jido} do
    {mock, context} = mock(List.duplicate(%{reply: {:text, "Default"}}, 3))
    context = update_in(context.ai.assistant.options, &Keyword.put(&1, :temperature, 0.6))
    server = start_agent(jido, Agent.new!())

    for opts <- [
          [model: nil, llm_opts: nil, req_http_options: nil],
          [model: "", llm_opts: %{}],
          [llm_opts: []]
        ] do
      assert {:ok, "Default"} = Agent.ask_sync(server, "Default", [context: context] ++ opts)
    end

    assert Enum.all?(
             MockLLM.report(mock).requests,
             &(&1.body["model"] == "gpt-4o-mini" and &1.body["temperature"] == 0.6)
           )

    assert_script_done(mock)
  end
end
