defmodule JidoAI.Examples.ToolFlow.DesignRequirementsTest do
  use JidoAI.Examples.Case
  alias JidoAI.Examples.ToolFlow.Agent
  @moduletag :design_requirement

  @tag requirements: ["TLS-REQ-015"]
  test "TLS-REQ-015 a Flow tool uses the result without the Action's direct-caller extras", %{jido: jido} do
    alias JidoAI.Examples.ToolFlow.{Receipt, ReceiptFlow}
    assert {:ok, %{value: 6}, [%{receipt: "DIRECT_CALLER_ONLY"}]} = Jido.Exec.run(Receipt, %{a: 2, b: 3}, %{})

    profile = Jido.AI.Agent.profile(Agent, :assistant) |> Map.from_struct()
    profile = %{profile | tools: [%{name: "price", target: ReceiptFlow}]}

    base = %{
      name: "receipt_example",
      schema: Agent.domain_schema(),
      routes: [{"ai.ask", Jido.AI.Authoring.ai(:assistant)}]
    }

    assert {:ok, definition} = Jido.AI.Authoring.lower(base, [profile])
    server = start_agent(jido, Jido.Agent.instantiate!(definition))

    {mock, context} =
      native_mock([
        %{reply: {:tools, [%{id: "price", name: "price", arguments: %{a: 2, b: 3}}]}},
        %{reply: {:text, "Price is 6"}}
      ])

    signal = Jido.Signal.new!("ai.ask", %{query: "Price"}, source: "/examples/receipt")
    assert {:ok, agent} = Server.call(server, signal, context: context)
    assert agent.state.answer == "Price is 6"
    assert_script_done(mock)
    [_, final] = MockLLM.report(mock).requests
    [result] = Enum.filter(final.body["input"], &(&1["type"] == "function_call_output"))
    assert Jason.decode!(result["output"]) == %{"ok" => true, "result" => %{"value" => 6}}
    refute result["output"] =~ "DIRECT_CALLER_ONLY"
  end

  @tag requirements: ["TLS-REQ-007"]
  test "TLS-REQ-007 an unknown tool returns a model-visible error without a fallback Action", %{jido: jido} do
    {mock, context} =
      native_mock([
        %{reply: {:tools, [%{id: "unknown", name: "not_declared", arguments: %{}}]}},
        %{reply: {:text, "I cannot use that tool."}}
      ])

    server = start_agent(jido, Agent.new!())
    outcome = Agent.calculate(server, "Use an unavailable tool", context: context)
    assert {:ok, agent} = outcome
    assert agent.state.answer == "I cannot use that tool."
    [_, wire] = MockLLM.report(mock).requests
    result = Enum.find(wire.body["input"], &(&1["type"] == "function_call_output"))
    assert result["call_id"] == "unknown"
    assert result["output"] =~ "error"
    assert_script_done(mock)
  end

  @tag requirements: ["TLS-REQ-007"]
  test "a mixed unknown tool batch performs no partial tool work", %{jido: jido} do
    observe_tools()

    {mock, context} =
      native_mock([
        %{
          reply:
            {:tools,
             [
               %{id: "known", name: "multiply", arguments: %{a: 2, b: 3}},
               %{id: "unknown", name: "not_declared", arguments: %{}}
             ]}
        },
        %{reply: {:text, "The batch was rejected."}}
      ])

    server = start_agent(jido, Agent.new!())
    assert {:ok, agent} = Agent.calculate(server, "Use both tools", context: context)
    assert agent.state.answer == "The batch was rejected."
    refute_received {:example_tool_started, _}
    [_, wire] = MockLLM.report(mock).requests
    results = Enum.filter(wire.body["input"], &(&1["type"] == "function_call_output"))
    assert Enum.map(results, & &1["call_id"]) == ["known", "unknown"]
    assert Enum.all?(results, &(Jason.decode!(&1["output"])["ok"] == false))
    assert_script_done(mock)
  end
end
