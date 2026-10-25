defmodule JidoAI.Examples.SessionValueTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive.Reply
  alias JidoAI.Examples.SessionValue
  alias JidoAI.Examples.SessionValue.Agent

  @moduletag :example

  @tag capture_log: true
  test "a complete Agent records a typed exchange and closes its Session" do
    assert {:ok, %Jido.Agent{module: Agent} = agent} =
             SessionValue.new(id: "session-value")

    record = Agent.record_signal!(%{note: "Keep this conversation portable."})

    assert {:ok, agent, [%Reply{signal: recorded}]} = Jido.Agent.cmd(agent, record)
    assert recorded.data == %{note: "Keep this conversation portable."}
    assert agent.state.session.status == :open
    assert [^record, recorded_history] = agent.state.session.thread.signals
    assert recorded_history.type == recorded.type
    assert recorded_history.data == recorded.data
    assert agent.state.session.thread.rev == 2

    close = Agent.close_signal!()

    assert {:ok, closed, [%Reply{signal: closed_reply}]} = Jido.Agent.cmd(agent, close)
    assert closed_reply.data == %{session_id: closed.state.session.id, status: "closed"}
    assert closed.state.session.status == :closed

    assert [^record, ^recorded_history, ^close, closed_history] =
             closed.state.session.thread.signals

    assert closed_history.type == closed_reply.type
    assert closed_history.data == closed_reply.data
    assert closed.state.session.thread.rev == 4
    assert Jido.PortableTerm.valid?(closed.state.session)

    assert {:error, _reason} =
             Jido.Agent.cmd(
               closed,
               Agent.record_signal!(%{note: "This must not be committed."})
             )

    assert closed.state.session.thread.rev == 4
  end
end
