defmodule JidoAI.Examples.StructuredOutputTest do
  use JidoAI.Examples.Case
  alias JidoAI.Examples.StructuredOutput.Agent

  test "schema feedback reaches one repair before a valid object commits", %{jido: jido} do
    {mock, context} = native_mock([%{reply: {:object, %{answer: ""}}}, %{reply: {:object, %{answer: "Fixed"}}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, agent} = Agent.answer(server, "Help", context: context)
    assert %{answer: %{answer: "Fixed"}, case_id: "case-42"} = agent.state
    assert [first, second] = MockLLM.report(mock).requests
    assert first.body["text"]["format"]["type"] == "json_schema"
    assert get_in(first.body, ["text", "format", "schema", "properties", "answer", "minLength"]) == 1
    assert second.body["input"] != first.body["input"]
    feedback = List.last(second.body["input"])["content"] |> List.first() |> Map.fetch!("text")
    assert feedback =~ "Validation error:"
    assert feedback =~ "answer"
    assert_script_done(mock)
  end

  test "repair exhaustion preserves complete prior state and a later request succeeds", %{jido: jido} do
    {mock, context} =
      native_mock([
        %{reply: {:object, %{answer: ""}}},
        %{reply: {:object, %{answer: ""}}},
        %{reply: {:object, %{answer: "Recovered"}}}
      ])

    server = start_agent(jido, Agent.new!(state: %{answer: %{answer: "Previous"}, case_id: "existing"}))
    before = Server.agent(server).state
    assert {:error, _} = Agent.answer(server, "Help", context: context)
    assert Server.agent(server).state == before
    assert length(MockLLM.report(mock).requests) == 2
    assert {:ok, agent} = Agent.answer(server, "Next", context: context)
    assert %{answer: %{answer: "Recovered"}, case_id: "existing"} = agent.state
    assert_script_done(mock)
  end

  test "a provider error does not enter schema repair", %{jido: jido} do
    {mock, context} = native_mock([%{reply: {:error, 400, "Invalid request"}}])
    server = start_agent(jido, Agent.new!())
    before = Server.agent(server).state
    assert {:error, _} = Agent.answer(server, "Help", context: context)
    assert Server.agent(server).state == before
    assert length(MockLLM.report(mock).requests) == 1
    assert_script_done(mock)
  end
end
