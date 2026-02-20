defmodule Jido.AI.Reasoning.ChainOfDraft.CLIAdapterTest do
  use ExUnit.Case, async: true

  alias Jido.AI.CLI.Adapter
  alias Jido.AI.Reasoning.ChainOfDraft.CLIAdapter, as: CoDAdapter

  defmodule StubCoDAgent do
    def draft(pid, query) do
      send(self(), {:cod_submit_called, pid, query})
      {:ok, :submitted}
    end
  end

  describe "create_ephemeral_agent/1" do
    test "creates ephemeral agent module with default config" do
      config = %{}
      module = CoDAdapter.create_ephemeral_agent(config)

      assert is_atom(module)
      assert function_exported?(module, :draft, 2)
      assert function_exported?(module, :name, 0)
      assert module.name() == "cli_cod_agent"
    end

    test "creates unique module names" do
      config = %{}
      module1 = CoDAdapter.create_ephemeral_agent(config)
      module2 = CoDAdapter.create_ephemeral_agent(config)

      assert module1 != module2
    end

    test "uses custom model from config" do
      config = %{model: "openai:gpt-4"}
      module = CoDAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:model] == "openai:gpt-4"
    end

    test "uses custom system_prompt from config" do
      config = %{system_prompt: "Draft minimally."}
      module = CoDAdapter.create_ephemeral_agent(config)

      opts = module.strategy_opts()
      assert opts[:system_prompt] == "Draft minimally."
    end

    test "uses default values when not specified" do
      module = CoDAdapter.create_ephemeral_agent(%{})
      opts = module.strategy_opts()

      assert opts[:model] == "anthropic:claude-haiku-4-5"
      assert is_binary(opts[:system_prompt])
      assert opts[:system_prompt] != ""
    end
  end

  describe "behavior implementation" do
    test "implements all required callbacks" do
      Code.ensure_loaded!(CoDAdapter)
      assert function_exported?(CoDAdapter, :start_agent, 3)
      assert function_exported?(CoDAdapter, :submit, 3)
      assert function_exported?(CoDAdapter, :await, 3)
      assert function_exported?(CoDAdapter, :stop, 1)
      assert function_exported?(CoDAdapter, :create_ephemeral_agent, 1)
    end
  end

  describe "adapter wiring" do
    test "submit delegates to configured CoD agent draft/2 function" do
      assert {:ok, :submitted} = CoDAdapter.submit(self(), "Keep it short", %{agent_module: StubCoDAgent})
      assert_received {:cod_submit_called, pid, "Keep it short"}
      assert pid == self()
    end

    test "await returns timeout error when timeout budget is exhausted" do
      assert {:error, :timeout} = CoDAdapter.await(self(), 0, %{})
    end

    test "weather CoD example resolves to CoD adapter" do
      assert {:ok, CoDAdapter} = Adapter.resolve(nil, Jido.AI.Examples.Weather.CoDAgent)
    end
  end
end
