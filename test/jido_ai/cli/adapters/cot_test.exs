defmodule Jido.AI.CLI.Adapters.CoTTest do
  use ExUnit.Case, async: true

  alias Jido.AI.CLI.Adapters.CoT, as: CoTAdapter

  describe "create_ephemeral_agent/1" do
    test "creates ephemeral agent module with default config" do
      config = %{}
      module = CoTAdapter.create_ephemeral_agent(config)

      assert is_atom(module)
      assert function_exported?(module, :think, 2)
      assert function_exported?(module, :name, 0)
      assert module.name() == "cli_cot_agent"
    end

    test "creates unique module names" do
      config = %{}
      module1 = CoTAdapter.create_ephemeral_agent(config)
      module2 = CoTAdapter.create_ephemeral_agent(config)

      assert module1 != module2
    end

    test "uses custom model from config" do
      config = %{model: "openai:gpt-4"}
      module = CoTAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:model] == "openai:gpt-4"
    end

    test "uses default values when not specified" do
      config = %{}
      module = CoTAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:model] == "anthropic:claude-haiku-4-5"
    end

    test "uses custom system_prompt from config" do
      config = %{system_prompt: "You are a helpful reasoning assistant."}
      module = CoTAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:system_prompt] == "You are a helpful reasoning assistant."
    end
  end

  describe "behavior implementation" do
    test "implements all required callbacks" do
      assert function_exported?(CoTAdapter, :start_agent, 3)
      assert function_exported?(CoTAdapter, :submit, 3)
      assert function_exported?(CoTAdapter, :await, 3)
      assert function_exported?(CoTAdapter, :stop, 1)
      assert function_exported?(CoTAdapter, :create_ephemeral_agent, 1)
    end
  end
end
