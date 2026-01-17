defmodule Jido.AI.Strategy.StateOpsHelpersTest do
  @moduledoc """
  Unit tests for StateOpsHelpers.
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Strategy.StateOpsHelpers
  alias Jido.Agent.StateOp

  doctest StateOpsHelpers

  describe "update_strategy_state/1" do
    test "creates SetState operation with given attributes" do
      op = StateOpsHelpers.update_strategy_state(%{status: :running, iteration: 1})

      assert %StateOp.SetState{} = op
      assert op.attrs == %{status: :running, iteration: 1}
    end
  end

  describe "set_strategy_field/2" do
    test "creates SetPath operation for a single field" do
      op = StateOpsHelpers.set_strategy_field(:status, :running)

      assert %StateOp.SetPath{} = op
      assert op.path == [:status]
      assert op.value == :running
    end
  end

  describe "set_iteration_status/1" do
    test "creates SetPath operation for status" do
      op = StateOpsHelpers.set_iteration_status(:awaiting_llm)

      assert %StateOp.SetPath{} = op
      assert op.path == [:status]
      assert op.value == :awaiting_llm
    end
  end

  describe "set_iteration/1" do
    test "creates SetPath operation for iteration counter" do
      op = StateOpsHelpers.set_iteration(5)

      assert %StateOp.SetPath{} = op
      assert op.path == [:iteration]
      assert op.value == 5
    end

    test "accepts zero as valid iteration" do
      op = StateOpsHelpers.set_iteration(0)

      assert %StateOp.SetPath{} = op
      assert op.value == 0
    end
  end

  describe "set_iteration_counter/1" do
    test "aliases set_iteration/1" do
      op1 = StateOpsHelpers.set_iteration_counter(3)
      op2 = StateOpsHelpers.set_iteration(3)

      assert op1.path == op2.path
      assert op1.value == op2.value
    end
  end

  describe "append_conversation/1" do
    test "creates SetState operation for conversation list" do
      messages = [%{role: :user, content: "Hello"}]
      op = StateOpsHelpers.append_conversation(messages)

      assert %StateOp.SetState{} = op
      assert op.attrs == %{conversation: messages}
    end
  end

  describe "prepend_conversation/2" do
    test "creates SetState operation with message prepended" do
      message = %{role: :user, content: "Hello"}
      existing = [%{role: :assistant, content: "Hi"}]
      op = StateOpsHelpers.prepend_conversation(message, existing)

      assert %StateOp.SetState{} = op
      assert op.attrs.conversation == [message | existing]
    end

    test "works with empty existing conversation" do
      message = %{role: :user, content: "Hello"}
      op = StateOpsHelpers.prepend_conversation(message, [])

      assert %StateOp.SetState{} = op
      assert op.attrs.conversation == [message]
    end
  end

  describe "set_conversation/1" do
    test "creates SetState operation for entire conversation" do
      messages = [
        %{role: :user, content: "Hello"},
        %{role: :assistant, content: "Hi"}
      ]

      op = StateOpsHelpers.set_conversation(messages)

      assert %StateOp.SetState{} = op
      assert op.attrs == %{conversation: messages}
    end
  end

  describe "set_pending_tools/1" do
    test "creates SetState operation for pending tools" do
      tools = [%{id: "call_1", name: "search", arguments: %{query: "test"}}]
      op = StateOpsHelpers.set_pending_tools(tools)

      assert %StateOp.SetState{} = op
      assert op.attrs == %{pending_tool_calls: tools}
    end
  end

  describe "add_pending_tool/1" do
    test "creates SetState operation for single tool" do
      tool = %{id: "call_1", name: "search", arguments: %{query: "test"}}
      op = StateOpsHelpers.add_pending_tool(tool)

      assert %StateOp.SetState{} = op
      assert op.attrs.pending_tool_calls == [tool]
    end
  end

  describe "clear_pending_tools/0" do
    test "creates SetState operation to clear tools" do
      op = StateOpsHelpers.clear_pending_tools()

      assert %StateOp.SetState{} = op
      assert op.attrs == %{pending_tool_calls: []}
    end
  end

  describe "remove_pending_tool/1" do
    test "creates DeletePath operation for tool ID" do
      op = StateOpsHelpers.remove_pending_tool("call_1")

      assert %StateOp.DeletePath{} = op
      assert op.path == [:pending_tool_calls, "call_1"]
    end
  end

  describe "set_call_id/1" do
    test "creates SetPath operation for call ID" do
      op = StateOpsHelpers.set_call_id("call_123")

      assert %StateOp.SetPath{} = op
      assert op.path == [:current_llm_call_id]
      assert op.value == "call_123"
    end
  end

  describe "clear_call_id/0" do
    test "creates DeletePath operation for call ID" do
      op = StateOpsHelpers.clear_call_id()

      assert %StateOp.DeletePath{} = op
      assert op.path == [:current_llm_call_id]
    end
  end

  describe "set_final_answer/1" do
    test "creates SetPath operation for final answer" do
      op = StateOpsHelpers.set_final_answer("42")

      assert %StateOp.SetPath{} = op
      assert op.path == [:final_answer]
      assert op.value == "42"
    end
  end

  describe "set_termination_reason/1" do
    test "creates SetPath operation for termination reason" do
      op = StateOpsHelpers.set_termination_reason(:final_answer)

      assert %StateOp.SetPath{} = op
      assert op.path == [:termination_reason]
      assert op.value == :final_answer
    end
  end

  describe "set_streaming_text/1" do
    test "creates SetPath operation for streaming text" do
      op = StateOpsHelpers.set_streaming_text("Hello")

      assert %StateOp.SetPath{} = op
      assert op.path == [:streaming_text]
      assert op.value == "Hello"
    end
  end

  describe "append_streaming_text/1" do
    test "creates SetPath operation to append streaming text" do
      op = StateOpsHelpers.append_streaming_text(" world")

      assert %StateOp.SetPath{} = op
      assert op.path == [:streaming_text]
      assert op.value == " world"
    end
  end

  describe "set_usage/1" do
    test "creates SetState operation for usage metadata" do
      usage = %{input_tokens: 10, output_tokens: 20}
      op = StateOpsHelpers.set_usage(usage)

      assert %StateOp.SetState{} = op
      assert op.attrs == %{usage: usage}
    end
  end

  describe "delete_temp_keys/0" do
    test "creates DeleteKeys operation for temp keys" do
      op = StateOpsHelpers.delete_temp_keys()

      assert %StateOp.DeleteKeys{} = op
      assert op.keys == [:temp, :cache, :ephemeral]
    end
  end

  describe "delete_keys/1" do
    test "creates DeleteKeys operation for specified keys" do
      op = StateOpsHelpers.delete_keys([:temp1, :temp2])

      assert %StateOp.DeleteKeys{} = op
      assert op.keys == [:temp1, :temp2]
    end
  end

  describe "reset_strategy_state/0" do
    test "creates ReplaceState operation with initial values" do
      op = StateOpsHelpers.reset_strategy_state()

      assert %StateOp.ReplaceState{} = op
      assert op.state.status == :idle
      assert op.state.iteration == 0
      assert op.state.conversation == []
      assert op.state.pending_tool_calls == []
      assert op.state.final_answer == nil
      assert op.state.current_llm_call_id == nil
      assert op.state.termination_reason == nil
    end
  end

  describe "compose/1" do
    test "returns list of state operations unchanged" do
      ops = [
        StateOpsHelpers.set_iteration_status(:running),
        StateOpsHelpers.set_iteration(1)
      ]

      result = StateOpsHelpers.compose(ops)

      assert result == ops
      assert length(result) == 2
    end

    test "handles empty list" do
      result = StateOpsHelpers.compose([])

      assert result == []
    end
  end
end
