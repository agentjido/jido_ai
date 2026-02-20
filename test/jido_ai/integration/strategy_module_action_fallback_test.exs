defmodule Jido.AI.Integration.StrategyModuleActionFallbackTest do
  use ExUnit.Case, async: false

  alias Jido.Agent
  alias Jido.AI.Reasoning.Adaptive.Strategy, as: Adaptive
  alias Jido.AI.Reasoning.ChainOfThought.Strategy, as: CoT
  alias Jido.AI.Reasoning.GraphOfThoughts.Strategy, as: GoT
  alias Jido.AI.Reasoning.ReAct.Strategy, as: ReAct
  alias Jido.AI.Reasoning.TRM.Strategy, as: TRM
  alias Jido.AI.Reasoning.TreeOfThoughts.Strategy, as: ToT

  defmodule MarkerAction do
    use Jido.Action,
      name: "strategy_marker_action",
      description: "Marks state when executed by strategy fallback"

    def run(params, context) do
      {:ok,
       %{
         strategy_marker: params[:marker],
         strategy_context_contract: %{
           has_state: is_map(context[:state]),
           has_agent: match?(%Jido.Agent{}, context[:agent]),
           has_plugin_state: is_map(context[:plugin_state])
         }
       }}
    end
  end

  defmodule TestTool do
    use Jido.Action,
      name: "strategy_test_tool",
      description: "tool required for react init",
      schema:
        Zoi.object(%{
          value: Zoi.integer() |> Zoi.default(1)
        })

    def run(params, _context), do: {:ok, %{value: params[:value] || 1}}
  end

  test "fallback executes module actions on ReAct strategy" do
    agent = %Agent{id: "react-agent", name: "react", state: %{}}
    ctx = %{agent_module: __MODULE__, strategy_opts: [tools: [TestTool]]}

    {agent, _} = ReAct.init(agent, ctx)

    instruction = %Jido.Instruction{action: MarkerAction, params: %{marker: :react}}
    {updated_agent, directives} = ReAct.cmd(agent, [instruction], ctx)

    assert updated_agent.state.strategy_marker == :react
    assert updated_agent.state.strategy_context_contract.has_state == true
    assert updated_agent.state.strategy_context_contract.has_agent == true
    assert updated_agent.state.strategy_context_contract.has_plugin_state == true
    assert directives == []
  end

  test "fallback executes module actions on CoT strategy" do
    assert_strategy_fallback(CoT, :cot)
  end

  test "fallback executes module actions on ToT strategy" do
    assert_strategy_fallback(ToT, :tot)
  end

  test "fallback executes module actions on GoT strategy" do
    assert_strategy_fallback(GoT, :got)
  end

  test "fallback executes module actions on TRM strategy" do
    assert_strategy_fallback(TRM, :trm)
  end

  test "fallback executes module actions on Adaptive strategy" do
    assert_strategy_fallback(Adaptive, :adaptive)
  end

  defp assert_strategy_fallback(strategy_module, marker) do
    agent = %Agent{id: "#{marker}-agent", name: "#{marker}", state: %{}}
    ctx = %{agent_module: __MODULE__, strategy_opts: []}

    {agent, _} = strategy_module.init(agent, ctx)

    instruction = %Jido.Instruction{action: MarkerAction, params: %{marker: marker}}
    {updated_agent, directives} = strategy_module.cmd(agent, [instruction], ctx)

    assert updated_agent.state.strategy_marker == marker
    assert updated_agent.state.strategy_context_contract.has_state == true
    assert updated_agent.state.strategy_context_contract.has_agent == true
    assert updated_agent.state.strategy_context_contract.has_plugin_state == true
    assert directives == []
  end
end
