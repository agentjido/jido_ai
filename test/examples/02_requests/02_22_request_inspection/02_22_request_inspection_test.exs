defmodule JidoAI.Examples.RequestInspectionTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Request, Session}
  alias JidoAI.Examples.RequestInspection.Agent

  defp submit(server, context, opts \\ []) do
    Request.create_and_send(
      server,
      "Inspect this request",
      [signal_type: "case.ask", source: "/examples/inspection", context: context] ++ opts
    )
  end

  defp owner(server), do: Server.children(server)[{:plugin, Session.Plugin}].pid
  defp events(request), do: Enum.to_list(Request.Stream.events(request))

  defp tools,
    do: %{
      reply: {:tools, [%{id: "held", name: "inspect_hold", arguments: %{password: "private", case_id: "one"}}]}
    }

  test "idle inspection uses the core revision and an unknown request is an error", %{jido: jido} do
    server = start_agent(jido, Agent.new!())
    assert {:ok, view} = Session.snapshot(server)
    assert Map.take(view, [:agent, :state_version]) == Server.snapshot(server)
    assert view.details.phase == :idle
    assert view.details.trace.events == []
    assert view.request == nil and view.live == nil
    assert {:error, :request_not_found} = Session.snapshot(server, request_id: "absent")
  end

  test "a held model has live identity and a separate committed request", %{jido: jido} do
    {mock, context} = mock([%{reply: {:wait, :model, {:text, "Done"}}}])
    server = start_agent(jido, Agent.new!())
    {:ok, request} = submit(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :model, _}, 2_000
    assert {:ok, view} = Session.snapshot(server)
    assert view.request.id == request.id
    assert view.request.status == :pending
    assert view.details.phase == :awaiting_llm
    assert view.details.iteration == 1
    assert view.details.model_calls == 1
    assert view.details.model == "openai:gpt-4o-mini"
    assert view.details.current_llm_call_id != nil
    assert view.details.active_request_id == request.id
    assert view.live.request_id == request.id
    assert view.live.run_id == view.request.run_id
    assert is_pid(view.live.worker_pid) and Process.alive?(view.live.worker_pid)
    assert view.live.worker_status == :running
    assert Enum.map(view.details.trace.events, & &1.kind) == [:request_started, :llm_started]
    assert :ok = Jido.Action.validate_static_data(view.agent.state)
    assert List.last(view.details.conversation).content == "Inspect this request"
    :ok = MockLLM.release(mock, :model)
    assert {:ok, "Done"} = Request.await(request)
    assert_script_done(mock)
  end

  test "held tools expose redacted arguments and completed tool results survive the next model",
       %{jido: jido} do
    {mock, context} = mock([tools(), %{reply: {:wait, :final, {:text, "Checked"}}}])
    server = start_agent(jido, Agent.new!())
    {:ok, request} = submit(server, context)
    assert_receive {:inspection_tool, tool}, 2_000
    {:ok, view} = Session.snapshot(server, request_id: request.id)
    assert view.details.phase == :executing_tool

    assert [%{id: "held", name: "inspect_hold", status: :running, arguments: args}] =
             view.details.tool_calls

    assert args == %{"password" => "[REDACTED]", "case_id" => "one"}
    assert view.details.usage.total_tokens == 15
    send(tool, :release)
    assert_receive {:mock_llm_waiting, ^mock, :final, _}, 2_000
    {:ok, view} = Session.snapshot(server)
    assert view.details.tool_calls == []
    assert [%{id: "held", status: :ok}] = view.details.tool_results
    assert view.details.model_calls == 2
    :ok = MockLLM.release(mock, :final)
    assert {:ok, "Checked"} = Request.await(request)
    assert_script_done(mock)
  end

  for {module, streaming?} <- [
        {JidoAI.Examples.RequestInspection.ReplayBuffered, false},
        {JidoAI.Examples.RequestInspection.ReplayStream, true}
      ] do
    test "#{module} keeps tool results and the live phase when a completion is replayed", %{jido: jido} do
      calls = [
        %{id: "held", name: "inspect_hold", arguments: %{case_id: "one"}},
        %{id: "failed", name: "inspect_fail", arguments: %{}}
      ]

      {mock, context} =
        mock([
          %{reply: {:tools, calls}},
          %{reply: {:wait, :final, {:text, "Checked"}}},
          %{reply: {:wait, :next, {:text, "Next"}}}
        ])

      server = start_agent(jido, unquote(module).new!())
      assert {:ok, request} = submit(server, context)
      assert_receive {:inspection_tool, tool}, 2_000
      assert {:ok, held} = Session.snapshot(server)

      assert Enum.find(held.details.tool_calls, &(&1.id == "held")) == %{
               id: "held",
               name: "inspect_hold",
               arguments: %{"case_id" => "one"},
               status: :running,
               result: nil
             }

      send(tool, :release)
      assert_receive {:mock_llm_waiting, ^mock, :final, _}, 2_000
      assert {:ok, before} = Session.snapshot(server)
      replay = Enum.find(before.details.trace.events, &(&1.kind == :tool_completed and &1.tool_call_id == "held"))
      assert replay != nil

      for _ <- 1..2 do
        assert :ok =
                 GenServer.call(
                   owner(server),
                   {:event, request.id, before.request.run_id, :tool_completed, replay.data}
                 )

        assert {:ok, view} = Session.snapshot(server)
        assert view.details.phase == :awaiting_llm
        assert view.details.tool_results == before.details.tool_results
      end

      assert :ok = MockLLM.release(mock, :final)
      assert {:ok, "Checked"} = Request.await(request)
      assert {:ok, done} = Session.snapshot(server)
      assert done.details.phase == :request_completed and done.live == nil
      assert done.details.tool_calls == []

      assert [%{id: "held", result: {:ok, %{checked: true}, []}}, %{id: "failed", result: {:error, error, []}}] =
               done.details.tool_results

      assert error == %{
               type: :timeout,
               message: "search timed out",
               details: %{tool_name: "inspect_fail", tool_call_id: "failed"},
               retryable?: true
             }

      assert :ok =
               GenServer.call(owner(server), {:event, request.id, before.request.run_id, :tool_completed, replay.data})

      assert {:ok, retained} = Session.snapshot(server, request_id: request.id)
      assert retained.request == done.request
      assert {:ok, next} = submit(server, context)
      assert_receive {:mock_llm_waiting, ^mock, :next, _}, 2_000
      assert {:ok, fresh} = Session.snapshot(server)
      assert fresh.details.tool_results == [] and fresh.details.tool_calls == []
      assert {:ok, retained} = Session.snapshot(server, request_id: request.id)
      assert retained.details.tool_results == done.details.tool_results
      assert :ok = MockLLM.release(mock, :next)
      assert {:ok, "Next"} = Request.await(next)
      [_, final_wire, _] = MockLLM.report(mock).requests
      assert Enum.count(final_wire.body["messages"], &(&1["role"] == "tool")) == 2
      assert Enum.all?(MockLLM.report(mock).requests, &(&1.body["stream"] == unquote(streaming?)))
      assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
      refute_receive {:inspection_tool, _}, 30
      assert_script_done(mock)
    end
  end

  test "terminal inspection keeps the observed stream prefix and remains selectable after another request",
       %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "First"}}, %{reply: {:text, "Next"}}])
    server = start_agent(jido, Agent.new!())
    {:ok, first} = submit(server, context, stream_to: self())
    assert {:ok, "First"} = Request.await(first)
    streamed = events(first)
    {:ok, view} = Session.snapshot(server, request_id: first.id)
    assert view.details.trace.events == Enum.take(streamed, view.details.trace.seq)
    assert view.details.trace.scope == :observed_prefix
    assert view.details.phase == :request_completed
    assert view.details.streaming_text == "First"
    assert view.request.result == "First"
    assert view.live == nil
    assert view.details.duration_ms >= 0
    assert view.details.trace.seq == length(streamed) - 1
    refute view.details.trace.truncated?
    {:ok, next} = submit(server, context)
    assert {:ok, "Next"} = Request.await(next)
    {:ok, latest} = Session.snapshot(server)
    assert latest.request.id == next.id
    {:ok, retained} = Session.snapshot(server, request_id: first.id)
    assert retained.request == view.request
    assert retained.details.trace == view.details.trace
    assert map_size(retained.details.trace_summary) == 2
    assert_script_done(mock)
  end

  test "cancellation keeps its raw reason and the observed prefix before commit", %{jido: jido} do
    {mock, context} = mock([%{reply: {:wait, :cancel, {:text, "Unused"}}}])
    server = start_agent(jido, Agent.new!())
    {:ok, request} = submit(server, context, stream_to: self())
    assert_receive {:mock_llm_waiting, ^mock, :cancel, provider}, 2_000
    monitor = Process.monitor(provider)
    assert :ok = Session.cancel(request, reason: :operator_stop)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert {:error, {:cancelled, :operator_stop}} = Request.await(request)
    {:ok, view} = Session.snapshot(server)
    assert view.request.error == {:cancelled, :operator_stop}
    assert view.details.cancel_reason == :operator_stop
    assert view.details.phase == :request_cancelled
    assert view.details.trace.events == Enum.take(events(request), view.details.trace.seq)
    assert view.live == nil
    assert_script_done(mock)
  end

  test "task failure keeps the actual failure and the trace before the task stopped", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:wait, :crash, {:text, "Unused"}}}])
    server = start_agent(jido, Agent.new!())
    {:ok, request} = submit(server, context, stream_to: self())
    assert_receive {:mock_llm_waiting, ^mock, :crash, _}, 2_000
    {:ok, view} = Session.snapshot(server)
    Process.exit(view.live.worker_pid, :kill)
    assert {:error, :worker_crash} = Request.await(request)
    {:ok, failed} = Session.snapshot(server)
    assert failed.request.error == :worker_crash
    assert failed.details.phase == :request_failed
    assert failed.details.trace.events == Enum.take(events(request), failed.details.trace.seq)
    assert failed.details.model_calls == 1
    assert_script_done(mock)
  end

  test "Session recovery retains the last committed trace without live handles or tool replay", %{
    jido: jido
  } do
    {mock, context} = mock([tools(), %{reply: {:wait, :recovery, {:text, "Unused"}}}])
    server = start_agent(jido, Agent.new!())
    {:ok, request} = submit(server, context)
    assert_receive {:inspection_tool, tool}, 2_000
    send(tool, :release)
    assert_receive {:mock_llm_waiting, ^mock, :recovery, _}, 2_000
    before = Server.agent(server).state.requests[request.id]
    assert length(before.inspection.events) > 2
    Process.exit(owner(server), :kill)
    assert {:error, :request_interrupted} = Request.await(request)
    {:ok, restored} = Session.snapshot(server)

    assert Enum.take(restored.details.trace.events, length(before.inspection.events)) ==
             before.inspection.events

    assert restored.details.trace.events == before.inspection.events
    assert restored.details.phase == :request_failed
    assert restored.request.error == :request_interrupted
    assert restored.live == nil
    assert :ok = Jido.Action.validate_static_data(restored.agent.state)
    refute_receive {:inspection_tool, _}, 30
    assert_script_done(mock)
  end

  test "the trace cap keeps the first 2000 events and records overflow without hiding completion",
       %{jido: jido} do
    {mock, context} = mock([%{reply: {:wait, :overflow, {:text, "Done"}}}])
    server = start_agent(jido, Agent.new!())
    {:ok, request} = submit(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :overflow, _}, 2_000
    {:ok, view} = Session.snapshot(server)
    runtime = owner(server)

    for n <- 1..2_010,
        do:
          GenServer.call(
            runtime,
            {:event, request.id, view.request.run_id, :llm_delta, %{delta: "x", chunk_type: :content, n: n}}
          )

    {:ok, active} = Session.snapshot(server)
    assert length(active.details.trace.events) == 2_000
    assert active.details.trace.truncated?
    assert Enum.map(active.details.trace.events, & &1.seq) == Enum.to_list(1..2_000)
    assert active.details.trace.seq == 2_012
    :ok = MockLLM.release(mock, :overflow)
    assert {:ok, "Done"} = Request.await(request)
    {:ok, done} = Session.snapshot(server)
    assert done.details.trace.events == active.details.trace.events
    assert done.details.trace.truncated?
    assert done.details.trace.seq > active.details.trace.seq
    assert done.request.status == :completed
    assert :ok = Jido.Action.validate_static_data(done.agent.state)
    assert_script_done(mock)
  end

  test "wrong-run data cannot enter the live or retained request trace", %{jido: jido} do
    {mock, context} = mock([%{reply: {:wait, :wrong_run, {:text, "Done"}}}])
    server = start_agent(jido, Agent.new!())
    {:ok, request} = submit(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :wrong_run, _}, 2_000
    {:ok, before} = Session.snapshot(server)

    assert :ok =
             GenServer.call(
               owner(server),
               {:event, request.id, "wrong", :llm_delta, %{delta: "forged"}}
             )

    {:ok, after_view} = Session.snapshot(server)
    assert before.details.trace == after_view.details.trace
    :ok = MockLLM.release(mock, :wrong_run)
    assert {:ok, "Done"} = Request.await(request)
    {:ok, done} = Session.snapshot(server)
    refute inspect(done.details.trace) =~ "forged"
    assert_script_done(mock)
  end

  test "decoded thinking stays with its model call and terminal inspection", %{jido: jido} do
    reply =
      {:raw,
       %{
         id: "inspection-thinking",
         object: "chat.completion",
         model: "gpt-4o-mini",
         choices: [
           %{
             index: 0,
             finish_reason: "stop",
             message: %{
               role: "assistant",
               content: "Checked",
               reasoning_content: "Synthetic inspection thought"
             }
           }
         ],
         usage: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15}
       }}

    {mock, context} = mock([%{reply: reply}])
    server = start_agent(jido, Agent.new!())
    {:ok, request} = submit(server, context)
    assert {:ok, "Checked"} = Request.await(request)
    {:ok, view} = Session.snapshot(server)
    assert view.details.streaming_text == "Checked"
    assert view.details.streaming_thinking == "Synthetic inspection thought"

    assert [%{call_id: call_id, iteration: 1, thinking: "Synthetic inspection thought"}] =
             view.details.thinking_trace

    assert call_id == view.details.current_llm_call_id
    assert Enum.any?(view.details.trace.events, &(&1.kind == :llm_completed))
    assert_script_done(mock)
  end

  test "terminal inspection works without conversation history", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "No history"}}])
    server = start_agent(jido, JidoAI.Examples.ContextViews.Stateless.new!())
    {:ok, request} = submit(server, context)
    assert {:ok, "No history"} = Request.await(request)
    {:ok, view} = Session.snapshot(server)
    assert view.request.result == "No history"
    assert view.details.conversation == []

    assert Enum.map(view.details.trace.events, & &1.kind) == [
             :request_started,
             :llm_started,
             :llm_completed
           ]

    assert_script_done(mock)
  end

  test "a stored terminal trace survives a lost completion reply and a new Agent Server", %{
    jido: jido
  } do
    alias JidoAI.Examples.Completion.Store
    {mock, context} = mock([%{reply: {:text, "Stored answer"}}])
    store = start_supervised!(Store)
    instance = Agent.new!()
    adapter = {Store, store: store, failure: :indeterminate}
    {:ok, server} = Jido.start_agent(jido, instance, persistence: adapter, restore: false)
    monitor = Process.monitor(server)
    {:ok, request} = submit(server, context)
    assert_receive {:DOWN, ^monitor, :process, ^server, _}, 2_000

    assert {:ok, restored, revision} =
             Jido.Persistence.load_agent_with_revision(adapter, Agent, instance.id, instance: jido)

    # The indeterminate write stored revision 3. The safety retry then saw the
    # newer value and added one rejected write attempt.
    assert revision + 1 == Store.writes(store)
    saved = restored.state.requests[request.id]
    assert saved.status == :completed
    assert length(saved.inspection.events) == 3
    assert :ok = Jido.Action.validate_static_data(saved)
    next_server = start_agent(jido, restored)
    {:ok, view} = Session.snapshot(next_server, request_id: request.id)
    assert view.request == saved
    assert view.details.trace.events == saved.inspection.events
    assert view.live == nil
    assert view.request.result == "Stored answer"
    assert_script_done(mock)
  end

  test "a refused completion leaves the durable request pending when the server stops", %{
    jido: jido
  } do
    alias JidoAI.Examples.Completion.Store
    {mock, context} = mock([%{reply: {:text, "Refused answer"}}])
    store = start_supervised!(Store)
    adapter = {Store, store: store, failure: :conflict}
    instance = Agent.new!()
    {:ok, server} = Jido.start_agent(jido, instance, persistence: adapter, restore: false)
    monitor = Process.monitor(server)
    {:ok, request} = submit(server, context)
    assert {:error, :agent_server_unavailable} = Request.await(request)
    assert_receive {:DOWN, ^monitor, :process, ^server, _}, 2_000

    assert {:ok, restored, _revision} =
             Jido.Persistence.load_agent_with_revision(adapter, Agent, instance.id, instance: jido)

    saved = restored.state.requests[request.id]
    assert saved.status == :pending and saved.result == nil
    refute Enum.any?(saved.inspection.events, &(&1.kind == :request_completed))
    assert :ok = Jido.Action.validate_static_data(saved)
    assert_script_done(mock)
  end

  test "events during cancellation admission keep stream order and a truthful saved prefix", %{
    jido: jido
  } do
    alias JidoAI.Examples.RequestInspection.CancelGate
    definition = Agent.definition()
    definition = %{definition | plugins: definition.plugins ++ [{CancelGate, observer: self()}]}
    {mock, context} = mock([%{reply: {:wait, :cancel_race, {:text, "Unused"}}}])
    server = start_agent(jido, Jido.Agent.instantiate!(definition))
    {:ok, request} = submit(server, context, stream_to: self())
    assert_receive {:mock_llm_waiting, ^mock, :cancel_race, provider}, 2_000
    monitor = Process.monitor(provider)
    runtime = owner(server)
    {:ok, before} = Session.snapshot(server)
    task = Task.async(fn -> Session.cancel(request) end)
    assert_receive {:cancel_admission, gate}, 2_000

    assert :ok =
             GenServer.call(
               runtime,
               {:event, request.id, before.request.run_id, :llm_delta, %{delta: "late", chunk_type: :content}}
             )

    send(gate, :release)
    assert :ok = Task.await(task)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert {:error, :cancelled} = Request.await(request)
    streamed = events(request)
    assert Enum.map(streamed, & &1.seq) == [1, 2, 3, 4]
    assert Enum.at(streamed, 2).data.delta == "late"
    assert List.last(streamed).kind == :request_cancelled
    {:ok, view} = Session.snapshot(server)
    assert view.details.trace.seq == 2
    assert view.details.trace.events == Enum.take(streamed, 2)
    assert view.request.error == :cancelled
    assert_script_done(mock)
  end
end
