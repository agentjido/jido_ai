defmodule Jido.AI.Reasoning.Adaptive.CLIAdapterTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Reasoning.Adaptive.CLIAdapter, as: AdaptiveAdapter
  alias Jido.AI.TestSupport.CLIAdapter, as: AdapterTestSupport

  setup :set_mimic_from_context

  defmodule StubAdaptiveAgent do
    def ask(pid, query) do
      send(self(), {:adaptive_submit_called, pid, query})
      {:ok, :submitted}
    end
  end

  setup_all do
    {:ok,
     default_module: AdaptiveAdapter.create_ephemeral_agent(%{}),
     custom_module:
       AdaptiveAdapter.create_ephemeral_agent(%{
         model: "openai:gpt-4",
         default_strategy: :cot,
         available_strategies: [:cot, :react]
       })}
  end

  describe "create_ephemeral_agent/1" do
    test "creates ephemeral agent module with default config", %{default_module: module} do
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

    test "uses custom model from config", %{custom_module: module} do
      opts = module.strategy_opts()
      assert opts[:model] == "openai:gpt-4"
    end

    test "uses custom default_strategy from config", %{custom_module: module} do
      opts = module.strategy_opts()
      assert opts[:default_strategy] == :cot
    end

    test "uses custom available_strategies from config", %{custom_module: module} do
      opts = module.strategy_opts()
      assert opts[:available_strategies] == [:cot, :react]
    end

    test "uses default values when not specified", %{default_module: module} do
      opts = module.strategy_opts()
      assert opts[:model] == :fast
      assert opts[:default_strategy] == :react
      assert opts[:available_strategies] == [:cod, :cot, :react, :tot, :got, :trm]
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

  describe "adapter wiring" do
    test "submit delegates to configured Adaptive agent ask/2 function" do
      assert {:ok, :submitted} =
               AdaptiveAdapter.submit(self(), "Choose a strategy", %{agent_module: StubAdaptiveAgent})

      assert_received {:adaptive_submit_called, pid, "Choose a strategy"}
      assert pid == self()
    end

    test "await returns timeout error when timeout budget is exhausted" do
      assert {:error, :timeout} = AdaptiveAdapter.await(self(), 0, %{})
    end

    test "await propagates status errors" do
      expect(Jido.AgentServer, :status, fn _pid -> {:error, :not_found} end)
      assert {:error, :not_found} = AdaptiveAdapter.await(self(), 100, %{})
    end

    test "await returns completed result with adaptive metadata" do
      status =
        AdapterTestSupport.status(
          result: nil,
          details: %{available_strategies: [:cot, :react]},
          raw_state: %{
            last_result: "Adaptive answer",
            __strategy__: %{strategy_type: :cot, complexity_score: 0.42, task_type: :reasoning}
          }
        )

      expect(Jido.AgentServer, :status, fn _pid -> {:ok, status} end)

      assert {:ok, %{answer: "Adaptive answer", meta: meta}} = AdaptiveAdapter.await(self(), 100, %{})
      assert meta.status == :success
      assert meta.selected_strategy == :cot
      assert meta.complexity_score == 0.42
      assert meta.task_type == :reasoning
      assert meta.available_strategies == [:cot, :react]
    end
  end
end
