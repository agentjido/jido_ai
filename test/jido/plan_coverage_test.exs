defmodule Jido.PlanCoverageTest do
  @moduledoc """
  Additional tests specifically designed to improve coverage for jido_plan.ex
  by targeting missed code paths and edge cases.
  """
  use ExUnit.Case, async: true

  alias Jido.Instruction
  alias Jido.Plan

  # Mock action modules for testing
  defmodule TestActions do
    defmodule SimpleAction do
      use Jido.Action,
        name: "simple_action",
        description: "Simple action for testing"

      @impl true
      def run(params, context) do
        {:ok, %{result: "simple", params: params, context: context}}
      end
    end

    defmodule AnotherAction do
      use Jido.Action,
        name: "another_action",
        description: "Another action for testing"

      @impl true
      def run(params, context) do
        {:ok, %{result: "another", params: params, context: context}}
      end
    end
  end

  describe "Error handling coverage" do
    test "add/4 raises error when instruction normalization fails" do
      # This tests line 172: raise "Invalid instruction format" 
      assert_raise RuntimeError, "Invalid instruction format", fn ->
        Plan.new()
        |> Plan.add(:invalid, {:not_an_atom, %{}, []})
      end
    end

    test "build/3 error when add_step_from_def raises exception" do
      # This tests line 287: error -> {:error, error}
      # We need to create a case where add() raises an exception 
      # Since atoms are valid actions, let's use a completely invalid format
      plan_def = [
        # Invalid format - not an atom, tuple, or instruction
        invalid_step: 123
      ]

      {:error, error} = Plan.build(plan_def)
      assert is_exception(error)
    end

    test "validate_graph when find_cycle returns nil (no cycle found)" do
      # This tests line 338: nil -> :ok
      # Create a simple valid acyclic graph
      plan =
        Plan.new()
        |> Plan.add(:step1, TestActions.SimpleAction)
        |> Plan.add(:step2, TestActions.AnotherAction, depends_on: :step1)

      # This should validate successfully (no cycle found)
      {:ok, {_graph, _plan_instructions}} = Plan.normalize(plan)
    end
  end

  describe "DFS and cycle detection edge cases" do
    test "complex graph with no cycles to trigger successful DFS paths" do
      # Create a complex diamond-shaped DAG to trigger various DFS paths
      plan =
        Plan.new()
        |> Plan.add(:root, TestActions.SimpleAction)
        |> Plan.add(:left, TestActions.SimpleAction, depends_on: :root)
        |> Plan.add(:right, TestActions.AnotherAction, depends_on: :root)
        |> Plan.add(:bottom_left, TestActions.SimpleAction, depends_on: :left)
        |> Plan.add(:bottom_right, TestActions.AnotherAction, depends_on: :right)
        |> Plan.add(:merge, TestActions.SimpleAction, depends_on: [:bottom_left, :bottom_right])

      # This complex graph should normalize successfully and trigger various DFS paths
      {:ok, {graph, _plan_instructions}} = Plan.normalize(plan)

      assert Graph.is_acyclic?(graph)
      assert Graph.num_vertices(graph) == 6

      # This should trigger multiple paths through the DFS algorithm
      {:ok, phases} = Plan.execution_phases(plan)
      assert length(phases) == 4
    end

    test "graph with isolated vertices to test empty neighbors" do
      # Create a plan with steps that have no dependencies to test empty neighbors case
      plan =
        Plan.new()
        |> Plan.add(:isolated1, TestActions.SimpleAction)
        |> Plan.add(:isolated2, TestActions.AnotherAction)
        |> Plan.add(:isolated3, TestActions.SimpleAction)

      # All steps are independent, so should normalize successfully
      {:ok, {graph, _plan_instructions}} = Plan.normalize(plan)

      assert Graph.is_acyclic?(graph)
      # No dependencies means no edges
      assert Graph.num_edges(graph) == 0
      assert Graph.num_vertices(graph) == 3

      # All steps should be in the same phase since they're independent
      {:ok, phases} = Plan.execution_phases(plan)
      assert length(phases) == 1
      assert length(hd(phases)) == 3
    end
  end

  describe "instruction_to_step_def edge cases" do
    test "instruction with empty params and opts" do
      # This tests line 430: {params, opts} when map_size(params) == 0 and opts != []
      instruction = %Instruction{
        action: TestActions.SimpleAction,
        params: %{},
        opts: [retry: true]
      }

      plan_instruction = %Plan.PlanInstruction{
        name: :test_step,
        instruction: instruction,
        depends_on: [],
        opts: []
      }

      plan = %Plan{steps: %{test_step: plan_instruction}}
      result = Plan.to_keyword(plan)
      result_map = Map.new(result)

      # Should return {action, opts} format when params is empty but opts exist
      assert result_map[:test_step] == {TestActions.SimpleAction, retry: true}
    end

    test "instruction with params and opts" do
      # This tests line 431: {params, opts} when opts != []
      instruction = %Instruction{
        action: TestActions.SimpleAction,
        params: %{input: "test"},
        opts: [retry: true, timeout: 5000]
      }

      plan_instruction = %Plan.PlanInstruction{
        name: :test_step,
        instruction: instruction,
        depends_on: [],
        opts: []
      }

      plan = %Plan{steps: %{test_step: plan_instruction}}
      result = Plan.to_keyword(plan)
      result_map = Map.new(result)

      # Should return {action, params, opts} format when both params and opts exist
      assert result_map[:test_step] ==
               {TestActions.SimpleAction, %{input: "test"}, retry: true, timeout: 5000}
    end
  end

  describe "add_depends_on_to_step_def edge cases" do
    test "step with params gets depends_on added" do
      # This tests line 441: {action, params, depends_on: depends_on}
      plan =
        Plan.new()
        |> Plan.add(:step1, TestActions.SimpleAction)
        |> Plan.add(:step2, {TestActions.AnotherAction, %{input: "test"}}, depends_on: :step1)

      result = Plan.to_keyword(plan)
      result_map = Map.new(result)

      assert result_map[:step2] ==
               {TestActions.AnotherAction, %{input: "test"}, depends_on: [:step1]}
    end

    test "step with keyword opts gets depends_on added" do
      # This tests lines 443-444: {action, Keyword.put(opts, :depends_on, depends_on)}
      plan_def = [
        step1: TestActions.SimpleAction,
        step2: {TestActions.AnotherAction, [retry: true, depends_on: :step1]}
      ]

      {:ok, plan} = Plan.build(plan_def)
      result = Plan.to_keyword(plan)
      result_map = Map.new(result)

      # opts should be converted to map format when there are no params
      assert result_map[:step2] ==
               {TestActions.AnotherAction, %{retry: true}, depends_on: [:step1]}
    end

    test "step with params and opts gets depends_on added" do
      # This tests line 447: {action, params, Keyword.put(opts, :depends_on, depends_on)}
      # We need to test this through the to_keyword conversion function directly
      # by creating a plan that has both params and opts in the instruction
      instruction = %Instruction{
        action: TestActions.AnotherAction,
        params: %{input: "test"},
        opts: [retry: true]
      }

      plan_instruction = %Plan.PlanInstruction{
        name: :test_step,
        instruction: instruction,
        depends_on: [:step1],
        opts: []
      }

      plan = %Plan{steps: %{test_step: plan_instruction}}
      result = Plan.to_keyword(plan)
      result_map = Map.new(result)

      # Should return {action, params, opts} format with depends_on added
      assert result_map[:test_step] ==
               {TestActions.AnotherAction, %{input: "test"}, depends_on: [:step1], retry: true}
    end
  end
end
