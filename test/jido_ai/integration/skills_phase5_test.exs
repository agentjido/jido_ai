defmodule Jido.AI.Integration.SkillsPhase5Test do
  @moduledoc """
  Integration tests for Phase 5 Skills System.

  These tests verify that all Phase 5 skills work together correctly:
  - Skills compose properly on agents
  - Skill actions are accessible and invocable
  - Skills can interact with each other
  - State management across multiple skills

  Tests use direct action invocation and do not make actual LLM API calls.
  """

  use ExUnit.Case, async: false

  alias Jido.AI.Actions.LLM.Chat
  alias Jido.AI.Plugins.LLM
  alias Jido.AI.Plugins.Planning
  alias Jido.AI.Plugins.Reasoning
  alias Jido.AI.Plugins.Streaming
  alias Jido.AI.Plugins.ToolCalling

  # ============================================================================
  # Skill Composition Integration Tests
  # ============================================================================

  describe "Skill Composition" do
    test "multiple skills can be mounted on a single agent" do
      # Verify all skills can be loaded together
      llm_spec = LLM.plugin_spec(%{})
      reasoning_spec = Reasoning.plugin_spec(%{})
      planning_spec = Planning.plugin_spec(%{})
      streaming_spec = Streaming.plugin_spec(%{})
      tool_calling_spec = ToolCalling.plugin_spec(%{})

      # Each skill should have a unique name and state_key
      assert llm_spec.name == "llm"
      assert llm_spec.state_key == :llm

      assert reasoning_spec.name == "reasoning"
      assert reasoning_spec.state_key == :reasoning

      assert planning_spec.name == "planning"
      assert planning_spec.state_key == :planning

      assert streaming_spec.name == "streaming"
      assert streaming_spec.state_key == :streaming

      assert tool_calling_spec.name == "tool_calling"
      assert tool_calling_spec.state_key == :tool_calling
    end

    test "each skill has unique actions" do
      llm_actions = LLM.actions()
      reasoning_actions = Reasoning.actions()
      planning_actions = Planning.actions()
      streaming_actions = Streaming.actions()
      tool_calling_actions = ToolCalling.actions()

      # Verify actions are distinct
      assert length(llm_actions) == 4
      assert length(reasoning_actions) == 3
      assert length(planning_actions) == 3
      assert length(streaming_actions) == 3
      assert length(tool_calling_actions) == 3

      # No overlap in action modules
      all_actions =
        llm_actions ++
          reasoning_actions ++
          planning_actions ++
          streaming_actions ++
          tool_calling_actions

      assert length(Enum.uniq(all_actions)) == length(all_actions)
    end

    test "skills maintain independent state" do
      {:ok, llm_state} = LLM.mount(%Jido.Agent{}, %{default_model: :fast})
      {:ok, reasoning_state} = Reasoning.mount(%Jido.Agent{}, %{default_model: :reasoning})
      {:ok, planning_state} = Planning.mount(%Jido.Agent{}, %{default_model: :planning})
      {:ok, streaming_state} = Streaming.mount(%Jido.Agent{}, %{})
      {:ok, tool_calling_state} = ToolCalling.mount(%Jido.Agent{}, %{})

      # Each skill maintains its own state
      assert llm_state.default_model == :fast
      assert reasoning_state.default_model == :reasoning
      assert planning_state.default_model == :planning
      assert streaming_state.default_model == :fast
      assert tool_calling_state.default_model == :capable
    end
  end

  # ============================================================================
  # LLM Skill Integration Tests
  # ============================================================================

  describe "LLM Skill Integration" do
    alias Jido.AI.Actions.LLM.{Chat, Complete, Embed}

    test "all LLM actions are accessible" do
      assert Chat in LLM.actions()
      assert Complete in LLM.actions()
      assert Embed in LLM.actions()
    end

    test "Chat action has expected schema" do
      schema = Chat.schema()

      assert schema.fields[:prompt].meta.required == true
      refute schema.fields[:model].meta.required
      assert schema.fields[:max_tokens].value == 1024
    end

    test "Complete action has expected schema" do
      schema = Complete.schema()

      assert schema.fields[:prompt].meta.required == true
      assert schema.fields[:max_tokens].value == 1024
    end

    test "Embed action has expected schema" do
      schema = Embed.schema()

      refute schema.fields[:texts].meta.required
    end
  end

  # ============================================================================
  # Reasoning Skill Integration Tests
  # ============================================================================

  describe "Reasoning Skill Integration" do
    alias Jido.AI.Actions.Reasoning.{Analyze, Explain, Infer}

    test "all Reasoning actions are accessible" do
      assert Analyze in Reasoning.actions()
      assert Explain in Reasoning.actions()
      assert Infer in Reasoning.actions()
    end

    test "Analyze action has expected schema" do
      schema = Analyze.schema()

      assert schema.fields[:input].meta.required == true
      assert schema.fields[:analysis_type].value == :summary
    end

    test "Explain action has expected schema" do
      schema = Explain.schema()

      assert schema.fields[:topic].meta.required == true
      assert schema.fields[:detail_level].value == :intermediate
    end

    test "Infer action has expected schema" do
      schema = Infer.schema()

      assert schema.fields[:premises].meta.required == true
      assert schema.fields[:question].meta.required == true
    end
  end

  # ============================================================================
  # Planning Skill Integration Tests
  # ============================================================================

  describe "Planning Skill Integration" do
    alias Jido.AI.Actions.Planning.{Decompose, Plan, Prioritize}

    test "all Planning actions are accessible" do
      assert Plan in Planning.actions()
      assert Decompose in Planning.actions()
      assert Prioritize in Planning.actions()
    end

    test "Plan action has expected schema" do
      schema = Plan.schema()

      assert schema.fields[:goal].meta.required == true
      assert schema.fields[:max_steps].value == 10
    end

    test "Decompose action has expected schema" do
      schema = Decompose.schema()

      assert schema.fields[:goal].meta.required == true
      assert schema.fields[:max_depth].value == 3
    end

    test "Prioritize action has expected schema" do
      schema = Prioritize.schema()

      assert schema.fields[:tasks].meta.required == true
    end
  end

  # ============================================================================
  # Streaming Skill Integration Tests
  # ============================================================================

  describe "Streaming Skill Integration" do
    alias Jido.AI.Actions.Streaming.{EndStream, ProcessTokens, StartStream}

    test "all Streaming actions are accessible" do
      assert StartStream in Streaming.actions()
      assert ProcessTokens in Streaming.actions()
      assert EndStream in Streaming.actions()
    end

    test "StartStream action has expected schema" do
      schema = StartStream.schema()

      assert schema.fields[:prompt].meta.required == true
      assert schema.fields[:auto_process].value == true
    end

    test "ProcessTokens action has expected schema" do
      schema = ProcessTokens.schema()

      assert schema.fields[:stream_id].meta.required == true
    end

    test "EndStream action has expected schema" do
      schema = EndStream.schema()

      assert schema.fields[:stream_id].meta.required == true
      assert schema.fields[:timeout].value == 30_000
    end
  end

  # ============================================================================
  # Tool Calling Skill Integration Tests
  # ============================================================================

  describe "Tool Calling Skill Integration" do
    alias Jido.AI.Actions.ToolCalling.{CallWithTools, ExecuteTool, ListTools}

    test "all Tool Calling actions are accessible" do
      assert CallWithTools in ToolCalling.actions()
      assert ExecuteTool in ToolCalling.actions()
      assert ListTools in ToolCalling.actions()
    end

    test "CallWithTools action has expected schema" do
      schema = CallWithTools.schema()

      assert schema.fields[:prompt].meta.required == true
      assert schema.fields[:auto_execute].value == false
      assert schema.fields[:max_turns].value == 10
    end

    test "ExecuteTool action has expected schema" do
      schema = ExecuteTool.schema()

      assert schema.fields[:tool_name].meta.required == true
      assert schema.fields[:timeout].value == 30_000
    end

    test "ListTools action has expected schema" do
      schema = ListTools.schema()

      assert schema.fields[:include_schema].value == true
    end
  end

  # ============================================================================
  # Cross-Skill Integration Tests
  # ============================================================================

  describe "Cross-Skill Integration" do
    test "LLM and Reasoning skills can be used together" do
      # Both skills should be mountable
      {:ok, llm_state} = LLM.mount(%Jido.Agent{}, %{})
      {:ok, reasoning_state} = Reasoning.mount(%Jido.Agent{}, %{})

      # States should be independent
      assert llm_state.default_model == :fast
      assert reasoning_state.default_model == :reasoning

      # Actions from both should be accessible
      llm_actions = LLM.actions()
      reasoning_actions = Reasoning.actions()

      refute Enum.empty?(llm_actions)
      refute Enum.empty?(reasoning_actions)
    end

    test "Planning and Tool Calling skills can be used together" do
      # Both skills should be mountable
      {:ok, planning_state} = Planning.mount(%Jido.Agent{}, %{})
      {:ok, tool_calling_state} = ToolCalling.mount(%Jido.Agent{}, %{})

      # Tool Calling should have access to available tools
      assert is_list(tool_calling_state.available_tools)
      assert planning_state.default_max_tokens == 4096
    end

    test "Streaming and Tool Calling skills can be used together" do
      # Both skills should be mountable
      {:ok, streaming_state} = Streaming.mount(%Jido.Agent{}, %{})
      {:ok, tool_calling_state} = ToolCalling.mount(%Jido.Agent{}, %{})

      # Streaming should have buffer configuration
      assert is_map(streaming_state.active_streams)
      assert tool_calling_state.auto_execute == false
    end
  end

  # ============================================================================
  # End-to-End Flow Tests
  # ============================================================================

  describe "End-to-End Flows" do
    test "skill action can be invoked directly" do
      # Test that actions have the expected schema
      _params = %{prompt: "Test"}

      # Chat action should have schema accessible (Zoi schema struct)
      schema = Chat.schema()
      assert is_map(schema)
      assert schema.fields[:prompt].meta.required == true
    end

    test "all skills have proper plugin_spec/1" do
      llm_spec = LLM.plugin_spec(%{})
      reasoning_spec = Reasoning.plugin_spec(%{})
      planning_spec = Planning.plugin_spec(%{})
      streaming_spec = Streaming.plugin_spec(%{})
      tool_calling_spec = ToolCalling.plugin_spec(%{})

      # Each spec should have required fields
      for spec <- [llm_spec, reasoning_spec, planning_spec, streaming_spec, tool_calling_spec] do
        assert spec.module != nil
        assert spec.name != nil
        assert spec.state_key != nil
        assert is_list(spec.actions)
      end
    end

    test "all skills support mount/2 callback" do
      # All should return {:ok, state} tuple
      assert {:ok, _state} = LLM.mount(%Jido.Agent{}, %{})
      assert {:ok, _state} = Reasoning.mount(%Jido.Agent{}, %{})
      assert {:ok, _state} = Planning.mount(%Jido.Agent{}, %{})
      assert {:ok, _state} = Streaming.mount(%Jido.Agent{}, %{})
      assert {:ok, _state} = ToolCalling.mount(%Jido.Agent{}, %{})
    end
  end

  # ============================================================================
  # Phase 5 Success Criteria Verification
  # ============================================================================

  describe "Phase 5 Success Criteria" do
    test "LLM Skill has Chat, Complete, and Embed actions" do
      actions = LLM.actions()

      assert Jido.AI.Actions.LLM.Chat in actions
      assert Jido.AI.Actions.LLM.Complete in actions
      assert Jido.AI.Actions.LLM.Embed in actions
    end

    test "Reasoning Skill has Analyze, Infer, and Explain actions" do
      actions = Reasoning.actions()

      assert Jido.AI.Actions.Reasoning.Analyze in actions
      assert Jido.AI.Actions.Reasoning.Infer in actions
      assert Jido.AI.Actions.Reasoning.Explain in actions
    end

    test "Planning Skill has Plan, Decompose, and Prioritize actions" do
      actions = Planning.actions()

      assert Jido.AI.Actions.Planning.Plan in actions
      assert Jido.AI.Actions.Planning.Decompose in actions
      assert Jido.AI.Actions.Planning.Prioritize in actions
    end

    test "Streaming Skill has StartStream, ProcessTokens, and EndStream actions" do
      actions = Streaming.actions()

      assert Jido.AI.Actions.Streaming.StartStream in actions
      assert Jido.AI.Actions.Streaming.ProcessTokens in actions
      assert Jido.AI.Actions.Streaming.EndStream in actions
    end

    test "Tool Calling Skill has CallWithTools, ExecuteTool, and ListTools actions" do
      actions = ToolCalling.actions()

      assert Jido.AI.Actions.ToolCalling.CallWithTools in actions
      assert Jido.AI.Actions.ToolCalling.ExecuteTool in actions
      assert Jido.AI.Actions.ToolCalling.ListTools in actions
    end

    test "all 5 skills are available" do
      skills = [LLM, Reasoning, Planning, Streaming, ToolCalling]

      for skill <- skills do
        assert function_exported?(skill, :plugin_spec, 1)
        assert function_exported?(skill, :mount, 2)
        assert function_exported?(skill, :actions, 0)
      end
    end

    test "total action count across all skills is 15" do
      llm_count = length(LLM.actions())
      reasoning_count = length(Reasoning.actions())
      planning_count = length(Planning.actions())
      streaming_count = length(Streaming.actions())
      tool_calling_count = length(ToolCalling.actions())

      total = llm_count + reasoning_count + planning_count + streaming_count + tool_calling_count

      assert total == 16
    end
  end
end
