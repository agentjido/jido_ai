defmodule Jido.AI.Directive.DeadlockPreventionTest do
  @moduledoc """
  Tests for deadlock prevention fixes:
  - Issue #1: Unknown tool name produces error result (not silent drop)
  - Issue #2: Tool execution crash still produces error result
  - Issue #3: EmitRequestError directive works correctly
  """
  use ExUnit.Case, async: true

  alias Jido.AI.Directive.{EmitToolError, EmitRequestError, ToolExec}
  alias Jido.AI.Signal

  # ============================================================================
  # Issue #1: EmitToolError Directive
  # ============================================================================

  describe "EmitToolError directive - Issue #1 fix" do
    test "creates valid EmitToolError directive" do
      directive =
        EmitToolError.new!(%{
          id: "tc_123",
          tool_name: "unknown_tool",
          error: {:unknown_tool, "Tool 'unknown_tool' not found"}
        })

      assert directive.id == "tc_123"
      assert directive.tool_name == "unknown_tool"
      assert {:unknown_tool, _message} = directive.error
    end

    test "raises on invalid EmitToolError directive" do
      assert_raise RuntimeError, ~r/Invalid EmitToolError/, fn ->
        EmitToolError.new!(%{id: "tc_123"})
      end
    end
  end

  # ============================================================================
  # Issue #3: EmitRequestError Directive
  # ============================================================================

  describe "EmitRequestError directive - Issue #3 fix" do
    test "creates valid EmitRequestError directive" do
      directive =
        EmitRequestError.new!(%{
          call_id: "call_456",
          reason: :busy,
          message: "Agent is busy"
        })

      assert directive.call_id == "call_456"
      assert directive.reason == :busy
      assert directive.message == "Agent is busy"
    end

    test "raises on invalid EmitRequestError directive" do
      assert_raise RuntimeError, ~r/Invalid EmitRequestError/, fn ->
        EmitRequestError.new!(%{call_id: "call_123"})
      end
    end
  end

  # ============================================================================
  # Issue #2: ToolExec Try/Rescue Coverage
  # ============================================================================

  describe "ToolExec directive - Issue #2 fix" do
    test "creates valid ToolExec directive" do
      directive =
        ToolExec.new!(%{
          id: "tc_789",
          tool_name: "calculator",
          action_module: FakeCalculator,
          arguments: %{a: 1, b: 2},
          context: %{user_id: "user_1"}
        })

      assert directive.id == "tc_789"
      assert directive.tool_name == "calculator"
      assert directive.action_module == FakeCalculator
      assert directive.arguments == %{a: 1, b: 2}
    end
  end

  # ============================================================================
  # Signal Types for Fixes
  # ============================================================================

  describe "RequestError signal - Issue #3" do
    test "creates valid RequestError signal" do
      {:ok, signal} =
        Signal.RequestError.new(%{
          call_id: "call_123",
          reason: :busy,
          message: "Agent is busy processing another request"
        })

      assert signal.type == "ai.request_error"
      assert signal.data.call_id == "call_123"
      assert signal.data.reason == :busy
      assert signal.data.message == "Agent is busy processing another request"
    end
  end

  describe "ToolResult signal with error" do
    test "creates valid ToolResult signal with error result" do
      {:ok, signal} =
        Signal.ToolResult.new(%{
          call_id: "tc_123",
          tool_name: "unknown_tool",
          result: {:error, {:unknown_tool, "Tool 'unknown_tool' not found"}}
        })

      assert signal.type == "ai.tool_result"
      assert signal.data.call_id == "tc_123"
      assert signal.data.tool_name == "unknown_tool"
      assert {:error, {:unknown_tool, _}} = signal.data.result
    end

    test "creates valid ToolResult signal with exception error" do
      {:ok, signal} =
        Signal.ToolResult.new(%{
          call_id: "tc_456",
          tool_name: "crashy_tool",
          result:
            {:error,
             %{
               error: "something went wrong",
               tool_name: "crashy_tool",
               type: :exception,
               exception_type: RuntimeError
             }}
        })

      assert signal.type == "ai.tool_result"

      assert signal.data.result ==
               {:error,
                %{
                  error: "something went wrong",
                  tool_name: "crashy_tool",
                  type: :exception,
                  exception_type: RuntimeError
                }}
    end
  end
end
