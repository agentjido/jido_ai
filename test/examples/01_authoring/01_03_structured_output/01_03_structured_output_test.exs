defmodule JidoAI.Examples.StructuredOutputTest do
  use JidoAI.Examples.Case, async: true
  alias JidoAI.Examples.StructuredOutput

  test "invalid object feedback reaches a bounded repair and only valid output commits", %{
    jido: jido
  } do
    {mock, context} =
      mock([%{reply: {:object, %{answer: ""}}}, %{reply: {:object, %{answer: "Fixed"}}}])

    server = start_agent(jido, StructuredOutput.Agent.new!())
    assert {:ok, agent} = ask(server, context)
    assert agent.state == %{answer: "Fixed", commits: 1, case_id: "case-42"}
    assert [first, second] = MockLLM.report(mock).requests
    assert first.body["response_format"]["type"] == "json_schema"

    assert get_in(first.body, [
             "response_format",
             "json_schema",
             "schema",
             "properties",
             "answer",
             "minLength"
           ]) == 1

    prompt = List.last(second.body["messages"])["content"]
    assert prompt != List.last(first.body["messages"])["content"]
    assert prompt =~ "Validation feedback:"
    assert prompt =~ "answer"
    assert_script_done(mock)
  end

  test "two invalid attempts leave the original live state intact", %{jido: jido} do
    {mock, context} = mock(List.duplicate(%{reply: {:object, %{answer: ""}}}, 2))

    server =
      start_agent(
        jido,
        StructuredOutput.Agent.new!(state: %{answer: "Previous answer", case_id: "existing-case", commits: 7})
      )

    before = Server.snapshot(server)
    assert {:error, _} = ask(server, context)
    assert Server.snapshot(server) == before
    assert_script_done(mock)
  end
end
