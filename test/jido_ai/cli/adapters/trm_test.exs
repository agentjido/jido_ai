defmodule Jido.AI.Reasoning.TRM.CLIAdapterTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Reasoning.TRM.CLIAdapter, as: TRMAdapter

  describe "create_ephemeral_agent/1" do
    test "creates ephemeral agent module with default config" do
      config = %{}
      module = TRMAdapter.create_ephemeral_agent(config)

      assert is_atom(module)
      assert function_exported?(module, :reason, 2)
      assert function_exported?(module, :name, 0)
      assert module.name() == "cli_trm_agent"
    end

    test "creates unique module names" do
      config = %{}
      module1 = TRMAdapter.create_ephemeral_agent(config)
      module2 = TRMAdapter.create_ephemeral_agent(config)

      assert module1 != module2
    end

    test "uses custom model from config" do
      config = %{model: "openai:gpt-4"}
      module = TRMAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:model] == "openai:gpt-4"
    end

    test "uses custom max_supervision_steps from config" do
      config = %{max_supervision_steps: 10}
      module = TRMAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:max_supervision_steps] == 10
    end

    test "uses custom act_threshold from config" do
      config = %{act_threshold: 0.95}
      module = TRMAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:act_threshold] == 0.95
    end

    test "uses default values when not specified" do
      config = %{}
      module = TRMAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:model] == "anthropic:claude-haiku-4-5"
      assert opts[:max_supervision_steps] == 5
      assert opts[:act_threshold] == 0.9
    end
  end

  describe "behavior implementation" do
    test "implements all required callbacks" do
      Code.ensure_loaded!(TRMAdapter)
      assert function_exported?(TRMAdapter, :start_agent, 3)
      assert function_exported?(TRMAdapter, :submit, 3)
      assert function_exported?(TRMAdapter, :await, 3)
      assert function_exported?(TRMAdapter, :stop, 1)
      assert function_exported?(TRMAdapter, :create_ephemeral_agent, 1)
    end
  end
end
