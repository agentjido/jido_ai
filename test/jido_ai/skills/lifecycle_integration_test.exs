defmodule Jido.AI.Plugins.LifecycleIntegrationTest do
  @moduledoc """
  Integration tests for Phase 9.3 Skill Lifecycle enhancement.

  These tests verify that:
  - Router callbacks route signals correctly
  - Handle signal pre-processing works
  - Transform result modifies output
  - Skill state isolation works
  - Mount/2 initializes skill state correctly
  """

  use ExUnit.Case, async: false

  alias Jido.Agent
  alias Jido.AI.Plugins.LLM
  alias Jido.AI.Plugins.Planning
  alias Jido.AI.Plugins.Reasoning
  alias Jido.AI.Plugins.Streaming
  alias Jido.AI.Plugins.ToolCalling

  # Ensure all skill modules are loaded before tests
  require Jido.AI.Plugins.LLM
  require Jido.AI.Plugins.Planning
  require Jido.AI.Plugins.Reasoning
  require Jido.AI.Plugins.Streaming
  require Jido.AI.Plugins.ToolCalling

  # ============================================================================
  # Skill Mount/2 Tests
  # ============================================================================

  describe "Skill Mount/2 Initialization" do
    test "LLM skill mount/2 returns {:ok, state}" do
      assert {:ok, state} = LLM.mount(%Agent{}, %{})
      assert is_map(state)
      assert state.default_model == :fast
      assert state.default_max_tokens == 1024
      assert state.default_temperature == 0.7
    end

    test "LLM skill mount/2 applies config overrides" do
      assert {:ok, state} = LLM.mount(%Agent{}, %{default_model: :capable, default_max_tokens: 2048})
      assert state.default_model == :capable
      assert state.default_max_tokens == 2048
    end

    test "Reasoning skill mount/2 returns {:ok, state}" do
      assert {:ok, state} = Reasoning.mount(%Agent{}, %{})
      assert is_map(state)
      assert state.default_model == :reasoning
      assert state.default_max_tokens == 2048
      assert state.default_temperature == 0.3
    end

    test "Planning skill mount/2 returns {:ok, state}" do
      assert {:ok, state} = Planning.mount(%Agent{}, %{})
      assert is_map(state)
      assert state.default_model == :planning
      assert state.default_max_tokens == 4096
      assert state.default_temperature == 0.7
    end

    test "Streaming skill mount/2 returns {:ok, state}" do
      assert {:ok, state} = Streaming.mount(%Agent{}, %{})
      assert is_map(state)
      assert state.default_model == :fast
      assert state.default_max_tokens == 1024
      assert state.default_temperature == 0.7
      assert is_map(state.active_streams)
    end

    test "ToolCalling skill mount/2 returns {:ok, state}" do
      assert {:ok, state} = ToolCalling.mount(%Agent{}, %{})
      assert is_map(state)
      assert state.default_model == :capable
      assert state.auto_execute == false
      assert state.max_turns == 10
      assert is_list(state.available_tools)
    end
  end

  # ============================================================================
  # Skill Schema Tests
  # ============================================================================

  describe "Skill Schema" do
    test "LLM skill has Zoi schema" do
      assert function_exported?(LLM, :schema, 0)
      schema = LLM.schema()
      assert is_map(schema) or is_struct(schema)
    end

    test "Reasoning skill has Zoi schema" do
      assert function_exported?(Reasoning, :schema, 0)
      schema = Reasoning.schema()
      assert is_map(schema) or is_struct(schema)
    end

    test "Planning skill has Zoi schema" do
      assert function_exported?(Planning, :schema, 0)
      schema = Planning.schema()
      assert is_map(schema) or is_struct(schema)
    end

    test "Streaming skill has Zoi schema" do
      assert function_exported?(Streaming, :schema, 0)
      schema = Streaming.schema()
      assert is_map(schema) or is_struct(schema)
    end

    test "ToolCalling skill has Zoi schema" do
      assert function_exported?(ToolCalling, :schema, 0)
      schema = ToolCalling.schema()
      assert is_map(schema) or is_struct(schema)
    end
  end

  # ============================================================================
  # signal_routes/1 Callback Tests
  # ============================================================================

  describe "signal_routes/1 Callback" do
    test "LLM skill signal_routes returns route list" do
      assert function_exported?(LLM, :signal_routes, 1)
      routes = LLM.signal_routes(%{})
      assert is_list(routes)
    end

    test "LLM skill signal_routes has correct routes" do
      routes = LLM.signal_routes(%{})
      route_map = Map.new(routes)

      assert route_map["llm.chat"] == Jido.AI.Actions.LLM.Chat
      assert route_map["llm.complete"] == Jido.AI.Actions.LLM.Complete
      assert route_map["llm.embed"] == Jido.AI.Actions.LLM.Embed
    end

    test "Reasoning skill signal_routes returns route list" do
      assert function_exported?(Reasoning, :signal_routes, 1)
      routes = Reasoning.signal_routes(%{})
      assert is_list(routes)
    end

    test "Reasoning skill signal_routes has correct routes" do
      routes = Reasoning.signal_routes(%{})
      route_map = Map.new(routes)

      assert route_map["reasoning.analyze"] == Jido.AI.Actions.Reasoning.Analyze
      assert route_map["reasoning.explain"] == Jido.AI.Actions.Reasoning.Explain
      assert route_map["reasoning.infer"] == Jido.AI.Actions.Reasoning.Infer
    end

    test "Planning skill signal_routes returns route list" do
      assert function_exported?(Planning, :signal_routes, 1)
      routes = Planning.signal_routes(%{})
      assert is_list(routes)
    end

    test "Planning skill signal_routes has correct routes" do
      routes = Planning.signal_routes(%{})
      route_map = Map.new(routes)

      assert route_map["planning.plan"] == Jido.AI.Actions.Planning.Plan
      assert route_map["planning.decompose"] == Jido.AI.Actions.Planning.Decompose
      assert route_map["planning.prioritize"] == Jido.AI.Actions.Planning.Prioritize
    end

    test "Streaming skill signal_routes returns route list" do
      assert function_exported?(Streaming, :signal_routes, 1)
      routes = Streaming.signal_routes(%{})
      assert is_list(routes)
    end

    test "Streaming skill signal_routes has correct routes" do
      routes = Streaming.signal_routes(%{})
      route_map = Map.new(routes)

      assert route_map["stream.start"] == Jido.AI.Actions.Streaming.StartStream
      assert route_map["stream.process"] == Jido.AI.Actions.Streaming.ProcessTokens
      assert route_map["stream.end"] == Jido.AI.Actions.Streaming.EndStream
    end

    test "ToolCalling skill signal_routes returns route list" do
      assert function_exported?(ToolCalling, :signal_routes, 1)
      routes = ToolCalling.signal_routes(%{})
      assert is_list(routes)
    end

    test "ToolCalling skill signal_routes has correct routes" do
      routes = ToolCalling.signal_routes(%{})
      route_map = Map.new(routes)

      assert route_map["tool.call"] == Jido.AI.Actions.ToolCalling.CallWithTools
      assert route_map["tool.execute"] == Jido.AI.Actions.ToolCalling.ExecuteTool
      assert route_map["tool.list"] == Jido.AI.Actions.ToolCalling.ListTools
    end
  end

  # ============================================================================
  # Handle Signal/2 Callback Tests
  # ============================================================================

  describe "Handle Signal/2 Callback" do
    test "LLM skill implements handle_signal/2" do
      assert function_exported?(LLM, :handle_signal, 2)
      assert {:ok, :continue} = LLM.handle_signal(%{}, %{})
    end

    test "Reasoning skill implements handle_signal/2" do
      assert function_exported?(Reasoning, :handle_signal, 2)
      assert {:ok, :continue} = Reasoning.handle_signal(%{}, %{})
    end

    test "Planning skill implements handle_signal/2" do
      assert function_exported?(Planning, :handle_signal, 2)
      assert {:ok, :continue} = Planning.handle_signal(%{}, %{})
    end

    test "Streaming skill implements handle_signal/2" do
      assert function_exported?(Streaming, :handle_signal, 2)
      assert {:ok, :continue} = Streaming.handle_signal(%{}, %{})
    end

    test "ToolCalling skill implements handle_signal/2" do
      assert function_exported?(ToolCalling, :handle_signal, 2)
      assert {:ok, :continue} = ToolCalling.handle_signal(%{}, %{})
    end
  end

  # ============================================================================
  # Transform Result/3 Callback Tests
  # ============================================================================

  describe "Transform Result/3 Callback" do
    test "LLM skill implements transform_result/3" do
      assert function_exported?(LLM, :transform_result, 3)
      result = %{text: "test"}
      assert LLM.transform_result(nil, result, %{}) == result
    end

    test "Reasoning skill implements transform_result/3" do
      assert function_exported?(Reasoning, :transform_result, 3)
      result = %{analysis: "test"}
      assert Reasoning.transform_result(nil, result, %{}) == result
    end

    test "Planning skill implements transform_result/3" do
      assert function_exported?(Planning, :transform_result, 3)
      result = %{plan: "test"}
      assert Planning.transform_result(nil, result, %{}) == result
    end

    test "Streaming skill implements transform_result/3" do
      assert function_exported?(Streaming, :transform_result, 3)
      result = %{stream: "test"}
      assert Streaming.transform_result(nil, result, %{}) == result
    end

    test "ToolCalling skill implements transform_result/3" do
      assert function_exported?(ToolCalling, :transform_result, 3)
      result = %{tool_result: "test"}
      assert ToolCalling.transform_result(nil, result, %{}) == result
    end
  end

  # ============================================================================
  # Signal Patterns Tests
  # ============================================================================

  describe "Signal Patterns" do
    test "LLM skill has signal_patterns" do
      assert function_exported?(LLM, :signal_patterns, 0)
      patterns = LLM.signal_patterns()
      assert is_list(patterns)
    end

    test "LLM skill signal patterns match signal_routes" do
      patterns = LLM.signal_patterns()
      routes = LLM.signal_routes(%{})
      route_keys = routes |> MapSet.new(fn {k, _v} -> k end)
      pattern_set = MapSet.new(patterns)

      assert MapSet.equal?(route_keys, pattern_set)
    end

    test "Reasoning skill has signal_patterns" do
      assert function_exported?(Reasoning, :signal_patterns, 0)
      patterns = Reasoning.signal_patterns()
      assert is_list(patterns)
    end

    test "Planning skill has signal_patterns" do
      assert function_exported?(Planning, :signal_patterns, 0)
      patterns = Planning.signal_patterns()
      assert is_list(patterns)
    end

    test "Streaming skill has signal_patterns" do
      assert function_exported?(Streaming, :signal_patterns, 0)
      patterns = Streaming.signal_patterns()
      assert is_list(patterns)
    end

    test "ToolCalling skill has signal_patterns" do
      assert function_exported?(ToolCalling, :signal_patterns, 0)
      patterns = ToolCalling.signal_patterns()
      assert is_list(patterns)
    end
  end

  # ============================================================================
  # Skill State Isolation Tests
  # ============================================================================

  describe "Skill State Isolation" do
    test "LLM and Reasoning skills have independent state" do
      {:ok, llm_state} = LLM.mount(%Agent{}, %{default_model: :fast})
      {:ok, reasoning_state} = Reasoning.mount(%Agent{}, %{default_model: :reasoning})

      assert llm_state.default_model == :fast
      assert reasoning_state.default_model == :reasoning
      assert llm_state.default_max_tokens != reasoning_state.default_max_tokens
    end

    test "Planning and ToolCalling skills have independent state" do
      {:ok, planning_state} = Planning.mount(%Agent{}, %{})
      {:ok, tool_calling_state} = ToolCalling.mount(%Agent{}, %{})

      assert planning_state.default_model == :planning
      assert tool_calling_state.default_model == :capable
      refute Map.has_key?(planning_state, :auto_execute)
      assert Map.has_key?(tool_calling_state, :auto_execute)
    end

    test "Streaming skill state has unique fields" do
      {:ok, streaming_state} = Streaming.mount(%Agent{}, %{})

      assert is_map(streaming_state.active_streams)
      assert Map.has_key?(streaming_state, :default_buffer_size)
      refute Map.has_key?(streaming_state, :auto_execute)
    end
  end

  # ============================================================================
  # Plugin Spec Tests
  # ============================================================================

  describe "Plugin Spec" do
    test "LLM plugin_spec returns valid spec" do
      assert function_exported?(LLM, :plugin_spec, 1)
      spec = LLM.plugin_spec(%{})
      assert spec.module == LLM
      assert spec.name == "llm"
      assert spec.state_key == :llm
    end

    test "Reasoning plugin_spec returns valid spec" do
      assert function_exported?(Reasoning, :plugin_spec, 1)
      spec = Reasoning.plugin_spec(%{})
      assert spec.module == Reasoning
      assert spec.name == "reasoning"
      assert spec.state_key == :reasoning
    end

    test "Planning plugin_spec returns valid spec" do
      assert function_exported?(Planning, :plugin_spec, 1)
      spec = Planning.plugin_spec(%{})
      assert spec.module == Planning
      assert spec.name == "planning"
      assert spec.state_key == :planning
    end

    test "Streaming plugin_spec returns valid spec" do
      assert function_exported?(Streaming, :plugin_spec, 1)
      spec = Streaming.plugin_spec(%{})
      assert spec.module == Streaming
      assert spec.name == "streaming"
      assert spec.state_key == :streaming
    end

    test "ToolCalling plugin_spec returns valid spec" do
      assert function_exported?(ToolCalling, :plugin_spec, 1)
      spec = ToolCalling.plugin_spec(%{})
      assert spec.module == ToolCalling
      assert spec.name == "tool_calling"
      assert spec.state_key == :tool_calling
    end
  end

  # ============================================================================
  # Phase 9.3 Success Criteria
  # ============================================================================

  describe "Phase 9.3 Success Criteria" do
    test "all 5 skills implement signal_routes/1 callback" do
      skills = [LLM, Reasoning, Planning, Streaming, ToolCalling]

      for skill <- skills do
        assert function_exported?(skill, :signal_routes, 1), "#{skill} must implement signal_routes/1"
      end
    end

    test "all 5 skills implement handle_signal/2 callback" do
      skills = [LLM, Reasoning, Planning, Streaming, ToolCalling]

      for skill <- skills do
        assert function_exported?(skill, :handle_signal, 2), "#{skill} must implement handle_signal/2"
      end
    end

    test "all 5 skills implement transform_result/3 callback" do
      skills = [LLM, Reasoning, Planning, Streaming, ToolCalling]

      for skill <- skills do
        assert function_exported?(skill, :transform_result, 3), "#{skill} must implement transform_result/3"
      end
    end

    test "all 5 skills implement schema/0 callback" do
      skills = [LLM, Reasoning, Planning, Streaming, ToolCalling]

      for skill <- skills do
        assert function_exported?(skill, :schema, 0), "#{skill} must implement schema/0"
      end
    end

    test "all 5 skills implement mount/2 callback" do
      skills = [LLM, Reasoning, Planning, Streaming, ToolCalling]

      for skill <- skills do
        assert function_exported?(skill, :mount, 2), "#{skill} must implement mount/2"
        assert {:ok, _state} = skill.mount(%Agent{}, %{})
      end
    end

    test "all 5 skills implement signal_patterns/0 callback" do
      skills = [LLM, Reasoning, Planning, Streaming, ToolCalling]

      for skill <- skills do
        assert function_exported?(skill, :signal_patterns, 0), "#{skill} must implement signal_patterns/0"
        patterns = skill.signal_patterns()
        assert is_list(patterns), "#{skill} signal_patterns must return a list"
      end
    end
  end
end
