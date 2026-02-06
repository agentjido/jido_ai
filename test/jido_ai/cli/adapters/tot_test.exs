defmodule Jido.AI.CLI.Adapters.ToTTest do
  use ExUnit.Case, async: true

  alias Jido.AI.CLI.Adapters.ToT, as: ToTAdapter
  alias Jido.AI.Test.ModuleExports

  describe "create_ephemeral_agent/1" do
    test "creates ephemeral agent module with default config" do
      config = %{}
      module = ToTAdapter.create_ephemeral_agent(config)

      assert is_atom(module)
      assert ModuleExports.exported?(module, :explore, 2)
      assert ModuleExports.exported?(module, :name, 0)
      assert module.name() == "cli_tot_agent"
    end

    test "creates unique module names" do
      config = %{}
      module1 = ToTAdapter.create_ephemeral_agent(config)
      module2 = ToTAdapter.create_ephemeral_agent(config)

      assert module1 != module2
    end

    test "uses custom model from config" do
      config = %{model: "openai:gpt-4"}
      module = ToTAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:model] == "openai:gpt-4"
    end

    test "uses custom branching_factor from config" do
      config = %{branching_factor: 5}
      module = ToTAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:branching_factor] == 5
    end

    test "uses custom max_depth from config" do
      config = %{max_depth: 10}
      module = ToTAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:max_depth] == 10
    end

    test "uses custom traversal_strategy from config" do
      config = %{traversal_strategy: :dfs}
      module = ToTAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:traversal_strategy] == :dfs
    end

    test "uses default values when not specified" do
      config = %{}
      module = ToTAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:model] == "anthropic:claude-haiku-4-5"
      assert opts[:branching_factor] == 3
      assert opts[:max_depth] == 3
      assert opts[:traversal_strategy] == :best_first
    end
  end

  describe "behavior implementation" do
    test "implements all required callbacks" do
      Code.ensure_loaded!(ToTAdapter)
      assert ModuleExports.exported?(ToTAdapter, :start_agent, 3)
      assert ModuleExports.exported?(ToTAdapter, :submit, 3)
      assert ModuleExports.exported?(ToTAdapter, :await, 3)
      assert ModuleExports.exported?(ToTAdapter, :stop, 1)
      assert ModuleExports.exported?(ToTAdapter, :create_ephemeral_agent, 1)
    end
  end
end
