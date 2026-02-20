defmodule Jido.AI.Integration.JidoV2MigrationTest do
  @moduledoc """
  Contract integration tests for the current public plugin and strategy surface.
  """

  use ExUnit.Case, async: false

  alias Jido.Agent
  alias Jido.AI.Plugins.Chat
  alias Jido.AI.Plugins.Planning
  alias Jido.AI.Plugins.Reasoning.{Adaptive, AlgorithmOfThoughts, ChainOfThought, GraphOfThoughts, TRM, TreeOfThoughts}
  alias Jido.AI.Reasoning.ReAct.Strategy, as: ReAct

  require Jido.AI.Actions.LLM.Chat
  require Jido.AI.Actions.LLM.Complete
  require Jido.AI.Actions.LLM.Embed
  require Jido.AI.Actions.LLM.GenerateObject
  require Jido.AI.Actions.Planning.Decompose
  require Jido.AI.Actions.Planning.Plan
  require Jido.AI.Actions.Planning.Prioritize
  require Jido.AI.Actions.Reasoning.RunStrategy
  require Jido.AI.Actions.ToolCalling.CallWithTools
  require Jido.AI.Actions.ToolCalling.ExecuteTool
  require Jido.AI.Actions.ToolCalling.ListTools

  defmodule TestCalculator do
    use Jido.Action,
      name: "calculator",
      description: "A simple calculator for testing"

    def run(%{operation: "add", a: a, b: b}, _context), do: {:ok, %{result: a + b}}
    def run(%{operation: "multiply", a: a, b: b}, _context), do: {:ok, %{result: a * b}}
    def run(%{operation: "subtract", a: a, b: b}, _context), do: {:ok, %{result: a - b}}
  end

  defmodule PluginFallbackAction do
    use Jido.Action,
      name: "plugin_fallback_action",
      description: "sets a marker in state"

    def run(_params, _context), do: {:ok, %{plugin_fallback_executed: true}}
  end

  describe "Strategy Configuration" do
    test "ReAct strategy initializes with tools" do
      agent = %Agent{id: "test-agent", name: "test", state: %{}}

      assert {agent, []} = ReAct.init(agent, %{strategy_opts: [tools: [TestCalculator]]})
      assert agent.id == "test-agent"
    end

    test "ReAct strategy initializes with model alias" do
      agent = %Agent{id: "test-agent", name: "test", state: %{}}

      assert {agent, []} = ReAct.init(agent, %{strategy_opts: [model: :fast, tools: [TestCalculator]]})
      assert is_map(agent.state)
    end

    test "ReAct strategy executes plugin-routed module actions through fallback" do
      agent = %Agent{id: "test-agent", name: "test", state: %{}}
      {agent, _} = ReAct.init(agent, %{strategy_opts: [tools: [TestCalculator]]})

      instruction = %Jido.Instruction{action: PluginFallbackAction, params: %{}}

      {updated_agent, directives} =
        ReAct.cmd(agent, [instruction], %{agent_module: __MODULE__, strategy_opts: [tools: [TestCalculator]]})

      assert updated_agent.state.plugin_fallback_executed == true
      assert is_list(directives)
    end
  end

  describe "Direct Action Execution" do
    test "Chat action is available" do
      action = Jido.AI.Actions.LLM.Chat
      assert function_exported?(action, :schema, 0)
      assert function_exported?(action, :run, 2)
    end

    test "RunStrategy action is available" do
      action = Jido.AI.Actions.Reasoning.RunStrategy
      assert function_exported?(action, :schema, 0)
      assert function_exported?(action, :run, 2)
    end

    test "Planning and tool actions are available" do
      assert function_exported?(Jido.AI.Actions.Planning.Plan, :run, 2)
      assert function_exported?(Jido.AI.Actions.ToolCalling.ExecuteTool, :run, 2)
    end
  end

  describe "Plugin Mounting" do
    test "Chat plugin can be mounted" do
      agent = %Agent{id: "test-agent", name: "test", state: %{}}

      assert {:ok, plugin_state} = Chat.mount(agent, %{})
      assert is_map(plugin_state)
      assert plugin_state.default_model == :capable
    end

    test "strategy plugins can be mounted" do
      agent = %Agent{id: "test-agent", name: "test", state: %{}}

      assert {:ok, cot_state} = ChainOfThought.mount(agent, %{})
      assert {:ok, aot_state} = AlgorithmOfThoughts.mount(agent, %{})
      assert {:ok, adaptive_state} = Adaptive.mount(agent, %{})

      assert cot_state.strategy == :cot
      assert aot_state.strategy == :aot
      assert adaptive_state.strategy == :adaptive
    end

    test "plugin states are independent" do
      agent = %Agent{id: "test-agent", name: "test", state: %{}}

      {:ok, chat_state} = Chat.mount(agent, %{default_max_tokens: 2048})
      {:ok, planning_state} = Planning.mount(agent, %{default_max_tokens: 4096})

      assert chat_state.default_max_tokens == 2048
      assert planning_state.default_max_tokens == 4096
    end
  end

  describe "Public API Stability" do
    test "plugin_spec/1 is available for public plugins" do
      for plugin <- [
            Chat,
            Planning,
            ChainOfThought,
            AlgorithmOfThoughts,
            TreeOfThoughts,
            GraphOfThoughts,
            TRM,
            Adaptive
          ] do
        assert function_exported?(plugin, :plugin_spec, 1)
        spec = plugin.plugin_spec(%{})
        assert spec.module == plugin
      end
    end

    test "ReAct.start_action/0 is available" do
      assert function_exported?(ReAct, :start_action, 0)
      assert ReAct.start_action() == :ai_react_start
    end
  end

  describe "Signal Routes" do
    test "ReAct signal_routes/1 is available" do
      assert function_exported?(ReAct, :signal_routes, 1)
      routes = ReAct.signal_routes(%{})
      assert is_list(routes)
    end

    test "ReAct routes include expected patterns" do
      routes = ReAct.signal_routes(%{})
      route_map = Map.new(routes)

      assert Map.has_key?(route_map, "ai.react.query")
      assert Map.has_key?(route_map, "ai.react.worker.event")
      assert route_map["ai.llm.response"] == Jido.Actions.Control.Noop
      assert route_map["ai.tool.result"] == Jido.Actions.Control.Noop
    end

    test "chat and reasoning plugin routes include expected patterns" do
      chat_routes = Map.new(Chat.signal_routes(%{}))

      assert Map.has_key?(chat_routes, "chat.message")
      assert Map.has_key?(chat_routes, "chat.list_tools")

      assert Map.has_key?(Map.new(ChainOfThought.signal_routes(%{})), "reasoning.cot.run")
      assert Map.has_key?(Map.new(AlgorithmOfThoughts.signal_routes(%{})), "reasoning.aot.run")
      assert Map.has_key?(Map.new(TreeOfThoughts.signal_routes(%{})), "reasoning.tot.run")
      assert Map.has_key?(Map.new(GraphOfThoughts.signal_routes(%{})), "reasoning.got.run")
      assert Map.has_key?(Map.new(TRM.signal_routes(%{})), "reasoning.trm.run")
      assert Map.has_key?(Map.new(Adaptive.signal_routes(%{})), "reasoning.adaptive.run")
    end
  end

  describe "Strict Break Contracts" do
    test "legacy plugin modules are not part of the public surface" do
      refute Code.ensure_loaded?(Jido.AI.Plugins.LLM)
      refute Code.ensure_loaded?(Jido.AI.Plugins.ToolCalling)
      refute Code.ensure_loaded?(Jido.AI.Plugins.Reasoning)
    end

    test "legacy react.* signal names are not routed" do
      route_map = ReAct.signal_routes(%{}) |> Map.new()

      refute Map.has_key?(route_map, "react.input")
      refute Map.has_key?(route_map, "react.cancel")
      refute Map.has_key?(route_map, "react.llm.response")
      refute Map.has_key?(route_map, "react.tool.result")
      refute Map.has_key?(route_map, "react.request.error")
    end
  end

  describe "Helpers Availability" do
    test "Helpers module is available" do
      assert Code.ensure_loaded?(Jido.AI.Reasoning.Helpers)
    end

    test "Helpers has expected runtime fallback functions" do
      helpers = Jido.AI.Reasoning.Helpers

      assert function_exported?(helpers, :maybe_execute_action_instruction, 3)
      assert function_exported?(helpers, :execute_action_instruction, 3)
      assert function_exported?(helpers, :action_context, 2)
    end
  end
end
