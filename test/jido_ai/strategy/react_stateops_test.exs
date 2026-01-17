defmodule Jido.AI.Strategy.ReActStateOpsTest do
  @moduledoc """
  Integration tests for StateOps usage in the ReAct strategy.

  These tests verify that the ReAct strategy correctly integrates with
  the Jido V2 StateOps system.
  """

  use ExUnit.Case, async: true

  alias Jido.Agent.StateOp
  alias Jido.AI.Strategy.ReAct
  alias Jido.AI.Strategy.StateOpsHelpers

  @moduletag :stateops
  @moduletag :react_strategy

  describe "StateOps Integration" do
    test "StateOpsHelpers module is available" do
      assert function_exported?(StateOpsHelpers, :set_iteration_status, 1)
      assert function_exported?(StateOpsHelpers, :set_iteration, 1)
      assert function_exported?(StateOpsHelpers, :set_conversation, 1)
      assert function_exported?(StateOpsHelpers, :set_pending_tools, 1)
    end

    test "StateOp.SetState creates valid state operation" do
      op = StateOp.set_state(%{status: :running, iteration: 1})

      assert %StateOp.SetState{} = op
      assert op.attrs.status == :running
      assert op.attrs.iteration == 1
    end

    test "StateOp.SetPath creates valid path operation" do
      op = StateOp.set_path([:status], :awaiting_llm)

      assert %StateOp.SetPath{} = op
      assert op.path == [:status]
      assert op.value == :awaiting_llm
    end

    test "StateOp.DeleteKeys creates valid delete operation" do
      op = StateOp.delete_keys([:temp, :cache])

      assert %StateOp.DeleteKeys{} = op
      assert op.keys == [:temp, :cache]
    end
  end

  describe "StateOpsHelpers Functionality" do
    test "update_strategy_state/1 creates SetState operation" do
      op = StateOpsHelpers.update_strategy_state(%{status: :running})

      assert %StateOp.SetState{} = op
      assert op.attrs.status == :running
    end

    test "set_iteration_status/1 creates SetPath operation" do
      op = StateOpsHelpers.set_iteration_status(:awaiting_llm)

      assert %StateOp.SetPath{} = op
      assert op.path == [:status]
      assert op.value == :awaiting_llm
    end

    test "set_iteration/1 creates SetPath operation for counter" do
      op = StateOpsHelpers.set_iteration(5)

      assert %StateOp.SetPath{} = op
      assert op.path == [:iteration]
      assert op.value == 5
    end

    test "set_conversation/1 creates SetState operation" do
      messages = [%{role: :user, content: "Hello"}]
      op = StateOpsHelpers.set_conversation(messages)

      assert %StateOp.SetState{} = op
      assert op.attrs.conversation == messages
    end

    test "prepend_conversation/2 prepends message to conversation" do
      message = %{role: :user, content: "Hello"}
      existing = [%{role: :assistant, content: "Hi"}]
      op = StateOpsHelpers.prepend_conversation(message, existing)

      assert %StateOp.SetState{} = op
      assert op.attrs.conversation == [message | existing]
    end

    test "set_pending_tools/1 creates SetState operation" do
      tools = [%{id: "call_1", name: "search"}]
      op = StateOpsHelpers.set_pending_tools(tools)

      assert %StateOp.SetState{} = op
      assert op.attrs.pending_tool_calls == tools
    end

    test "clear_pending_tools/0 creates empty tools operation" do
      op = StateOpsHelpers.clear_pending_tools()

      assert %StateOp.SetState{} = op
      assert op.attrs.pending_tool_calls == []
    end

    test "set_call_id/1 creates SetPath operation" do
      op = StateOpsHelpers.set_call_id("call_123")

      assert %StateOp.SetPath{} = op
      assert op.path == [:current_llm_call_id]
      assert op.value == "call_123"
    end

    test "clear_call_id/0 creates DeletePath operation" do
      op = StateOpsHelpers.clear_call_id()

      assert %StateOp.DeletePath{} = op
      assert op.path == [:current_llm_call_id]
    end

    test "set_final_answer/1 creates SetPath operation" do
      op = StateOpsHelpers.set_final_answer("42")

      assert %StateOp.SetPath{} = op
      assert op.path == [:final_answer]
      assert op.value == "42"
    end

    test "set_termination_reason/1 creates SetPath operation" do
      op = StateOpsHelpers.set_termination_reason(:final_answer)

      assert %StateOp.SetPath{} = op
      assert op.path == [:termination_reason]
      assert op.value == :final_answer
    end

    test "set_streaming_text/1 creates SetPath operation" do
      op = StateOpsHelpers.set_streaming_text("Hello")

      assert %StateOp.SetPath{} = op
      assert op.path == [:streaming_text]
      assert op.value == "Hello"
    end

    test "delete_temp_keys/0 creates DeleteKeys operation" do
      op = StateOpsHelpers.delete_temp_keys()

      assert %StateOp.DeleteKeys{} = op
      assert op.keys == [:temp, :cache, :ephemeral]
    end

    test "delete_keys/1 creates custom DeleteKeys operation" do
      op = StateOpsHelpers.delete_keys([:custom1, :custom2])

      assert %StateOp.DeleteKeys{} = op
      assert op.keys == [:custom1, :custom2]
    end

    test "reset_strategy_state/0 creates ReplaceState operation" do
      op = StateOpsHelpers.reset_strategy_state()

      assert %StateOp.ReplaceState{} = op
      assert op.state.status == :idle
      assert op.state.iteration == 0
      assert op.state.conversation == []
      assert op.state.pending_tool_calls == []
    end

    test "compose/1 returns list of operations unchanged" do
      ops = [
        StateOpsHelpers.set_iteration_status(:running),
        StateOpsHelpers.set_iteration(1)
      ]

      result = StateOpsHelpers.compose(ops)

      assert result == ops
      assert length(result) == 2
    end
  end

  describe "ReAct Strategy StateOps Compatibility" do
    test "ReAct strategy module exists and is valid" do
      assert function_exported?(ReAct, :start_action, 0)
      assert function_exported?(ReAct, :llm_result_action, 0)
      assert function_exported?(ReAct, :tool_result_action, 0)
    end

    test "ReAct strategy action specs are valid" do
      assert ReAct.action_spec(:react_start) != nil
      assert ReAct.action_spec(:react_llm_result) != nil
      assert ReAct.action_spec(:react_tool_result) != nil
      assert ReAct.action_spec(:react_llm_partial) != nil
    end

    test "ReAct strategy signal routes are valid" do
      routes = ReAct.signal_routes(%{})

      assert is_list(routes)
      assert length(routes) >= 4

      # Check expected routes exist
      route_patterns = Enum.map(routes, fn {pattern, _} -> pattern end)
      assert {"react.user_query", {:strategy_cmd, :react_start}} in routes
      assert {"reqllm.result", {:strategy_cmd, :react_llm_result}} in routes
    end
  end

  describe "StateOps Application Pattern" do
    test "multiple state ops can be composed" do
      ops = [
        StateOpsHelpers.set_iteration_status(:running),
        StateOpsHelpers.set_iteration(1),
        StateOpsHelpers.set_call_id("call_123")
      ]

      assert length(ops) == 3

      # Verify each op has correct type
      assert Enum.all?(ops, fn
        %StateOp.SetPath{} -> true
        _ -> false
      end)
    end

    test "state ops and directives can be combined" do
      state_ops = [
        StateOpsHelpers.set_iteration_status(:running),
        StateOpsHelpers.set_iteration(1)
      ]

      # In actual usage, these would be combined with directives
      # when returned from actions
      assert length(state_ops) == 2
    end

    test "delete operations work correctly" do
      temp_delete = StateOpsHelpers.delete_temp_keys()
      custom_delete = StateOpsHelpers.delete_keys([:custom1])
      call_id_delete = StateOpsHelpers.clear_call_id()

      assert %StateOp.DeleteKeys{} = temp_delete
      assert %StateOp.DeleteKeys{} = custom_delete
      assert %StateOp.DeletePath{} = call_id_delete
    end
  end

  describe "StateOps Helpers Integration" do
    test "helpers work with atom status values" do
      statuses = [:idle, :awaiting_llm, :awaiting_tool, :completed, :error]

      for status <- statuses do
        op = StateOpsHelpers.set_iteration_status(status)
        assert %StateOp.SetPath{} = op
        assert op.value == status
      end
    end

    test "helpers work with various iteration values" do
      for iteration <- [0, 1, 5, 10, 100] do
        op = StateOpsHelpers.set_iteration(iteration)
        assert %StateOp.SetPath{} = op
        assert op.value == iteration
      end
    end

    test "conversation helpers handle different message formats" do
      single_message = [%{role: :user, content: "Hello"}]
      multiple_messages = [
        %{role: :user, content: "Hello"},
        %{role: :assistant, content: "Hi"}
      ]

      op1 = StateOpsHelpers.set_conversation(single_message)
      op2 = StateOpsHelpers.set_conversation(multiple_messages)

      assert %StateOp.SetState{} = op1
      assert %StateOp.SetState{} = op2
      assert op1.attrs.conversation == single_message
      assert op2.attrs.conversation == multiple_messages
    end

    test "pending tools helpers work with various tool formats" do
      tools = [
        %{id: "call_1", name: "search", arguments: %{query: "test"}},
        %{id: "call_2", name: "calculate", arguments: %{expression: "1+1"}}
      ]

      op = StateOpsHelpers.set_pending_tools(tools)

      assert %StateOp.SetState{} = op
      assert op.attrs.pending_tool_calls == tools
    end
  end
end
