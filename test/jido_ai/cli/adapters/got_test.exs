defmodule Jido.AI.Reasoning.GraphOfThoughts.CLIAdapterTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Reasoning.GraphOfThoughts.CLIAdapter, as: GoTAdapter
  alias Jido.AI.TestSupport.CLIAdapter, as: AdapterTestSupport

  setup :set_mimic_from_context

  defmodule StubGoTAgent do
    def explore(pid, query) do
      send(self(), {:got_submit_called, pid, query})
      {:ok, :submitted}
    end
  end

  setup_all do
    {:ok,
     default_module: GoTAdapter.create_ephemeral_agent(%{}),
     custom_module:
       GoTAdapter.create_ephemeral_agent(%{
         model: "openai:gpt-4",
         max_nodes: 30,
         max_depth: 10,
         aggregation_strategy: :voting
       })}
  end

  describe "create_ephemeral_agent/1" do
    test "creates ephemeral agent module with default config", %{default_module: module} do
      assert is_atom(module)
      assert function_exported?(module, :explore, 2)
      assert function_exported?(module, :name, 0)
      assert module.name() == "cli_got_agent"
    end

    test "creates unique module names" do
      config = %{}
      module1 = GoTAdapter.create_ephemeral_agent(config)
      module2 = GoTAdapter.create_ephemeral_agent(config)

      assert module1 != module2
    end

    test "uses custom model from config", %{custom_module: module} do
      opts = module.strategy_opts()
      assert opts[:model] == "openai:gpt-4"
    end

    test "uses custom max_nodes from config", %{custom_module: module} do
      opts = module.strategy_opts()
      assert opts[:max_nodes] == 30
    end

    test "uses custom max_depth from config", %{custom_module: module} do
      opts = module.strategy_opts()
      assert opts[:max_depth] == 10
    end

    test "uses custom aggregation_strategy from config", %{custom_module: module} do
      opts = module.strategy_opts()
      assert opts[:aggregation_strategy] == :voting
    end

    test "uses default values when not specified", %{default_module: module} do
      opts = module.strategy_opts()
      assert opts[:model] == :fast
      assert opts[:max_nodes] == 20
      assert opts[:max_depth] == 5
      assert opts[:aggregation_strategy] == :synthesis
    end
  end

  describe "behavior implementation" do
    test "implements all required callbacks" do
      Code.ensure_loaded!(GoTAdapter)
      assert function_exported?(GoTAdapter, :start_agent, 3)
      assert function_exported?(GoTAdapter, :submit, 3)
      assert function_exported?(GoTAdapter, :await, 3)
      assert function_exported?(GoTAdapter, :stop, 1)
      assert function_exported?(GoTAdapter, :create_ephemeral_agent, 1)
    end
  end

  describe "adapter wiring" do
    test "submit delegates to configured GoT agent explore/2 function" do
      assert {:ok, :submitted} = GoTAdapter.submit(self(), "Explore graph", %{agent_module: StubGoTAgent})
      assert_received {:got_submit_called, pid, "Explore graph"}
      assert pid == self()
    end

    test "await returns timeout error when timeout budget is exhausted" do
      assert {:error, :timeout} = GoTAdapter.await(self(), 0, %{})
    end

    test "await propagates status errors" do
      expect(Jido.AgentServer, :status, fn _pid -> {:error, :not_found} end)
      assert {:error, :not_found} = GoTAdapter.await(self(), 100, %{})
    end

    test "await returns completed result with graph metadata" do
      status =
        AdapterTestSupport.status(
          result: nil,
          details: %{node_count: 9, edge_count: 11, aggregation_strategy: :voting},
          raw_state: %{last_result: "GoT answer"}
        )

      expect(Jido.AgentServer, :status, fn _pid -> {:ok, status} end)

      assert {:ok, %{answer: "GoT answer", meta: meta}} = GoTAdapter.await(self(), 100, %{})
      assert meta.status == :success
      assert meta.node_count == 9
      assert meta.edge_count == 11
      assert meta.aggregation_strategy == :voting
    end
  end
end
