defmodule Jido.AI.Reasoning.TRM.CLIAdapterTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Reasoning.TRM.CLIAdapter, as: TRMAdapter
  alias Jido.AI.TestSupport.CLIAdapter, as: AdapterTestSupport

  setup :set_mimic_from_context

  defmodule StubTRMAgent do
    def reason(pid, query) do
      send(self(), {:trm_submit_called, pid, query})
      {:ok, :submitted}
    end
  end

  setup_all do
    {:ok,
     default_module: TRMAdapter.create_ephemeral_agent(%{}),
     custom_module:
       TRMAdapter.create_ephemeral_agent(%{
         model: "openai:gpt-4",
         max_supervision_steps: 10,
         act_threshold: 0.95
       })}
  end

  describe "create_ephemeral_agent/1" do
    test "creates ephemeral agent module with default config", %{default_module: module} do
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

    test "uses custom model from config", %{custom_module: module} do
      opts = module.strategy_opts()
      assert opts[:model] == "openai:gpt-4"
    end

    test "uses custom max_supervision_steps from config", %{custom_module: module} do
      opts = module.strategy_opts()
      assert opts[:max_supervision_steps] == 10
    end

    test "uses custom act_threshold from config", %{custom_module: module} do
      opts = module.strategy_opts()
      assert opts[:act_threshold] == 0.95
    end

    test "uses default values when not specified", %{default_module: module} do
      opts = module.strategy_opts()
      assert opts[:model] == :fast
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

  describe "adapter wiring" do
    test "submit delegates to configured TRM agent reason/2 function" do
      assert {:ok, :submitted} = TRMAdapter.submit(self(), "Reason recursively", %{agent_module: StubTRMAgent})
      assert_received {:trm_submit_called, pid, "Reason recursively"}
      assert pid == self()
    end

    test "await returns timeout error when timeout budget is exhausted" do
      assert {:error, :timeout} = TRMAdapter.await(self(), 0, %{})
    end

    test "await propagates status errors" do
      expect(Jido.AgentServer, :status, fn _pid -> {:error, :not_found} end)
      assert {:error, :not_found} = TRMAdapter.await(self(), 100, %{})
    end

    test "await returns completed result with TRM metadata" do
      status =
        AdapterTestSupport.status(
          result: nil,
          details: %{supervision_step: 3, best_score: 0.91, act_triggered: true},
          raw_state: %{last_result: "TRM answer"}
        )

      expect(Jido.AgentServer, :status, fn _pid -> {:ok, status} end)

      assert {:ok, %{answer: "TRM answer", meta: meta}} = TRMAdapter.await(self(), 100, %{})
      assert meta.status == :success
      assert meta.supervision_step == 3
      assert meta.best_score == 0.91
      assert meta.act_triggered == true
    end
  end
end
