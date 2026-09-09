defmodule JidoAI.Examples.ToolFlowTest do
  use JidoAI.Examples.Case, async: true
  alias JidoAI.Examples.ToolFlow

  test "an Action and nested Flow produce correlated tool results for the next model call", %{
    jido: jido
  } do
    calls = [
      %{id: "direct", name: "multiply", arguments: %{a: 2, b: 3}},
      %{id: "nested", name: "quote", arguments: %{a: 4, b: 5}}
    ]

    {mock, context} =
      mock([%{reply: {:tools, calls}}, %{reply: {:text, "The results are 6 and 20"}}])

    server = start_agent(jido, ToolFlow.Agent.new!())
    assert {:ok, agent} = ask(server, context)
    assert agent.state == %{answer: "The results are 6 and 20", case_id: "case-42", commits: 1}
    assert_receive {:tool_executed, 2, 3}
    assert_receive {:tool_executed, 4, 5}
    assert [first, final] = MockLLM.report(mock).requests

    assert Enum.map(first.body["tools"], &get_in(&1, ["function", "name"])) == [
             "multiply",
             "quote"
           ]

    messages = final.body["messages"]
    assert Enum.map(messages, & &1["role"]) == ["user", "assistant", "tool", "tool"]
    [_, assistant, one, two] = messages
    assert Enum.map(assistant["tool_calls"], & &1["id"]) == ["direct", "nested"]
    assert one["tool_call_id"] == "direct"
    assert two["tool_call_id"] == "nested"
    assert Jason.decode!(one["content"]) == %{"value" => 6}
    assert Jason.decode!(two["content"]) == %{"value" => 20}
    assert_script_done(mock)
  end

  for invalid <- [
        %{id: "invalid", name: "unknown", arguments: %{a: 1, b: 2}},
        %{id: "invalid", name: "quote", arguments: %{a: "wrong", b: 2}}
      ] do
    test "the entire tool batch is validated before work: #{inspect(invalid)}", %{jido: jido} do
      valid = %{id: "valid", name: "multiply", arguments: %{a: 2, b: 3}}
      {mock, context} = mock([%{reply: {:tools, [valid, unquote(Macro.escape(invalid))]}}])
      server = start_agent(jido, ToolFlow.Agent.new!())
      before = Server.snapshot(server)
      assert {:error, _} = ask(server, context)
      assert Server.snapshot(server) == before
      refute_received {:tool_executed, _, _}
      assert_script_done(mock)
    end
  end
end
