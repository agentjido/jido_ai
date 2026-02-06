defmodule Jido.AI.CLI.Adapters.GoTTest do
  use ExUnit.Case, async: true

  alias Jido.AI.CLI.Adapters.GoT, as: GoTAdapter
  alias Jido.AI.Test.ModuleExports

  describe "create_ephemeral_agent/1" do
    test "creates ephemeral agent module with default config" do
      config = %{}
      module = GoTAdapter.create_ephemeral_agent(config)

      assert is_atom(module)
      assert ModuleExports.exported?(module, :explore, 2)
      assert ModuleExports.exported?(module, :name, 0)
      assert module.name() == "cli_got_agent"
    end

    test "creates unique module names" do
      config = %{}
      module1 = GoTAdapter.create_ephemeral_agent(config)
      module2 = GoTAdapter.create_ephemeral_agent(config)

      assert module1 != module2
    end

    test "uses custom model from config" do
      config = %{model: "openai:gpt-4"}
      module = GoTAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:model] == "openai:gpt-4"
    end

    test "uses custom max_nodes from config" do
      config = %{max_nodes: 30}
      module = GoTAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:max_nodes] == 30
    end

    test "uses custom max_depth from config" do
      config = %{max_depth: 10}
      module = GoTAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:max_depth] == 10
    end

    test "uses custom aggregation_strategy from config" do
      config = %{aggregation_strategy: :voting}
      module = GoTAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:aggregation_strategy] == :voting
    end

    test "uses default values when not specified" do
      config = %{}
      module = GoTAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:model] == "anthropic:claude-haiku-4-5"
      assert opts[:max_nodes] == 20
      assert opts[:max_depth] == 5
      assert opts[:aggregation_strategy] == :synthesis
    end
  end

  describe "behavior implementation" do
    test "implements all required callbacks" do
      Code.ensure_loaded!(GoTAdapter)
      assert ModuleExports.exported?(GoTAdapter, :start_agent, 3)
      assert ModuleExports.exported?(GoTAdapter, :submit, 3)
      assert ModuleExports.exported?(GoTAdapter, :await, 3)
      assert ModuleExports.exported?(GoTAdapter, :stop, 1)
      assert ModuleExports.exported?(GoTAdapter, :create_ephemeral_agent, 1)
    end
  end
end
