defmodule Jido.AI.Reasoning.ChainOfThought.CLIAdapterTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.CLI.Adapter
  alias Jido.AI.Reasoning.ChainOfThought.CLIAdapter, as: CoTAdapter
  alias Jido.AI.TestSupport.CLIAdapter, as: AdapterTestSupport

  setup :set_mimic_from_context

  defmodule StubCoTAgent do
    def think(pid, query) do
      send(self(), {:cot_submit_called, pid, query})
      {:ok, :submitted}
    end
  end

  setup_all do
    {:ok,
     default_module: CoTAdapter.create_ephemeral_agent(%{}),
     model_module: CoTAdapter.create_ephemeral_agent(%{model: "openai:gpt-4"}),
     prompt_module: CoTAdapter.create_ephemeral_agent(%{system_prompt: "You are a helpful reasoning assistant."})}
  end

  describe "create_ephemeral_agent/1" do
    test "creates ephemeral agent module with default config", %{default_module: module} do
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

    test "uses custom model from config", %{model_module: module} do
      opts = module.strategy_opts()
      assert opts[:model] == "openai:gpt-4"
    end

    test "uses default values when not specified", %{default_module: module} do
      opts = module.strategy_opts()
      assert opts[:model] == :fast
      refute Keyword.has_key?(opts, :system_prompt)
    end

    test "uses custom system_prompt from config", %{prompt_module: module} do
      opts = module.strategy_opts()
      assert opts[:system_prompt] == "You are a helpful reasoning assistant."
    end
  end

  describe "behavior implementation" do
    test "implements all required callbacks" do
      Code.ensure_loaded!(CoTAdapter)
      assert function_exported?(CoTAdapter, :start_agent, 3)
      assert function_exported?(CoTAdapter, :submit, 3)
      assert function_exported?(CoTAdapter, :await, 3)
      assert function_exported?(CoTAdapter, :stop, 1)
      assert function_exported?(CoTAdapter, :create_ephemeral_agent, 1)
    end
  end

  describe "adapter wiring" do
    test "submit delegates to configured CoT agent think/2 function" do
      assert {:ok, :submitted} = CoTAdapter.submit(self(), "Reason it out", %{agent_module: StubCoTAgent})
      assert_received {:cot_submit_called, pid, "Reason it out"}
      assert pid == self()
    end

    test "await returns timeout error when timeout budget is exhausted" do
      assert {:error, :timeout} = CoTAdapter.await(self(), 0, %{})
    end

    test "await propagates status errors" do
      expect(Jido.AgentServer, :status, fn _pid -> {:error, :not_found} end)
      assert {:error, :not_found} = CoTAdapter.await(self(), 100, %{})
    end

    test "await returns completed result with CoT metadata" do
      status =
        AdapterTestSupport.status(
          result: nil,
          details: %{steps_count: 4, phase: :complete, duration_ms: 123},
          raw_state: %{last_result: "CoT answer"}
        )

      expect(Jido.AgentServer, :status, fn _pid -> {:ok, status} end)

      assert {:ok, %{answer: "CoT answer", meta: meta}} = CoTAdapter.await(self(), 100, %{})
      assert meta.status == :success
      assert meta.steps_count == 4
      assert meta.phase == :complete
      assert meta.duration_ms == 123
    end

    test "weather CoT example resolves to CoT adapter" do
      assert {:ok, CoTAdapter} = Adapter.resolve(nil, Jido.AI.Examples.Weather.CoTAgent)
    end
  end
end
