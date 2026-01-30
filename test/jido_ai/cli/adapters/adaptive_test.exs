defmodule Jido.AI.CLI.Adapters.AdaptiveTest do
  use ExUnit.Case, async: true

  alias Jido.AI.CLI.Adapters.Adaptive, as: AdaptiveAdapter

  describe "create_ephemeral_agent/1" do
    test "creates ephemeral agent module with default config" do
      config = %{}
      module = AdaptiveAdapter.create_ephemeral_agent(config)

      assert is_atom(module)
      assert function_exported?(module, :ask, 2)
      assert function_exported?(module, :name, 0)
      assert module.name() == "cli_adaptive_agent"
    end

    test "creates unique module names" do
      config = %{}
      module1 = AdaptiveAdapter.create_ephemeral_agent(config)
      module2 = AdaptiveAdapter.create_ephemeral_agent(config)

      assert module1 != module2
    end

    test "uses custom model from config" do
      config = %{model: "openai:gpt-4"}
      module = AdaptiveAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:model] == "openai:gpt-4"
    end

    test "uses custom default_strategy from config" do
      config = %{default_strategy: :cot}
      module = AdaptiveAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:default_strategy] == :cot
    end

    test "uses custom available_strategies from config" do
      config = %{available_strategies: [:cot, :react]}
      module = AdaptiveAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:available_strategies] == [:cot, :react]
    end

    test "uses default values when not specified" do
      config = %{}
      module = AdaptiveAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:model] == "anthropic:claude-haiku-4-5"
      assert opts[:default_strategy] == :react
      assert opts[:available_strategies] == [:cot, :react, :tot, :got, :trm]
    end
  end

  describe "behavior implementation" do
    test "implements all required callbacks" do
      Code.ensure_loaded!(AdaptiveAdapter)
      assert function_exported?(AdaptiveAdapter, :start_agent, 3)
      assert function_exported?(AdaptiveAdapter, :submit, 3)
      assert function_exported?(AdaptiveAdapter, :await, 3)
      assert function_exported?(AdaptiveAdapter, :stop, 1)
      assert function_exported?(AdaptiveAdapter, :create_ephemeral_agent, 1)
    end
  end
end
