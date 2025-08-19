defmodule Jido.Tools.ActionPlanTest do
  use ExUnit.Case, async: true

  alias Jido.Plan
  alias Jido.Tools.ActionPlan

  # Test actions for workflow execution
  defmodule TestAction do
    use Jido.Action,
      name: "test_action",
      description: "A test action"

    @impl Jido.Action
    def run(params, _context) do
      result = Map.get(params, :result, "test_result")
      {:ok, %{result: result}}
    end
  end

  defmodule AddAction do
    use Jido.Action,
      name: "add_action",
      description: "Adds two numbers"

    @impl Jido.Action
    def run(params, _context) do
      a = Map.get(params, :a, 0)
      b = Map.get(params, :b, 0)
      {:ok, %{sum: a + b}}
    end
  end

  defmodule MultiplyAction do
    use Jido.Action,
      name: "multiply_action",
      description: "Multiplies a number by 2"

    @impl Jido.Action
    def run(params, _context) do
      value = Map.get(params, :sum, 0)
      {:ok, %{product: value * 2}}
    end
  end

  defmodule FailingAction do
    use Jido.Action,
      name: "failing_action",
      description: "An action that always fails"

    @impl Jido.Action
    def run(_params, _context) do
      {:error, "This action always fails"}
    end
  end

  # Test ActionPlan implementations
  defmodule SimpleActionPlan do
    use ActionPlan,
      name: "simple_workflow",
      description: "A simple workflow with one step"

    @impl ActionPlan
    def build(_params, context) do
      Plan.new(context: context)
      |> Plan.add(:test_step, TestAction)
    end
  end

  defmodule SequentialActionPlan do
    use ActionPlan,
      name: "sequential_workflow",
      description: "A workflow with sequential steps"

    @impl ActionPlan
    def build(params, context) do
      Plan.new(context: context)
      |> Plan.add(:add, {AddAction, %{a: params[:a] || 1, b: params[:b] || 2}})
      |> Plan.add(:multiply, MultiplyAction, depends_on: :add)
    end
  end

  defmodule ParallelActionPlan do
    use ActionPlan,
      name: "parallel_workflow",
      description: "A workflow with parallel steps"

    @impl ActionPlan
    def build(_params, context) do
      Plan.new(context: context)
      |> Plan.add(:step1, {TestAction, %{result: "result1"}})
      |> Plan.add(:step2, {TestAction, %{result: "result2"}})
      |> Plan.add(:merge, TestAction, depends_on: [:step1, :step2])
    end
  end

  defmodule TransformingActionPlan do
    use ActionPlan,
      name: "transforming_workflow",
      description: "A workflow that transforms results"

    @impl ActionPlan
    def build(_params, context) do
      Plan.new(context: context)
      |> Plan.add(:test_step, TestAction)
    end

    @impl ActionPlan
    def transform_result(result) do
      {:ok, %{transformed: true, original: result}}
    end
  end

  defmodule FailingActionPlan do
    use ActionPlan,
      name: "failing_workflow",
      description: "A workflow with a failing step"

    @impl ActionPlan
    def build(_params, context) do
      Plan.new(context: context)
      |> Plan.add(:failing_step, FailingAction)
    end
  end

  defmodule InvalidActionPlan do
    use ActionPlan,
      name: "invalid_workflow",
      description: "A workflow that causes execution issues"

    @impl ActionPlan
    def build(_params, context) do
      Plan.new(context: context)
      |> Plan.add(:step1, TestAction, depends_on: :step2)
      |> Plan.add(:step2, TestAction, depends_on: :step1)
    end
  end

  defmodule ErrorInTransformActionPlan do
    use ActionPlan,
      name: "error_transform_workflow",
      description: "A workflow that errors in transform_result"

    @impl ActionPlan
    def build(_params, context) do
      Plan.new(context: context)
      |> Plan.add(:test_step, TestAction)
    end

    @impl ActionPlan
    def transform_result(_result) do
      {:error, "Transform failed"}
    end
  end

  defmodule EmptyPhasesActionPlan do
    use ActionPlan,
      name: "empty_phases_workflow",
      description: "A workflow that results in empty phases"

    @impl ActionPlan
    def build(_params, context) do
      Plan.new(context: context)
    end
  end

  defmodule ParameterMergingActionPlan do
    use ActionPlan,
      name: "parameter_merging_workflow",
      description: "Tests parameter merging behavior"

    @impl ActionPlan
    def build(_params, context) do
      Plan.new(context: context)
      |> Plan.add(:step1, {TestAction, %{result: "override"}})
    end
  end

  defmodule ComplexActionPlan do
    use ActionPlan,
      name: "complex_workflow",
      description: "A complex workflow with multiple phases and dependencies"

    @impl ActionPlan
    def build(_params, context) do
      Plan.new(context: context)
      |> Plan.add(:init, {TestAction, %{result: "initialized"}})
      |> Plan.add(:process1, {AddAction, %{a: 1, b: 2}}, depends_on: :init)
      |> Plan.add(:process2, {AddAction, %{a: 3, b: 4}}, depends_on: :init)
      |> Plan.add(:combine, MultiplyAction, depends_on: [:process1, :process2])
    end
  end

  describe "ActionPlan behavior" do
    test "simple workflow executes successfully" do
      params = %{}
      context = %{}

      assert {:ok, result} = SimpleActionPlan.run(params, context)
      assert %{test_step: %{result: "test_result"}} = result
    end

    test "sequential workflow executes in order" do
      params = %{a: 5, b: 3}
      context = %{}

      assert {:ok, result} = SequentialActionPlan.run(params, context)
      assert %{add: %{sum: 8}, multiply: %{product: 16}} = result
    end

    test "parallel workflow executes parallel steps" do
      params = %{}
      context = %{}

      assert {:ok, result} = ParallelActionPlan.run(params, context)
      assert %{step1: %{result: "result1"}, step2: %{result: "result2"}} = result
      assert Map.has_key?(result, :merge)
    end

    test "workflow with transform_result callback" do
      params = %{}
      context = %{}

      assert {:ok, result} = TransformingActionPlan.run(params, context)
      assert %{transformed: true, original: %{test_step: %{result: "test_result"}}} = result
    end

    test "workflow handles step failures" do
      params = %{}
      context = %{}

      assert {:error, error} = FailingActionPlan.run(params, context)
      assert %{type: :step_execution_failed, step_name: :failing_step} = error
      assert is_exception(error.reason)
      assert Exception.message(error.reason) =~ "This action always fails"
    end

    test "workflow handles plan execution failures" do
      params = %{}
      context = %{}

      assert {:error, error} = InvalidActionPlan.run(params, context)
      assert error.message =~ "circular dependencies"
    end
  end

  describe "ActionPlan module attributes" do
    test "has correct name and description" do
      assert SimpleActionPlan.name() == "simple_workflow"
      assert SimpleActionPlan.description() == "A simple workflow with one step"
    end

    test "inherits Action behavior" do
      assert function_exported?(SimpleActionPlan, :run, 2)
      assert function_exported?(SimpleActionPlan, :name, 0)
      assert function_exported?(SimpleActionPlan, :description, 0)
    end
  end

  describe "error handling" do
    test "handles error in transform_result callback" do
      params = %{}
      context = %{}

      assert {:error, "Transform failed"} = ErrorInTransformActionPlan.run(params, context)
    end

    test "handles empty workflow with no steps" do
      params = %{}
      context = %{}

      assert {:ok, result} = EmptyPhasesActionPlan.run(params, context)
      assert result == %{}
    end
  end

  describe "phase execution" do
    test "executes multiple phases sequentially with parameter passing" do
      params = %{a: 10, b: 5}
      context = %{}

      assert {:ok, result} = SequentialActionPlan.run(params, context)
      assert %{add: %{sum: 15}, multiply: %{product: 30}} = result
    end

    test "handles empty phase list" do
      params = %{}
      context = %{}

      assert {:ok, result} = EmptyPhasesActionPlan.run(params, context)
      assert result == %{}
    end

    test "stops execution on first phase failure" do
      params = %{}
      context = %{}

      assert {:error, error} = FailingActionPlan.run(params, context)
      assert %{type: :step_execution_failed} = error
    end
  end

  describe "step parameter merging" do
    test "instruction params take precedence over current params" do
      params = %{result: "original"}
      context = %{}

      assert {:ok, result} = ParameterMergingActionPlan.run(params, context)
      assert %{step1: %{result: "override"}} = result
    end
  end

  describe "callback behavior" do
    test "default transform_result returns result unchanged" do
      params = %{}
      context = %{}

      assert {:ok, result} = SimpleActionPlan.run(params, context)
      assert %{test_step: %{result: "test_result"}} = result
    end

    test "can override transform_result behavior" do
      params = %{}
      context = %{}

      assert {:ok, result} = TransformingActionPlan.run(params, context)
      assert %{transformed: true, original: %{test_step: %{result: "test_result"}}} = result
    end
  end

  describe "complex workflow scenarios" do
    test "executes complex workflow with mixed parallel and sequential phases" do
      params = %{}
      context = %{}

      assert {:ok, result} = ComplexActionPlan.run(params, context)

      assert %{init: _, process1: _, process2: _, combine: _} = result
      assert %{result: "initialized"} = result.init
      assert %{sum: 3} = result.process1
      assert %{sum: 7} = result.process2
      assert %{product: _} = result.combine
    end
  end

  describe "plan building and execution" do
    test "build callback is required" do
      # Verify that the build callback is defined
      assert function_exported?(SimpleActionPlan, :build, 2)
    end

    test "transform_result callback is optional with default implementation" do
      # Test that the default transform_result is defined
      assert function_exported?(SimpleActionPlan, :transform_result, 1)

      # Test default behavior
      result = %{some: "data"}
      assert {:ok, ^result} = SimpleActionPlan.transform_result(result)
    end

    test "can override default transform_result" do
      # Test that overridden transform_result works
      result = %{some: "data"}

      assert {:ok, %{transformed: true, original: ^result}} =
               TransformingActionPlan.transform_result(result)
    end
  end

  describe "execution flow coverage" do
    test "exercises execute_plan path with successful plan" do
      params = %{}
      context = %{}

      # This test ensures execute_plan -> execute_phases -> execute_phase -> execute_step flow
      assert {:ok, _result} = SimpleActionPlan.run(params, context)
    end

    test "exercises error paths in execution" do
      params = %{}
      context = %{}

      # Test the error path in execute_phases when a step fails
      assert {:error, _error} = FailingActionPlan.run(params, context)
    end

    test "exercises parameter merging in execute_step" do
      params = %{base_param: "value"}
      context = %{}

      # This exercises the parameter merging logic in execute_step
      assert {:ok, _result} = ParameterMergingActionPlan.run(params, context)
    end

    test "exercises phase result flattening and parameter passing" do
      params = %{a: 1, b: 2}
      context = %{}

      # This exercises the parameter flattening logic between phases
      assert {:ok, result} = SequentialActionPlan.run(params, context)
      # Verify the sum was passed to the multiply step
      # (1+2) * 2
      assert result.multiply.product == 6
    end
  end
end
