defmodule Jido.AI.Strategy.StateOpsHelpersTest do
  @moduledoc """
  Unit tests for StateOpsHelpers.
  """

  use ExUnit.Case, async: true

  alias Jido.Agent.StateOp
  alias Jido.AI.Strategy.StateOpsHelpers

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

  describe "update_config/1" do
    test "creates SetState operation for config" do
      config = %{tools: [], model: "test"}
      op = StateOpsHelpers.update_config(config)

      assert %StateOp.SetState{} = op
      assert op.attrs == %{config: config}
    end

    test "creates SetState operation with nested config" do
      config = %{
        tools: [SomeAction],
        actions_by_name: %{"action" => SomeAction},
        reqllm_tools: [%{name: "action"}]
      }

      op = StateOpsHelpers.update_config(config)

      assert %StateOp.SetState{} = op
      assert op.attrs.config.tools == [SomeAction]
      assert op.attrs.config.actions_by_name == %{"action" => SomeAction}
    end
  end

  describe "set_config_field/2" do
    test "creates SetPath operation for nested config field" do
      op = StateOpsHelpers.set_config_field(:tools, [SomeAction])

      assert %StateOp.SetPath{} = op
      assert op.path == [:config, :tools]
      assert op.value == [SomeAction]
    end

    test "creates SetPath operation for model field" do
      op = StateOpsHelpers.set_config_field(:model, "openai:gpt-4")

      assert %StateOp.SetPath{} = op
      assert op.path == [:config, :model]
      assert op.value == "openai:gpt-4"
    end
  end

  describe "update_config_fields/1" do
    test "creates multiple SetPath operations" do
      fields = %{tools: [], model: "test"}
      ops = StateOpsHelpers.update_config_fields(fields)

      assert length(ops) == 2

      assert Enum.all?(ops, fn op -> %StateOp.SetPath{} = op end)

      tools_op = Enum.find(ops, fn op -> op.path == [:config, :tools] end)
      assert tools_op.value == []

      model_op = Enum.find(ops, fn op -> op.path == [:config, :model] end)
      assert model_op.value == "test"
    end

    test "handles empty map" do
      ops = StateOpsHelpers.update_config_fields(%{})
      assert ops == []
    end

    test "creates SetPath operations in field order" do
      fields = %{model: "gpt-4", tools: [], max_tokens: 4096}
      ops = StateOpsHelpers.update_config_fields(fields)

      assert length(ops) == 3

      # Verify all paths are present
      paths = Enum.map(ops, & &1.path)
      assert [:config, :model] in paths
      assert [:config, :tools] in paths
      assert [:config, :max_tokens] in paths
    end
  end

  describe "update_tools_config/3" do
    test "creates three SetPath operations for tools config" do
      tools = [SomeAction]
      actions_by_name = %{"action" => SomeAction}
      reqllm_tools = [%{name: "action"}]

      ops = StateOpsHelpers.update_tools_config(tools, actions_by_name, reqllm_tools)

      assert length(ops) == 3

      assert Enum.all?(ops, fn op -> %StateOp.SetPath{} = op end)

      tools_op = Enum.find(ops, fn op -> op.path == [:config, :tools] end)
      assert tools_op.value == [SomeAction]

      actions_op = Enum.find(ops, fn op -> op.path == [:config, :actions_by_name] end)
      assert actions_op.value == %{"action" => SomeAction}

      reqllm_op = Enum.find(ops, fn op -> op.path == [:config, :reqllm_tools] end)
      assert reqllm_op.value == [%{name: "action"}]
    end

    test "handles empty tools list" do
      ops = StateOpsHelpers.update_tools_config([], %{}, [])

      assert length(ops) == 3

      tools_op = Enum.find(ops, fn op -> op.path == [:config, :tools] end)
      assert tools_op.value == []

      actions_op = Enum.find(ops, fn op -> op.path == [:config, :actions_by_name] end)
      assert actions_op.value == %{}

      reqllm_op = Enum.find(ops, fn op -> op.path == [:config, :reqllm_tools] end)
      assert reqllm_op.value == []
    end

    test "creates operations in consistent order" do
      tools = [Action1, Action2]
      actions_by_name = %{"action1" => Action1, "action2" => Action2}
      reqllm_tools = [%{name: "action1"}, %{name: "action2"}]

      ops = StateOpsHelpers.update_tools_config(tools, actions_by_name, reqllm_tools)

      # Verify order: tools, actions_by_name, reqllm_tools
      assert hd(ops).path == [:config, :tools]
      assert Enum.at(ops, 1).path == [:config, :actions_by_name]
      assert Enum.at(ops, 2).path == [:config, :reqllm_tools]
    end
  end

  describe "apply_to_state/2" do
    test "applies SetState operation" do
      ops = [StateOpsHelpers.update_strategy_state(%{status: :running})]
      result = StateOpsHelpers.apply_to_state(%{iteration: 1}, ops)

      assert result.status == :running
      assert result.iteration == 1
    end

    test "applies SetPath operation for nested key" do
      ops = [StateOpsHelpers.set_config_field(:tools, [SomeAction])]
      result = StateOpsHelpers.apply_to_state(%{}, ops)

      assert result.config.tools == [SomeAction]
    end

    test "applies multiple SetPath operations" do
      ops = StateOpsHelpers.update_tools_config([SomeAction], %{"action" => SomeAction}, [%{name: "action"}])
      result = StateOpsHelpers.apply_to_state(%{other: "value"}, ops)

      assert result.config.tools == [SomeAction]
      assert result.config.actions_by_name == %{"action" => SomeAction}
      assert result.config.reqllm_tools == [%{name: "action"}]
      assert result.other == "value"
    end

    test "applies DeleteKeys operation" do
      ops = [StateOpsHelpers.delete_keys([:temp, :cache])]
      result = StateOpsHelpers.apply_to_state(%{temp: "data", cache: "data", keep: "this"}, ops)

      assert result == %{keep: "this"}
    end

    test "applies ReplaceState operation" do
      ops = [StateOpsHelpers.reset_strategy_state()]
      result = StateOpsHelpers.apply_to_state(%{old: "data", more: "stuff"}, ops)

      assert result.status == :idle
      assert result.iteration == 0
      refute Map.has_key?(result, :old)
      refute Map.has_key?(result, :more)
    end

    test "applies operations in order" do
      ops = [
        StateOpsHelpers.set_strategy_field(:status, :running),
        StateOpsHelpers.set_strategy_field(:count, 5)
      ]

      result = StateOpsHelpers.apply_to_state(%{}, ops)

      assert result.status == :running
      assert result.count == 5
    end

    test "deep merges nested maps with SetState" do
      ops = [StateOpsHelpers.update_strategy_state(%{config: %{model: "gpt-4"}})]
      result = StateOpsHelpers.apply_to_state(%{config: %{tools: []}}, ops)

      assert result.config.tools == []
      assert result.config.model == "gpt-4"
    end
  end
end
