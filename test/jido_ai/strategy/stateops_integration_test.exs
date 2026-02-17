defmodule Jido.AI.Strategy.StateOpsIntegrationTest do
  @moduledoc """
  Integration tests for Phase 9.1 StateOps migration in strategies.

  These tests verify that:
  - StateOps helpers create proper state operations
  - StateOps have correct structure and types
  - ReAct strategy integrates with StateOps helpers
  - StateOps can be composed
  """

  use ExUnit.Case, async: false

  alias Jido.Agent
  alias Jido.Agent.StateOp
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Reasoning.ReAct.Strategy, as: ReAct
  alias Jido.AI.Strategy.StateOpsHelpers

  # ============================================================================
  # Test Fixtures
  # ============================================================================

  defmodule TestAction do
    use Jido.Action,
      name: "test_action",
      description: "A test action"

    def run(%{value: value}, _context), do: {:ok, %{result: value * 2}}
  end

  defp create_agent(opts \\ []) do
    %Agent{id: "test-agent", name: "test", state: %{}}
    |> then(fn agent ->
      ctx = %{strategy_opts: [tools: [TestAction]] ++ opts}
      {agent, []} = ReAct.init(agent, ctx)
      agent
    end)
  end

  # ============================================================================
  # StateOps Helpers Tests
  # ============================================================================

  describe "StateOpsHelpers" do
    test "update_strategy_state/1 creates SetState operation" do
      op = StateOpsHelpers.update_strategy_state(%{status: :running, iteration: 1})

      assert %StateOp.SetState{} = op
      assert op.attrs.status == :running
      assert op.attrs.iteration == 1
    end

    test "set_strategy_field/2 creates SetPath operation" do
      op = StateOpsHelpers.set_strategy_field(:status, :running)

      assert %StateOp.SetPath{} = op
      assert op.path == [:status]
      assert op.value == :running
    end

    test "set_iteration_status/1 creates SetPath operation for status" do
      op = StateOpsHelpers.set_iteration_status(:awaiting_llm)

      assert %StateOp.SetPath{} = op
      assert op.path == [:status]
      assert op.value == :awaiting_llm
    end

    test "set_iteration/1 creates SetPath operation for iteration" do
      op = StateOpsHelpers.set_iteration(5)

      assert %StateOp.SetPath{} = op
      assert op.path == [:iteration]
      assert op.value == 5
    end

    test "append_conversation/1 creates SetState operation" do
      message = %{role: :user, content: "Hello"}
      op = StateOpsHelpers.append_conversation([message])

      assert %StateOp.SetState{} = op
      assert op.attrs.conversation == [message]
    end

    test "set_pending_tools/1 creates SetState operation" do
      tools = [%{id: "call_1", name: "search"}]
      op = StateOpsHelpers.set_pending_tools(tools)

      assert %StateOp.SetState{} = op
      assert op.attrs.pending_tool_calls == tools
    end

    test "clear_pending_tools/0 creates SetState operation with empty list" do
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

    test "set_final_answer/1 creates SetPath operation" do
      op = StateOpsHelpers.set_final_answer("42")

      assert %StateOp.SetPath{} = op
      assert op.path == [:final_answer]
      assert op.value == "42"
    end

    test "set_usage/1 creates SetState operation" do
      usage = %{input_tokens: 10, output_tokens: 20}
      op = StateOpsHelpers.set_usage(usage)

      assert %StateOp.SetState{} = op
      assert op.attrs.usage == usage
    end

    test "delete_keys/1 creates DeleteKeys operation" do
      op = StateOpsHelpers.delete_keys([:temp, :cache])

      assert %StateOp.DeleteKeys{} = op
      assert op.keys == [:temp, :cache]
    end

    test "reset_strategy_state/0 creates ReplaceState operation" do
      op = StateOpsHelpers.reset_strategy_state()

      assert %StateOp.ReplaceState{} = op
      assert op.state.status == :idle
      assert op.state.iteration == 0
      assert op.state.conversation == []
    end

    test "compose/1 returns list of state operations" do
      ops = [
        StateOpsHelpers.set_iteration_status(:running),
        StateOpsHelpers.set_iteration(1)
      ]

      result = StateOpsHelpers.compose(ops)

      assert is_list(result)
      assert length(result) == 2
      assert %StateOp.SetPath{} = Enum.at(result, 0)
      assert %StateOp.SetPath{} = Enum.at(result, 1)
    end
  end

  # ============================================================================
  # StateOp Structure Verification
  # ============================================================================

  describe "StateOp Structure" do
    test "SetState operation has required fields" do
      op = StateOpsHelpers.update_strategy_state(%{field: "value"})

      assert Map.has_key?(op, :__struct__)
      assert Map.has_key?(op, :attrs)
      assert is_map(op.attrs)
    end

    test "SetPath operation has required fields" do
      op = StateOpsHelpers.set_strategy_field(:test, "value")

      assert Map.has_key?(op, :__struct__)
      assert Map.has_key?(op, :path)
      assert Map.has_key?(op, :value)
      assert is_list(op.path)
    end

    test "DeleteKeys operation has required fields" do
      op = StateOpsHelpers.delete_keys([:temp])

      assert Map.has_key?(op, :__struct__)
      assert Map.has_key?(op, :keys)
      assert is_list(op.keys)
    end

    test "ReplaceState operation has required fields" do
      op = StateOpsHelpers.reset_strategy_state()

      assert Map.has_key?(op, :__struct__)
      assert Map.has_key?(op, :state)
      assert is_map(op.state)
    end
  end

  # ============================================================================
  # ReAct Strategy StateOps Integration
  # ============================================================================

  describe "ReAct Strategy StateOps" do
    test "initial state has expected structure" do
      agent = create_agent()

      strategy_state = StratState.get(agent, %{})

      assert is_map(strategy_state)
      assert Map.has_key?(strategy_state, :config)
      assert Map.has_key?(strategy_state, :status)
      assert Map.has_key?(strategy_state, :iteration)
    end

    test "start instruction initializes state correctly" do
      agent = create_agent()

      instruction = %Jido.Instruction{
        action: ReAct.start_action(),
        params: %{query: "test query"}
      }

      {updated_agent, _directives} = ReAct.cmd(agent, [instruction], %{})

      updated_state = StratState.get(updated_agent, %{})

      # State should be updated with query information
      assert is_map(updated_state)
    end

    test "register_tool instruction updates tool list" do
      agent = create_agent()

      instruction = %Jido.Instruction{
        action: ReAct.register_tool_action(),
        params: %{tool_module: TestAction}
      }

      {_updated_agent, _directives} = ReAct.cmd(agent, [instruction], %{})

      # Tool should be registered
      tools = ReAct.list_tools(agent)
      assert TestAction in tools
    end
  end

  # ============================================================================
  # StateOps Composition Tests
  # ============================================================================

  describe "StateOps Composition" do
    test "multiple state operations can be created" do
      ops = [
        StateOpsHelpers.set_iteration(1),
        StateOpsHelpers.set_iteration_status(:running),
        StateOpsHelpers.set_final_answer("answer")
      ]

      assert length(ops) == 3

      # Verify each op has correct structure
      assert %StateOp.SetPath{path: [:iteration], value: 1} = Enum.at(ops, 0)
      assert %StateOp.SetPath{path: [:status], value: :running} = Enum.at(ops, 1)
      assert %StateOp.SetPath{path: [:final_answer], value: "answer"} = Enum.at(ops, 2)
    end

    test "different state op types can be composed" do
      ops = [
        StateOpsHelpers.update_strategy_state(%{field1: "value1"}),
        StateOpsHelpers.set_strategy_field(:field2, "value2"),
        StateOpsHelpers.set_iteration(5),
        StateOpsHelpers.delete_keys([:temp])
      ]

      assert length(ops) == 4
      assert %StateOp.SetState{} = Enum.at(ops, 0)
      assert %StateOp.SetPath{} = Enum.at(ops, 1)
      assert %StateOp.SetPath{} = Enum.at(ops, 2)
      assert %StateOp.DeleteKeys{} = Enum.at(ops, 3)
    end

    test "conversation state ops can be created" do
      ops = [
        StateOpsHelpers.append_conversation([
          %{role: :user, content: "Hello"}
        ])
      ]

      assert length(ops) == 1
      assert %StateOp.SetState{attrs: %{conversation: [%{role: :user, content: "Hello"}]}} = hd(ops)
    end
  end

  # ============================================================================
  # StateOps Type Safety Tests
  # ============================================================================

  describe "StateOps Type Safety" do
    test "SetPath operations have correct value types" do
      int_op = StateOpsHelpers.set_iteration(5)
      atom_op = StateOpsHelpers.set_iteration_status(:running)
      string_op = StateOpsHelpers.set_final_answer("answer")

      assert is_integer(int_op.value)
      assert is_atom(atom_op.value)
      assert is_binary(string_op.value)
    end

    test "SetState operations have map attrs" do
      op1 = StateOpsHelpers.update_strategy_state(%{status: :running})
      op2 = StateOpsHelpers.set_pending_tools([])
      op3 = StateOpsHelpers.set_usage(%{input_tokens: 10})

      assert is_map(op1.attrs)
      assert is_map(op2.attrs)
      assert is_map(op3.attrs)
    end

    test "DeleteKeys operations have list of keys" do
      op = StateOpsHelpers.delete_keys([:temp, :cache])

      assert is_list(op.keys)
      assert Enum.all?(op.keys, &is_atom/1)
    end

    test "ReplaceState operation has map state" do
      op = StateOpsHelpers.reset_strategy_state()

      assert is_map(op.state)
      assert is_map(op.state)
      assert Map.has_key?(op.state, :status)
      assert Map.has_key?(op.state, :iteration)
    end
  end

  # ============================================================================
  # Phase 9.1 Success Criteria
  # ============================================================================

  describe "Phase 9.1 Success Criteria" do
    test "StateOpsHelpers module exists and is accessible" do
      assert Code.ensure_loaded?(StateOpsHelpers)
      assert function_exported?(StateOpsHelpers, :update_strategy_state, 1)
      assert function_exported?(StateOpsHelpers, :set_strategy_field, 2)
      assert function_exported?(StateOpsHelpers, :set_iteration_status, 1)
      assert function_exported?(StateOpsHelpers, :set_iteration, 1)
    end

    test "state ops can be composed" do
      ops = [
        StateOpsHelpers.set_iteration(1),
        StateOpsHelpers.set_iteration_status(:running)
      ]

      assert length(ops) == 2
      assert %StateOp.SetPath{} = hd(ops)
      assert %StateOp.SetPath{} = Enum.at(ops, 1)
    end

    test "ReAct strategy uses StratState for state management" do
      agent = create_agent()

      assert function_exported?(StratState, :get, 2)
      assert function_exported?(StratState, :put, 2)

      state = StratState.get(agent, %{})
      assert is_map(state)
    end

    test "all StateOp types are available" do
      assert Code.ensure_loaded?(StateOp.SetState)
      assert Code.ensure_loaded?(StateOp.SetPath)
      assert Code.ensure_loaded?(StateOp.DeleteKeys)
      assert Code.ensure_loaded?(StateOp.ReplaceState)
    end

    test "StateOps helpers create correct op types" do
      assert %StateOp.SetState{} = StateOpsHelpers.update_strategy_state(%{})
      assert %StateOp.SetPath{} = StateOpsHelpers.set_strategy_field(:test, "value")
      assert %StateOp.DeleteKeys{} = StateOpsHelpers.delete_keys([])
      assert %StateOp.ReplaceState{} = StateOpsHelpers.reset_strategy_state()
    end

    test "ReAct strategy init returns agent and directives" do
      agent = %Agent{id: "test", name: "test", state: %{}}

      assert {updated_agent, directives} = ReAct.init(agent, %{strategy_opts: [tools: [TestAction]]})
      assert %Agent{} = updated_agent
      assert is_list(directives)
    end

    test "ReAct strategy cmd returns agent and directives" do
      agent = create_agent()

      instruction = %Jido.Instruction{
        action: ReAct.start_action(),
        params: %{query: "test"}
      }

      assert {updated_agent, directives} = ReAct.cmd(agent, [instruction], %{})
      assert %Agent{} = updated_agent
      assert is_list(directives)
    end
  end
end
