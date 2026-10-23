defmodule JidoAI.Examples.SessionValueTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive.Reply
  alias JidoAI.Examples.SessionValue
  alias JidoAI.Examples.SessionValue.{Agent, Close, Record}

  @moduletag :example

  @tag capture_log: true
  test "a complete Agent records a typed exchange and closes its Session" do
    assert {:ok, %Jido.Agent{module: Agent} = agent} =
             SessionValue.new(id: "session-value")

    record = Record.new!(%{note: "Keep this conversation portable."})

    assert {:ok, agent, [%Reply{signal: recorded}]} = Jido.Agent.cmd(agent, record)
    assert recorded.data == %{note: "Keep this conversation portable."}
    assert agent.state.session.status == :open
    assert agent.state.session.thread.signals == [record, recorded]
    assert agent.state.session.thread.rev == 2

    close = Close.new!()

    assert {:ok, closed, [%Reply{signal: closed_reply}]} = Jido.Agent.cmd(agent, close)
    assert closed_reply.data == %{session_id: closed.state.session.id, status: "closed"}
    assert closed.state.session.status == :closed
    assert closed.state.session.thread.signals == [record, recorded, close, closed_reply]
    assert closed.state.session.thread.rev == 4
    assert Jido.PortableTerm.valid?(closed.state.session)

    assert {:error, _reason} =
             Jido.Agent.cmd(closed, Record.new!(%{note: "This must not be committed."}))

    assert closed.state.session.thread.rev == 4
  end
end
