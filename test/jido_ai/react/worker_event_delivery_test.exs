defmodule Jido.AI.Reasoning.ReAct.WorkerEventDeliveryTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AgentServer.{DirectiveExec, ParentRef}
  alias Jido.AI.Reasoning.ReAct.{Strategy, Worker}
  alias Jido.AI.Request
  alias Jido.AI.Request.Handle
  alias Jido.AI.Runtime.Event

  defmodule ParentAgent do
    use Jido.AI.Agent, name: "ordered_worker_events", tools: []
  end

  setup :set_mimic_from_context

  setup do
    Mimic.copy(Task.Supervisor)

    # Hold any dispatch tasks and run them in reverse order. Event delivery
    # must not depend on the order in which the task supervisor runs them.
    Mimic.stub(Task.Supervisor, :start_child, fn _supervisor, fun ->
      Process.put(:dispatch_tasks, [fun | Process.get(:dispatch_tasks, [])])
      {:ok, self()}
    end)

    :ok
  end

  for terminal <- [:request_completed, :request_failed, :request_cancelled] do
    test "preserves events and terminal state for #{terminal} under reversed task scheduling" do
      request_id = "ordered_request"
      terminal = unquote(terminal)
      parent_ref = ParentRef.new!(%{pid: self(), id: "parent", tag: :react_worker})
      worker = Worker.Agent.new(state: %{__parent__: parent_ref})
      parent = Request.start_request(ParentAgent.new(), request_id, "test", stream_to: {:pid, self()})

      events = [
        event(1, :request_started, %{query: "test"}),
        event(2, :llm_completed, %{text: "done", model: "test:model"}),
        event(3, :checkpoint, %{token: "terminal_token", reason: :terminal}),
        event(4, terminal, %{result: "done", error: :test, reason: :test})
      ]

      Enum.reduce(events, worker, fn event, worker ->
        params = %{request_id: request_id, event: Map.from_struct(event)}
        input = Jido.Signal.new!("ai.react.worker.runtime.event", params, source: "/test")
        instruction = %Jido.Instruction{action: :react_worker_runtime_event, params: params}
        {worker, directives} = Worker.Strategy.cmd(worker, [instruction], %{})

        state =
          struct(Jido.AgentServer.State,
            id: worker.id,
            agent: worker,
            agent_module: Worker.Agent,
            jido: nil
          )

        Enum.each(directives, &DirectiveExec.exec(&1, input, state))
        worker
      end)

      Enum.each(Process.get(:dispatch_tasks, []), & &1.())

      parent =
        Enum.reduce(events, parent, fn _, parent ->
          signal = receive_worker_event()
          instruction = %Jido.Instruction{action: :ai_react_worker_event, params: signal.data}
          {parent, directives} = Strategy.cmd(parent, [instruction], %{})

          {:ok, parent, _} =
            ParentAgent.on_after_cmd(parent, {:ai_react_worker_event, signal.data}, directives)

          parent
        end)

      streamed =
        Handle.new(request_id, self(), "test")
        |> Request.Stream.events(stream_event_timeout_ms: 0)
        |> Enum.to_list()

      assert Enum.map(streamed, & &1.seq) == [1, 2, 3, 4]
      assert List.last(streamed).kind == terminal
      state = StratState.get(parent)
      assert Enum.map(state.request_traces[request_id].events, & &1.seq) == [1, 2, 3, 4]
      assert state.checkpoint_token == "terminal_token"
      assert state.active_request_id == nil
      assert state.status == unquote(if(terminal == :request_completed, do: :completed, else: :error))
      assert Request.stream_sink(parent, request_id) == nil
    end
  end

  test "a worker without a parent does not emit an event" do
    worker = Worker.Agent.new()
    event = event(1, :request_started, %{query: "test"})

    instruction = %Jido.Instruction{
      action: :react_worker_runtime_event,
      params: %{request_id: event.request_id, event: Map.from_struct(event)}
    }

    assert {_worker, []} = Worker.Strategy.cmd(worker, [instruction], %{})
  end

  defp receive_worker_event do
    receive do
      {:"$gen_cast", {:signal, %Jido.Signal{type: "ai.react.worker.event"} = signal}} -> signal
      {:signal, %Jido.Signal{type: "ai.react.worker.event"} = signal} -> signal
    after
      1_000 -> flunk("worker event was not delivered")
    end
  end

  defp event(seq, kind, data) do
    Event.new(%{
      seq: seq,
      kind: kind,
      data: data,
      request_id: "ordered_request",
      run_id: "ordered_request",
      iteration: 1
    })
  end
end
