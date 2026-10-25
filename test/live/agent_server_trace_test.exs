defmodule Jido.AI.Live.AgentServerTraceTest do
  use Jido.AI.Test.LiveCase, async: false

  alias Jido.Agent.Directive.Reply
  alias Jido.AgentServer
  alias JidoAI.Examples.RequestModes
  alias JidoAI.Examples.RequestModes.Agent

  setup do
    jido = :"jido_ai_live_trace_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido})
    {:ok, jido: jido}
  end

  test "a routed live turn includes core Jido runtime telemetry", %{jido: jido} do
    input = "Reply with Ready in one short sentence."

    {:ok, server} = RequestModes.start(jido, id: "live-agent-server-trace")

    request = Agent.ask_signal!(%{question: input})

    {result, trace_path} =
      capture_live(RequestModes.Agent, input, "agent_server_turn", [], fn ->
        with {:ok, _agent, [%Reply{signal: reply}]} <- AgentServer.call(server, request) do
          assert_receive %Jido.Signal{} = delivered, 1_000
          assert delivered.id == reply.id
          assert delivered.type == reply.type
          assert delivered.data == reply.data
          await_idle(server)
          {:ok, reply.data}
        end
      end)

    assert {:ok, %{answer: answer}} = result
    assert is_binary(answer)

    trace = trace_path |> File.read!() |> Jason.decode!()
    event_types = Enum.map(trace["runtime_events"], & &1["type"])

    assert "jido.agent_server.turn.stop" in event_types
    assert "jido.agent_server.commit" in event_types
    assert "jido.agent_server.turn.settled" in event_types
    assert "jido.agent_server.effects.stop" in event_types

    assert turn =
             Enum.find(trace["runtime_events"], &(&1["type"] == "jido.agent_server.turn.stop"))

    assert turn["metadata"]["status"] == "ok"
    assert is_binary(turn["metadata"]["trace_id"])
    assert is_binary(turn["metadata"]["span_id"])
  end

  defp await_idle(server, attempts \\ 100)

  defp await_idle(_server, 0), do: flunk("AgentServer effects did not finish")

  defp await_idle(server, attempts) do
    case AgentServer.status(server) do
      %{phase: :idle} ->
        :ok

      _status ->
        Process.sleep(5)
        await_idle(server, attempts - 1)
    end
  end
end
