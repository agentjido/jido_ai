defmodule Jido.AI.Reasoning.ReAct.CLIAdapterTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Reasoning.ReAct.CLIAdapter, as: ReActAdapter

  defmodule TestCalculator do
    use Jido.Action,
      name: "test_calculator",
      description: "Basic calculator for CLI adapter tests",
      schema: []

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  describe "create_ephemeral_agent/1" do
    test "creates ephemeral agent module with default config" do
      module = ReActAdapter.create_ephemeral_agent(%{})

      assert is_atom(module)
      assert function_exported?(module, :ask, 2)
      assert function_exported?(module, :name, 0)
      assert module.name() == "cli_react_agent"
    end

    test "creates unique module names" do
      module1 = ReActAdapter.create_ephemeral_agent(%{})
      module2 = ReActAdapter.create_ephemeral_agent(%{})

      assert module1 != module2
    end

    test "uses custom model/tools/max_iterations/system_prompt from config" do
      module =
        ReActAdapter.create_ephemeral_agent(%{
          model: "openai:gpt-4.1",
          tools: [TestCalculator],
          max_iterations: 4,
          system_prompt: "Think step by step, then call tools."
        })

      state = module.new() |> StratState.get(%{})
      config = state[:config]

      assert config.model == "openai:gpt-4.1"
      assert config.tools == [TestCalculator]
      assert config.max_iterations == 4
      assert config.system_prompt == "Think step by step, then call tools."
    end

    test "uses default values when options are omitted" do
      module = ReActAdapter.create_ephemeral_agent(%{})
      state = module.new() |> StratState.get(%{})
      config = state[:config]

      assert config.model == Jido.AI.resolve_model(:fast)
      assert config.max_iterations == 10

      assert config.tools == [
               Jido.Tools.Arithmetic.Add,
               Jido.Tools.Arithmetic.Subtract,
               Jido.Tools.Arithmetic.Multiply,
               Jido.Tools.Arithmetic.Divide,
               Jido.Tools.Weather
             ]

      assert is_binary(config.system_prompt)
      assert config.system_prompt != ""
    end
  end

  describe "behavior implementation" do
    test "implements all required callbacks" do
      Code.ensure_loaded!(ReActAdapter)
      assert function_exported?(ReActAdapter, :start_agent, 3)
      assert function_exported?(ReActAdapter, :submit, 3)
      assert function_exported?(ReActAdapter, :await, 3)
      assert function_exported?(ReActAdapter, :stop, 1)
      assert function_exported?(ReActAdapter, :create_ephemeral_agent, 1)
    end
  end
end
