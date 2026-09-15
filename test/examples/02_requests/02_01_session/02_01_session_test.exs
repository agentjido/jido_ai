defmodule JidoAI.Examples.SessionTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Request, Session}
  alias Jido.AI.Request.Stream
  alias JidoAI.Examples.Session.Agent

  # The Audit Plugin also counts independent observation Signal commits.
  # A rejected command must preserve domain data and complete request records.
  defp request_state(server),
    do: server |> Server.agent() |> Map.fetch!(:state) |> Map.delete(:commits)

  defp session_definition(changes \\ %{}, schema \\ Agent.domain_schema()) do
    profile = Jido.AI.Agent.profile(Agent, :assistant) |> Map.from_struct()

    profile = %{
      profile
      | controls: Map.put(profile.controls, :input, [JidoAI.Examples.Session.ObserveOwner]),
        tools:
          profile.tools ++
            [%{name: "wait", target: JidoAI.Examples.AIRuntime.WaitTool, forward_context: [:observer], timeout: 8_000}]
    }

    profile = Map.merge(profile, changes)

    base = %{
      name: "source_session",
      schema: schema,
      plugins: [JidoAI.Examples.Support.CommitCounter],
      routes: [
        {"ai.ask", Jido.AI.Authoring.ai(:assistant)},
        {"case.close", JidoAI.Examples.Support.CloseCase}
      ]
    }

    {:ok, definition} = Jido.AI.Authoring.lower(base, [profile])
    {definition, base, profile}
  end

  defp streaming_server(jido, changes \\ %{}, schema \\ Agent.domain_schema()) do
    {definition, _, _} =
      session_definition(Map.put(changes, :requests, %{mode: :session, streaming: true}), schema)

    start_agent(jido, Jido.Agent.instantiate!(definition))
  end

  defp start_fixture(jido) do
    {definition, _, _} = session_definition()
    start_agent(jido, Jido.Agent.instantiate!(definition))
  end

  test "the authored session runs without test controls or blocking tools", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Ready"}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Help", context: context)
    assert {:ok, "Ready"} = Request.await(request)
    assert_script_done(mock)
  end

  @tag history_case: "HIST-07/public-stream"
  test "admission commits before work and the final Turn preserves intervening domain changes", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:wait, :answer, {:text, "Done"}}}])
    server = start_fixture(jido)
    assert {:ok, request, events} = Agent.ask_stream(server, "Work", context: context)
    id = request.id
    assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000

    assert %{
             state: %{
               requests: %{^id => %{status: :pending}},
               reply: "",
               commits: admission_commits
             }
           } =
             Server.agent(server)

    # Observation batches also pass through the core commit and Plugin path.
    assert admission_commits >= 1
    assert {:ok, %{state: %{commits: close_commits}}} = Agent.close(server, "closed")
    assert close_commits > admission_commits
    assert :ok = MockLLM.release(mock, :answer)
    assert {:ok, "Done"} = Request.await(request)
    events = Enum.to_list(events)

    assert Enum.map(events, & &1.kind) == [
             :request_started,
             :llm_started,
             :llm_completed,
             :request_completed
           ]

    assert Enum.map(events, & &1.seq) == [1, 2, 3, 4]
    assert Enum.all?(events, &(&1.request_id == id))

    assert %{state: %{reply: "Done", case_id: "closed", commits: final_commits} = state} =
             Server.agent(server)

    assert final_commits > close_commits
    assert :ok = Jido.Action.validate_static_data(state)
    assert state.requests[id].meta.model_calls == 1
    assert_script_done(mock)
  end

  test "busy and duplicate IDs reject before work and preserve the first stream", %{jido: jido} do
    {mock, context} = mock([%{reply: {:wait, :answer, {:text, "First"}}}])
    server = start_fixture(jido)

    assert {:ok, first, events} =
             Agent.ask_stream(server, "First", context: context, request_id: "first")

    assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000
    before = request_state(server)

    assert {:error, :busy} =
             Agent.ask(server, "Second",
               context: context,
               request_id: "second",
               stream_to: self()
             )

    assert_receive {:jido_ai_request_event,
                    %{
                      request_id: "second",
                      kind: :request_failed,
                      data: %{error: :busy}
                    }}

    assert {:error, %{details: %{reason: :duplicate_request}}} =
             Agent.ask(server, "Again", context: context, request_id: "first", stream_to: self())

    assert request_state(server) == before
    MockLLM.release(mock, :answer)
    assert {:ok, "First"} = Request.await(first)
    assert Enum.count(events, &Stream.terminal_kind?(&1.kind)) == 1
    assert_script_done(mock)
  end

  @tag history_case: "HIST-07/consumer-timeout"
  test "caller and consumer timeouts leave the accepted work alive", %{jido: jido} do
    {mock, context} = mock([%{reply: {:wait, :answer, {:text, "Later"}}}])
    server = start_fixture(jido)

    assert {:ok, request, events} =
             Agent.ask_stream(server, "Work", context: context, stream_event_timeout_ms: 10)

    assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000
    assert {:error, :timeout} = Request.await(request, timeout: 10)
    assert Enum.all?(Enum.to_list(events), &(not Stream.terminal_kind?(&1.kind)))
    assert :ok = MockLLM.release(mock, :answer)
    assert {:ok, "Later"} = Request.await(request)
    assert_script_done(mock)
  end

  test "cancellation stops a held real tool and cannot stop the next request", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:tools, [%{id: "held", name: "wait", arguments: %{n: 1}}]}},
        %{reply: {:text, "Next"}}
      ])

    server = start_fixture(jido)
    assert {:ok, request, events} = Agent.ask_stream(server, "Wait", context: context)
    assert_receive {:tool_waiting, worker, 1}, 2_000
    monitor = Process.monitor(worker)
    assert :ok = Session.cancel(request)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
    assert {:error, :cancelled} = Request.await(request)
    assert Enum.count(events, &(&1.kind == :request_cancelled)) == 1
    assert Server.agent(server).state.requests[request.id].meta.usage.total_tokens > 0
    assert {:ok, next} = Agent.ask(server, "Next", context: context)
    assert {:error, %{details: %{reason: :request_already_finished}}} = Session.cancel(request)
    assert {:ok, "Next"} = Request.await(next)
    assert_script_done(mock)
  end

  test "a runtime crash interrupts portable requests and fresh resources serve the next request",
       %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:tools, [%{id: "held", name: "wait", arguments: %{n: 2}}]}},
        %{reply: {:text, "Recovered"}}
      ])

    server = start_fixture(jido)
    assert {:ok, request} = Agent.ask(server, "Wait", context: context, stream_to: self())
    id = request.id
    assert_receive {:session_owner, owner, ^id}, 2_000
    assert_receive {:tool_waiting, worker, 2}, 2_000
    monitor = Process.monitor(worker)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
    assert {:error, :stream_interrupted} = Request.await(request)
    assert {:ok, next} = Agent.ask(server, "Next", context: context)
    assert {:ok, "Recovered"} = Request.await(next)
    next_id = next.id
    assert_receive {:session_owner, next_owner, ^next_id}
    refute owner == next_owner
    assert_script_done(mock)
  end

  test "untrusted completion input cannot publish a result", %{jido: jido} do
    {mock, context} = mock([%{reply: {:wait, :answer, {:text, "Real"}}}])
    server = start_fixture(jido)
    {:ok, request} = Agent.ask(server, "Work", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000
    before = request_state(server)

    assert {:error, %{details: %{reason: :stale_request}}} =
             Server.call(server, Session.settle_signal(request.id),
               context: %{jido_ai_completion: %{outcome: {:ok, %{result: "Fake", meta: %{}}}}}
             )

    assert request_state(server) == before
    MockLLM.release(mock, :answer)
    assert {:ok, "Real"} = Request.await(request)
    assert_script_done(mock)
  end

  test "invalid sinks and unsupported options reject before admission", %{jido: jido} do
    {mock, context} = mock([])
    server = start_fixture(jido)
    before = Server.snapshot(server)

    assert {:error, {:invalid_stream_to, :invalid}} =
             Agent.ask(server, "Work", context: context, stream_to: :invalid)

    assert {:error, _} =
             Agent.ask(server, "Work", context: context, request_transformer: __MODULE__)

    assert Server.snapshot(server) == before
    assert_script_done(mock)
  end

  test "media query, model options, refs and real tool output reach the provider", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:tools, [%{id: "multiply", name: "multiply", arguments: %{a: 3, b: 4}}]}},
        %{reply: {:text, "Twelve"}}
      ])

    server = start_fixture(jido)

    observe_tools()

    query = [
      ReqLLM.Message.ContentPart.text("Read this"),
      ReqLLM.Message.ContentPart.image_url("https://example.com/image.png")
    ]

    {:ok, request} =
      Agent.ask(server, query,
        context: context,
        llm_opts: %{temperature: 0.3},
        extra_refs: %{case: "42"}
      )

    assert {:ok, "Twelve"} = Request.await(request)
    assert_receive {:example_tool_started, "multiply"}
    [first, second] = MockLLM.report(mock).requests
    assert first.body["temperature"] == 0.3
    assert List.last(first.body["messages"])["content"] |> Enum.any?(&(&1["type"] == "image_url"))

    assert Enum.any?(
             second.body["messages"],
             &(&1["role"] == "tool" and &1["tool_call_id"] == "multiply")
           )

    assert {:ok, %{request: saved}} = Session.snapshot(server, request_id: request.id)
    assert saved.extra_refs == %{case: "42"}
    assert saved.result == "Twelve"
    assert_script_done(mock)
  end

  test "completed requests have bounded retention and await_many keeps input order", %{jido: jido} do
    {mock, context} = mock(for text <- ["One", "Two", "Three"], do: %{reply: {:text, text}})
    server = start_fixture(jido)

    requests =
      for text <- ["One", "Two", "Three"] do
        {:ok, request} = Agent.ask(server, text, context: context)
        assert {:ok, ^text} = Request.await(request)
        request
      end

    [old, two, three] = requests
    assert {:error, :request_not_found} = Request.await(old)
    assert [{:ok, "Three"}, {:ok, "Two"}] = Request.await_many([three, two], timeout: :infinity)
    assert {:ok, records} = Server.plugin_state(server, Session.Plugin)
    assert map_size(records) == 2
    assert_script_done(mock)
  end

  @tag history_case: "HIST-01/stream-headers"
  test "real SSE text and request headers precede the final commit", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:stream, [%{content: "First "}, {:wait, :middle}, %{content: "last"}]}}])

    server = streaming_server(jido)

    assert {:ok, request} =
             Agent.ask(server, "Stream",
               context: context,
               stream_to: self(),
               req_http_options: [headers: [{"x-case", "session-stream"}], retry: false]
             )

    id = request.id
    assert_receive {:mock_llm_waiting, ^mock, :middle, _}, 2_000

    assert_receive {:jido_ai_request_event, %{request_id: ^id, kind: :llm_delta, data: %{delta: "First "}} = delta},
                   2_000

    assert is_binary(delta.llm_call_id)
    assert delta.iteration == 1
    assert Server.agent(server).state.reply == ""
    MockLLM.release(mock, :middle)
    assert {:ok, "First last"} = Request.await(request)
    assert [wire] = MockLLM.report(mock).requests
    assert wire.body["stream"] == true
    assert wire.headers["x-case"] == "session-stream"
    assert_script_done(mock)
  end

  test "a disconnect after visible text fails without publishing partial output", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:stream, [%{content: "Partial"}, {:wait, :break}, :disconnect]}}])

    server = streaming_server(jido)
    {:ok, request} = Agent.ask(server, "Stream", context: context, stream_to: self())
    id = request.id
    assert_receive {:mock_llm_waiting, ^mock, :break, _}, 2_000

    assert_receive {:jido_ai_request_event, %{request_id: ^id, kind: :llm_delta, data: %{delta: "Partial"}}},
                   2_000

    MockLLM.release(mock, :break)
    assert {:error, _} = Request.await(request)
    assert Server.agent(server).state.reply == ""
    events = request |> Stream.events(stream_event_timeout_ms: 1_000) |> Enum.to_list()
    assert List.last(events).kind == :request_failed
    assert Enum.count(events, &Stream.terminal_kind?(&1.kind)) == 1
    assert_script_done(mock)
  end

  test "SSE cancellation closes provider resources before the next request", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:stream, [%{content: "Partial"}, {:wait, :cancel}]}},
        %{reply: {:text, "Next stream"}}
      ])

    server = streaming_server(jido)
    {:ok, request} = Agent.ask(server, "Stream", context: context, stream_to: self())
    assert_receive {:mock_llm_waiting, ^mock, :cancel, worker}, 2_000
    monitor = Process.monitor(worker)
    assert :ok = Session.cancel(request)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
    assert_receive {:mock_llm_closed, ^mock, ^worker}, 2_000
    assert {:error, :cancelled} = Request.await(request)
    {:ok, next} = Agent.ask(server, "Next", context: context)
    assert {:ok, "Next stream"} = Request.await(next)
    assert_script_done(mock)
  end

  test "streamed tool calls execute once and event IDs follow the model rounds", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:tools, [%{id: "multiply", name: "multiply", arguments: %{a: 6, b: 7}}]}},
        %{reply: {:text, "Forty-two"}}
      ])

    server = streaming_server(jido)
    observe_tools()
    {:ok, request, events} = Agent.ask_stream(server, "Calculate", context: context)
    assert {:ok, "Forty-two"} = Request.await(request)
    assert_receive {:example_tool_started, "multiply"}
    refute_received {:example_tool_started, "multiply"}
    events = Enum.to_list(events)
    assert Enum.map(events, & &1.seq) == Enum.to_list(1..length(events))
    starts = Enum.filter(events, &(&1.kind == :llm_started))
    assert Enum.map(starts, & &1.iteration) == [1, 2]
    assert length(Enum.uniq_by(starts, & &1.llm_call_id)) == 2
    assert Enum.count(events, &(&1.kind == :tool_completed and &1.tool_call_id == "multiply")) == 1
    assert_script_done(mock)
  end

  test "streamed objects use the provider schema and the common result validator", %{jido: jido} do
    {mock, context} = mock([%{reply: {:object, %{answer: "Typed"}}}])

    schema =
      Zoi.object(%{
        reply: Zoi.map() |> Zoi.default(%{}),
        case_id: Zoi.string() |> Zoi.default("open")
      })

    result = %{schema: Zoi.object(%{answer: Zoi.string()}), into: :reply}
    server = streaming_server(jido, %{tools: [], result: result}, schema)
    {:ok, request} = Agent.ask(server, "Object", context: context)
    assert {:ok, %{answer: "Typed"}} = Request.await(request)
    assert [wire] = MockLLM.report(mock).requests
    assert wire.body["stream"] == true
    assert wire.body["response_format"]["type"] == "json_schema"
    assert_script_done(mock)
  end

  test "a result that violates the domain schema becomes a committed failure", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Wrong shape"}}])

    schema =
      Zoi.object(%{
        reply: Zoi.map() |> Zoi.default(%{}),
        case_id: Zoi.string() |> Zoi.default("open")
      })

    server = streaming_server(jido, %{}, schema)
    {:ok, request} = Agent.ask(server, "Work", context: context)
    assert {:error, :invalid_domain_result} = Request.await(request)
    assert Server.agent(server).state.reply == %{}
    assert_script_done(mock)
  end

  test "restored request records reject runtime resources and mismatched IDs" do
    schema = Session.Record.records_schema()
    assert {:error, _} = Zoi.parse(schema, %{"bad" => %{stream_to: self()}})

    record = %{
      id: "different",
      run_id: "run",
      profile_id: :assistant,
      query: "Work",
      status: :pending,
      inserted_at: 1,
      completed_at: nil,
      streamed: false,
      max_requests: 2
    }

    assert {:error, _} = Zoi.parse(schema, %{"bad" => record})

    assert {:error, _} =
             Zoi.parse(schema, %{"different" => Map.put(record, :extra_refs, %{resource: self()})})
  end

  test "DSL, source profiles, source JSON and Builder use the same session targets", %{jido: jido} do
    {definition, base, profile} =
      session_definition(Jido.AI.Agent.profile(Agent, :assistant) |> Map.from_struct())

    assert definition.plugins == Agent.definition().plugins
    assert definition.routes == Agent.definition().routes
    attrs = definition |> Map.from_struct() |> Map.drop([:id, :state])
    assert {:ok, ^definition} = attrs |> Jido.Agent.Builder.new() |> Jido.Agent.Builder.build()

    atoms = [
      :id,
      :instructions,
      :models,
      :reasoning,
      :controls,
      :tools,
      :result,
      :requests,
      :routes,
      :assistant,
      :answer,
      :model,
      :generation,
      :method,
      :react,
      :tool_concurrency,
      :input,
      :operation,
      :output,
      :max_iterations,
      :max_model_calls,
      :max_tool_calls,
      :timeout,
      :into,
      :reply,
      :schema,
      :max_repairs,
      :mode,
      :session,
      :on_busy,
      :reject,
      :max_requests,
      :streaming,
      :steering,
      :memory,
      :observability,
      :effect_policy,
      :history,
      :name,
      :target,
      :description,
      :forward_context,
      :observer,
      JidoAI.Examples.Session.ObserveOwner,
      JidoAI.Examples.Support.Multiply,
      JidoAI.Examples.AIRuntime.WaitTool
    ]

    registry =
      atoms
      |> Kernel.++(profile_atoms(profile))
      |> Enum.uniq()
      |> Map.new(&{"atoms/#{&1}", {:atom, &1}})
      |> Map.put("model/answer", {:value, profile.models.answer.model})

    assert {:ok, document} = Jido.AI.Authoring.Codec.encode([profile], registry)
    document = document |> Jason.encode!() |> Jason.decode!()
    assert {:ok, ^definition} = Jido.AI.Authoring.Codec.decode(base, document, registry)
    {mock, context} = mock([%{reply: {:text, "Imported session"}}])
    server = start_agent(jido, Jido.Agent.instantiate!(definition))
    {:ok, request} = Agent.ask(server, "Imported", context: context)
    assert {:ok, "Imported session"} = Request.await(request)
    assert_script_done(mock)
  end

  test "Signal profile input cannot replace the declared session route binding", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Bound"}}])
    server = start_fixture(jido)

    signal =
      Jido.Signal.new!("ai.ask", %{request_id: "bound", query: "Work", profile_id: :unknown}, source: "/example")

    assert {:ok, %{state: %{requests: %{"bound" => %{profile_id: :assistant}}}}} =
             Server.call(server, signal, context: context)

    request = Request.Handle.new("bound", server, "Work")
    assert {:ok, "Bound"} = Request.await(request)
    assert_script_done(mock)
  end

  test "Agent shutdown stops held tool work", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:tools, [%{id: "held", name: "wait", arguments: %{n: 9}}]}}])

    server = start_fixture(jido)
    {:ok, _request} = Agent.ask(server, "Wait", context: context)
    assert_receive {:tool_waiting, worker, 9}, 2_000
    monitor = Process.monitor(worker)
    assert :ok = Server.stop(server)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
    assert_script_done(mock)
  end

  @tag history_case: "HIST-05/unloaded-action"
  test "a compiled generated Action loads in a fresh runtime and executes as a session tool" do
    dir = Path.join(System.tmp_dir!(), "jido_ai_unloaded_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    [{module, beam}] =
      Code.compile_string("""
      defmodule JidoAI.Examples.UnloadedTool do
        use Jido.Action, name: "generated", schema: Zoi.object(%{n: Zoi.integer()})
        def run(%{n: n}, _), do: {:ok, %{value: n * 2}}
      end
      """)

    File.write!(Path.join(dir, "#{module}.beam"), beam)
    :code.purge(module)
    :code.delete(module)

    {output, status} =
      System.cmd(
        "mix",
        ["run", "--no-compile", "--no-deps-check", "test/examples/support/unloaded_tool_session.exs", dir],
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "test"}]
      )

    assert status == 0, output
    assert output =~ "UNLOADED_TOOL_SESSION_OK"
  end

  for reason <- ["incomplete", "error", "cancelled", "length", "content_filter"] do
    @tag history_case: "HIST-06/blank-terminal"
    test "a blank SSE response with #{reason} does not complete and retains usage", %{jido: jido} do
      {mock, context} = mock([%{reply: {:stream, [], unquote(reason)}}])
      server = streaming_server(jido)
      {:ok, request, events} = Agent.ask_stream(server, "Work", context: context)
      assert {:error, _} = Request.await(request)
      record = Server.agent(server).state.requests[request.id]
      assert record.status == :failed
      assert record.meta.usage.total_tokens > 0
      assert Server.agent(server).state.reply == ""
      events = Enum.to_list(events)
      refute Enum.any?(events, &(&1.kind in [:llm_completed, :request_completed]))
      assert List.last(events).kind == :request_failed
      assert_script_done(mock)
    end
  end

  @tag history_case: "HIST-06/accepted-partial"
  test "non-empty incomplete content keeps the accepted legacy result", %{jido: jido} do
    {mock, context} = mock([%{reply: {:stream, [%{content: "Usable partial"}], "incomplete"}}])
    server = streaming_server(jido)
    {:ok, request} = Agent.ask(server, "Work", context: context)
    assert {:ok, "Usable partial"} = Request.await(request)
    assert_script_done(mock)
  end
end
