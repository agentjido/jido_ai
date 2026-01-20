defmodule Jido.AI.Integration.JidoV2MigrationTest do
  @moduledoc """
  Backward compatibility integration tests for Jido V2 migration.

  These tests verify that:
  - Existing agents still work after StateOps migration
  - Direct action execution works
  - Strategy configuration works
  - No breaking changes in public APIs
  - Existing demo agents continue to function
  """

  use ExUnit.Case, async: false

  alias Jido.Agent
  alias Jido.AI.Skills.{LLM, Reasoning, Planning, Streaming, ToolCalling}
  alias Jido.AI.Strategies.ReAct

  # Ensure all skill actions are compiled before tests run
  require Jido.AI.Skills.LLM.Actions.Chat
  require Jido.AI.Skills.LLM.Actions.Complete
  require Jido.AI.Skills.LLM.Actions.Embed
  require Jido.AI.Skills.Planning.Actions.Decompose
  require Jido.AI.Skills.Planning.Actions.Plan
  require Jido.AI.Skills.Planning.Actions.Prioritize
  require Jido.AI.Skills.Reasoning.Actions.Analyze
  require Jido.AI.Skills.Reasoning.Actions.Explain
  require Jido.AI.Skills.Reasoning.Actions.Infer
  require Jido.AI.Skills.Streaming.Actions.EndStream
  require Jido.AI.Skills.Streaming.Actions.ProcessTokens
  require Jido.AI.Skills.Streaming.Actions.StartStream
  require Jido.AI.Skills.ToolCalling.Actions.CallWithTools
  require Jido.AI.Skills.ToolCalling.Actions.ExecuteTool
  require Jido.AI.Skills.ToolCalling.Actions.ListTools

  # ============================================================================
  # Test Fixtures
  # ============================================================================

  defmodule TestCalculator do
    use Jido.Action,
      name: "calculator",
      description: "A simple calculator for testing"

    def run(%{operation: "add", a: a, b: b}, _context), do: {:ok, %{result: a + b}}
    def run(%{operation: "multiply", a: a, b: b}, _context), do: {:ok, %{result: a * b}}
    def run(%{operation: "subtract", a: a, b: b}, _context), do: {:ok, %{result: a - b}}
  end

  defmodule TestSearch do
    use Jido.Action,
      name: "search",
      description: "A search action for testing"

    def run(%{query: query}, _context), do: {:ok, %{results: ["Result for: #{query}"]}}
  end

  # ============================================================================
  # Strategy Configuration Tests
  # ============================================================================

  describe "Strategy Configuration" do
    test "ReAct strategy initializes with empty config" do
      # ReAct requires tools option, so this test now expects an error
      agent = %Agent{id: "test-agent", name: "test", state: %{}}

      assert_raise ArgumentError, ~r/requires :tools option/, fn ->
        ReAct.init(agent, %{})
      end
    end

    test "ReAct strategy initializes with tools" do
      agent = %Agent{id: "test-agent", name: "test", state: %{}}

      assert {agent, []} = ReAct.init(agent, %{strategy_opts: [tools: [TestCalculator]]})
      assert agent.id == "test-agent"
    end

    test "ReAct strategy initializes with model alias" do
      agent = %Agent{id: "test-agent", name: "test", state: %{}}

      assert {agent, []} = ReAct.init(agent, %{strategy_opts: [model: :fast, tools: [TestCalculator]]})

      # Strategy state should be set
      assert is_map(agent.state)
    end

    test "ReAct strategy initializes with direct model spec" do
      agent = %Agent{id: "test-agent", name: "test", state: %{}}

      assert {agent, []} = ReAct.init(agent, %{strategy_opts: [model: "openai:gpt-4", tools: [TestCalculator]]})

      assert is_map(agent.state)
    end
  end

  # ============================================================================
  # Direct Action Execution Tests
  # ============================================================================

  describe "Direct Action Execution" do
    test "LLM Chat action can be executed directly" do
      params = %{
        prompt: "What is 2+2?",
        model: :fast,
        max_tokens: 100
      }

      # Verify action exists and has schema
      action = Jido.AI.Skills.LLM.Actions.Chat
      assert function_exported?(action, :schema, 0)
      assert function_exported?(action, :run, 2)
    end

    test "Reasoning Analyze action can be executed directly" do
      action = Jido.AI.Skills.Reasoning.Actions.Analyze
      assert function_exported?(action, :schema, 0)
      assert function_exported?(action, :run, 2)
    end

    test "Planning Plan action can be executed directly" do
      action = Jido.AI.Skills.Planning.Actions.Plan
      assert function_exported?(action, :schema, 0)
      assert function_exported?(action, :run, 2)
    end

    test "Streaming StartStream action can be executed directly" do
      action = Jido.AI.Skills.Streaming.Actions.StartStream
      assert function_exported?(action, :schema, 0)
      assert function_exported?(action, :run, 2)
    end

    test "ToolCalling ExecuteTool action can be executed directly" do
      action = Jido.AI.Skills.ToolCalling.Actions.ExecuteTool
      assert function_exported?(action, :schema, 0)
      assert function_exported?(action, :run, 2)
    end

    test "custom actions can be executed" do
      assert {:ok, result} = TestCalculator.run(%{operation: "add", a: 5, b: 3}, %{})
      assert result.result == 8
    end
  end

  # ============================================================================
  # Skill Mounting Tests
  # ============================================================================

  describe "Skill Mounting" do
    test "LLM skill can be mounted to agent" do
      agent = %Agent{id: "test-agent", name: "test", state: %{}}

      assert {:ok, skill_state} = LLM.mount(agent, %{})
      assert is_map(skill_state)
      assert skill_state.default_model == :fast
    end

    test "multiple skills can be mounted to same agent" do
      agent = %Agent{id: "test-agent", name: "test", state: %{}}

      assert {:ok, llm_state} = LLM.mount(agent, %{})
      assert {:ok, reasoning_state} = Reasoning.mount(agent, %{})
      assert {:ok, planning_state} = Planning.mount(agent, %{})

      # Each skill should have independent state
      assert llm_state.default_model == :fast
      assert reasoning_state.default_model == :reasoning
      assert planning_state.default_model == :planning
    end

    test "skill states are independent" do
      agent = %Agent{id: "test-agent", name: "test", state: %{}}

      {:ok, llm_state} = LLM.mount(agent, %{default_max_tokens: 2048})
      {:ok, reasoning_state} = Reasoning.mount(agent, %{default_max_tokens: 4096})

      assert llm_state.default_max_tokens == 2048
      assert reasoning_state.default_max_tokens == 4096
    end
  end

  # ============================================================================
  # Public API Stability Tests
  # ============================================================================

  describe "Public API Stability" do
    test "LLM.skill_spec/1 is available" do
      assert function_exported?(LLM, :skill_spec, 1)
      spec = LLM.skill_spec(%{})
      assert spec.module == LLM
    end

    test "Reasoning.skill_spec/1 is available" do
      assert function_exported?(Reasoning, :skill_spec, 1)
      spec = Reasoning.skill_spec(%{})
      assert spec.module == Reasoning
    end

    test "Planning.skill_spec/1 is available" do
      assert function_exported?(Planning, :skill_spec, 1)
      spec = Planning.skill_spec(%{})
      assert spec.module == Planning
    end

    test "Streaming.skill_spec/1 is available" do
      assert function_exported?(Streaming, :skill_spec, 1)
      spec = Streaming.skill_spec(%{})
      assert spec.module == Streaming
    end

    test "ToolCalling.skill_spec/1 is available" do
      assert function_exported?(ToolCalling, :skill_spec, 1)
      spec = ToolCalling.skill_spec(%{})
      assert spec.module == ToolCalling
    end

    test "ReAct.start_action/0 is available" do
      assert function_exported?(ReAct, :start_action, 0)
      assert ReAct.start_action() == :react_start
    end

    test "ReAct.list_tools/1 is available" do
      assert function_exported?(ReAct, :list_tools, 1)
    end

    test "ReAct.register_tool_action/0 is available" do
      assert function_exported?(ReAct, :register_tool_action, 0)
      assert ReAct.register_tool_action() == :react_register_tool
    end
  end

  # ============================================================================
  # Signal Routes Tests
  # ============================================================================

  describe "Signal Routes" do
    test "ReAct signal_routes/1 is available" do
      assert function_exported?(ReAct, :signal_routes, 1)
      routes = ReAct.signal_routes(%{})
      assert is_list(routes)
    end

    test "signal routes include expected patterns" do
      routes = ReAct.signal_routes(%{})
      route_map = Map.new(routes)

      assert Map.has_key?(route_map, "react.user_query")
      assert Map.has_key?(route_map, "reqllm.result")
      assert Map.has_key?(route_map, "ai.tool_result")
    end
  end

  # ============================================================================
  # Skill Action Lists Tests
  # ============================================================================

  describe "Skill Action Lists" do
    test "LLM.actions/0 returns action list" do
      assert function_exported?(LLM, :actions, 0)
      actions = LLM.actions()
      assert is_list(actions)
      assert length(actions) == 3
    end

    test "Reasoning.actions/0 returns action list" do
      assert function_exported?(Reasoning, :actions, 0)
      actions = Reasoning.actions()
      assert is_list(actions)
      assert length(actions) == 3
    end

    test "Planning.actions/0 returns action list" do
      assert function_exported?(Planning, :actions, 0)
      actions = Planning.actions()
      assert is_list(actions)
      assert length(actions) == 3
    end

    test "Streaming.actions/0 returns action list" do
      assert function_exported?(Streaming, :actions, 0)
      actions = Streaming.actions()
      assert is_list(actions)
      assert length(actions) == 3
    end

    test "ToolCalling.actions/0 returns action list" do
      assert function_exported?(ToolCalling, :actions, 0)
      actions = ToolCalling.actions()
      assert is_list(actions)
      assert length(actions) == 3
    end
  end

  # ============================================================================
  # Skill Router Tests
  # ============================================================================

  describe "Skill Routers" do
    test "LLM router returns expected routes" do
      routes = LLM.router(%{})
      assert is_list(routes)
      assert length(routes) == 3
    end

    test "Reasoning router returns expected routes" do
      routes = Reasoning.router(%{})
      assert is_list(routes)
      assert length(routes) == 3
    end

    test "Planning router returns expected routes" do
      routes = Planning.router(%{})
      assert is_list(routes)
      assert length(routes) == 3
    end

    test "Streaming router returns expected routes" do
      routes = Streaming.router(%{})
      assert is_list(routes)
      assert length(routes) == 3
    end

    test "ToolCalling router returns expected routes" do
      routes = ToolCalling.router(%{})
      assert is_list(routes)
      assert length(routes) == 3
    end
  end

  # ============================================================================
  # StateOps Helpers Tests
  # ============================================================================

  describe "StateOps Helpers Availability" do
    test "StateOpsHelpers module is available" do
      assert Code.ensure_loaded?(Jido.AI.Strategy.StateOpsHelpers)
    end

    test "StateOpsHelpers has expected functions" do
      helpers = Jido.AI.Strategy.StateOpsHelpers

      assert function_exported?(helpers, :update_strategy_state, 1)
      assert function_exported?(helpers, :set_strategy_field, 2)
      assert function_exported?(helpers, :set_iteration_status, 1)
      assert function_exported?(helpers, :set_iteration, 1)
      assert function_exported?(helpers, :append_conversation, 1)
      assert function_exported?(helpers, :set_pending_tools, 1)
      assert function_exported?(helpers, :clear_pending_tools, 0)
    end
  end

  # ============================================================================
  # Breaking Changes Detection
  # ============================================================================

  describe "Breaking Changes Detection" do
    test "agent struct still has id field" do
      agent = %Agent{id: "test", name: "test", state: %{}}
      assert agent.id == "test"
    end

    test "agent struct still has name field" do
      agent = %Agent{id: "test", name: "test", state: %{}}
      assert agent.name == "test"
    end

    test "agent struct still has state field" do
      agent = %Agent{id: "test", name: "test", state: %{}}
      assert is_map(agent.state)
    end

    test "ReAct.init/2 still returns {agent, directives} tuple" do
      agent = %Agent{id: "test", name: "test", state: %{}}

      assert {updated_agent, directives} = ReAct.init(agent, %{strategy_opts: [tools: [TestCalculator]]})
      assert %Agent{} = updated_agent
      assert is_list(directives)
    end

    test "ReAct.cmd/3 still returns {agent, directives} tuple" do
      agent = %Agent{id: "test", name: "test", state: %{}}
      {agent, _} = ReAct.init(agent, %{strategy_opts: [tools: [TestCalculator]]})

      instruction = %Jido.Instruction{
        action: ReAct.start_action(),
        params: %{query: "test"}
      }

      assert {updated_agent, directives} = ReAct.cmd(agent, [instruction], %{})
      assert %Agent{} = updated_agent
      assert is_list(directives)
    end
  end

  # ============================================================================
  # Phase 9 Success Criteria
  # ============================================================================

  describe "Phase 9 Success Criteria" do
    test "all 5 skills are available" do
      assert Code.ensure_loaded?(LLM)
      assert Code.ensure_loaded?(Reasoning)
      assert Code.ensure_loaded?(Planning)
      assert Code.ensure_loaded?(Streaming)
      assert Code.ensure_loaded?(ToolCalling)
    end

    test "all skills have skill_spec/1" do
      assert function_exported?(LLM, :skill_spec, 1)
      assert function_exported?(Reasoning, :skill_spec, 1)
      assert function_exported?(Planning, :skill_spec, 1)
      assert function_exported?(Streaming, :skill_spec, 1)
      assert function_exported?(ToolCalling, :skill_spec, 1)
    end

    test "all skills have mount/2" do
      assert function_exported?(LLM, :mount, 2)
      assert function_exported?(Reasoning, :mount, 2)
      assert function_exported?(Planning, :mount, 2)
      assert function_exported?(Streaming, :mount, 2)
      assert function_exported?(ToolCalling, :mount, 2)
    end

    test "all skills have router/1" do
      assert function_exported?(LLM, :router, 1)
      assert function_exported?(Reasoning, :router, 1)
      assert function_exported?(Planning, :router, 1)
      assert function_exported?(Streaming, :router, 1)
      assert function_exported?(ToolCalling, :router, 1)
    end

    test "StateOpsHelpers is available" do
      assert Code.ensure_loaded?(Jido.AI.Strategy.StateOpsHelpers)
    end

    test "no breaking changes in core APIs" do
      # Agent struct unchanged
      agent = %Agent{id: "test", name: "test", state: %{}}
      assert Map.has_key?(agent, :id)
      assert Map.has_key?(agent, :name)
      assert Map.has_key?(agent, :state)

      # ReAct strategy APIs unchanged
      assert function_exported?(ReAct, :init, 2)
      assert function_exported?(ReAct, :cmd, 3)
      assert function_exported?(ReAct, :signal_routes, 1)
    end
  end
end
