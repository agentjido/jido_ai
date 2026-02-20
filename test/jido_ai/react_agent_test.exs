defmodule Jido.AI.AgentRuntimeAdapterTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Examples.Weather.{Overview, ReActAgent}
  alias Jido.AI.Reasoning.ReAct.CLIAdapter, as: ReActCLIAdapter

  defmodule EchoTool do
    use Jido.Action,
      name: "echo",
      description: "Echo input text",
      schema: Zoi.object(%{text: Zoi.string()})

    def run(%{text: text}, _context), do: {:ok, %{text: text}}
  end

  defmodule RuntimeDefaultAgent do
    use Jido.AI.Agent,
      name: "runtime_default_agent",
      tools: [EchoTool]
  end

  defmodule RuntimeOptOutAgent do
    use Jido.AI.Agent,
      name: "runtime_opt_out_agent",
      tools: [EchoTool],
      runtime_adapter: false
  end

  test "enables runtime adapter by default" do
    agent = RuntimeDefaultAgent.new()
    config = agent |> StratState.get(%{}) |> Map.get(:config, %{})

    assert config.runtime_adapter == true
  end

  test "ignores runtime adapter opt-out and stays delegated" do
    agent = RuntimeOptOutAgent.new()
    config = agent |> StratState.get(%{}) |> Map.get(:config, %{})

    assert config.runtime_adapter == true
  end

  test "weather react example uses the React CLI adapter" do
    assert ReActAgent.cli_adapter() == ReActCLIAdapter
  end

  test "weather overview maps :react to ReAct weather module" do
    assert Overview.agents().react == ReActAgent
  end
end
