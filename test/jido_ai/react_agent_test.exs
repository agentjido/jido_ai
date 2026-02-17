defmodule Jido.AI.ReActAgentTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Strategy.State, as: StratState

  defmodule EchoTool do
    use Jido.Action,
      name: "echo",
      description: "Echo input text",
      schema: Zoi.object(%{text: Zoi.string()})

    def run(%{text: text}, _context), do: {:ok, %{text: text}}
  end

  defmodule RuntimeDefaultAgent do
    use Jido.AI.ReActAgent,
      name: "runtime_default_agent",
      tools: [EchoTool]
  end

  defmodule RuntimeOptOutAgent do
    use Jido.AI.ReActAgent,
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
end
