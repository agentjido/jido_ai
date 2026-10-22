defmodule JidoAI.Examples.ToolLimitsPublicTest do
  use JidoAI.Examples.Case
  alias Jido.AI.Request

  test "the authored tool budget permits one call and rejects a larger batch", %{jido: jido} do
    alias JidoAI.Examples.ToolLimits.Agent
    call = %{id: "one", name: "multiply", arguments: %{a: 3, b: 4}}

    {mock, context} =
      mock([%{reply: {:tools, [call]}}, %{reply: {:text, "Twelve"}}, %{reply: {:tools, [call, %{call | id: "two"}]}}])

    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Multiply", context: context, model: MockLLM.model())
    assert {:ok, "Twelve"} = Request.await(request)
    assert {:ok, rejected} = Agent.ask(server, "Two operations", context: context, model: MockLLM.model())
    assert {:error, _} = Request.await(rejected)
    assert Server.agent(server).state.reply == "Twelve"
    assert_script_done(mock)
  end
end
