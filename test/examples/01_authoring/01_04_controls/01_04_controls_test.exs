defmodule JidoAI.Examples.ControlsTest do
  use JidoAI.Examples.Case, async: true
  alias JidoAI.Examples.Controls

  test "input rejection makes no model call", %{jido: jido} do
    {mock, context} = mock([])
    server = start_agent(jido, Controls.Agent.new!())
    before = Server.snapshot(server)
    assert {:error, _} = ask(server, Map.put(context, :authorized, false))
    assert Server.snapshot(server) == before
    assert_receive :input_control
    refute_received :output_control
    assert MockLLM.report(mock).requests == []
    assert_script_done(mock)
  end

  test "output rejection prevents a live commit", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Unsupported answer"}}])
    server = start_agent(jido, Controls.Agent.new!())
    before = Server.snapshot(server)
    assert {:error, _} = ask(server, Map.put(context, :authorized, true))
    assert Server.snapshot(server) == before
    assert_receive :input_control
    assert_receive :output_control
    assert_script_done(mock)
  end

  test "provider failure stops before output controls and state assembly", %{jido: jido} do
    {mock, context} = mock([%{reply: {:error, 503, "Unavailable"}}])
    server = start_agent(jido, Controls.Agent.new!())
    before = Server.snapshot(server)
    assert {:error, _} = ask(server, Map.put(context, :authorized, true))
    assert Server.snapshot(server) == before
    assert_receive :input_control
    refute_received :output_control
    assert_script_done(mock)
  end

  test "accepted output reaches one complete commit", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Answer [evidence]"}}])
    server = start_agent(jido, Controls.Agent.new!())
    assert {:ok, agent} = ask(server, Map.put(context, :authorized, true))
    assert agent.state == %{answer: "Answer [evidence]", commits: 1, case_id: "case-42"}
    assert_receive :input_control
    assert_receive :output_control
    assert_script_done(mock)
  end

  test "a provider decoder exception becomes a command error and preserves state", %{jido: jido} do
    {mock, context} = mock([%{reply: {:raw, %{choices: "invalid"}}}])
    server = start_agent(jido, Controls.Agent.new!())
    before = Server.snapshot(server)
    assert {:error, _} = ask(server, Map.put(context, :authorized, true))
    assert Server.snapshot(server) == before
    refute_received :output_control
    assert_script_done(mock)
  end
end
