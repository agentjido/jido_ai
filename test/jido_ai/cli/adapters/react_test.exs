defmodule Jido.AI.Reasoning.ReAct.CLIAdapterTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Reasoning.ReAct.CLIAdapter, as: ReActAdapter
  alias Jido.AI.TestSupport.CLIAdapter, as: AdapterTestSupport

  setup :set_mimic_from_context

  defp profile(module) do
    {Jido.AI.Runtime.Plugin, opts} =
      Enum.find(module.definition().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))

    opts[:profiles].assistant
  end

  defmodule StubReActAgent do
    def ask(pid, query) do
      send(self(), {:react_submit_called, pid, query})
      {:ok, :submitted}
    end

    def ask(pid, query, opts) do
      send(self(), {:react_submit_called_with_opts, pid, query, opts})
      {:ok, :submitted_with_opts}
    end
  end

  defmodule TestCalculator do
    use Jido.Action,
      name: "test_calculator",
      description: "Basic calculator for CLI adapter tests",
      schema: Zoi.object(%{})

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  setup_all do
    {:ok,
     default_module: ReActAdapter.create_ephemeral_agent(%{}),
     custom_module:
       ReActAdapter.create_ephemeral_agent(%{
         model: "openai:gpt-4.1",
         tools: [TestCalculator],
         max_iterations: 4,
         max_tokens: 4_096,
         system_prompt: "Think step by step, then call tools.",
         req_http_options: [plug: {Req.Test, []}],
         llm_opts: [thinking: %{type: :enabled, budget_tokens: 512}, reasoning_effort: :high]
       })}
  end

  describe "create_ephemeral_agent/1" do
    test "creates ephemeral agent module with default config", %{default_module: module} do
      assert is_atom(module)
      assert function_exported?(module, :ask, 2)
      assert function_exported?(module, :name, 0)
      assert module.name() == "cli_react_agent"
    end

    test "creates unique module names" do
      module1 = ReActAdapter.create_ephemeral_agent(%{})
      module2 = ReActAdapter.create_ephemeral_agent(%{})

      assert module1 != module2
    end

    test "uses custom model/tools/max_iterations/system_prompt from config", %{custom_module: module} do
      config = profile(module)
      generation = config.models.answer.generation

      assert config.models.answer.model == "openai:gpt-4.1"
      assert Enum.map(config.tools, & &1.target) == [TestCalculator]
      assert config.controls.max_iterations == 4
      assert generation[:max_tokens] == 4_096
      assert config.instructions == "Think step by step, then call tools."
      assert generation[:req_http_options] == [plug: {Req.Test, []}]
      assert generation[:thinking] == %{type: :enabled, budget_tokens: 512}
      assert generation[:reasoning_effort] == :high
    end

    test "uses default values when options are omitted", %{default_module: module} do
      config = profile(module)

      assert config.models.answer.model == :fast
      assert config.controls.max_iterations == 10
      assert config.models.answer.generation[:max_tokens] == 4_096

      assert MapSet.new(Enum.map(config.tools, & &1.target)) ==
               MapSet.new([
                 Jido.AI.Tools.Arithmetic.Add,
                 Jido.AI.Tools.Arithmetic.Subtract,
                 Jido.AI.Tools.Arithmetic.Multiply,
                 Jido.AI.Tools.Arithmetic.Divide
               ])

      assert is_binary(config.instructions)
      assert config.instructions != ""
    end
  end

  describe "behavior implementation" do
    test "implements all required callbacks" do
      Code.ensure_loaded!(ReActAdapter)
      assert function_exported?(ReActAdapter, :start_agent, 3)
      assert function_exported?(ReActAdapter, :submit, 3)
      assert function_exported?(ReActAdapter, :await, 3)
      assert function_exported?(ReActAdapter, :stop, 1)
      assert function_exported?(ReActAdapter, :create_ephemeral_agent, 1)
    end
  end

  describe "adapter wiring" do
    test "submit delegates to configured ReAct agent ask/2 function" do
      assert {:ok, :submitted} = ReActAdapter.submit(self(), "Use tools", %{agent_module: StubReActAgent})
      assert_received {:react_submit_called, pid, "Use tools"}
      assert pid == self()
    end

    test "submit uses ask/3 with forwarded request options when provided" do
      config = %{
        agent_module: StubReActAgent,
        req_http_options: [plug: {Req.Test, []}],
        llm_opts: [reasoning_effort: :high]
      }

      assert {:ok, :submitted_with_opts} = ReActAdapter.submit(self(), "Use tools", config)
      assert_received {:react_submit_called_with_opts, pid, "Use tools", opts}
      assert pid == self()
      assert opts[:req_http_options] == [plug: {Req.Test, []}]
      assert opts[:llm_opts] == [reasoning_effort: :high]
    end

    test "await returns timeout error when timeout budget is exhausted" do
      assert {:error, :timeout} = ReActAdapter.await(self(), 0, %{})
    end

    test "await propagates status errors" do
      expect(Jido.AI.CLI.Adapter, :status, fn _pid -> {:error, :not_found} end)
      assert {:error, :not_found} = ReActAdapter.await(self(), 100, %{})
    end

    test "await returns completed result with usage metadata" do
      status =
        AdapterTestSupport.status(
          result: nil,
          details: %{
            model: "openai:gpt-4o",
            iteration: 2,
            usage: %{input_tokens: 10, output_tokens: 5}
          },
          raw_state: %{last_answer: "ReAct answer"}
        )

      expect(Jido.AI.CLI.Adapter, :status, fn _pid -> {:ok, status} end)

      assert {:ok, %{answer: "ReAct answer", meta: meta}} = ReActAdapter.await(self(), 100, %{})
      assert meta.status == :success
      assert meta.iterations == 2
      assert meta.model == "openai:gpt-4o"
      assert meta.usage.input_tokens == 10
      assert meta.usage.output_tokens == 5
      assert meta.usage.total_tokens == 15
    end

    test "await inspects non-binary failure results for CLI-safe output" do
      status = AdapterTestSupport.status(result: {:provider_error, :overloaded}, snapshot_status: :failure)

      expect(Jido.AI.CLI.Adapter, :status, fn _pid -> {:ok, status} end)

      assert {:ok, %{answer: "{:provider_error, :overloaded}", meta: meta}} =
               ReActAdapter.await(self(), 100, %{})

      assert meta.status == :failure
    end
  end
end
