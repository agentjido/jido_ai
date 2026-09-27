defmodule Jido.AI.Integration.RequestStreamOrderTest do
  use Jido.AI.TestCase, async: false

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Context
  alias Jido.AI.Request

  defmodule EchoTool do
    use Jido.Action,
      name: "echo",
      description: "Echo test text",
      schema: Zoi.object(%{text: Zoi.string()})

    def run(%{text: text}, _context), do: {:ok, %{text: text}}
  end

  defmodule StreamAgent do
    use Jido.AI.Agent,
      name: "request_stream_order",
      tools: [EchoTool]
  end

  setup do
    if is_nil(Process.whereis(Jido)) do
      start_supervised!({Jido, name: Jido})
    end

    pid = start_supervised!({Jido.AgentServer, agent: StreamAgent})
    %{pid: pid}
  end

  test "repeated tool requests deliver all events before completion", %{pid: pid} do
    # Reuse the worker to cover the transition from a finished request to a new one.
    for run <- 1..3 do
      reset_context(pid, run)

      script =
        expect_react do
          user("echo hello")
          call("echo", %{text: "hello"})
          answer("hello")
        end

      assert {:ok, %{request: request, events: events}} =
               StreamAgent.ask_stream(pid, "echo hello", react_opts(script) ++ [stream_event_timeout_ms: 5_000])

      events = Enum.to_list(events)
      assert_complete_stream(events, :request_completed)
      assert Enum.any?(events, &(&1.kind == :tool_completed))
      assert Enum.any?(events, &(&1.kind == :llm_completed and is_binary(&1.data.model)))
      assert {:ok, "hello"} = StreamAgent.await(request, timeout: 5_000)
      assert_parent_state(pid, request.id, events, :completed)
    end
  end

  test "failed requests deliver all events and the final checkpoint before failure", %{pid: pid} do
    script =
      expect_react do
        user("fail after tool")
        call("echo", %{text: "hello"})
        fail(%{type: :provider_error, message: "test failure"})
      end

    assert {:ok, %{request: request, events: events}} =
             StreamAgent.ask_stream(pid, "fail after tool", react_opts(script) ++ [stream_event_timeout_ms: 5_000])

    events = Enum.to_list(events)
    assert_complete_stream(events, :request_failed)
    assert Enum.any?(events, &(&1.kind == :tool_completed))
    assert {:error, _} = StreamAgent.await(request, timeout: 5_000)
    assert_parent_state(pid, request.id, events, :error)
  end

  defp assert_complete_stream(events, terminal_kind) do
    assert List.last(events).kind == terminal_kind
    assert Enum.map(events, & &1.seq) == Enum.to_list(1..List.last(events).seq)
    assert %{kind: :checkpoint, data: %{reason: :terminal, token: token}} = Enum.at(events, -2)
    assert is_binary(token)
  end

  defp reset_context(pid, run) do
    signal =
      Jido.Signal.new!(
        "ai.react.context.modify",
        %{
          op_id: "reset_#{run}",
          operation: %{type: :replace, reason: :manual, result_context: Context.new()}
        },
        source: "/test/request_stream_order"
      )

    assert {:ok, _agent} = Jido.AgentServer.call(pid, signal, 5_000)
  end

  defp assert_parent_state(pid, request_id, events, status) do
    {:ok, server} = Jido.AgentServer.state(pid)
    state = StratState.get(server.agent)
    assert state.status == status
    assert state.active_request_id == nil
    assert state.react_worker_status == :ready
    assert state.checkpoint_token == Enum.at(events, -2).data.token
    assert Enum.map(state.request_traces[request_id].events, & &1.seq) == Enum.map(events, & &1.seq)
    assert Request.stream_sink(server.agent, request_id) == nil
  end
end
