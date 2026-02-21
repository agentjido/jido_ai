defmodule Jido.AI.Reasoning.AlgorithmOfThoughts.CLIAdapterTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Reasoning.AlgorithmOfThoughts.CLIAdapter, as: AoTAdapter

  describe "create_ephemeral_agent/1" do
    test "creates ephemeral agent module with default config" do
      module = AoTAdapter.create_ephemeral_agent(%{})

      assert is_atom(module)
      assert function_exported?(module, :explore, 2)
      assert function_exported?(module, :name, 0)
      assert module.name() == "cli_aot_agent"
    end

    test "creates unique module names" do
      module1 = AoTAdapter.create_ephemeral_agent(%{})
      module2 = AoTAdapter.create_ephemeral_agent(%{})

      assert module1 != module2
    end

    test "uses custom AoT options from config" do
      module =
        AoTAdapter.create_ephemeral_agent(%{
          model: "openai:gpt-4.1",
          profile: :long,
          search_style: :bfs,
          temperature: 0.3,
          max_tokens: 4096,
          require_explicit_answer: false
        })

      opts = module.strategy_opts()
      assert opts[:model] == "openai:gpt-4.1"
      assert opts[:profile] == :long
      assert opts[:search_style] == :bfs
      assert opts[:temperature] == 0.3
      assert opts[:max_tokens] == 4096
      assert opts[:require_explicit_answer] == false
    end

    test "uses expected defaults when options are omitted" do
      module = AoTAdapter.create_ephemeral_agent(%{})
      opts = module.strategy_opts()

      assert opts[:model] == :fast
      assert opts[:profile] == :standard
      assert opts[:search_style] == :dfs
      assert opts[:temperature] == 0.0
      assert opts[:max_tokens] == 2048
      assert opts[:require_explicit_answer] == true
    end
  end

  describe "behavior implementation" do
    test "implements all required callbacks" do
      Code.ensure_loaded!(AoTAdapter)
      assert function_exported?(AoTAdapter, :start_agent, 3)
      assert function_exported?(AoTAdapter, :submit, 3)
      assert function_exported?(AoTAdapter, :await, 3)
      assert function_exported?(AoTAdapter, :stop, 1)
      assert function_exported?(AoTAdapter, :create_ephemeral_agent, 1)
    end
  end
end
