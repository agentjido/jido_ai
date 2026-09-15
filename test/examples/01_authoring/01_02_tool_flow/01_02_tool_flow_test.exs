defmodule JidoAI.Examples.ToolFlowTest do
  use JidoAI.Examples.Case
  alias JidoAI.Examples.ToolFlow.Agent

  test "an Action and Flow supply real, correlated results to the next model call", %{jido: jido} do
    calls = [
      %{id: "direct", name: "multiply", arguments: %{a: 2, b: 3}},
      %{id: "nested", name: "quote", arguments: %{a: 4, b: 5}}
    ]

    {mock, context} = native_mock([%{reply: {:tools, calls}}, %{reply: {:text, "The results are 6 and 20"}}])
    server = start_agent(jido, Agent.new!())
    observe_tools()
    assert {:ok, agent} = Agent.calculate(server, "Calculate both prices", context: context)
    assert %{answer: "The results are 6 and 20", case_id: "case-42"} = agent.state
    assert_receive {:example_tool_started, "multiply"}
    assert_receive {:example_tool_started, "quote"}
    assert [first, final] = MockLLM.report(mock).requests
    assert Enum.map(first.body["tools"], & &1["name"]) == ["multiply", "quote"]
    [one, two] = Enum.filter(final.body["input"], &(&1["type"] == "function_call_output"))
    assert one["call_id"] == "direct"
    assert two["call_id"] == "nested"
    assert Jason.decode!(one["output"]) == %{"ok" => true, "result" => %{"value" => 6}}
    assert Jason.decode!(two["output"]) == %{"ok" => true, "result" => %{"value" => 20}}
    assert_script_done(mock)
  end

  for invalid <- [
        %{id: "invalid", name: "unknown", arguments: %{a: 1, b: 2}},
        %{id: "invalid", name: "quote", arguments: %{a: "wrong", b: 2}}
      ] do
    test "batch preflight rejects #{inspect(invalid)} before any tool starts", %{jido: jido} do
      valid = %{id: "valid", name: "multiply", arguments: %{a: 2, b: 3}}
      {mock, context} = native_mock([%{reply: {:tools, [valid, unquote(Macro.escape(invalid))]}}])
      server = start_agent(jido, Agent.new!())
      observe_tools()
      before = Server.agent(server).state
      assert {:error, _} = Agent.calculate(server, "Calculate", context: context)
      assert Server.agent(server).state == before
      refute_received {:example_tool_started, _}
      assert_script_done(mock)
    end
  end

  test "the model call limit rejects another tool round without committing an answer", %{jido: jido} do
    call = %{id: "one", name: "multiply", arguments: %{a: 2, b: 3}}
    {mock, context} = native_mock([%{reply: {:tools, [call]}}, %{reply: {:tools, [%{call | id: "two"}]}}])
    server = start_agent(jido, Agent.new!())
    before = Server.agent(server).state
    assert {:error, _} = Agent.calculate(server, "Calculate", context: context)
    assert Server.agent(server).state == before
    assert length(MockLLM.report(mock).requests) == 2
    assert_script_done(mock)
  end
end
