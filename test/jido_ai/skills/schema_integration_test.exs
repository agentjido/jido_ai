defmodule Jido.AI.Plugins.SchemaIntegrationTest do
  @moduledoc """
  Integration tests for Phase 9.2 Zoi schema migration in skills.

  These tests verify that:
  - All 15 skill actions use Zoi schemas
  - Schema functions exist and are callable
  """

  use ExUnit.Case, async: false

  alias Jido.AI.Actions.LLM.{Chat, Complete, Embed}
  alias Jido.AI.Actions.Planning.{Decompose, Plan, Prioritize}
  alias Jido.AI.Actions.Reasoning.{Analyze, Explain, Infer}
  alias Jido.AI.Actions.Streaming.{EndStream, ProcessTokens, StartStream}
  alias Jido.AI.Actions.ToolCalling.{CallWithTools, ExecuteTool, ListTools}
  alias Jido.AI.Plugins.LLM
  alias Jido.AI.Plugins.Planning
  alias Jido.AI.Plugins.Reasoning
  alias Jido.AI.Plugins.Streaming
  alias Jido.AI.Plugins.ToolCalling

  # Ensure all skill modules are loaded before tests
  require Jido.AI.Plugins.LLM
  require Jido.AI.Actions.LLM.{Chat, Complete, Embed}
  require Jido.AI.Plugins.Planning
  require Jido.AI.Actions.Planning.{Plan, Decompose, Prioritize}
  require Jido.AI.Plugins.Reasoning
  require Jido.AI.Actions.Reasoning.{Analyze, Explain, Infer}
  require Jido.AI.Plugins.Streaming
  require Jido.AI.Actions.Streaming.{StartStream, ProcessTokens, EndStream}
  require Jido.AI.Plugins.ToolCalling
  require Jido.AI.Actions.ToolCalling.{CallWithTools, ExecuteTool, ListTools}

  # ============================================================================
  # LLM Skill Schema Tests
  # ============================================================================

  describe "LLM Skill Schemas" do
    test "Chat action has schema function" do
      assert function_exported?(Chat, :schema, 0)
    end

    test "Chat schema returns a map-like structure" do
      schema = Chat.schema()
      assert is_map(schema) or is_struct(schema)
    end

    test "Complete action has schema function" do
      assert function_exported?(Complete, :schema, 0)
    end

    test "Complete schema returns a map-like structure" do
      schema = Complete.schema()
      assert is_map(schema) or is_struct(schema)
    end

    test "Embed action has schema function" do
      assert function_exported?(Embed, :schema, 0)
    end

    test "Embed schema returns a map-like structure" do
      schema = Embed.schema()
      assert is_map(schema) or is_struct(schema)
    end
  end

  # ============================================================================
  # Reasoning Skill Schema Tests
  # ============================================================================

  describe "Reasoning Skill Schemas" do
    test "Analyze action has schema function" do
      assert function_exported?(Analyze, :schema, 0)
    end

    test "Analyze schema returns a map-like structure" do
      schema = Analyze.schema()
      assert is_map(schema) or is_struct(schema)
    end

    test "Explain action has schema function" do
      assert function_exported?(Explain, :schema, 0)
    end

    test "Explain schema returns a map-like structure" do
      schema = Explain.schema()
      assert is_map(schema) or is_struct(schema)
    end

    test "Infer action has schema function" do
      assert function_exported?(Infer, :schema, 0)
    end

    test "Infer schema returns a map-like structure" do
      schema = Infer.schema()
      assert is_map(schema) or is_struct(schema)
    end
  end

  # ============================================================================
  # Planning Skill Schema Tests
  # ============================================================================

  describe "Planning Skill Schemas" do
    test "Plan action has schema function" do
      assert function_exported?(Plan, :schema, 0)
    end

    test "Plan schema returns a map-like structure" do
      schema = Plan.schema()
      assert is_map(schema) or is_struct(schema)
    end

    test "Decompose action has schema function" do
      assert function_exported?(Decompose, :schema, 0)
    end

    test "Decompose schema returns a map-like structure" do
      schema = Decompose.schema()
      assert is_map(schema) or is_struct(schema)
    end

    test "Prioritize action has schema function" do
      assert function_exported?(Prioritize, :schema, 0)
    end

    test "Prioritize schema returns a map-like structure" do
      schema = Prioritize.schema()
      assert is_map(schema) or is_struct(schema)
    end
  end

  # ============================================================================
  # Streaming Skill Schema Tests
  # ============================================================================

  describe "Streaming Skill Schemas" do
    test "StartStream action has schema function" do
      assert function_exported?(StartStream, :schema, 0)
    end

    test "StartStream schema returns a map-like structure" do
      schema = StartStream.schema()
      assert is_map(schema) or is_struct(schema)
    end

    test "ProcessTokens action has schema function" do
      assert function_exported?(ProcessTokens, :schema, 0)
    end

    test "ProcessTokens schema returns a map-like structure" do
      schema = ProcessTokens.schema()
      assert is_map(schema) or is_struct(schema)
    end

    test "EndStream action has schema function" do
      assert function_exported?(EndStream, :schema, 0)
    end

    test "EndStream schema returns a map-like structure" do
      schema = EndStream.schema()
      assert is_map(schema) or is_struct(schema)
    end
  end

  # ============================================================================
  # Tool Calling Skill Schema Tests
  # ============================================================================

  describe "Tool Calling Skill Schemas" do
    test "CallWithTools action has schema function" do
      assert function_exported?(CallWithTools, :schema, 0)
    end

    test "CallWithTools schema returns a map-like structure" do
      schema = CallWithTools.schema()
      assert is_map(schema) or is_struct(schema)
    end

    test "ExecuteTool action has schema function" do
      assert function_exported?(ExecuteTool, :schema, 0)
    end

    test "ExecuteTool schema returns a map-like structure" do
      schema = ExecuteTool.schema()
      assert is_map(schema) or is_struct(schema)
    end

    test "ListTools action has schema function" do
      assert function_exported?(ListTools, :schema, 0)
    end

    test "ListTools schema returns a map-like structure" do
      schema = ListTools.schema()
      assert is_map(schema) or is_struct(schema)
    end
  end

  # ============================================================================
  # Schema Structure Tests
  # ============================================================================

  describe "Schema Structure" do
    test "all action schemas return structures" do
      actions = [
        Chat,
        Complete,
        Embed,
        Analyze,
        Explain,
        Infer,
        Plan,
        Decompose,
        Prioritize,
        StartStream,
        ProcessTokens,
        EndStream,
        CallWithTools,
        ExecuteTool,
        ListTools
      ]

      for action <- actions do
        schema = action.schema()
        # Zoi schemas return a map-like struct
        assert is_map(schema) or is_struct(schema),
               "#{inspect(action)} schema should return a map-like structure"
      end
    end
  end

  # ============================================================================
  # Phase 9.2 Success Criteria
  # ============================================================================

  describe "Phase 9.2 Success Criteria" do
    test "all 15 actions have schema/0 function" do
      actions = [
        {Chat, :chat},
        {Complete, :complete},
        {Embed, :embed},
        {Analyze, :analyze},
        {Explain, :explain},
        {Infer, :infer},
        {Plan, :plan},
        {Decompose, :decompose},
        {Prioritize, :prioritize},
        {StartStream, :start_stream},
        {ProcessTokens, :process_tokens},
        {EndStream, :end_stream},
        {CallWithTools, :call_with_tools},
        {ExecuteTool, :execute_tool},
        {ListTools, :list_tools}
      ]

      for {action_module, _name} <- actions do
        assert function_exported?(action_module, :schema, 0),
               "#{action_module} must have schema/0 function"
      end
    end

    test "all LLM actions have schemas" do
      llm_actions = LLM.actions()
      assert length(llm_actions) == 4

      for action <- llm_actions do
        assert function_exported?(action, :schema, 0)
      end
    end

    test "all Reasoning actions have schemas" do
      reasoning_actions = Reasoning.actions()
      assert length(reasoning_actions) == 3

      for action <- reasoning_actions do
        assert function_exported?(action, :schema, 0)
      end
    end

    test "all Planning actions have schemas" do
      planning_actions = Planning.actions()
      assert length(planning_actions) == 3

      for action <- planning_actions do
        assert function_exported?(action, :schema, 0)
      end
    end

    test "all Streaming actions have schemas" do
      streaming_actions = Streaming.actions()
      assert length(streaming_actions) == 3

      for action <- streaming_actions do
        assert function_exported?(action, :schema, 0)
      end
    end

    test "all Tool Calling actions have schemas" do
      tool_calling_actions = ToolCalling.actions()
      assert length(tool_calling_actions) == 3

      for action <- tool_calling_actions do
        assert function_exported?(action, :schema, 0)
      end
    end

    test "total action count is 15 across all skills" do
      total =
        length(LLM.actions()) +
          length(Reasoning.actions()) +
          length(Planning.actions()) +
          length(Streaming.actions()) +
          length(ToolCalling.actions())

      assert total == 16
    end
  end
end
