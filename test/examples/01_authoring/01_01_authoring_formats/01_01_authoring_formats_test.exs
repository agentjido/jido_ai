defmodule JidoAI.Examples.AuthoringFormatsTest do
  use JidoAI.Examples.Case
  alias JidoAI.Examples.AuthoringFormats.Agent

  test "the generated command commits an answer and preserves domain data", %{jido: jido} do
    {mock, context} = native_mock([%{reply: {:text, "Ready"}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, agent} = Agent.answer(server, "Help with this case", context: context)
    assert %{answer: "Ready", case_id: "case-42"} = agent.state
    assert Server.agent(server).state == agent.state
    assert [request] = MockLLM.report(mock).requests

    assert List.last(request.body["input"])["content"] ==
             [%{"type" => "input_text", "text" => "Help with this case"}]

    assert {:ok, signal} = Agent.answer_signal("Next question")
    assert signal.type == "examples.ai.01_01.answer"
    assert signal.source == "/examples/ai/01_authoring/01_01"
    assert_script_done(mock)
  end

  test "a provider failure preserves the previous answer and permits a later request", %{jido: jido} do
    {mock, context} = native_mock([%{reply: {:error, 400, "Invalid request"}}, %{reply: {:text, "Recovered"}}])
    server = start_agent(jido, Agent.new!(state: %{answer: "Previous", case_id: "existing"}))
    before = Server.agent(server).state
    assert {:error, _} = Agent.answer(server, "Help", context: context)
    assert Server.agent(server).state == before
    assert {:ok, agent} = Agent.answer(server, "Try again", context: context)
    assert %{answer: "Recovered", case_id: "existing"} = agent.state
    assert_script_done(mock)
  end
end
