defmodule JidoAI.Examples.ToolFlow.MultiRoundTest do
  use JidoAI.Examples.Case
  alias JidoAI.Examples.ToolFlow.MultiRoundAgent, as: Agent

  setup do
    previous = Application.fetch_env!(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, Map.put(previous, :fast, "openai:gpt-4o-mini"))
    on_exit(fn -> Application.put_env(:jido_ai, :model_aliases, previous) end)
    :ok
  end

  defp rounds do
    Enum.map(
      [
        {"box", "quote", 7, 13},
        {"shipment", "multiply", 91, 6},
        {"order", "multiply", 546, 4}
      ],
      fn {id, name, a, b} ->
        %{reply: {:tools, [%{id: id, name: name, arguments: %{a: a, b: b}}]}}
      end
    )
  end

  test "three dependent tool rounds precede the committed answer", %{jido: jido} do
    {mock, context} = native_mock(rounds() ++ [%{reply: {:text, "91, 546, and 2184 cents"}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, agent} = Agent.calculate(server, Agent.prompt(), context: context)
    assert agent.state.answer == "91, 546, and 2184 cents"
    assert agent.state.case_id == "quote-42"
    assert Server.agent(server).state == agent.state
    assert [_, second, third, final] = MockLLM.report(mock).requests

    for {request, id, value} <- [{second, "box", 91}, {third, "shipment", 546}, {final, "order", 2184}] do
      output = Enum.find(request.body["input"], &(&1["type"] == "function_call_output" and &1["call_id"] == id))
      assert Jason.decode!(output["output"]) == %{"ok" => true, "result" => %{"value" => value}}
    end

    {:ok, profile} = Jido.AI.Configuration.profile(agent)
    {:ok, history} = Jido.AI.Orchestration.Transcript.read(agent.state, profile)
    assert Enum.count(history, &(&1.role == :tool)) == 3
    assert_script_done(mock)
  end

  test "provider failure after tool work leaves state unchanged", %{jido: jido} do
    {mock, context} = native_mock(Enum.take(rounds(), 1) ++ [%{reply: {:error, 400, "Rejected"}}])
    server = start_agent(jido, Agent.new!())
    before = Server.agent(server).state
    assert {:error, _} = Agent.calculate(server, Agent.prompt(), context: context)
    assert Server.agent(server).state == before
    assert_script_done(mock)
  end
end
