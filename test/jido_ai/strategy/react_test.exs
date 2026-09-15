defmodule Jido.AI.Reasoning.ReAct.StrategyTest do
  use Jido.AI.Test.ReasoningCase, async: false

  alias Jido.AI.Reasoning.ReAct
  alias Jido.AI.Reasoning.ReAct.{Config, Token}
  alias Jido.AI.Usage
  alias Jido.AI.Profile
  alias Jido.Thread
  alias Jido.AI.Thread.Control, as: ContextOps
  alias ReqLLM.Message.ContentPart

  defmodule TestCalculator do
    use Jido.Action,
      name: "calculator",
      description: "A simple calculator",
      schema: Zoi.object(%{operation: Zoi.string(), a: Zoi.number(), b: Zoi.number()})

    def run(%{operation: operation, a: a, b: b}, context) do
      if context[:hold_tool] do
        send(context.observer, {:calculator_held, self()})

        receive do
          :release -> :ok
        end
      end

      if context[:observe_context] do
        send(
          context.observer,
          {:calculator_context, Map.take(context, [:state, :agent_state, :agent_module, :agent_id, :tenant, :region])}
        )
      end

      case operation do
        "add" -> {:ok, %{result: a + b}}
        "multiply" -> {:ok, %{result: a * b}}
      end
    end
  end

  defmodule TestSearch do
    use Jido.Action,
      name: "search",
      description: "Search for information",
      schema: Zoi.object(%{query: Zoi.string()})

    def run(%{query: "timeout"}, _ctx), do: {:error, %{type: :timeout, message: "search timed out"}}
    def run(%{query: query}, _ctx), do: {:ok, %{results: ["Found: #{query}"]}}
  end

  defmodule PreparedRequest do
    @behaviour Jido.AI.Control

    def check(request, context) do
      send(context.observer, {:prepared_request, request, context.jido_ai_profiles.assistant})
      if context[:capture_only], do: {:error, :configuration_observed}, else: :ok
    end
  end

  defmodule NativeTransform do
    def transform_request(request, state, config, context) do
      send(context.observer, {:native_transform, request, state.iteration, config})
      {:ok, %{llm_opts: [temperature: 0.35]}}
    end
  end

  defmodule RawFailure do
    @behaviour Jido.AI.Control
    def check(_, context), do: {:error, context.failure}
  end

  defp raw_failure(jido, raw) do
    mock =
      start_supervised!({MockLLM, script: [%{reply: {:text, "Provider answer"}}], observer: self()}, id: make_ref())

    server = native_start(jido, [tools: []], %{controls: %{output: [RawFailure]}})
    assert {:ok, handle} = request(server, mock, :react, "Fail", context: %{observer: self(), failure: raw})
    assert {:error, ^raw} = Request.await(handle)
    assert {:ok, view} = Session.snapshot(server)
    assert view.request.status == :failed and view.request.error == raw
    assert view.live == nil and view.details.active_request_id == nil
    streamed = events(handle)
    assert List.last(streamed).kind == :request_failed and List.last(streamed).data.error == raw
    assert ReAct.collect_stream(streamed).result == raw
    assert_script_done(mock)
    view
  end

  defp native_checkpoint(jido) do
    mock = mock([%{reply: {:text, "Done"}}])
    server = start_reasoning(jido, :react, tools: [])
    assert {:ok, handle} = request(server, mock, :react, "Checkpoint")
    assert {:ok, "Done"} = Request.await(handle)
    assert {:ok, view} = Session.snapshot(server)
    assert view.live == nil and view.details.active_request_id == nil
    assert {:ok, saved} = Jido.Agent.checkpoint(view.agent)
    assert saved.state.requests[handle.id] == view.request
    assert saved.state.requests[handle.id].result == "Done"

    assert Usage.token_counts(saved.state.requests[handle.id].meta.usage) == %{
             input_tokens: 10,
             output_tokens: 5,
             total_tokens: 15
           }

    assert :ok = Jido.Action.validate_static_data(saved)
    assert_script_done(mock)
    {server, handle, saved}
  end

  defp standalone_terminal(jido) do
    mock = start_supervised!({MockLLM, script: [%{reply: {:text, "Token done"}}], observer: self()}, id: make_ref())

    config =
      Config.new(%{
        model: MockLLM.model(),
        tools: [],
        streaming: false,
        llm_opts: MockLLM.options(mock),
        token_secret: "react-terminal-contract"
      })

    result = ReAct.run("Token", config, context: %{jido: jido})
    assert result.result == "Token done"
    assert {:ok, state, _} = Token.decode_state(result.final_token, config)
    assert state.status == :completed and state.result == "Token done"
    assert state.usage == result.usage
    assert_script_done(mock)
    {mock, config, result}
  end

  defmodule CaptureMessages do
    def transform_request(request, state, _config, context) do
      send(context.observer, {:model_messages, state.request_id, request.messages})
      {:ok, %{}}
    end
  end

  defp native_definition(opts, changes \\ %{}) do
    opts = Keyword.merge([name: "react_setup", tools: [TestCalculator], model: MockLLM.model(), streaming: false], opts)
    source = definition(:react, opts)

    plugins =
      Enum.map(source.plugins, fn
        {Jido.AI.Runtime.Plugin, config} ->
          profile = config[:profiles].assistant
          source = profile |> Map.from_struct() |> Map.merge(changes)
          source = Map.update!(source, :controls, &Map.put(&1, :model, [PreparedRequest]))
          assert {:ok, profile} = Jido.AI.Profile.new(source)
          {Jido.AI.Runtime.Plugin, Keyword.put(config, :profiles, %{assistant: profile})}

        plugin ->
          plugin
      end)

    %{source | plugins: plugins}
  end

  defp native_start(jido, opts \\ [], changes \\ %{}),
    do: start_agent(jido, Jido.Agent.instantiate!(native_definition(opts, changes)))

  # Old setup cases inspected the deferred worker payload before any model call.
  # This control observes the equivalent prepared request and stops explicitly.
  # HTTP transport and provider acceptance are covered by separate live cases.
  defp prepared(jido, base, overrides \\ []) do
    mock = mock([])
    server = native_start(jido, base)
    context = %{observer: self(), capture_only: true, ai: %{assistant: %{options: MockLLM.options(mock)}}}
    assert {:ok, handle} = request(server, mock, :react, "Inspect setup", Keyword.put(overrides, :context, context))
    assert {:error, :configuration_observed} = Request.await(handle)
    assert_receive {:prepared_request, request, profile}, 1_000
    assert MockLLM.report(mock).requests == []
    assert_script_done(mock)
    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    {request, profile}
  end

  defp user_texts(server) do
    current_history(server)
    |> Enum.filter(&(&1.role == :user))
    |> Enum.map(&Jido.AI.Query.summarize(&1.content))
  end

  defp context_agent(opts) do
    source = definition(:react, Keyword.merge([tools: [TestCalculator], model: MockLLM.model()], opts))

    schema = %{
      source.schema
      | fields: Keyword.put(source.schema.fields, :custom_counter, Zoi.integer() |> Zoi.default(7))
    }

    Jido.Agent.instantiate!(%{source | schema: schema})
  end

  defp calculation do
    %{reply: {:tools, [%{id: "calc", name: "calculator", arguments: %{operation: "add", a: 2, b: 3}}]}}
  end

  defp current_history(server) do
    agent = Server.agent(server)
    assert {:ok, profile} = Configuration.profile(agent)
    assert {:ok, entries} = Jido.AI.Session.Transcript.read(agent.state, profile)
    Enum.map(entries, &message_data/1)
  end

  defp history_entries(%Thread{} = thread) do
    Enum.map(thread.entries, fn entry ->
      {:ok, message} = Jido.AI.Thread.Projection.message(entry)
      [value] = Jido.AI.Model.Messages.entries([message])
      message_data(%{value | refs: entry.refs})
    end)
  end

  defp conversation(prompt, messages) do
    Enum.reduce(messages, Thread.new(metadata: %{system_prompt: prompt}), fn message, thread ->
      {:ok, thread} = Jido.AI.Thread.Projection.append(thread, [message], Map.get(message, :refs, %{}))
      thread
    end)
  end

  # Compare message data across input and projection forms. Canonical entry
  # timestamps and lane references are checked on Thread entries separately.
  defp message_data(entry) do
    refs = Map.drop(entry.refs || %{}, [:context_ref])

    content =
      if is_list(entry.content) and Enum.all?(entry.content, &match?(%ContentPart{type: :text}, &1)),
        do: Jido.AI.Query.summarize(entry.content),
        else: entry.content

    calls = if is_list(entry.tool_calls), do: Enum.map(entry.tool_calls, &ReqLLM.ToolCall.from_map/1), else: nil
    %{entry | timestamp: nil, content: content, tool_calls: calls, refs: if(refs == %{}, do: nil, else: refs)}
  end

  defp context_lane(server), do: Server.agent(server).state[ContextOps.key()][:assistant] || %{}
  defp thread_messages(server), do: Thread.filter_by_kind(Server.agent(server).state.messages.thread, :ai_message)

  defp context_operations(server),
    do: Thread.filter_by_kind(Server.agent(server).state.messages.thread, :ai_context_operation)

  defp replace_context(server, value, opts),
    do: Session.modify_context(server, %{type: :replace, result_context: value}, opts)

  defp deferred_context(jido, terminal) do
    first =
      case terminal do
        :task_loss -> calculation()
        :failure -> %{reply: {:wait, :active, {:error, 503, "Unavailable"}}}
        :complete -> %{reply: {:wait, :active, {:text, "Old answer"}}}
      end

    mock = mock([first, %{reply: {:text, "Next answer"}}])
    server = start_reasoning(jido, :react, tools: [TestCalculator], system_prompt: "Original prompt")
    context = %{observer: self(), hold_tool: terminal == :task_loss}
    assert {:ok, handle} = request(server, mock, :react, "Q1", context: context)

    worker =
      if terminal == :task_loss do
        assert_receive {:calculator_held, tool}, 2_000
        tool
      else
        assert_receive {:mock_llm_waiting, ^mock, :active, provider}, 2_000
        provider
      end

    monitor = Process.monitor(worker)
    before = current_history(server)
    replacement = conversation("Recovered prompt", [%{role: :user, content: "Recovered history"}])
    assert {:ok, _} = replace_context(server, replacement, op_id: "deferred", context_ref: "recovered")
    assert current_history(server) == before
    pending = context_lane(server).pending_context_op
    assert pending.operation.type == :replace
    assert %Thread{} = pending.operation.result_context
    assert {:ok, [%{role: :user} = message]} = Jido.AI.Thread.Projection.messages(pending.operation.result_context)
    assert Jido.AI.Query.summarize(message.content) == "Recovered history"
    assert context_lane(server).applied_context_ops == []
    assert {:ok, %{instructions: "Original prompt"}} = Configuration.profile(Server.agent(server))

    case terminal do
      :task_loss ->
        assert {:ok, view} = Session.snapshot(server)
        assert view.details.phase == :executing_tool
        Process.exit(view.live.worker_pid, :kill)
        assert {:error, :worker_crash} = Request.await(handle)

      :failure ->
        assert :ok = MockLLM.release(mock, :active)
        assert {:error, error} = Request.await(handle)
        assert error.details.status == 503

      :complete ->
        assert :ok = MockLLM.release(mock, :active)
        assert {:ok, "Old answer"} = Request.await(handle)
    end

    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
    assert current_history(server) == history_entries(replacement)
    assert {:ok, %Profile{instructions: "Recovered prompt"}} = Configuration.profile(Server.agent(server))
    assert context_lane(server).pending_context_op == nil
    assert context_lane(server).applied_context_ops == ["deferred"]
    assert [entry] = context_operations(server)
    assert {:ok, %{operation: %{type: :replace, reason: :manual}}} = Jido.AI.Thread.Operation.decode(entry)
    assert List.last(Thread.to_list(Server.agent(server).state.messages.thread)).id == entry.id
    assert {:ok, next} = request(server, mock, :react, "Continue")
    assert {:ok, "Next answer"} = Request.await(next)
    [first_wire, second_wire] = MockLLM.report(mock).requests
    assert Enum.map(first_wire.body["messages"], & &1["content"]) == ["Original prompt", "Q1"]

    assert Enum.map(second_wire.body["messages"], & &1["content"]) == [
             "Recovered prompt",
             "Recovered history",
             "Continue"
           ]

    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    assert_script_done(mock)
  end

  defp collection_event(kind, request_id, seq, data) do
    %{
      id: "evt_#{seq}",
      seq: seq,
      at_ms: 1_700_000_000_000 + seq,
      run_id: request_id,
      request_id: request_id,
      iteration: 1,
      kind: kind,
      llm_call_id: "call_#{request_id}",
      tool_call_id: nil,
      tool_name: nil,
      data: data
    }
  end

  describe "init validation" do
    test "definition rejects unsupported request policy" do
      assert_raise Jido.AI.Error.Validation.Invalid, ~r/requests:.*reject on busy/, fn ->
        native_definition(request_policy: :queue)
      end
    end

    test "definition rejects an unloaded request transformer" do
      assert_raise Jido.AI.Error.Validation.Invalid, ~r/request_transformer/, fn ->
        native_definition(request_transformer: :not_a_module)
      end
    end

    test "explicit nil instructions preserve the old direct no-prompt behavior", %{jido: jido} do
      mock = mock([%{reply: {:text, "Done"}}])
      server = native_start(jido, [], %{instructions: nil})
      assert {:ok, profile} = Configuration.profile(Server.agent(server))
      assert profile.instructions == nil
      assert {:ok, handle} = request(server, mock, :react, "No prompt", context: %{observer: self()})
      assert {:ok, "Done"} = Request.await(handle)
      [wire] = MockLLM.report(mock).requests
      assert wire.body["messages"] == [%{"role" => "user", "content" => "No prompt"}]
      assert_script_done(mock)
    end

    test "definition rejects a non-text system prompt" do
      assert_raise Jido.AI.Error.Validation.Invalid, ~r/instructions/, fn ->
        native_definition(system_prompt: 123)
      end
    end
  end

  describe "signal_routes/1" do
    test "native routes bind ReAct and common control signals", %{jido: jido} do
      server = native_start(jido)
      signal = Jido.Signal.new!("ai.react.query", %{query: "Work"}, source: "/test")
      assert %{id: :assistant, mode: :session} = Jido.AI.Authoring.request_binding(Server.agent(server), signal)
      assert Jido.AI.Authoring.request_method(Server.agent(server), signal) == :react
      assert {:ok, router} = Jido.Signal.Router.new(Server.agent(server).routes)

      for type <- [
            Session.cancel_type(),
            "jido.ai.session.control",
            "jido.ai.configure",
            "jido.ai.context.modify"
          ] do
        assert {:ok, _} = Jido.Signal.Router.route(router, %{signal | type: type})
      end

      before = Server.agent(server).state

      for type <- ["ai.llm.response", "ai.tool.result", "ai.llm.delta"] do
        assert {:ok, after_signal} =
                 Server.call(server, Jido.Signal.new!(type, %{request_id: "unowned"}, source: "/test"))

        assert after_signal.state == before
      end

      assert {:ok, %{request: nil, live: nil}} = Session.snapshot(server)
    end
  end

  describe "delegation lifecycle" do
    test "start commits one request before its owned model worker runs", %{jido: jido} do
      mock = mock([%{reply: {:wait, :held, {:text, "4"}}}])
      server = native_start(jido, streaming: true)
      assert {:ok, %{request: nil, live: nil}} = Session.snapshot(server)
      assert {:ok, handle} = request(server, mock, :react, "What is 2 + 2?", context: %{observer: self()})
      assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
      assert %{status: :pending, query: "What is 2 + 2?"} = record(server, handle)
      assert {:ok, view} = Session.snapshot(server)
      assert view.details.active_request_id == handle.id
      assert view.details.phase == :awaiting_llm
      assert Process.alive?(view.live.worker_pid)
      assert [%{body: %{"stream" => true}}] = MockLLM.report(mock).requests
      assert :ok = MockLLM.release(mock, :held)
      assert {:ok, "4"} = Request.await(handle)
      assert record(server, handle).meta.model_calls == 1
      assert_script_done(mock)
    end

    test "a real tool receives the Agent state snapshot and ignores a forged state binding", %{jido: jido} do
      assert_raise Jido.AI.Error.Validation.Invalid, ~r/tool_context/, fn ->
        definition(:react, tools: [TestCalculator], tool_context: %{state: %{override: true}, tenant: "acme"})
      end

      mock = mock([calculation(), %{reply: {:text, "Five"}}])
      server = start_agent(jido, context_agent(tool_context: %{tenant: "acme"}))

      assert {:ok, handle} =
               request(server, mock, :react, "Add",
                 context: %{observer: self(), observe_context: true},
                 tool_context: %{"state" => %{override: true}, state: %{override: true}, agent_state: %{override: true}}
               )

      assert {:ok, "Five"} = Request.await(handle)
      assert_receive {:calculator_context, seen}, 1_000
      assert seen.state.custom_counter == 7 and seen.agent_state == seen.state
      refute Map.has_key?(seen.state, :override)
      assert seen.tenant == "acme"
      assert Server.agent(server).state.custom_counter == 7
      [_, wire] = MockLLM.report(mock).requests
      result = Enum.find(wire.body["messages"], &(&1["role"] == "tool"))
      assert Jason.decode!(result["content"]) == %{"ok" => true, "result" => %{"result" => 5}}
      assert_script_done(mock)
    end

    test "start uses buffered HTTP when streaming is disabled", %{jido: jido} do
      mock = mock([%{reply: {:text, "4"}}])
      server = native_start(jido, streaming: false)
      assert {:ok, handle} = request(server, mock, :react, "Add", context: %{observer: self()})
      assert {:ok, "4"} = Request.await(handle)
      assert [%{body: %{"stream" => false}}] = MockLLM.report(mock).requests
      refute Enum.any?(events(handle), &(&1.kind == :llm_delta))
      assert_script_done(mock)
    end

    test "start sends the configured token limit over HTTP", %{jido: jido} do
      mock = mock([%{reply: {:text, "4"}}])
      server = native_start(jido, max_tokens: 4_096)
      assert {:ok, handle} = request(server, mock, :react, "Add", context: %{observer: self()})
      assert {:ok, "4"} = Request.await(handle)
      assert [%{body: %{"max_tokens" => 4_096}}] = MockLLM.report(mock).requests
      assert_script_done(mock)
    end

    test "prepared request keeps the declared iteration limit", %{jido: jido} do
      {_, profile} = prepared(jido, max_iterations: 4)
      assert profile.controls.max_iterations == 4
      assert profile.controls.max_model_calls == 4
    end

    test "prepared request uses its iteration override", %{jido: jido} do
      {_, profile} = prepared(jido, [max_iterations: 4], max_iterations: 2)
      assert profile.controls.max_iterations == 2
      assert profile.controls.max_model_calls == 4
    end

    test "invalid iteration override keeps the declared limit", %{jido: jido} do
      {_, profile} = prepared(jido, [max_iterations: 4], max_iterations: 0)
      assert profile.controls.max_iterations == 4
      assert profile.controls.max_model_calls == 4
    end

    test "prepared request keeps its declared idle timeout", %{jido: jido} do
      {_, profile} = prepared(jido, stream_timeout_ms: 123_456)
      assert profile.requests.idle_timeout == 123_456
    end

    test "prepared request uses its idle timeout override", %{jido: jido} do
      {_, profile} = prepared(jido, [stream_timeout_ms: 123_456], stream_timeout_ms: 222_222)
      assert profile.requests.idle_timeout == 222_222
    end

    test "prepared request merges declared and request HTTP options", %{jido: jido} do
      {request, _} =
        prepared(jido, [req_http_options: [plug: {Req.Test, []}]], req_http_options: [adapter: [recv_timeout: 1234]])

      assert request.options[:req_http_options] ==
               [plug: {Req.Test, []}, retry: false, receive_timeout: 5_000, adapter: [recv_timeout: 1234]]
    end

    test "prepared request merges declared and request generation options", %{jido: jido} do
      {request, _} =
        prepared(
          jido,
          [llm_opts: [thinking: %{type: :enabled, budget_tokens: 1_024}, reasoning_effort: :low]],
          llm_opts: [reasoning_effort: :high]
        )

      assert request.options[:thinking] == %{type: :enabled, budget_tokens: 1_024}
      assert request.options[:reasoning_effort] == :high
    end

    test "prepared request applies the allowed tool filter", %{jido: jido} do
      {request, profile} = prepared(jido, [tools: [TestCalculator, TestSearch]], allowed_tools: ["search"])
      assert Enum.map(profile.tools, & &1.name) == ["search"]
      assert Enum.map(request.options[:tools], & &1.name) == ["search"]
    end

    test "prepared request uses the request tool catalog", %{jido: jido} do
      {request, profile} = prepared(jido, [tools: [TestCalculator]], tools: [TestSearch])
      assert Enum.map(profile.tools, & &1.name) == ["search"]
      assert Enum.map(request.options[:tools], & &1.name) == ["search"]
      assert profile.reasoning.request_transformer == nil
    end

    test "request transformer override runs before the model control", %{jido: jido} do
      {request, profile} = prepared(jido, [], request_transformer: NativeTransform)
      assert profile.reasoning.request_transformer == NativeTransform
      assert request.options[:temperature] == 0.35
      assert_receive {:native_transform, _, 1, _}, 1_000
    end

    test "a real tool receives the host module identity and admitted context defaults", %{jido: jido} do
      mock = mock([calculation(), %{reply: {:text, "Five"}}])
      server = start_agent(jido, context_agent(tool_context: %{tenant: "tenant-1"}))
      agent = Server.agent(server)

      assert {:ok, handle} =
               request(server, mock, :react, "Add",
                 context: %{observer: self(), observe_context: true},
                 tool_context: %{agent_module: __MODULE__, agent_id: "forged"}
               )

      assert {:ok, "Five"} = Request.await(handle)
      assert_receive {:calculator_context, seen}, 1_000
      assert seen.agent_module == agent.module and seen.agent_module == Jido.Agent
      assert seen.agent_id == agent.id
      assert seen.tenant == "tenant-1"
      assert {:ok, profile} = Configuration.profile(Server.agent(server))
      assert profile.tool_context == %{tenant: "tenant-1"}
      assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
      assert_script_done(mock)
    end

    test "request idle timeout overrides the profile timeout", %{jido: jido} do
      {_, profile} = prepared(jido, [stream_timeout_ms: 4_500], stream_timeout_ms: 9_000)
      assert profile.requests.idle_timeout == 9_000
    end

    test "unknown allowed tools fail admission before model work", %{jido: jido} do
      mock = mock([])
      server = native_start(jido)

      assert {:error, {:unknown_allowed_tools, ["search"]}} =
               request(server, mock, :react, "Bad tool", allowed_tools: ["search"], context: %{observer: self()})

      assert {:ok, %{request: nil, live: nil}} = Session.snapshot(server)
      assert Server.agent(server).state.requests == %{}
      refute_receive {:prepared_request, _, _}, 0
      assert MockLLM.report(mock).requests == []
      assert_script_done(mock)
    end

    test "prepared request normalizes string generation option names", %{jido: jido} do
      {request, _} =
        prepared(
          jido,
          [
            llm_opts: %{
              "thinking" => %{type: :enabled, budget_tokens: 1_024},
              "reasoning_effort" => :low,
              "top_p" => 0.7
            }
          ],
          llm_opts: %{"reasoning_effort" => :high, "top_p" => 0.9, "unknown_provider_flag" => true}
        )

      assert request.options[:thinking] == %{type: :enabled, budget_tokens: 1_024}
      assert request.options[:reasoning_effort] == :high
      assert request.options[:top_p] == 0.9
      refute Keyword.has_key?(request.options, nil)
    end

    test "prepared request retains an existing atom option name", %{jido: jido} do
      existing_key = :custom_provider_flag
      {request, _} = prepared(jido, [], llm_opts: %{Atom.to_string(existing_key) => true})
      assert request.options[existing_key] == true
    end

    test "prepared request drops unknown option names without atom creation", %{jido: jido} do
      key = "__jido_ai_nonexistent_llm_opt_key__"
      assert_raise ArgumentError, fn -> String.to_existing_atom(key) end
      {request, _} = prepared(jido, [], llm_opts: %{key => true})
      refute Keyword.has_key?(request.options, nil)
      assert_raise ArgumentError, fn -> String.to_existing_atom(key) end
      assert Enum.all?(Keyword.keys(request.options), &is_atom/1)

      assert MapSet.new(Keyword.keys(request.options)) ==
               MapSet.new([
                 :max_retries,
                 :api_key,
                 :base_url,
                 :req_http_options,
                 :tools,
                 :receive_timeout,
                 :max_tokens,
                 :temperature
               ])
    end

    test "prepared request normalizes provider option keys by schema", %{jido: jido} do
      {request, _} =
        prepared(jido, [model: "openai:gpt-4o"],
          llm_opts: %{"provider_options" => %{"verbosity" => "high", "__jido_ai_nonexistent_provider_option__" => true}}
        )

      assert request.options[:provider_options] == [verbosity: "high"]
      refute Keyword.has_key?(request.options[:provider_options], nil)
    end

    test "the owned worker receives the prompt exactly once", %{jido: jido} do
      mock = mock([%{reply: {:wait, :held, {:text, "4"}}}])
      server = start_reasoning(jido, :react, tools: [])
      assert {:ok, handle} = request(server, mock, :react, "Test prompt")
      assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
      assert [wire] = MockLLM.report(mock).requests
      assert Enum.count(wire.body["messages"], &(&1["role"] == "user" and &1["content"] == "Test prompt")) == 1
      assert :ok = MockLLM.release(mock, :held)
      assert {:ok, "4"} = Request.await(handle)
      assert length(MockLLM.report(mock).requests) == 1
      assert record(server, handle).meta.model_calls == 1
      assert_script_done(mock)
    end

    test "owned runtime events update inspection and publish one request lifecycle", %{jido: jido} do
      mock = mock([%{reply: {:wait, :held, {:text, "Done"}}}])
      server = start_reasoning(jido, :react, tools: [])
      assert {:ok, handle} = request(server, mock, :react, "Hello")
      assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
      assert {:ok, active} = Session.snapshot(server)
      assert active.details.phase == :awaiting_llm
      assert active.details.active_request_id == handle.id
      assert Enum.map(active.details.trace.events, & &1.kind) == [:request_started, :llm_started]
      refute active.details.trace.truncated?
      assert :ok = MockLLM.release(mock, :held)
      assert {:ok, "Done"} = Request.await(handle)
      all = events(handle)
      assert hd(all).kind == :request_started
      assert List.last(all).kind == :request_completed
      assert Enum.count(all, &(&1.kind == :request_started)) == 1
      assert Enum.count(all, &(&1.kind == :request_completed)) == 1
      assert Enum.all?(all, &(&1.request_id == handle.id and &1.run_id == active.request.run_id))
      assert {:ok, done} = Session.snapshot(server)
      assert done.details.phase == :request_completed and done.live == nil
      assert done.details.trace.events == Enum.take(all, done.details.trace.seq)
      assert_script_done(mock)
    end

    test "steer queues request input and preserves its source and refs on consumption", %{jido: jido} do
      mock = mock([%{reply: {:wait, :held, {:text, "First"}}}, %{reply: {:text, "Revised"}}])
      server = start_reasoning(jido, :react, tools: [])
      assert {:ok, handle} = request(server, mock, :react, "Q1")
      assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
      id = handle.id

      assert {:ok, %{status: :queued, request_id: ^id, input_id: input_id}} =
               Session.steer(handle, "Actually answer Q2", source: "/test/steer", extra_refs: %{origin: "suite"})

      assert user_texts(server) == ["Q1"]
      assert :ok = MockLLM.release(mock, :held)
      assert {:ok, "Revised"} = Request.await(handle)
      assert [injected] = Enum.filter(events(handle), &(&1.kind == :input_injected))
      assert injected.data.input_id == input_id
      assert injected.data.source == "/test/steer"
      assert injected.data.refs == %{origin: "suite"}
      assert user_texts(server) == ["Q1", "Actually answer Q2"]
      assert_script_done(mock)
    end

    test "provider failure discards undrained input before the next request", %{jido: jido} do
      mock = mock([%{reply: {:wait, :held, {:error, 429, "Rate limited"}}}, %{reply: {:text, "Next"}}])
      server = start_reasoning(jido, :react, tools: [])
      assert {:ok, first} = request(server, mock, :react, "Q1")
      assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
      assert {:ok, %{status: :queued}} = Session.steer(first, "Discard this input")
      assert :ok = MockLLM.release(mock, :held)
      assert {:error, error} = Request.await(first)
      assert error.details.status == 429
      assert record(server, first).status == :failed
      assert {:ok, %{live: nil, details: %{active_request_id: nil}}} = Session.snapshot(server)
      refute Enum.any?(events(first), &(&1.kind == :input_injected))
      assert user_texts(server) == ["Q1"]
      assert {:ok, next} = request(server, mock, :react, "Q2")
      assert {:ok, "Next"} = Request.await(next)
      assert user_texts(server) == ["Q1", "Q2"]
      [_, wire] = MockLLM.report(mock).requests
      refute Enum.any?(wire.body["messages"], &(&1["content"] == "Discard this input"))
      assert_script_done(mock)
    end

    test "idle injection rejects without starting work or changing history", %{jido: jido} do
      mock = mock([])
      server = start_reasoning(jido, :react, tools: [])
      before = Server.agent(server).state
      assert {:error, %{status: :rejected, reason: :idle, kind: :inject}} = Session.inject(server, "Programmatic input")
      assert Server.agent(server).state == before
      assert {:ok, %{request: nil, live: nil}} = Session.snapshot(server)
      assert MockLLM.report(mock).requests == []
      assert_script_done(mock)
    end

    test "stale steering rejects without adding an input or model call", %{jido: jido} do
      mock = mock([%{reply: {:wait, :held, {:text, "Done"}}}])
      server = start_reasoning(jido, :react, tools: [])
      assert {:ok, handle} = request(server, mock, :react, "Q1")
      assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
      before = Server.agent(server).state.messages

      assert {:error, %{status: :rejected, reason: :request_mismatch}} =
               Session.steer(server, "Wrong request", expected_request_id: "stale")

      assert Server.agent(server).state.messages == before
      assert :ok = MockLLM.release(mock, :held)
      assert {:ok, "Done"} = Request.await(handle)
      refute Enum.any?(events(handle), &(&1.kind == :input_injected))
      assert user_texts(server) == ["Q1"]
      assert record(server, handle).meta.model_calls == 1
      assert_script_done(mock)
    end

    test "blank steering rejects without adding an input or model call", %{jido: jido} do
      mock = mock([%{reply: {:wait, :held, {:text, "Done"}}}])
      server = start_reasoning(jido, :react, tools: [])
      assert {:ok, handle} = request(server, mock, :react, "Q1")
      assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
      before = Server.agent(server).state.messages
      assert {:error, %{status: :rejected, reason: :empty_content}} = Session.steer(handle, "   ")
      assert Server.agent(server).state.messages == before
      assert :ok = MockLLM.release(mock, :held)
      assert {:ok, "Done"} = Request.await(handle)
      refute Enum.any?(events(handle), &(&1.kind == :input_injected))
      assert user_texts(server) == ["Q1"]
      assert record(server, handle).meta.model_calls == 1
      assert_script_done(mock)
    end

    test "consumed injection commits one user message before the next model call", %{jido: jido} do
      mock = mock([%{reply: {:wait, :held, {:text, "First"}}}, %{reply: {:text, "Revised"}}])
      server = start_reasoning(jido, :react, tools: [])
      assert {:ok, handle} = request(server, mock, :react, "Q1")
      assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000

      assert {:ok, %{input_id: input_id}} =
               Session.inject(handle, "Actually answer Q2", source: "/test/runtime", extra_refs: %{origin: "suite"})

      assert user_texts(server) == ["Q1"]
      assert :ok = MockLLM.release(mock, :held)
      assert {:ok, "Revised"} = Request.await(handle)
      assert [injected] = Enum.filter(events(handle), &(&1.kind == :input_injected))
      assert injected.data.input_id == input_id and injected.request_id == handle.id
      assert user_texts(server) == ["Q1", "Actually answer Q2"]
      entry = Enum.find(current_history(server), &(&1.content == "Actually answer Q2"))
      assert entry.refs == %{request_id: handle.id, run_id: injected.run_id, source: "/test/runtime", origin: "suite"}
      [_, wire] = MockLLM.report(mock).requests
      users = Enum.filter(wire.body["messages"], &(&1["role"] == "user"))
      assert Enum.map(users, & &1["content"]) == ["Q1", "Actually answer Q2"]
      assert_script_done(mock)
    end

    test "native checkpoints and standalone tokens keep terminal result and usage", %{jido: jido} do
      {_server, _handle, saved} = native_checkpoint(jido)
      {_, config, result} = standalone_terminal(jido)
      assert result.termination_reason == :final_answer
      assert is_binary(result.final_token)
      assert {:ok, replay} = ReAct.collect(result.final_token, config, run_until_terminal?: false)
      assert replay.result == result.result and replay.usage == result.usage
      assert replay.final_token == result.final_token
      assert {:ok, restored} = Jido.Agent.restore(Jido.Agent, saved)
      assert restored.state == saved.state
    end

    test "request usage sums real model calls and collection keeps nested provider metadata", %{jido: jido} do
      first = %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15}
      second = %{prompt_tokens: 7, completion_tokens: 3, total_tokens: 10}
      mock = mock([%{reply: {:wait, :draft, response("Draft one", first)}}, %{reply: response("Draft two", second)}])
      server = start_reasoning(jido, :react, tools: [])
      assert {:ok, handle} = request(server, mock, :react, "Draft")
      assert_receive {:mock_llm_waiting, ^mock, :draft, _}, 2_000
      assert {:ok, _} = Session.inject(handle, "Revise")
      assert :ok = MockLLM.release(mock, :draft)
      assert {:ok, "Draft two"} = Request.await(handle)

      assert Usage.token_counts(record(server, handle).meta.usage) == %{
               input_tokens: 17,
               output_tokens: 8,
               total_tokens: 25
             }

      assert record(server, handle).meta.model_calls == 2
      assert_script_done(mock)

      # This public event boundary retains provider metadata after SDK decoding.
      # HTTP dialect normalization is checked separately above and in 02_24.
      usage_1 = %{
        input_tokens: 10,
        output_tokens: 5,
        total_cost: 0.001,
        input_includes_cached: false,
        cost: %{total: 0.001, input_cost: 0.0008, line_items: [%{id: "first"}]},
        image_usage: %{images: 1}
      }

      usage_2 = %{
        input_tokens: 7,
        output_tokens: 3,
        total_cost: 0.002,
        input_includes_cached: true,
        cost: %{total: 0.002, input_cost: 0.0015, line_items: [%{id: "second"}]},
        image_usage: %{images: 2}
      }

      result =
        ReAct.collect_stream([
          collection_event(:llm_completed, "nested", 1, %{usage: usage_1}),
          collection_event(:llm_completed, "nested", 2, %{usage: usage_2})
        ])

      assert result.usage == %{
               input_tokens: 17,
               output_tokens: 8,
               total_cost: 0.003,
               input_includes_cached: true,
               cost: %{total: 0.003, input_cost: 0.0023, line_items: [%{id: "second"}]},
               image_usage: %{images: 3}
             }
    end

    test "empty final model usage and empty terminal event usage preserve earlier accounting", %{jido: jido} do
      usage = %{prompt_tokens: 3, completion_tokens: 1, total_tokens: 4}
      {:raw, first} = response(nil, usage)

      first = %{
        first
        | choices: [
            %{
              index: 0,
              finish_reason: "tool_calls",
              message: %{
                role: "assistant",
                content: nil,
                tool_calls: [
                  %{
                    id: "calc",
                    type: "function",
                    function: %{name: "calculator", arguments: Jason.encode!(%{operation: "add", a: 2, b: 3})}
                  }
                ]
              }
            }
          ]
      }

      mock = mock([%{reply: {:raw, first}}, %{reply: response("5", %{})}])
      server = start_reasoning(jido, :react, tools: [TestCalculator])
      assert {:ok, handle} = request(server, mock, :react, "Add")
      assert {:ok, "5"} = Request.await(handle)
      streamed = events(handle)

      assert Usage.token_counts(record(server, handle).meta.usage) == %{
               input_tokens: 3,
               output_tokens: 1,
               total_tokens: 4
             }

      assert record(server, handle).meta.model_calls == 2
      # A terminal event with absent usage must retain the preceding LLM totals.
      empty_terminal =
        Enum.map(streamed, fn event ->
          if event.kind == :request_completed, do: %{event | data: Map.put(event.data, :usage, %{})}, else: event
        end)

      collected = ReAct.collect_stream(empty_terminal)
      assert collected.result == "5" and collected.termination_reason == :final_answer
      assert Usage.token_counts(collected.usage) == %{input_tokens: 3, output_tokens: 1, total_tokens: 4}
      assert_script_done(mock)
    end

    test "the next request reuses committed history and opaque reasoning details", %{jido: jido} do
      details = [
        %ReqLLM.Message.ReasoningDetails{
          text: "Remember the question",
          signature: "sig_123",
          encrypted?: true,
          provider: :openai,
          format: "responses/v1",
          index: 0,
          provider_data: %{"token" => "opaque"}
        }
      ]

      wire_details = Enum.map(details, &ReqLLM.Message.ReasoningDetails.to_openai_compatible/1)
      delta = %{content: "You asked who you are.", reasoning_details: wire_details}
      mock = mock([%{reply: {:stream, [delta], "stop"}}, %{reply: {:text, "You asked who you are."}}])
      server = start_reasoning(jido, :react, tools: [], streaming: true)
      assert {:ok, first} = request(server, mock, :react, "Who am I?")
      assert {:ok, "You asked who you are."} = Request.await(first)
      assert {:ok, next} = request(server, mock, :react, "What did I just ask?")
      assert {:ok, "You asked who you are."} = Request.await(next)
      [_, wire] = MockLLM.report(mock).requests
      history = Enum.reject(wire.body["messages"], &(&1["role"] == "system"))

      assert Enum.map(history, &Map.take(&1, ["role", "content"])) == [
               %{"role" => "user", "content" => "Who am I?"},
               %{"role" => "assistant", "content" => "You asked who you are."},
               %{"role" => "user", "content" => "What did I just ask?"}
             ]

      assert Enum.at(history, 1)["reasoning_details"] == wire_details
      assistant = Enum.find(current_history(server), &(&1.role == :assistant))
      assert assistant.reasoning_details == details
      assert assistant.refs.request_id == first.id and assistant.refs.run_id == record(server, first).run_id
      assert_script_done(mock)
    end

    test "inspection projects the committed message history", %{jido: jido} do
      mock = mock([%{reply: {:text, "Tracked"}}])
      server = start_reasoning(jido, :react, tools: [])
      assert {:ok, handle} = request(server, mock, :react, "Track this")
      assert {:ok, "Tracked"} = Request.await(handle)
      assert {:ok, view} = Session.snapshot(server)
      conversation = Enum.reject(view.details.conversation, &(&1.role == :system))

      assert Enum.map(conversation, &%{role: &1.role, content: Jido.AI.Query.summarize(&1.content)}) ==
               [%{role: :user, content: "Track this"}, %{role: :assistant, content: "Tracked"}]

      assert Enum.all?(conversation, &(&1.refs.request_id == handle.id and &1.refs.run_id == view.request.run_id))
      assert :ok = Jido.Action.validate_static_data(view.agent.state)
      assert_script_done(mock)
    end

    test "inspection normalizes string-key provider calls while a real tool runs", %{jido: jido} do
      call = %{
        "id" => "call_string",
        "type" => "function",
        "function" => %{"name" => "calculator", "arguments" => Jason.encode!(%{operation: "add", a: 2, b: 3})}
      }

      wire = %{
        "id" => "string-call",
        "object" => "chat.completion",
        "model" => "gpt-4o-mini",
        "choices" => [
          %{
            "index" => 0,
            "message" => %{"role" => "assistant", "content" => nil, "tool_calls" => [call]},
            "finish_reason" => "tool_calls"
          }
        ],
        "usage" => %{"prompt_tokens" => 3, "completion_tokens" => 1, "total_tokens" => 4}
      }

      mock = mock([%{reply: {:raw, wire}}, %{reply: {:text, "5"}}])
      server = start_reasoning(jido, :react, tools: [TestCalculator])
      assert {:ok, handle} = request(server, mock, :react, "Add", context: %{observer: self(), hold_tool: true})
      assert_receive {:calculator_held, tool}, 2_000
      assert {:ok, view} = Session.snapshot(server)

      assert view.details.tool_calls == [
               %{
                 id: "call_string",
                 name: "calculator",
                 arguments: %{"operation" => "add", "a" => 2, "b" => 3},
                 status: :running,
                 result: nil
               }
             ]

      send(tool, :release)
      assert {:ok, "5"} = Request.await(handle)
      assert {:ok, done} = Session.snapshot(server)
      assert done.details.tool_calls == []
      assert [%{id: "call_string", result: {:ok, %{result: 5}, []}}] = done.details.tool_results
      assert_script_done(mock)
    end

    test "completed tool inspection keeps one result per call after replay and the final answer", %{jido: jido} do
      calls = [
        %{id: "call_calc", name: "calculator", arguments: %{operation: "add", a: 2, b: 3}},
        %{id: "call_search", name: "search", arguments: %{query: "timeout"}}
      ]

      mock =
        mock([
          %{reply: {:tools, calls}},
          %{reply: {:wait, :final, {:text, "The tools finished."}}},
          %{reply: {:wait, :next, {:text, "Next"}}}
        ])

      server = start_reasoning(jido, :react, tools: [TestCalculator, TestSearch])
      assert {:ok, handle} = request(server, mock, :react, "Use tools")
      assert_receive {:mock_llm_waiting, ^mock, :final, _}, 2_000
      assert {:ok, before} = Session.snapshot(server)
      replay = Enum.find(before.details.trace.events, &(&1.kind == :tool_completed and &1.tool_call_id == "call_calc"))
      assert replay != nil

      assert :ok =
               GenServer.call(owner(server), {:event, handle.id, before.request.run_id, :tool_completed, replay.data})

      assert {:ok, replayed} = Session.snapshot(server)
      assert replayed.details.phase == :awaiting_llm
      assert replayed.details.tool_results == before.details.tool_results
      assert :ok = MockLLM.release(mock, :final)
      assert {:ok, "The tools finished."} = Request.await(handle)
      assert {:ok, done} = Session.snapshot(server)
      assert done.request.result == "The tools finished."
      assert done.details.tool_calls == []

      assert Enum.map(done.details.tool_results, &Map.take(&1, [:id, :name, :arguments, :result])) == [
               %{
                 id: "call_calc",
                 name: "calculator",
                 arguments: %{operation: "add", a: 2, b: 3},
                 result: {:ok, %{result: 5}, []}
               },
               %{
                 id: "call_search",
                 name: "search",
                 arguments: %{query: "timeout"},
                 result:
                   {:error,
                    %{
                      type: :timeout,
                      message: "search timed out",
                      details: %{tool_name: "search", tool_call_id: "call_search"},
                      retryable?: true
                    }, []}
               }
             ]

      [_, final_wire] = MockLLM.report(mock).requests
      assert Enum.count(final_wire.body["messages"], &(&1["role"] == "tool")) == 2

      assert :ok =
               GenServer.call(owner(server), {:event, handle.id, before.request.run_id, :tool_completed, replay.data})

      assert {:ok, retained} = Session.snapshot(server, request_id: handle.id)
      assert retained.request == done.request
      assert {:ok, next} = request(server, mock, :react, "Next run")
      assert_receive {:mock_llm_waiting, ^mock, :next, _}, 2_000
      assert {:ok, fresh} = Session.snapshot(server)
      assert fresh.details.tool_results == [] and fresh.details.tool_calls == []
      assert {:ok, retained} = Session.snapshot(server, request_id: handle.id)
      assert retained.details.tool_results == done.details.tool_results
      assert :ok = MockLLM.release(mock, :next)
      assert {:ok, "Next"} = Request.await(next)
      assert_script_done(mock)
    end

    test "request HTTP and generation overrides end before the next request", %{jido: jido} do
      mock = mock([%{reply: {:text, "First"}}, %{reply: {:text, "Next"}}])
      server = start_reasoning(jido, :react, tools: [], llm_opts: [temperature: 0.3])
      definition = Jido.Agent.definition(Server.agent(server))

      assert {:ok, first} =
               request(server, mock, :react, "Q1",
                 llm_opts: MockLLM.options(mock) ++ [temperature: 0.8],
                 req_http_options: [headers: [{"x-request-only", "first"}]]
               )

      assert {:ok, "First"} = Request.await(first)
      assert {:ok, %{live: nil}} = Session.snapshot(server)
      assert {:ok, next} = request(server, mock, :react, "Q2")
      assert {:ok, "Next"} = Request.await(next)
      [first_wire, next_wire] = MockLLM.report(mock).requests
      assert first_wire.body["temperature"] == 0.8 and next_wire.body["temperature"] == 0.3
      assert first_wire.headers["x-request-only"] == "first"
      refute Map.has_key?(next_wire.headers, "x-request-only")
      assert Jido.Agent.definition(Server.agent(server)) == definition
      assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
      refute inspect(Server.agent(server).state) =~ "x-request-only"
      assert_script_done(mock)
    end

    test "terminal checkpoint restore and token collection do not reopen completed work", %{jido: jido} do
      {server, handle, saved} = native_checkpoint(jido)
      assert :ok = Server.stop(server, :normal)
      copy = saved |> :erlang.term_to_binary() |> :erlang.binary_to_term([:safe])
      assert {:ok, restored} = Jido.Agent.restore(Jido.Agent, copy)
      server = start_agent(jido, restored)
      assert {:ok, view} = Session.snapshot(server, request_id: handle.id)
      assert view.request.status == :completed and view.request.result == "Done"
      assert view.live == nil and view.details.active_request_id == nil
      assert view.details.phase == :request_completed
      {mock, config, result} = standalone_terminal(jido)
      completion = Enum.find_index(result.trace, &(&1.kind == :request_completed))
      terminal = Enum.find_index(result.trace, &(&1.kind == :checkpoint and &1.data.reason == :terminal))
      assert is_integer(completion) and terminal > completion
      assert Enum.at(result.trace, terminal).data.token == result.final_token
      assert {:ok, replay} = ReAct.collect(result.final_token, config, [])
      assert replay.result == "Token done" and replay.termination_reason == :final_answer
      assert length(MockLLM.report(mock).requests) == 1
      assert_script_done(mock)
    end

    test "cancellation keeps its reason and closes the provider connection", %{jido: jido} do
      mock = mock([%{reply: {:wait, :held, {:text, "unused"}}}])
      server = start_reasoning(jido, :react, tools: [])
      assert {:ok, handle} = request(server, mock, :react)
      assert_receive {:mock_llm_waiting, ^mock, :held, provider}, 2_000
      monitor = Process.monitor(provider)
      assert :ok = Session.cancel(handle, reason: :user_cancelled)
      assert {:error, {:cancelled, :user_cancelled}} = Request.await(handle)
      assert record(server, handle).error == {:cancelled, :user_cancelled}
      assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000

      assert {:ok, %{live: nil, details: %{active_request_id: nil, cancel_reason: :user_cancelled}}} =
               Session.snapshot(server)

      eventually(fn -> MockLLM.report(mock).waiting == [] end)
      assert_script_done(mock)
    end

    test "a worker crash fails its request and permits a later request", %{jido: jido} do
      mock = mock([%{reply: {:wait, :held, {:text, "unused"}}}, %{reply: {:text, "Next"}}])
      server = start_reasoning(jido, :react, tools: [])
      assert {:ok, first} = request(server, mock, :react)
      assert_receive {:mock_llm_waiting, ^mock, :held, provider}, 2_000
      monitor = Process.monitor(provider)
      assert {:ok, view} = Session.snapshot(server)
      Process.exit(view.live.worker_pid, :kill)
      assert {:error, :worker_crash} = Request.await(first)
      assert record(server, first).error == :worker_crash
      assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
      assert {:ok, %{live: nil, details: %{active_request_id: nil}}} = Session.snapshot(server)
      assert {:ok, next} = request(server, mock, :react, "Next")
      assert {:ok, "Next"} = Request.await(next)
      eventually(fn -> MockLLM.report(mock).waiting == [] end)
      assert_script_done(mock)
    end

    test "streamed deltas preserve request run call and sequence IDs", %{jido: jido} do
      mock =
        mock([%{reply: {:stream, [%{content: "Step 1: Add."}, {:wait, :held}, %{content: "\n4"}], "stop"}}])

      server = start_reasoning(jido, :react, tools: [], streaming: true)
      assert {:ok, handle} = request(server, mock, :react)
      assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
      assert_receive {:jido_ai_request_event, %{kind: :llm_delta} = delta}, 1_000
      assert delta.data.delta == "Step 1: Add." and delta.data.chunk_type == :content
      assert delta.request_id == handle.id and delta.run_id == record(server, handle).run_id
      assert delta.method == :react
      assert_receive {:signal, %{type: "ai.llm.delta", data: data}}, 1_000
      assert data.call_id == delta.llm_call_id and is_binary(data.call_id)
      assert data.seq == delta.seq and data.run_id == delta.run_id and data.request_id == handle.id
      assert data.delta == delta.data.delta and data.chunk_type == :content
      assert :ok = MockLLM.release(mock, :held)
      assert {:ok, "Step 1: Add.\n4"} = Request.await(handle)
      all = Enum.sort_by([delta | events(handle)], & &1.seq)
      assert Enum.map(all, & &1.seq) == Enum.to_list(1..length(all))
      assert List.last(all).kind == :request_completed
      assert_script_done(mock)
    end

    test "complete content parts reach both streams and the stored multimodal result", %{jido: jido} do
      image = ContentPart.image(<<1, 2, 3>>, "image/png")
      delta = %{images: [%{type: "image_url", image_url: %{url: "data:image/png;base64,AQID"}}]}
      mock = mock([%{reply: {:stream, [delta, {:wait, :held}], "stop"}}])
      server = start_reasoning(jido, :react, tools: [], streaming: true)
      assert {:ok, handle} = request(server, mock, :react)
      assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000

      assert_receive {:jido_ai_request_event, %{kind: :llm_delta, data: %{chunk_type: :content_part, delta: ^image}}},
                     1_000

      assert_receive {:signal, %{type: "ai.llm.delta", data: %{chunk_type: :content_part, delta: ^image}}}, 1_000
      assert {:ok, active} = Session.snapshot(server)
      assert active.details.streaming_text == ""
      assert :ok = MockLLM.release(mock, :held)
      assert {:ok, [^image]} = Request.await(handle)
      assert record(server, handle).result == [image]
      assert {:ok, %{details: %{streaming_text: ""}}} = Session.snapshot(server)
      assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
      assert_script_done(mock)
    end

    test "delta telemetry uses the effective runtime model", %{jido: jido} do
      handler_id = "react-model-#{System.unique_integer([:positive])}"
      request_id = "model-#{System.unique_integer([:positive])}"
      parent = self()

      :ok =
        :telemetry.attach(
          handler_id,
          Jido.AI.Observe.llm(:delta),
          fn _, _, metadata, _ ->
            if metadata.request_id == request_id, do: send(parent, {:delta_metadata, metadata})
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)
      mock = mock([%{reply: {:stream, [%{content: "Runtime model"}], "stop"}}])
      server = start_reasoning(jido, :react, tools: [], model: "openai:gpt-4o", streaming: true)
      assert {:ok, handle} = request(server, mock, :react, "Use override", request_id: request_id)
      assert {:ok, "Runtime model"} = Request.await(handle)
      assert_receive {:delta_metadata, metadata}, 1_000
      assert metadata.model == "openai:gpt-4o-mini"
      assert [%{body: %{"model" => "gpt-4o-mini"}}] = MockLLM.report(mock).requests
      assert {:ok, view} = Session.snapshot(server)
      assert view.details.model == metadata.model
      assert_script_done(mock)
    end

    test "the trace keeps its first 2000 events and records overflow through completion", %{jido: jido} do
      mock = mock([%{reply: {:wait, :held, {:text, "Done"}}}])
      server = start_reasoning(jido, :react, tools: [])
      assert {:ok, handle} = request(server, mock, :react)
      assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
      assert {:ok, view} = Session.snapshot(server)

      for n <- 1..2_010 do
        assert :ok =
                 GenServer.call(
                   owner(server),
                   {:event, handle.id, view.request.run_id, :llm_delta, %{delta: "x", chunk_type: :content, n: n}}
                 )
      end

      assert {:ok, active} = Session.snapshot(server)
      assert active.details.trace.truncated?
      assert Enum.map(active.details.trace.events, & &1.seq) == Enum.to_list(1..2_000)
      assert active.details.trace.seq == 2_012
      assert :ok = MockLLM.release(mock, :held)
      assert {:ok, "Done"} = Request.await(handle)
      assert {:ok, done} = Session.snapshot(server)
      assert done.details.trace.events == active.details.trace.events
      assert done.details.trace.truncated? and done.details.trace.seq > active.details.trace.seq
      assert done.request.status == :completed
      assert_script_done(mock)
    end

    test "blank provider failure and the exact incomplete tuple retain their error values", %{jido: jido} do
      mock = mock([%{reply: {:stream, [], "incomplete"}}])
      server = start_reasoning(jido, :react, tools: [], streaming: true)
      assert {:ok, handle} = request(server, mock, :react)
      # The Chat SDK maps the wire value to :error. Do not claim :incomplete decoding.
      assert {:error, {:incomplete_response, :error}} = Request.await(handle)
      assert {:ok, view} = Session.snapshot(server)
      assert view.request.error == {:incomplete_response, :error}
      assert view.request.meta.error_type == :llm_response
      assert_script_done(mock)
      raw = {:incomplete_response, :incomplete}
      # An exact domain error uses the real output control, after a model call.
      assert raw_failure(jido, raw).request.error == raw

      collected =
        ReAct.collect_stream([collection_event(:request_failed, "exact", 1, %{error: raw, error_type: :llm_response})])

      assert collected.result == raw and collected.termination_reason == :failed
    end
  end

  describe "tool configuration and compatibility" do
    test "tool registration updates the live catalog and the next provider request", %{jido: jido} do
      mock =
        mock([
          %{reply: {:tools, [%{id: "search", name: "search", arguments: %{query: "jido"}}]}},
          %{reply: {:text, "Found"}}
        ])

      server = start_reasoning(jido, :react, tools: [TestCalculator])
      assert Jido.AI.list_tools(Server.agent(server)) == [TestCalculator]
      assert {:ok, _} = Configuration.live(server, :register, TestSearch)
      assert MapSet.new(Jido.AI.list_tools(Server.agent(server))) == MapSet.new([TestCalculator, TestSearch])
      assert {:ok, handle} = request(server, mock, :react, "Search")
      assert {:ok, "Found"} = Request.await(handle)
      [first, final] = MockLLM.report(mock).requests
      assert MapSet.new(Enum.map(first.body["tools"], & &1["function"]["name"])) == MapSet.new(["calculator", "search"])
      result = Enum.find(final.body["messages"], &(&1["role"] == "tool"))
      assert Jason.decode!(result["content"]) == %{"ok" => true, "result" => %{"results" => ["Found: jido"]}}
      assert_script_done(mock)
    end

    test "tool removal updates the live catalog and the next provider request", %{jido: jido} do
      mock = mock([calculation(), %{reply: {:text, "Five"}}])
      server = start_reasoning(jido, :react, tools: [TestCalculator, TestSearch])
      assert {:ok, _} = Configuration.live(server, :unregister, "search")
      assert Jido.AI.list_tools(Server.agent(server)) == [TestCalculator]
      assert {:ok, handle} = request(server, mock, :react, "Add")
      assert {:ok, "Five"} = Request.await(handle)

      for wire <- MockLLM.report(mock).requests do
        assert Enum.map(wire.body["tools"], & &1["function"]["name"]) == ["calculator"]
      end

      assert record(server, handle).meta.tool_calls == 1
      assert_script_done(mock)
    end

    test "context replacement removes old defaults before real tool execution", %{jido: jido} do
      mock = mock([calculation(), %{reply: {:text, "Five"}}])
      server = start_reasoning(jido, :react, tools: [TestCalculator], tool_context: %{tenant: "a", region: "us"})
      assert {:ok, _} = Configuration.live(server, :tool_context, %{tenant: "b"})
      assert {:ok, profile} = Configuration.profile(Server.agent(server))
      assert profile.tool_context == %{tenant: "b"}
      assert {:ok, handle} = request(server, mock, :react, "Add", context: %{observer: self(), observe_context: true})
      assert {:ok, "Five"} = Request.await(handle)
      assert_receive {:calculator_context, seen}, 1_000
      assert seen.tenant == "b"
      refute Map.has_key?(seen, :region)
      assert_script_done(mock)
    end

    test "prompt replacement reaches the next provider request exactly once", %{jido: jido} do
      mock = mock([%{reply: {:text, "Done"}}])
      server = start_reasoning(jido, :react, tools: [], system_prompt: "Original prompt")
      assert {:ok, _} = Configuration.live(server, :prompt, "Updated prompt")
      assert {:ok, profile} = Configuration.profile(Server.agent(server))
      assert profile.instructions == "Updated prompt"
      assert {:ok, handle} = request(server, mock, :react, "Work")
      assert {:ok, "Done"} = Request.await(handle)
      [wire] = MockLLM.report(mock).requests

      assert Enum.filter(wire.body["messages"], &(&1["role"] == "system")) == [
               %{"role" => "system", "content" => "Updated prompt"}
             ]

      assert_script_done(mock)
    end

    test "context replacement updates committed history and the next model prompt", %{jido: jido} do
      mock = mock([%{reply: {:text, "Done"}}])
      server = start_reasoning(jido, :react, tools: [], system_prompt: "Original prompt")

      replacement =
        conversation("Restored prompt", [%{role: :user, content: "Hello"}, %{role: :assistant, content: "Hi there"}])

      assert {:ok, _} = replace_context(server, replacement, op_id: "replace")
      assert current_history(server) == history_entries(replacement)
      assert {:ok, %Profile{instructions: "Restored prompt"}} = Configuration.profile(Server.agent(server))
      assert {:ok, handle} = request(server, mock, :react, "Continue")
      assert {:ok, "Done"} = Request.await(handle)
      [wire] = MockLLM.report(mock).requests
      assert Enum.map(wire.body["messages"], & &1["content"]) == ["Restored prompt", "Hello", "Hi there", "Continue"]
      assert_script_done(mock)
    end

    test "a promptless context replacement preserves the configured model prompt", %{jido: jido} do
      mock = mock([%{reply: {:text, "Done"}}])
      server = start_reasoning(jido, :react, tools: [], system_prompt: "Keep me")
      replacement = conversation(nil, [%{role: :user, content: "test"}])
      assert {:ok, _} = replace_context(server, replacement, op_id: "nil-prompt")
      assert current_history(server) == history_entries(replacement)
      assert {:ok, %Profile{instructions: "Keep me"}} = Configuration.profile(Server.agent(server))
      assert [entry] = context_operations(server)
      assert {:ok, %{operation: %{result_context: snapshot}}} = Jido.AI.Thread.Operation.decode(entry)
      assert snapshot.metadata.system_prompt == nil
      assert {:ok, handle} = request(server, mock, :react, "next turn")
      assert {:ok, "Done"} = Request.await(handle)
      [wire] = MockLLM.report(mock).requests
      assert Enum.map(wire.body["messages"], & &1["content"]) == ["Keep me", "test", "next turn"]
      assert_script_done(mock)
    end

    test "deferred context applies once after completion and before the next request", %{jido: jido} do
      deferred_context(jido, :complete)
    end

    test "request inspection preserves a raw error map after real model work", %{jido: jido} do
      raw = %{type: :stream_error, status: 503, message: "Too many connections"}
      view = raw_failure(jido, raw)
      assert view.request.error == raw and view.details.phase == :request_failed
      assert :ok = Jido.Action.validate_static_data(view.agent.state)
    end

    test "deferred context applies once after provider failure and before the next request", %{jido: jido} do
      deferred_context(jido, :failure)
    end

    test "deferred context applies once after a worker crash during tool execution", %{jido: jido} do
      deferred_context(jido, :task_loss)
    end

    test "invalid context input returns an error without changing state", %{jido: jido} do
      mock = mock([])
      server = start_reasoning(jido, :react, tools: [], system_prompt: "Original")
      before = Server.agent(server).state

      assert {:error, _} = replace_context(server, "not a context", op_id: "invalid")
      assert Server.agent(server).state == before
      assert {:ok, %Profile{instructions: "Original"}} = Configuration.profile(Server.agent(server))
      assert MockLLM.report(mock).requests == []
      assert_script_done(mock)
    end

    test "idle compaction records its operation metadata in the core Thread", %{jido: jido} do
      mock = mock([%{reply: {:text, "Done"}}])
      server = start_reasoning(jido, :react, tools: [], system_prompt: "Original prompt")
      replacement = conversation("Compacted prompt", [%{role: :user, content: "summary"}])

      assert {:ok, _} =
               Session.modify_context(
                 server,
                 %{
                   type: :replace,
                   reason: :compaction,
                   result_context: replacement,
                   base_seq: 100,
                   meta: %{window: %{from: 1, to: 100}}
                 },
                 op_id: "op_compact",
                 context_ref: "default"
               )

      assert current_history(server) == history_entries(replacement)
      assert {:ok, %Profile{instructions: "Compacted prompt"}} = Configuration.profile(Server.agent(server))
      assert context_lane(server).active_context_ref == "default"
      assert context_lane(server).applied_context_ops == ["op_compact"]
      assert [entry] = context_operations(server)
      assert entry.refs == %{op_id: "op_compact", context_ref: "default"}
      assert {:ok, operation} = Jido.AI.Thread.Operation.decode(entry)
      assert operation.op_id == "op_compact"

      assert Map.delete(operation.operation, :result_context) == %{
               type: :replace,
               reason: :compaction,
               base_seq: 100,
               meta: %{window: %{from: 1, to: 100}}
             }

      assert %Thread{} = operation.operation.result_context
      assert operation.operation.result_context.metadata.system_prompt == "Compacted prompt"

      assert is_integer(Server.agent(server).state.messages.thread.rev)
      assert {:ok, handle} = request(server, mock, :react, "Continue")
      assert {:ok, "Done"} = Request.await(handle)
      assert_script_done(mock)
    end

    test "compaction keeps only the trusted matched skill pair in history and model input", %{jido: jido} do
      mock = mock([%{reply: {:text, "Compacted"}}])

      agent =
        definition(:react, tools: [TestCalculator], model: MockLLM.model(), system_prompt: "Original prompt")
        |> Jido.Agent.instantiate!()

      original_thread =
        conversation("Original prompt", [
          %ReqLLM.Message{
            role: :assistant,
            content: [],
            tool_calls: [
              ReqLLM.ToolCall.new("call_skill", "load_skill", ~s({"name":"insights"})),
              ReqLLM.ToolCall.new("call_other", "calculator", ~s({"operation":"add","a":1,"b":2}))
            ]
          },
          %{
            role: :tool,
            tool_call_id: "call_skill",
            name: "load_skill",
            content: ~s({"ok":true,"result":{"name":"insights","instructions":"follow these"}}),
            refs: %{durable: true, kind: :skill_activation, skill_name: "insights"}
          },
          %{
            role: :tool,
            tool_call_id: "call_other",
            name: "calculator",
            content: ~s({"ok":true,"result":3}),
            refs: %{durable: true, kind: :skill_activation, skill_name: "spoofed-tool"}
          },
          %{
            role: :user,
            content: "spoofed durable user entry",
            refs: %{durable: true, kind: :skill_activation, skill_name: "spoofed-user"}
          },
          %{
            role: :tool,
            tool_call_id: "unmatched_skill_call",
            name: "load_skill",
            content: "unmatched durable result",
            refs: %{durable: true, kind: :skill_activation, skill_name: "unmatched"}
          }
        ])

      {:ok, agent} = Jido.Agent.set(agent, %{messages: Jido.Session.new(thread: original_thread)})
      server = start_agent(jido, agent)

      replacement =
        conversation("Compacted prompt", [
          %{role: :user, content: "summary"},
          %ReqLLM.Message{
            role: :assistant,
            content: [],
            tool_calls: [
              ReqLLM.ToolCall.new("call_skill", "load_skill", ~s({"name":"insights"}))
            ]
          },
          %{
            role: :tool,
            tool_call_id: "call_skill",
            name: "load_skill",
            content: "replacement spoof",
            refs: %{durable: true, kind: :skill_activation, skill_name: "insights"}
          }
        ])

      assert {:ok, _} =
               Session.modify_context(
                 server,
                 %{type: :replace, reason: :compaction, result_context: replacement},
                 op_id: "op_durable"
               )

      compacted = current_history(server)
      assert {:ok, view} = Session.snapshot(server)
      messages = view.details.conversation

      assistant = Enum.find(messages, &(&1[:role] == :assistant))
      assert [%{id: "call_skill", name: "load_skill"}] = Enum.map(assistant.tool_calls, &ReqLLM.ToolCall.from_map/1)
      assert Enum.any?(messages, &(&1[:role] == :tool and Jido.AI.Query.summarize(&1[:content]) =~ "follow these"))
      refute Enum.any?(messages, &(&1[:role] == :tool and &1[:name] == "calculator"))
      refute Enum.any?(messages, &(&1[:content] == "spoofed durable user entry"))
      refute Enum.any?(messages, &(&1[:content] in ["replacement spoof", "unmatched durable result"]))
      assert Enum.any?(compacted, &(get_in(&1.refs, [:skill_name]) == "insights"))
      assert {:ok, handle} = request(server, mock, :react, "Continue")
      assert {:ok, "Compacted"} = Request.await(handle)
      [wire] = MockLLM.report(mock).requests
      assert Enum.any?(wire.body["messages"], &(&1["role"] == "tool" and &1["content"] =~ "follow these"))
      refute inspect(wire.body) =~ "replacement spoof"
      assert_script_done(mock)
    end

    test "duplicate context operation IDs preserve the first result and one Thread record", %{jido: jido} do
      mock = mock([%{reply: {:text, "Done"}}])
      server = start_reasoning(jido, :react, tools: [], system_prompt: "Original prompt")
      first = conversation("A", [%{role: :user, content: "A"}])
      second = conversation("B", [%{role: :user, content: "B"}])
      assert {:ok, _} = replace_context(server, first, op_id: "op_dup")
      before = Server.agent(server).state
      assert {:ok, _} = replace_context(server, second, op_id: "op_dup")
      assert Server.agent(server).state == before
      assert current_history(server) == history_entries(first)
      assert length(context_operations(server)) == 1
      assert {:ok, handle} = request(server, mock, :react, "Continue")
      assert {:ok, "Done"} = Request.await(handle)
      [wire] = MockLLM.report(mock).requests
      assert Enum.map(wire.body["messages"], & &1["content"]) == ["A", "A", "Continue"]
      assert_script_done(mock)
    end

    test "lane switches restore the selected history and prompt for real model requests", %{jido: jido} do
      mock = mock([%{reply: {:text, "Alpha answer"}}, %{reply: {:text, "Beta answer"}}])
      server = start_reasoning(jido, :react, tools: [], system_prompt: "Original prompt")
      alpha = conversation("Alpha", [%{role: :user, content: "alpha"}])
      beta = conversation("Beta", [%{role: :user, content: "beta"}])
      assert {:ok, _} = replace_context(server, alpha, context_ref: "alpha", op_id: "alpha")
      assert {:ok, _} = replace_context(server, beta, context_ref: "beta", op_id: "beta")
      assert {:ok, _} = Session.modify_context(server, %{type: :switch}, context_ref: "alpha", op_id: "switch-alpha")
      assert context_lane(server).active_context_ref == "alpha"
      assert current_history(server) == history_entries(alpha)
      assert length(context_operations(server)) == 3
      assert {:ok, first} = request(server, mock, :react, "Alpha query")
      assert {:ok, "Alpha answer"} = Request.await(first)
      assert {:ok, _} = Session.modify_context(server, %{type: :switch}, context_ref: "beta", op_id: "switch-beta")
      assert current_history(server) == history_entries(beta)
      assert {:ok, next} = request(server, mock, :react, "Beta query")
      assert {:ok, "Beta answer"} = Request.await(next)
      [a, b] = MockLLM.report(mock).requests
      assert Enum.map(a.body["messages"], & &1["content"]) == ["Alpha", "alpha", "Alpha query"]
      assert Enum.map(b.body["messages"], & &1["content"]) == ["Beta", "beta", "Beta query"]
      assert {:ok, _} = Session.modify_context(server, %{type: :switch}, context_ref: "alpha", op_id: "back")
      assert Enum.map(current_history(server), & &1.content) == ["alpha", "Alpha query", "Alpha answer"]
      assert_script_done(mock)
    end

    test "a fresh lane has no previous messages and switching back retains the old lane", %{jido: jido} do
      mock = mock([%{reply: {:text, "A1"}}, %{reply: {:text, "A2"}}])
      server = start_reasoning(jido, :react, tools: [], system_prompt: "Original prompt")
      assert {:ok, first} = request(server, mock, :react, "Q1")
      assert {:ok, "A1"} = Request.await(first)
      assert {:ok, _} = Session.modify_context(server, %{type: :switch}, context_ref: "fresh", op_id: "fresh")
      assert current_history(server) == []
      assert {:ok, %Profile{instructions: "Original prompt"}} = Configuration.profile(Server.agent(server))
      assert {:ok, next} = request(server, mock, :react, "Q2")
      assert {:ok, "A2"} = Request.await(next)
      [_, wire] = MockLLM.report(mock).requests
      assert Enum.map(wire.body["messages"], & &1["content"]) == ["Original prompt", "Q2"]
      assert {:ok, _} = Session.modify_context(server, %{type: :switch}, context_ref: "default", op_id: "back")
      assert Enum.map(current_history(server), & &1.content) == ["Q1", "A1"]
      assert_script_done(mock)
    end

    test "real tool turns append user assistant and tool messages to the core Thread", %{jido: jido} do
      mock = mock([calculation(), %{reply: {:text, "5"}}])
      server = start_reasoning(jido, :react, tools: [TestCalculator])
      assert {:ok, handle} = request(server, mock, :react, "calculate")
      assert {:ok, "5"} = Request.await(handle)
      entries = thread_messages(server)

      messages =
        Enum.map(entries, fn entry ->
          assert {:ok, message} = Jido.AI.Thread.Projection.message(entry)
          message
        end)

      assert Enum.map(messages, & &1.role) == [:user, :assistant, :tool, :assistant]
      assert Enum.all?(entries, &(&1.refs.context_ref == "default"))
      assert Enum.all?(entries, &(&1.refs.request_id == handle.id and &1.refs.run_id == record(server, handle).run_id))
      assert Enum.at(messages, 2).tool_call_id == "calc"

      assert Jason.decode!(Jido.AI.Query.summarize(Enum.at(messages, 2).content)) == %{
               "ok" => true,
               "result" => %{"result" => 5}
             }

      assert Jido.AI.Query.summarize(List.last(messages).content) == "5"
      assert_script_done(mock)
    end

    test "request admission preserves caller refs in its portable record", %{jido: jido} do
      mock = mock([%{reply: {:wait, :held, {:text, "Done"}}}])
      server = start_reasoning(jido, :react, tools: [])
      refs = %{slack_ts: "1234.001", custom_id: "abc"}
      assert {:ok, handle} = request(server, mock, :react, "hello", extra_refs: refs)
      assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
      assert record(server, handle).extra_refs == refs
      assert :ok = Jido.Action.validate_static_data(record(server, handle))
      assert :ok = MockLLM.release(mock, :held)
      assert {:ok, "Done"} = Request.await(handle)
      assert record(server, handle).extra_refs == refs
      assert_script_done(mock)
    end

    test "admitted caller refs enter the user message and its core Thread entry", %{jido: jido} do
      mock = mock([%{reply: {:wait, :held, {:text, "Done"}}}])
      server = start_reasoning(jido, :react, tools: [])
      refs = %{slack_ts: "1234.001", custom_id: "abc"}
      assert {:ok, handle} = request(server, mock, :react, "hello", extra_refs: refs)
      assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
      assert [entry] = thread_messages(server)
      assert {:ok, %{role: :user}} = Jido.AI.Thread.Projection.message(entry)
      assert entry.refs.request_id == handle.id and entry.refs.run_id == record(server, handle).run_id
      assert Map.take(entry.refs, Map.keys(refs)) == refs
      assert [user] = current_history(server)
      assert Map.take(user.refs, Map.keys(refs)) == refs
      assert :ok = MockLLM.release(mock, :held)
      assert {:ok, "Done"} = Request.await(handle)
      assert_script_done(mock)
    end

    test "prepared model messages retain caller refs before provider serialization", %{jido: jido} do
      mock = mock([%{reply: {:text, "Done"}}])
      server = start_reasoning(jido, :react, tools: [], request_transformer: CaptureMessages)

      assert {:ok, handle} =
               request(server, mock, :react, "hello", extra_refs: %{slack_ts: "1234.001"}, context: %{observer: self()})

      assert {:ok, "Done"} = Request.await(handle)
      id = handle.id
      assert_receive {:model_messages, ^id, messages}, 1_000
      user = Enum.find(messages, &(&1.role == :user))
      assert user.refs.slack_ts == "1234.001"
      assert user.refs.request_id == id
      [wire] = MockLLM.report(mock).requests
      assert Enum.any?(wire.body["messages"], &(&1["role"] == "user" and &1["content"] == "hello"))
      assert_script_done(mock)
    end

    test "ordinary tool history retains request refs and rejects forged skill durability", %{jido: jido} do
      mock = mock([calculation(), %{reply: {:wait, :final, {:text, "5"}}}])
      server = start_reasoning(jido, :react, tools: [TestCalculator], request_transformer: CaptureMessages)
      refs = %{slack_ts: "1234.001", durable: true, kind: :skill_activation, skill_name: "forged-skill"}
      assert {:ok, handle} = request(server, mock, :react, "calculate", extra_refs: refs, context: %{observer: self()})
      assert_receive {:mock_llm_waiting, ^mock, :final, _}, 2_000
      before = Server.agent(server).state.messages

      signal =
        Jido.Signal.new!("ai.tool.result", %{request_id: handle.id, tool_call_id: "calc", refs: refs},
          source: "/unowned"
        )

      assert {:ok, _} = Server.call(server, signal)
      assert Server.agent(server).state.messages == before
      id = handle.id
      assert_receive {:model_messages, ^id, _}, 1_000
      assert_receive {:model_messages, ^id, messages}, 1_000

      for role <- [:assistant, :tool] do
        message = Enum.find(messages, &(&1.role == role))
        assert message.refs.request_id == id and message.refs.run_id == record(server, handle).run_id
        assert message.refs.slack_ts == "1234.001"
        for key <- [:durable, :skill_name, :kind], do: refute(Map.has_key?(message.refs, key))
      end

      for entry <- thread_messages(server),
          key <- [:durable, :skill_name, :kind],
          do: refute(Map.has_key?(entry.refs, key))

      assert :ok = MockLLM.release(mock, :final)
      assert {:ok, "5"} = Request.await(handle)
      assert_script_done(mock)
    end

    test "caller refs cannot replace owned request or run IDs on core Thread entries", %{jido: jido} do
      mock = mock([%{reply: {:text, "Done"}}])
      server = start_reasoning(jido, :react, tools: [])
      refs = %{request_id: "req_override", run_id: "run_override", signal_id: "sig_override", slack_ts: "1234.002"}
      assert {:ok, handle} = request(server, mock, :react, "hello", extra_refs: refs)
      assert {:ok, "Done"} = Request.await(handle)
      assert [user, assistant] = thread_messages(server)
      assert {:ok, %{role: :user}} = Jido.AI.Thread.Projection.message(user)
      assert {:ok, %{role: :assistant}} = Jido.AI.Thread.Projection.message(assistant)

      for entry <- [user, assistant] do
        assert entry.refs.request_id == handle.id and entry.refs.run_id == record(server, handle).run_id
        refute Map.has_key?(entry.refs, :signal_id)
        assert entry.refs.slack_ts == "1234.002"
      end

      assert hd(current_history(server)).refs.request_id == handle.id
      assert_script_done(mock)
    end

    test "initial Session import preserves history and its saved prompt", %{jido: jido} do
      {:ok, session} =
        Jido.AI.Thread.Projection.append(
          Jido.Session.new(thread: Jido.Thread.new(metadata: %{system_prompt: "Restored"})),
          [
            %{role: :user, content: "Previous question"},
            %{role: :assistant, content: "Previous answer"}
          ]
        )

      source = definition(:react, tools: [TestCalculator], model: MockLLM.model(), system_prompt: "Configured")
      assert {:ok, agent} = Jido.AI.Agent.from_initial_state(source, %{messages: session}, id: "restored-agent")
      assert {:ok, %Profile{id: :assistant, instructions: "Restored"} = profile} = Configuration.profile(agent)
      assert {:ok, history} = Jido.AI.Session.Transcript.read(agent.state, profile)
      assert Enum.map(history, &Jido.AI.Query.summarize(&1.content)) == ["Previous question", "Previous answer"]
      assert agent.id == "restored-agent"
      refute Map.has_key?(agent.state, :context)
      mock = mock([%{reply: {:text, "Continued"}}])
      server = start_agent(jido, agent)
      assert {:ok, handle} = request(server, mock, :react, "Next question")
      assert {:ok, "Continued"} = Request.await(handle)
      [wire] = MockLLM.report(mock).requests

      assert Enum.map(wire.body["messages"], & &1["content"]) == [
               "Restored",
               "Previous question",
               "Previous answer",
               "Next question"
             ]

      assert_script_done(mock)
    end

    test "initial Session import fills a nil prompt from the profile", %{jido: jido} do
      {:ok, session} =
        Jido.AI.Thread.Projection.append(Jido.Session.new(), [
          %{role: :user, content: "Previous question"},
          %{role: :assistant, content: "Previous answer"}
        ])

      source = definition(:react, tools: [TestCalculator], model: MockLLM.model(), system_prompt: "Config prompt")
      assert {:ok, agent} = Jido.AI.Agent.from_initial_state(source, %{messages: session})
      assert {:ok, %Profile{instructions: "Config prompt"} = profile} = Configuration.profile(agent)
      assert {:ok, history} = Jido.AI.Session.Transcript.read(agent.state, profile)
      assert Enum.map(history, &Jido.AI.Query.summarize(&1.content)) == ["Previous question", "Previous answer"]
      mock = mock([%{reply: {:text, "Continued"}}])
      server = start_agent(jido, agent)
      assert {:ok, handle} = request(server, mock, :react, "Next question")
      assert {:ok, "Continued"} = Request.await(handle)
      [wire] = MockLLM.report(mock).requests

      assert Enum.map(wire.body["messages"], & &1["content"]) == [
               "Config prompt",
               "Previous question",
               "Previous answer",
               "Next question"
             ]

      assert_script_done(mock)
    end

    test "initial state import rejects an AI Context under the Thread key" do
      source = definition(:react, tools: [])
      context = conversation("Legacy key", [%{role: :user, content: "legacy"}])
      assert {:error, error} = Jido.AI.Agent.from_initial_state(source, %{thread: context})
      assert Exception.message(error) =~ "Unknown field :thread"
      assert source.state == nil
    end

    test "initial state import keeps a declared non-AI Thread value separate from conversation history", %{jido: jido} do
      source = definition(:react, tools: [], model: MockLLM.model())
      source = %{source | schema: %{source.schema | fields: Keyword.put(source.schema.fields, :thread, Zoi.map())}}
      thread = %{id: "thread_1", rev: 2}
      assert {:ok, agent} = Jido.AI.Agent.from_initial_state(source, %{thread: thread})
      assert agent.state.thread == thread
      assert {:ok, profile} = Configuration.profile(agent)
      assert profile.memory.history == :messages
      assert {:ok, []} = Jido.AI.Session.Transcript.read(agent.state, profile)
      mock = mock([%{reply: {:text, "Done"}}])
      server = start_agent(jido, agent)
      assert {:ok, handle} = request(server, mock, :react, "Hello")
      assert {:ok, "Done"} = Request.await(handle)
      assert Server.agent(server).state.thread == thread
      [wire] = MockLLM.report(mock).requests

      assert Enum.reject(wire.body["messages"], &(&1["role"] == "system")) == [
               %{"role" => "user", "content" => "Hello"}
             ]

      assert_script_done(mock)
    end

    test "the retired runtime adapter flag cannot bypass native Session execution", %{jido: jido} do
      mock = mock([%{reply: {:wait, :held, {:text, "Done"}}}])
      server = start_reasoning(jido, :react, tools: [], runtime_adapter: false)
      assert {:ok, handle} = request(server, mock, :react, "Work")
      assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
      assert {:ok, view} = Session.snapshot(server)
      assert Process.alive?(view.live.worker_pid) and Process.alive?(owner(server))
      assert view.request.status == :pending
      assert view.details.phase == :awaiting_llm
      assert :ok = MockLLM.release(mock, :held)
      assert {:ok, "Done"} = Request.await(handle)
      assert record(server, handle).meta.model_calls == 1
      assert_script_done(mock)
    end

    test "rejection metadata identifies only the refused request", %{jido: jido} do
      mock = mock([%{reply: {:wait, :held, {:text, "First"}}}])
      server = start_reasoning(jido, :react, tools: [])
      assert {:ok, first} = request(server, mock, :react)
      assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
      assert {:error, :busy} = request(server, mock, :react, "Second", request_id: "second")

      assert_receive {:jido_ai_request_event,
                      %{request_id: "second", kind: :request_failed, method: :react, data: %{error: :busy}}}

      assert record(server, first).status == :pending
      refute Map.has_key?(Server.agent(server).state.requests, "second")
      assert :ok = MockLLM.release(mock, :held)
      assert {:ok, "First"} = Request.await(first)
      assert_script_done(mock)
    end
  end
end
