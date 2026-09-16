defmodule JidoAI.Examples.ControlsTest do
  use JidoAI.Examples.Case
  alias JidoAI.Examples.Controls.Agent

  test "missing or refused authorization prevents model work", %{jido: jido} do
    {mock, context} = native_mock([])
    server = start_agent(jido, Agent.new!())
    before = Server.agent(server).state

    for host_context <- [context, Map.put(context, :authorized, false), Map.put(context, :authorized, "true")] do
      assert {:error, _} = ask_and_await(Agent, server, "Help", context: host_context)
      assert_domain_unchanged(server, before)
    end

    assert MockLLM.report(mock).requests == []
    assert_script_done(mock)
  end

  test "output rejection preserves prior state and accepted output can follow", %{jido: jido} do
    {mock, context} = native_mock([%{reply: {:text, "Unsupported answer"}}, %{reply: {:text, "Answer [evidence]"}}])
    context = Map.put(context, :authorized, true)
    server = start_agent(jido, Agent.new!(state: %{answer: "Previous", case_id: "existing"}))
    before = Server.agent(server).state
    assert {:error, _} = ask_and_await(Agent, server, "Help", context: context)
    assert_domain_unchanged(server, before)
    assert {:ok, agent} = ask_and_await(Agent, server, "Try again", context: context)
    assert %{answer: "Answer [evidence]", case_id: "existing"} = agent.state
    assert_script_done(mock)
  end

  for reply <- [{:error, 400, "Invalid request"}, {:raw, %{choices: "invalid"}}] do
    test "provider failure #{inspect(reply)} preserves complete state", %{jido: jido} do
      {mock, context} = native_mock([%{reply: unquote(Macro.escape(reply))}])
      server = start_agent(jido, Agent.new!())
      before = Server.agent(server).state
      assert {:error, _} = ask_and_await(Agent, server, "Help", context: Map.put(context, :authorized, true))
      assert_domain_unchanged(server, before)
      assert_script_done(mock)
    end
  end
end
