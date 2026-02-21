defmodule Jido.AI.Reasoning.TreeOfThoughts.CLIAdapterTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Reasoning.TreeOfThoughts.CLIAdapter, as: ToTAdapter
  alias Jido.AI.TestSupport.CLIAdapter, as: AdapterTestSupport

  setup :set_mimic_from_context

  defmodule StubToTAgent do
    def explore(pid, query) do
      send(self(), {:tot_submit_called, pid, query})
      {:ok, :submitted}
    end
  end

  setup_all do
    {:ok,
     default_module: ToTAdapter.create_ephemeral_agent(%{}),
     custom_module:
       ToTAdapter.create_ephemeral_agent(%{
         model: "openai:gpt-4",
         branching_factor: 5,
         max_depth: 10,
         traversal_strategy: :dfs
       })}
  end

  describe "create_ephemeral_agent/1" do
    test "creates ephemeral agent module with default config", %{default_module: module} do
      assert is_atom(module)
      assert function_exported?(module, :explore, 2)
      assert function_exported?(module, :name, 0)
      assert module.name() == "cli_tot_agent"
    end

    test "creates unique module names" do
      config = %{}
      module1 = ToTAdapter.create_ephemeral_agent(config)
      module2 = ToTAdapter.create_ephemeral_agent(config)

      assert module1 != module2
    end

    test "uses custom model from config", %{custom_module: module} do
      opts = module.strategy_opts()
      assert opts[:model] == "openai:gpt-4"
    end

    test "uses custom branching_factor from config", %{custom_module: module} do
      opts = module.strategy_opts()
      assert opts[:branching_factor] == 5
    end

    test "uses custom max_depth from config", %{custom_module: module} do
      opts = module.strategy_opts()
      assert opts[:max_depth] == 10
    end

    test "uses custom traversal_strategy from config", %{custom_module: module} do
      opts = module.strategy_opts()
      assert opts[:traversal_strategy] == :dfs
    end

    test "uses default values when not specified", %{default_module: module} do
      opts = module.strategy_opts()
      assert opts[:model] == :fast
      assert opts[:branching_factor] == 3
      assert opts[:max_depth] == 3
      assert opts[:traversal_strategy] == :best_first
      assert opts[:top_k] == 3
      assert opts[:min_depth] == 2
      assert opts[:max_nodes] == 100
    end
  end

  describe "behavior implementation" do
    test "implements all required callbacks" do
      Code.ensure_loaded!(ToTAdapter)
      assert function_exported?(ToTAdapter, :start_agent, 3)
      assert function_exported?(ToTAdapter, :submit, 3)
      assert function_exported?(ToTAdapter, :await, 3)
      assert function_exported?(ToTAdapter, :stop, 1)
      assert function_exported?(ToTAdapter, :create_ephemeral_agent, 1)
    end
  end

  describe "adapter wiring" do
    test "submit delegates to configured ToT agent explore/2 function" do
      assert {:ok, :submitted} = ToTAdapter.submit(self(), "Explore tree", %{agent_module: StubToTAgent})
      assert_received {:tot_submit_called, pid, "Explore tree"}
      assert pid == self()
    end

    test "await returns timeout error when timeout budget is exhausted" do
      assert {:error, :timeout} = ToTAdapter.await(self(), 0, %{})
    end

    test "await propagates status errors" do
      expect(Jido.AgentServer, :status, fn _pid -> {:error, :not_found} end)
      assert {:error, :not_found} = ToTAdapter.await(self(), 100, %{})
    end

    test "await returns best content answer with ToT metadata" do
      status =
        AdapterTestSupport.status(
          result: %{best: %{content: "ToT answer"}, usage: %{total_tokens: 5}},
          details: %{node_count: 7, traversal_strategy: :dfs, solution_path: [1, 2, 3]}
        )

      expect(Jido.AgentServer, :status, fn _pid -> {:ok, status} end)

      assert {:ok, %{answer: "ToT answer", meta: meta}} = ToTAdapter.await(self(), 100, %{})
      assert meta.status == :success
      assert meta.node_count == 7
      assert meta.traversal_strategy == :dfs
      assert meta.solution_path_length == 3
      assert meta.usage == %{total_tokens: 5}
      assert meta.tot_result == %{best: %{content: "ToT answer"}, usage: %{total_tokens: 5}}
    end
  end
end
