defmodule Jido.AI.Runner.ChainOfThought.ExecutionContextTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.ChainOfThought.ExecutionContext
  alias Jido.AI.Runner.ChainOfThought.ExecutionContext.EnrichedContext
  alias Jido.AI.Runner.ChainOfThought.ReasoningParser.{ReasoningPlan, ReasoningStep}

  describe "enrich/3" do
    test "enriches context with reasoning plan" do
      original_context = %{state: %{user_id: 123}}

      plan = %ReasoningPlan{
        goal: "Test goal",
        steps: [
          %ReasoningStep{number: 1, description: "Step 1", expected_outcome: "Done"}
        ]
      }

      enriched = ExecutionContext.enrich(original_context, plan, 0)

      assert enriched.cot.reasoning_plan == plan
      assert enriched.cot.step_index == 0
      assert enriched.cot.original_context == original_context
    end

    test "includes current step at given index" do
      plan = %ReasoningPlan{
        goal: "Test",
        steps: [
          %ReasoningStep{number: 1, description: "First", expected_outcome: "Result 1"},
          %ReasoningStep{number: 2, description: "Second", expected_outcome: "Result 2"}
        ]
      }

      context = ExecutionContext.enrich(%{}, plan, 1)

      assert context.cot.current_step.number == 2
      assert context.cot.current_step.description == "Second"
    end

    test "sets nil current step when index out of bounds" do
      plan = %ReasoningPlan{
        goal: "Test",
        steps: [%ReasoningStep{number: 1, description: "Only one", expected_outcome: ""}]
      }

      context = ExecutionContext.enrich(%{}, plan, 5)

      assert context.cot.current_step == nil
    end

    test "preserves original context fields" do
      original = %{state: %{data: "value"}, agent: %{id: "123"}}
      plan = %ReasoningPlan{goal: "Test", steps: []}

      enriched = ExecutionContext.enrich(original, plan, 0)

      assert enriched.state == %{data: "value"}
      assert enriched.agent == %{id: "123"}
    end
  end

  describe "get_reasoning_plan/1" do
    test "extracts reasoning plan from enriched context" do
      plan = %ReasoningPlan{goal: "Test goal", steps: []}
      enriched = ExecutionContext.enrich(%{}, plan, 0)

      assert {:ok, extracted_plan} = ExecutionContext.get_reasoning_plan(enriched)
      assert extracted_plan == plan
    end

    test "returns error for non-enriched context" do
      context = %{state: %{}, agent: %{}}

      assert {:error, :no_reasoning_context} = ExecutionContext.get_reasoning_plan(context)
    end
  end

  describe "get_current_step/1" do
    test "extracts current step from enriched context" do
      step = %ReasoningStep{number: 1, description: "Test", expected_outcome: "Done"}
      plan = %ReasoningPlan{goal: "Test", steps: [step]}
      enriched = ExecutionContext.enrich(%{}, plan, 0)

      assert {:ok, extracted_step} = ExecutionContext.get_current_step(enriched)
      assert extracted_step == step
    end

    test "returns error when no current step exists" do
      plan = %ReasoningPlan{goal: "Test", steps: []}
      enriched = ExecutionContext.enrich(%{}, plan, 0)

      assert {:error, :no_current_step} = ExecutionContext.get_current_step(enriched)
    end

    test "returns error for non-enriched context" do
      context = %{state: %{}}

      assert {:error, :no_reasoning_context} = ExecutionContext.get_current_step(context)
    end
  end

  describe "has_reasoning_context?/1" do
    test "returns true for enriched context" do
      plan = %ReasoningPlan{goal: "Test", steps: []}
      enriched = ExecutionContext.enrich(%{}, plan, 0)

      assert ExecutionContext.has_reasoning_context?(enriched) == true
    end

    test "returns false for non-enriched context" do
      context = %{state: %{}, agent: %{}}

      assert ExecutionContext.has_reasoning_context?(context) == false
    end

    test "returns false for empty context" do
      assert ExecutionContext.has_reasoning_context?(%{}) == false
    end
  end

  describe "EnrichedContext struct" do
    test "has default values" do
      context = %EnrichedContext{}

      assert context.reasoning_plan == nil
      assert context.current_step == nil
      assert context.step_index == 0
      assert context.original_context == %{}
    end
  end
end
