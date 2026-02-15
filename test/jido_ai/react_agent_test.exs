defmodule Jido.AI.ReActAgentTest do
  @moduledoc """
  Tests for Jido.AI.ReActAgent macro and compile-time alias expansion.
  """
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Request
  alias Jido.AI.ReActAgent
  alias Jido.AI.Strategies.ReAct

  # ============================================================================
  # Test Action Modules (simulating external modules like ash_jido)
  # ============================================================================

  defmodule TestDomain do
    @moduledoc "Mock domain module for testing tool_context resolution"
    def name, do: "test_domain"
  end

  defmodule TestActor do
    @moduledoc "Mock actor module for testing tool_context resolution"
    def name, do: "test_actor"
  end

  defmodule TestCalculator do
    use Jido.Action,
      name: "calculator",
      description: "A simple calculator"

    def run(%{operation: "add", a: a, b: b}, _ctx), do: {:ok, %{result: a + b}}
    def run(%{operation: "multiply", a: a, b: b}, _ctx), do: {:ok, %{result: a * b}}
  end

  defmodule TestSearch do
    use Jido.Action,
      name: "search",
      description: "Search for information"

    def run(%{query: query}, _ctx), do: {:ok, %{results: ["Found: #{query}"]}}
  end

  # ============================================================================
  # Test Agents Using ReActAgent Macro
  # ============================================================================

  defmodule BasicAgent do
    use Jido.AI.ReActAgent,
      name: "basic_agent",
      description: "A basic test agent",
      tools: [TestCalculator, TestSearch]
  end

  defmodule AgentWithToolContext do
    use Jido.AI.ReActAgent,
      name: "agent_with_context",
      tools: [TestCalculator],
      tool_context: %{
        domain: TestDomain,
        actor: TestActor,
        static_value: "hello"
      }
  end

  defmodule AgentWithPlainMapContext do
    use Jido.AI.ReActAgent,
      name: "agent_with_plain_map",
      tools: [TestCalculator],
      tool_context: %{tenant_id: "tenant_123", enabled: true}
  end

  # ============================================================================
  # expand_aliases_in_ast/2 Tests
  # ============================================================================

  describe "expand_aliases_in_ast/2" do
    test "expands module aliases to atoms" do
      # Simulate AST for %{domain: TestDomain}
      ast = {:%{}, [], [domain: {:__aliases__, [alias: false], [:SomeModule]}]}

      # Create a mock caller env
      env = __ENV__

      # The function should walk the AST and expand aliases
      result = ReActAgent.expand_aliases_in_ast(ast, env)

      # The __aliases__ node should be expanded (in this case to SomeModule atom)
      assert is_tuple(result)
    end

    test "allows literal values unchanged" do
      ast = {:%{}, [], [key: "string", num: 42, flag: true, atom_val: :test]}
      env = __ENV__

      result = ReActAgent.expand_aliases_in_ast(ast, env)

      # Should preserve the structure
      assert is_tuple(result)
    end

    test "allows nested maps" do
      ast = {:%{}, [], [outer: {:%{}, [], [inner: "value"]}]}
      env = __ENV__

      result = ReActAgent.expand_aliases_in_ast(ast, env)

      assert is_tuple(result)
    end

    test "allows lists" do
      ast = {:%{}, [], [items: [1, 2, 3]]}
      env = __ENV__

      result = ReActAgent.expand_aliases_in_ast(ast, env)

      assert is_tuple(result)
    end

    test "raises CompileError for function calls" do
      # Simulate AST for %{value: some_function()}
      ast = {:%{}, [], [value: {:some_function, [line: 1], []}]}
      env = __ENV__

      assert_raise CompileError, ~r/Unsafe construct.*function call/, fn ->
        ReActAgent.expand_aliases_in_ast(ast, env)
      end
    end
  end

  # ============================================================================
  # ReActAgent Macro Compilation Tests
  # ============================================================================

  describe "ReActAgent macro" do
    test "compiles agent with basic options" do
      assert function_exported?(BasicAgent, :ask, 2)
      assert function_exported?(BasicAgent, :ask, 3)
      assert function_exported?(BasicAgent, :on_before_cmd, 2)
      assert function_exported?(BasicAgent, :on_after_cmd, 3)
    end

    test "agent has correct name" do
      agent = BasicAgent.new()
      assert agent.name == "basic_agent"
    end

    test "agent has correct description" do
      agent = BasicAgent.new()
      assert agent.description == "A basic test agent"
    end

    test "tool_context with module aliases resolves correctly" do
      # When using ReActAgent, the strategy is auto-initialized via new()
      # The config is stored in agent.state.__strategy__.config
      agent = AgentWithToolContext.new()
      state = StratState.get(agent, %{})
      config = state[:config]

      # Modules should be resolved to atoms, not AST tuples
      # Now stored as base_tool_context (persistent)
      assert config.base_tool_context[:domain] == TestDomain
      assert config.base_tool_context[:actor] == TestActor
      assert config.base_tool_context[:static_value] == "hello"
    end

    test "tool_context with plain map values works" do
      agent = AgentWithPlainMapContext.new()
      state = StratState.get(agent, %{})
      config = state[:config]

      # Now stored as base_tool_context (persistent)
      assert config.base_tool_context[:tenant_id] == "tenant_123"
      assert config.base_tool_context[:enabled] == true
    end

    test "tools list resolves module aliases" do
      agent = BasicAgent.new()
      tools = ReAct.list_tools(agent)

      # Should be actual module atoms, not AST
      assert TestCalculator in tools
      assert TestSearch in tools
      assert Enum.all?(tools, &is_atom/1)
    end

    test "does not warn when consumer defines its own thinking_meta/1" do
      module_name = Module.concat(__MODULE__, :"CollisionAgent#{System.unique_integer([:positive, :monotonic])}")

      source = """
      defmodule #{inspect(module_name)} do
        use Jido.AI.ReActAgent,
          name: "collision_agent",
          tools: [#{inspect(TestCalculator)}]

        defp thinking_meta(_), do: %{custom: true}
      end
      """

      warnings =
        capture_io(:stderr, fn ->
          Code.compile_string(source)
        end)

      refute warnings =~ "this clause for thinking_meta/1 cannot match"
    end
  end

  # ============================================================================
  # ask/3 with Per-Request Tool Context
  # ============================================================================

  describe "ask/3 with tool_context option" do
    test "ask/2 works without options" do
      # We can't fully test without starting a server, but we can verify the function exists
      assert function_exported?(BasicAgent, :ask, 2)
      assert function_exported?(BasicAgent, :ask, 3)
    end

    test "ask/3 accepts tool_context option" do
      # The function signature should accept opts
      # This is a compile-time check - the function is generated by the macro
      assert :erlang.fun_info(&BasicAgent.ask/3, :arity) == {:arity, 3}
    end
  end

  describe "request lifecycle hooks" do
    test "on_before_cmd marks request as failed on react_request_error" do
      agent = BasicAgent.new()
      agent = Request.start_request(agent, "req_1", "query")

      {:ok, agent, _action} =
        BasicAgent.on_before_cmd(
          agent,
          {:ai_react_request_error, %{request_id: "req_1", reason: :busy, message: "busy"}}
        )

      assert get_in(agent.state, [:requests, "req_1", :status]) == :failed
      assert get_in(agent.state, [:requests, "req_1", :error]) == {:rejected, :busy, "busy"}
    end
  end

  # ============================================================================
  # tools_from_skills/1 Tests
  # ============================================================================

  describe "tools_from_skills/1" do
    defmodule MockSkill do
      def actions, do: [TestCalculator, TestSearch]
    end

    defmodule MockSkill2 do
      def actions, do: [TestSearch]
    end

    test "extracts actions from skill modules" do
      tools = ReActAgent.tools_from_skills([MockSkill])

      assert TestCalculator in tools
      assert TestSearch in tools
    end

    test "deduplicates actions from multiple skills" do
      tools = ReActAgent.tools_from_skills([MockSkill, MockSkill2])

      # Should have unique entries only
      assert length(Enum.filter(tools, &(&1 == TestSearch))) == 1
    end

    test "returns empty list for empty input" do
      assert ReActAgent.tools_from_skills([]) == []
    end
  end
end
