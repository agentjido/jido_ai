defmodule Jido.AI.Reasoning.AlgorithmOfThoughts.CLIAdapterTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Reasoning.AlgorithmOfThoughts.CLIAdapter, as: AoTAdapter
  alias Jido.AI.TestSupport.CLIAdapter, as: AdapterTestSupport

  setup :set_mimic_from_context

  defmodule StubAoTAgent do
    def explore(pid, query) do
      send(self(), {:aot_submit_called, pid, query})
      {:ok, :submitted}
    end
  end

  setup_all do
    {:ok,
     default_module: AoTAdapter.create_ephemeral_agent(%{}),
     custom_module:
       AoTAdapter.create_ephemeral_agent(%{
         model: "openai:gpt-4.1",
         profile: :long,
         search_style: :bfs,
         temperature: 0.3,
         max_tokens: 4096,
         require_explicit_answer: false
       })}
  end

  describe "create_ephemeral_agent/1" do
    test "creates ephemeral agent module with default config", %{default_module: module} do
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

    test "uses custom AoT options from config", %{custom_module: module} do
      opts = module.strategy_opts()
      assert opts[:model] == "openai:gpt-4.1"
      assert opts[:profile] == :long
      assert opts[:search_style] == :bfs
      assert opts[:temperature] == 0.3
      assert opts[:max_tokens] == 4096
      assert opts[:require_explicit_answer] == false
    end

    test "uses expected defaults when options are omitted", %{default_module: module} do
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

  describe "adapter wiring" do
    test "submit delegates to configured AoT agent explore/2 function" do
      assert {:ok, :submitted} = AoTAdapter.submit(self(), "Explore this", %{agent_module: StubAoTAgent})
      assert_received {:aot_submit_called, pid, "Explore this"}
      assert pid == self()
    end

    test "await returns timeout error when timeout budget is exhausted" do
      assert {:error, :timeout} = AoTAdapter.await(self(), 0, %{})
    end

    test "await propagates status errors" do
      expect(Jido.AgentServer, :status, fn _pid -> {:error, :not_found} end)
      assert {:error, :not_found} = AoTAdapter.await(self(), 100, %{})
    end

    test "await returns completed result with AoT metadata" do
      status =
        AdapterTestSupport.status(
          result: %{answer: "42", termination: :final_answer, usage: %{total_tokens: 11}},
          details: %{profile: :long, search_style: :bfs}
        )

      expect(Jido.AgentServer, :status, fn _pid -> {:ok, status} end)

      assert {:ok, %{answer: "42", meta: meta}} = AoTAdapter.await(self(), 100, %{})
      assert meta.status == :success
      assert meta.profile == :long
      assert meta.search_style == :bfs
      assert meta.termination == :final_answer
      assert meta.usage == %{total_tokens: 11}
    end

    test "await falls back to raw state answer when snapshot result is empty" do
      status = AdapterTestSupport.status(result: nil, raw_state: %{last_result: %{answer: "fallback answer"}})
      expect(Jido.AgentServer, :status, fn _pid -> {:ok, status} end)

      assert {:ok, %{answer: "fallback answer"}} = AoTAdapter.await(self(), 100, %{})
    end
  end
end
