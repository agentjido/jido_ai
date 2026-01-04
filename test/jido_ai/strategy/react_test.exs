defmodule Jido.AI.Strategy.ReActTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Strategy.ReAct
  alias Jido.AI.Config
  alias Jido.Agent.Strategy.State, as: StratState

  # Test action module
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

  # Helper to create a mock agent
  defp create_agent(opts \\ []) do
    %Jido.Agent{
      id: "test-agent",
      name: "test",
      state: %{}
    }
    |> then(fn agent ->
      ctx = %{strategy_opts: opts}
      {agent, []} = ReAct.init(agent, ctx)
      agent
    end)
  end

  # ============================================================================
  # Model Alias Resolution
  # ============================================================================

  describe "model alias resolution" do
    test "resolves :fast alias to full model spec" do
      agent = create_agent(tools: [TestCalculator], model: :fast)
      state = StratState.get(agent, %{})
      config = state[:config]

      assert config.model == Config.resolve_model(:fast)
      assert is_binary(config.model)
      assert String.contains?(config.model, ":")
    end

    test "resolves :capable alias to full model spec" do
      agent = create_agent(tools: [TestCalculator], model: :capable)
      state = StratState.get(agent, %{})
      config = state[:config]

      assert config.model == Config.resolve_model(:capable)
    end

    test "passes through string model specs unchanged" do
      agent = create_agent(tools: [TestCalculator], model: "openai:gpt-4")
      state = StratState.get(agent, %{})
      config = state[:config]

      assert config.model == "openai:gpt-4"
    end

    test "uses default model when not specified" do
      agent = create_agent(tools: [TestCalculator])
      state = StratState.get(agent, %{})
      config = state[:config]

      # Default is "anthropic:claude-haiku-4-5"
      assert config.model == "anthropic:claude-haiku-4-5"
    end
  end

  # ============================================================================
  # Snapshot with Usage and Duration
  # ============================================================================

  describe "snapshot/2" do
    test "includes usage in details when present" do
      agent = create_agent(tools: [TestCalculator])

      # Manually set usage in state
      state = StratState.get(agent, %{})
      state = put_in(state, [:usage], %{input_tokens: 100, output_tokens: 50})
      agent = StratState.put(agent, state)

      snapshot = ReAct.snapshot(agent, %{})

      assert snapshot.details[:usage] == %{input_tokens: 100, output_tokens: 50}
    end

    test "includes duration_ms when started_at is set" do
      agent = create_agent(tools: [TestCalculator])

      # Manually set started_at
      state = StratState.get(agent, %{})
      started_at = System.monotonic_time(:millisecond) - 1000
      state = put_in(state, [:started_at], started_at)
      agent = StratState.put(agent, state)

      snapshot = ReAct.snapshot(agent, %{})

      assert is_integer(snapshot.details[:duration_ms])
      assert snapshot.details[:duration_ms] >= 1000
    end

    test "excludes empty usage from details" do
      agent = create_agent(tools: [TestCalculator])
      snapshot = ReAct.snapshot(agent, %{})

      # Empty usage should not be included
      refute Map.has_key?(snapshot.details, :usage)
    end
  end

  # ============================================================================
  # Dynamic Tool Registration
  # ============================================================================

  describe "dynamic tool registration" do
    test "register_tool adds tool to config" do
      agent = create_agent(tools: [TestCalculator])

      # Get initial tools
      initial_tools = ReAct.list_tools(agent)
      assert TestCalculator in initial_tools
      refute TestSearch in initial_tools

      # Register new tool
      instruction = %Jido.Instruction{
        action: ReAct.register_tool_action(),
        params: %{tool_module: TestSearch}
      }

      {agent, _directives} = ReAct.cmd(agent, [instruction], %{})

      # Verify tool was added
      tools = ReAct.list_tools(agent)
      assert TestCalculator in tools
      assert TestSearch in tools
    end

    test "unregister_tool removes tool from config" do
      agent = create_agent(tools: [TestCalculator, TestSearch])

      # Verify both tools present
      initial_tools = ReAct.list_tools(agent)
      assert TestCalculator in initial_tools
      assert TestSearch in initial_tools

      # Unregister search
      instruction = %Jido.Instruction{
        action: ReAct.unregister_tool_action(),
        params: %{tool_name: "search"}
      }

      {agent, _directives} = ReAct.cmd(agent, [instruction], %{})

      # Verify search was removed
      tools = ReAct.list_tools(agent)
      assert TestCalculator in tools
      refute TestSearch in tools
    end

    test "register_tool updates actions_by_name" do
      agent = create_agent(tools: [TestCalculator])

      # Register new tool
      instruction = %Jido.Instruction{
        action: ReAct.register_tool_action(),
        params: %{tool_module: TestSearch}
      }

      {agent, _directives} = ReAct.cmd(agent, [instruction], %{})

      # Verify actions_by_name was updated
      state = StratState.get(agent, %{})
      config = state[:config]

      assert Map.has_key?(config.actions_by_name, "search")
      assert config.actions_by_name["search"] == TestSearch
    end
  end

  # ============================================================================
  # Action Specs
  # ============================================================================

  describe "action_spec/1" do
    test "returns spec for start action" do
      spec = ReAct.action_spec(ReAct.start_action())
      assert spec.name == "react.start"
      assert spec.doc =~ "Start a new ReAct conversation"
    end

    test "returns spec for register_tool action" do
      spec = ReAct.action_spec(ReAct.register_tool_action())
      assert spec.name == "react.register_tool"
      assert spec.doc =~ "Register a new tool"
    end

    test "returns spec for unregister_tool action" do
      spec = ReAct.action_spec(ReAct.unregister_tool_action())
      assert spec.name == "react.unregister_tool"
      assert spec.doc =~ "Unregister a tool"
    end

    test "returns nil for unknown action" do
      assert ReAct.action_spec(:unknown_action) == nil
    end
  end

  # ============================================================================
  # Signal Routes
  # ============================================================================

  describe "signal_routes/1" do
    test "returns expected signal routes" do
      routes = ReAct.signal_routes(%{})

      route_map = Map.new(routes)

      assert route_map["react.user_query"] == {:strategy_cmd, :react_start}
      assert route_map["reqllm.result"] == {:strategy_cmd, :react_llm_result}
      assert route_map["ai.tool_result"] == {:strategy_cmd, :react_tool_result}
      assert route_map["reqllm.partial"] == {:strategy_cmd, :react_llm_partial}
    end
  end

  # ============================================================================
  # use_registry Option
  # ============================================================================

  describe "use_registry option" do
    test "defaults to false" do
      agent = create_agent(tools: [TestCalculator])
      state = StratState.get(agent, %{})
      config = state[:config]

      assert config.use_registry == false
    end

    test "can be set to true" do
      agent = create_agent(tools: [TestCalculator], use_registry: true)
      state = StratState.get(agent, %{})
      config = state[:config]

      assert config.use_registry == true
    end
  end

  # ============================================================================
  # Public Helper Functions
  # ============================================================================

  describe "action helper functions" do
    test "start_action/0 returns correct atom" do
      assert ReAct.start_action() == :react_start
    end

    test "llm_result_action/0 returns correct atom" do
      assert ReAct.llm_result_action() == :react_llm_result
    end

    test "tool_result_action/0 returns correct atom" do
      assert ReAct.tool_result_action() == :react_tool_result
    end

    test "llm_partial_action/0 returns correct atom" do
      assert ReAct.llm_partial_action() == :react_llm_partial
    end

    test "register_tool_action/0 returns correct atom" do
      assert ReAct.register_tool_action() == :react_register_tool
    end

    test "unregister_tool_action/0 returns correct atom" do
      assert ReAct.unregister_tool_action() == :react_unregister_tool
    end
  end

  # ============================================================================
  # list_tools/1
  # ============================================================================

  describe "list_tools/1" do
    test "returns list of tool modules" do
      agent = create_agent(tools: [TestCalculator, TestSearch])
      tools = ReAct.list_tools(agent)

      assert is_list(tools)
      assert TestCalculator in tools
      assert TestSearch in tools
    end

    test "returns empty list for agent without config" do
      # Create a bare agent without init
      agent = %Jido.Agent{
        id: "bare-agent",
        name: "bare",
        state: %{}
      }

      tools = ReAct.list_tools(agent)
      assert tools == []
    end
  end
end
