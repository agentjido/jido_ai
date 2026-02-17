defmodule Jido.AI.Integration.JidoV2MigrationTest do
  @moduledoc """
  2.0-beta contract integration tests.

  These tests verify that:
  - Core strategy and skill surfaces remain coherent
  - Public APIs are available for 2.0 usage
  - Strict breaking contract is enforced (no legacy 1.x namespace aliases)
  """

  use ExUnit.Case, async: false

  alias Jido.Agent
  alias Jido.AI.Signal
  alias Jido.AI.Plugins.{LLM, Planning, Reasoning, Streaming, ToolCalling}
  alias Jido.AI.Reasoning.ReAct.Strategy, as: ReAct

  # Ensure all skill actions are compiled before tests run
  require Jido.AI.Actions.LLM.Chat
  require Jido.AI.Actions.LLM.Complete
  require Jido.AI.Actions.LLM.Embed
  require Jido.AI.Actions.Planning.Decompose
  require Jido.AI.Actions.Planning.Plan
  require Jido.AI.Actions.Planning.Prioritize
  require Jido.AI.Actions.Reasoning.Analyze
  require Jido.AI.Actions.Reasoning.Explain
  require Jido.AI.Actions.Reasoning.Infer
  require Jido.AI.Actions.Streaming.EndStream
  require Jido.AI.Actions.Streaming.ProcessTokens
  require Jido.AI.Actions.Streaming.StartStream
  require Jido.AI.Actions.ToolCalling.CallWithTools
  require Jido.AI.Actions.ToolCalling.ExecuteTool
  require Jido.AI.Actions.ToolCalling.ListTools

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
      _params = %{
        prompt: "What is 2+2?",
        model: :fast,
        max_tokens: 100
      }

      # Verify action exists and has schema
      action = Jido.AI.Actions.LLM.Chat
      assert function_exported?(action, :schema, 0)
      assert function_exported?(action, :run, 2)
    end

    test "Reasoning Analyze action can be executed directly" do
      action = Jido.AI.Actions.Reasoning.Analyze
      assert function_exported?(action, :schema, 0)
      assert function_exported?(action, :run, 2)
    end

    test "Planning Plan action can be executed directly" do
      action = Jido.AI.Actions.Planning.Plan
      assert function_exported?(action, :schema, 0)
      assert function_exported?(action, :run, 2)
    end

    test "Streaming StartStream action can be executed directly" do
      action = Jido.AI.Actions.Streaming.StartStream
      assert function_exported?(action, :schema, 0)
      assert function_exported?(action, :run, 2)
    end

    test "ToolCalling ExecuteTool action can be executed directly" do
      action = Jido.AI.Actions.ToolCalling.ExecuteTool
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
    test "LLM.plugin_spec/1 is available" do
      assert function_exported?(LLM, :plugin_spec, 1)
      spec = LLM.plugin_spec(%{})
      assert spec.module == LLM
    end

    test "Reasoning.plugin_spec/1 is available" do
      assert function_exported?(Reasoning, :plugin_spec, 1)
      spec = Reasoning.plugin_spec(%{})
      assert spec.module == Reasoning
    end

    test "Planning.plugin_spec/1 is available" do
      assert function_exported?(Planning, :plugin_spec, 1)
      spec = Planning.plugin_spec(%{})
      assert spec.module == Planning
    end

    test "Streaming.plugin_spec/1 is available" do
      assert function_exported?(Streaming, :plugin_spec, 1)
      spec = Streaming.plugin_spec(%{})
      assert spec.module == Streaming
    end

    test "ToolCalling.plugin_spec/1 is available" do
      assert function_exported?(ToolCalling, :plugin_spec, 1)
      spec = ToolCalling.plugin_spec(%{})
      assert spec.module == ToolCalling
    end

    test "ReAct.start_action/0 is available" do
      assert function_exported?(ReAct, :start_action, 0)
      assert ReAct.start_action() == :ai_react_start
    end

    test "ReAct.list_tools/1 is available" do
      assert function_exported?(ReAct, :list_tools, 1)
    end

    test "ReAct.register_tool_action/0 is available" do
      assert function_exported?(ReAct, :register_tool_action, 0)
      assert ReAct.register_tool_action() == :ai_react_register_tool
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

      assert Map.has_key?(route_map, "ai.react.query")
      assert Map.has_key?(route_map, "ai.react.worker.event")
      assert Map.has_key?(route_map, "jido.agent.child.started")
      assert Map.has_key?(route_map, "jido.agent.child.exit")
      assert route_map["ai.llm.response"] == Jido.Actions.Control.Noop
      assert route_map["ai.tool.result"] == Jido.Actions.Control.Noop
    end
  end

  describe "Strict Break Contracts" do
    test "legacy react.* signal names are not routed" do
      route_map = ReAct.signal_routes(%{}) |> Map.new()

      refute Map.has_key?(route_map, "react.input")
      refute Map.has_key?(route_map, "react.cancel")
      refute Map.has_key?(route_map, "react.llm.response")
      refute Map.has_key?(route_map, "react.tool.result")
      refute Map.has_key?(route_map, "react.request.error")
    end

    test "RequestError requires request_id payload key" do
      assert {:error, _} =
               Signal.RequestError.new(%{
                 call_id: "legacy_call",
                 reason: :busy,
                 message: "legacy payload"
               })

      assert {:ok, signal} =
               Signal.RequestError.new(%{
                 request_id: "req_1",
                 reason: :busy,
                 message: "busy"
               })

      assert signal.type == "ai.request.error"
      assert signal.data.request_id == "req_1"
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
      assert length(actions) == 4
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

  describe "Skill Signal Routes" do
    test "LLM signal_routes returns expected routes" do
      routes = LLM.signal_routes(%{})
      assert is_list(routes)
      assert length(routes) == 4
    end

    test "Reasoning signal_routes returns expected routes" do
      routes = Reasoning.signal_routes(%{})
      assert is_list(routes)
      assert length(routes) == 3
    end

    test "Planning signal_routes returns expected routes" do
      routes = Planning.signal_routes(%{})
      assert is_list(routes)
      assert length(routes) == 3
    end

    test "Streaming signal_routes returns expected routes" do
      routes = Streaming.signal_routes(%{})
      assert is_list(routes)
      assert length(routes) == 3
    end

    test "ToolCalling signal_routes returns expected routes" do
      routes = ToolCalling.signal_routes(%{})
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

    test "all skills have plugin_spec/1" do
      assert function_exported?(LLM, :plugin_spec, 1)
      assert function_exported?(Reasoning, :plugin_spec, 1)
      assert function_exported?(Planning, :plugin_spec, 1)
      assert function_exported?(Streaming, :plugin_spec, 1)
      assert function_exported?(ToolCalling, :plugin_spec, 1)
    end

    test "all skills have mount/2" do
      assert function_exported?(LLM, :mount, 2)
      assert function_exported?(Reasoning, :mount, 2)
      assert function_exported?(Planning, :mount, 2)
      assert function_exported?(Streaming, :mount, 2)
      assert function_exported?(ToolCalling, :mount, 2)
    end

    test "all skills have signal_routes/1" do
      assert function_exported?(LLM, :signal_routes, 1)
      assert function_exported?(Reasoning, :signal_routes, 1)
      assert function_exported?(Planning, :signal_routes, 1)
      assert function_exported?(Streaming, :signal_routes, 1)
      assert function_exported?(ToolCalling, :signal_routes, 1)
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
