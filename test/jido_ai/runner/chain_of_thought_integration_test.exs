defmodule Jido.AI.Runner.ChainOfThoughtIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Prompt
  alias Jido.AI.Runner.ChainOfThought
  alias Jido.AI.Runner.ChainOfThought.{ReasoningParser, ReasoningPrompt}

  @moduletag :integration

  describe "reasoning generation with various instruction sequences" do
    test "generates reasoning for single instruction" do
      instructions = [build_instruction(TestCalculateAction, %{x: 5, y: 3})]
      agent = build_test_agent()

      # Mock the reasoning generation
      reasoning_text = """
      GOAL: Calculate sum of x and y

      ANALYSIS: Simple arithmetic operation

      EXECUTION_PLAN:
      Step 1: Add x and y → sum calculated

      EXPECTED_RESULTS: Result should be 8

      POTENTIAL_ISSUES:
      - None expected for simple arithmetic
      """

      {:ok, plan} = ReasoningParser.parse(reasoning_text)

      assert plan.goal =~ "Calculate"
      assert length(plan.steps) == 1
      assert hd(plan.steps).description =~ "Add"
    end

    test "generates reasoning for multiple sequential instructions" do
      instructions = [
        build_instruction(TestCalculateAction, %{x: 5, y: 3}),
        build_instruction(TestMultiplyAction, %{value: 2})
      ]

      agent = build_test_agent()

      reasoning_text = """
      GOAL: Calculate then multiply result

      ANALYSIS: Two-step arithmetic operation

      EXECUTION_PLAN:
      Step 1: Add x and y → sum of 8
      Step 2: Multiply result by value → final result of 16

      EXPECTED_RESULTS: Final result should be 16

      POTENTIAL_ISSUES:
      - None expected
      """

      {:ok, plan} = ReasoningParser.parse(reasoning_text)

      assert length(plan.steps) == 2
      assert Enum.at(plan.steps, 0).description =~ "Add"
      assert Enum.at(plan.steps, 1).description =~ "Multiply"
    end

    test "generates reasoning for complex instruction sequence" do
      instructions = [
        build_instruction(TestValidateAction, %{data: "test"}),
        build_instruction(TestProcessAction, %{operation: :transform}),
        build_instruction(TestSaveAction, %{destination: "output"})
      ]

      reasoning_text = """
      GOAL: Validate, process, and save data

      ANALYSIS: Three-step data pipeline with validation, transformation, and persistence

      EXECUTION_PLAN:
      Step 1: Validate input data → data validated
      Step 2: Process validated data with transform operation → data transformed
      Step 3: Save transformed data to output → data persisted

      EXPECTED_RESULTS: Data should be validated, transformed, and saved to output

      POTENTIAL_ISSUES:
      - Validation might fail if data format is incorrect
      - Transform operation might error on invalid data
      - Save operation might fail if destination is not writable
      """

      {:ok, plan} = ReasoningParser.parse(reasoning_text)

      assert length(plan.steps) == 3
      assert length(plan.potential_issues) >= 2
      assert plan.goal =~ "Validate"
    end

    test "handles empty instruction list" do
      agent = build_test_agent_with_instructions([])

      {:ok, returned_agent, directives} = ChainOfThought.run(agent)

      assert returned_agent == agent
      assert directives == []
    end
  end

  describe "execution flow with reasoning context enrichment" do
    @tag :skip
    @tag :requires_llm
    test "enriches context with reasoning information" do
      # Requires LLM API key to test with actual reasoning
      # Or Simple runner compatibility for fallback
      agent =
        build_test_agent_with_instructions([
          build_instruction(ContextAwareAction, %{value: 42})
        ])

      result = ChainOfThought.run(agent, fallback_on_error: true)

      assert {:ok, _, _} = result
    end

    @tag :skip
    @tag :requires_llm
    test "executes actions with step information" do
      # Requires LLM API key for full test
      agent =
        build_test_agent_with_instructions([
          build_instruction(TestCalculateAction, %{x: 10, y: 5})
        ])

      result = ChainOfThought.run(agent, fallback_on_error: true)

      assert {:ok, _, _} = result
    end

    @tag :skip
    @tag :requires_llm
    test "maintains agent state through execution" do
      # Requires LLM API key for full test
      initial_state = %{counter: 0, data: "test"}

      agent =
        build_test_agent_with_instructions([
          build_instruction(TestCalculateAction, %{x: 1, y: 1})
        ])

      agent = %{agent | state: initial_state}

      result = ChainOfThought.run(agent, fallback_on_error: true)

      assert {:ok, updated_agent, _} = result
      assert updated_agent.state == initial_state
    end

    @tag :skip
    @tag :requires_llm
    test "accumulates directives from multiple instructions" do
      # Requires LLM API key for full test
      agent =
        build_test_agent_with_instructions([
          build_instruction(TestCalculateAction, %{x: 1, y: 1}),
          build_instruction(TestCalculateAction, %{x: 2, y: 2})
        ])

      result = ChainOfThought.run(agent, fallback_on_error: true)

      assert {:ok, _, directives} = result
      assert is_list(directives)
    end
  end

  describe "error handling and fallback mechanisms" do
    @tag :skip
    @tag :requires_llm
    test "falls back to simple runner on reasoning generation failure" do
      # Requires Simple runner compatibility
      agent =
        build_test_agent_with_instructions([
          build_instruction(TestCalculateAction, %{x: 5, y: 3})
        ])

      result =
        ChainOfThought.run(agent,
          fallback_on_error: true,
          model: "invalid-model"
        )

      assert {:ok, _, _} = result
    end

    test "returns error when fallback disabled and reasoning fails" do
      agent =
        build_test_agent_with_instructions([
          build_instruction(TestCalculateAction, %{x: 5, y: 3})
        ])

      # With fallback disabled, should return error
      result =
        ChainOfThought.run(agent,
          fallback_on_error: false,
          # Force reasoning failure
          model: "invalid-model"
        )

      assert {:error, _error} = result
    end

    @tag :skip
    @tag :requires_llm
    test "handles action execution errors with fallback" do
      # Requires Simple runner compatibility
      agent =
        build_test_agent_with_instructions([
          build_instruction(FailingAction, %{should_fail: true})
        ])

      result = ChainOfThought.run(agent, fallback_on_error: true)

      assert {:error, _} = result
    end

    @tag :skip
    @tag :requires_llm
    test "handles missing action module gracefully" do
      # Requires Simple runner compatibility
      agent =
        build_test_agent_with_instructions([
          %{action: NonExistentAction, params: %{}, id: "test"}
        ])

      result = ChainOfThought.run(agent, fallback_on_error: true)

      assert {:error, _} = result
    end

    @tag :skip
    @tag :requires_llm
    test "recovers from LLM timeout with retry" do
      # Requires LLM API key for full test
      agent =
        build_test_agent_with_instructions([
          build_instruction(TestCalculateAction, %{x: 1, y: 1})
        ])

      result = ChainOfThought.run(agent, fallback_on_error: true)

      assert {:ok, _, _} = result
    end
  end

  describe "outcome validation integration" do
    @tag :skip
    @tag :requires_llm
    test "validates successful outcomes match expectations" do
      # Requires LLM API key for full test
      agent =
        build_test_agent_with_instructions([
          build_instruction(TestCalculateAction, %{x: 5, y: 3})
        ])

      result =
        ChainOfThought.run(agent,
          enable_validation: true,
          fallback_on_error: true
        )

      assert {:ok, _, _} = result
    end

    @tag :skip
    @tag :requires_llm
    test "detects unexpected outcomes" do
      # Requires LLM API key for full test
      agent =
        build_test_agent_with_instructions([
          build_instruction(RandomOutcomeAction, %{seed: 123})
        ])

      result =
        ChainOfThought.run(agent,
          enable_validation: true,
          fallback_on_error: true
        )

      assert {:ok, _, _} = result
    end

    @tag :skip
    @tag :requires_llm
    test "can disable outcome validation" do
      # Requires LLM API key for full test
      agent =
        build_test_agent_with_instructions([
          build_instruction(TestCalculateAction, %{x: 1, y: 1})
        ])

      result =
        ChainOfThought.run(agent,
          enable_validation: false,
          fallback_on_error: true
        )

      assert {:ok, _, _} = result
    end

    @tag :skip
    @tag :requires_llm
    test "handles validation with matching results" do
      # Detailed validation testing is in outcome_validator_test.exs
      # This tests integration with runner
      agent =
        build_test_agent_with_instructions([
          build_instruction(PredictableAction, %{value: 42})
        ])

      result =
        ChainOfThought.run(agent,
          enable_validation: true,
          fallback_on_error: true
        )

      assert {:ok, _, _} = result
    end
  end

  describe "reasoning trace structure validation" do
    test "reasoning plan has all required fields" do
      reasoning_text = """
      GOAL: Test goal

      ANALYSIS: Test analysis

      EXECUTION_PLAN:
      Step 1: First step → first outcome
      Step 2: Second step → second outcome

      EXPECTED_RESULTS: Expected result

      POTENTIAL_ISSUES:
      - Issue 1
      - Issue 2
      """

      {:ok, plan} = ReasoningParser.parse(reasoning_text)

      assert is_binary(plan.goal)
      assert is_binary(plan.analysis)
      assert is_list(plan.steps)
      assert is_binary(plan.expected_results)
      assert is_list(plan.potential_issues)
      assert is_binary(plan.raw_text)
    end

    test "reasoning steps have correct structure" do
      reasoning_text = """
      GOAL: Test

      ANALYSIS: Analysis

      EXECUTION_PLAN:
      Step 1: Do something → result
      Step 2: Do another thing → another result

      EXPECTED_RESULTS: Results

      POTENTIAL_ISSUES:
      - None
      """

      {:ok, plan} = ReasoningParser.parse(reasoning_text)

      assert length(plan.steps) == 2

      Enum.each(plan.steps, fn step ->
        assert is_integer(step.number)
        assert is_binary(step.description)
        assert is_binary(step.expected_outcome)
      end)
    end

    test "validates reasoning plan completeness" do
      valid_plan = %ReasoningParser.ReasoningPlan{
        goal: "Complete task",
        analysis: "Detailed analysis",
        steps: [
          %ReasoningParser.ReasoningStep{
            number: 1,
            description: "Step 1",
            expected_outcome: "Outcome 1"
          }
        ],
        expected_results: "Final results",
        potential_issues: ["Issue 1"],
        raw_text: "Original text"
      }

      assert :ok = ReasoningParser.validate(valid_plan)
    end

    test "detects incomplete reasoning plans" do
      incomplete_plan = %ReasoningParser.ReasoningPlan{
        # Empty goal
        goal: "",
        analysis: "Analysis",
        # No steps
        steps: [],
        expected_results: "",
        potential_issues: [],
        raw_text: ""
      }

      assert {:error, _reason} = ReasoningParser.validate(incomplete_plan)
    end

    test "generates valid prompts for different modes" do
      instructions = [build_instruction(TestCalculateAction, %{x: 1, y: 1})]
      agent_state = %{data: "test"}

      # Test zero-shot mode
      zero_shot_prompt = ReasoningPrompt.zero_shot(instructions, agent_state)
      assert %Prompt{} = zero_shot_prompt
      assert length(zero_shot_prompt.messages) > 0

      # Test structured mode
      structured_prompt = ReasoningPrompt.structured(instructions, agent_state)
      assert %Prompt{} = structured_prompt
      assert length(structured_prompt.messages) > 0

      # Prompts should be different
      zero_shot_content = hd(zero_shot_prompt.messages).content
      structured_content = hd(structured_prompt.messages).content
      assert zero_shot_content != structured_content
    end
  end

  describe "full execution pipeline" do
    @tag :skip
    @tag :requires_llm
    test "completes full pipeline with reasoning" do
      # Requires LLM API key for full test
      agent =
        build_test_agent_with_instructions([
          build_instruction(TestCalculateAction, %{x: 10, y: 5}),
          build_instruction(TestMultiplyAction, %{value: 2})
        ])

      result =
        ChainOfThought.run(agent,
          mode: :zero_shot,
          enable_validation: true,
          fallback_on_error: true
        )

      assert {:ok, updated_agent, directives} = result
      assert updated_agent.id == agent.id
      assert is_list(directives)
    end

    @tag :skip
    @tag :requires_llm
    test "handles complex multi-step workflow" do
      # Requires LLM API key for full test
      agent =
        build_test_agent_with_instructions([
          build_instruction(TestValidateAction, %{data: "input"}),
          build_instruction(TestProcessAction, %{operation: :transform}),
          build_instruction(TestCalculateAction, %{x: 5, y: 5}),
          build_instruction(TestSaveAction, %{destination: "output"})
        ])

      result =
        ChainOfThought.run(agent,
          mode: :structured,
          enable_validation: true,
          fallback_on_error: true,
          max_iterations: 1
        )

      assert {:ok, _, _} = result
    end
  end

  # Test Helpers

  defp build_test_agent do
    %{
      id: "test-agent-#{:rand.uniform(10000)}",
      name: "Test Agent",
      state: %{},
      pending_instructions: :queue.new(),
      actions: [],
      runner: ChainOfThought,
      result: nil
    }
  end

  defp build_test_agent_with_instructions(instructions) do
    agent = build_test_agent()

    queue =
      Enum.reduce(instructions, :queue.new(), fn instruction, q ->
        :queue.in(instruction, q)
      end)

    %{agent | pending_instructions: queue}
  end

  defp build_instruction(action_module, params) do
    %{
      action: action_module,
      params: params,
      id: "instruction-#{:rand.uniform(10000)}"
    }
  end

  # Test Actions

  defmodule TestCalculateAction do
    use Jido.Action,
      name: "test_calculate",
      schema: [x: [type: :integer], y: [type: :integer]]

    def run(params, _context) do
      result = Map.get(params, :x, 0) + Map.get(params, :y, 0)
      {:ok, %{sum: result}}
    end
  end

  defmodule TestMultiplyAction do
    use Jido.Action,
      name: "test_multiply",
      schema: [value: [type: :integer]]

    def run(params, _context) do
      result = Map.get(params, :value, 1) * 2
      {:ok, %{product: result}}
    end
  end

  defmodule TestValidateAction do
    use Jido.Action,
      name: "test_validate",
      schema: [data: [type: :string]]

    def run(params, _context) do
      {:ok, %{validated: true, data: params.data}}
    end
  end

  defmodule TestProcessAction do
    use Jido.Action,
      name: "test_process",
      schema: [operation: [type: :atom]]

    def run(params, _context) do
      {:ok, %{processed: true, operation: params.operation}}
    end
  end

  defmodule TestSaveAction do
    use Jido.Action,
      name: "test_save",
      schema: [destination: [type: :string]]

    def run(params, _context) do
      {:ok, %{saved: true, destination: params.destination}}
    end
  end

  defmodule ContextAwareAction do
    use Jido.Action,
      name: "context_aware",
      schema: [value: [type: :integer]]

    alias Jido.AI.Runner.ChainOfThought.ExecutionContext

    def run(params, context) do
      has_reasoning = ExecutionContext.has_reasoning_context?(context)

      result = %{
        value: params.value,
        has_reasoning_context: has_reasoning
      }

      if has_reasoning do
        case ExecutionContext.get_current_step(context) do
          {:ok, step} ->
            {:ok, Map.put(result, :step_description, step.description)}

          _ ->
            {:ok, result}
        end
      else
        {:ok, result}
      end
    end
  end

  defmodule FailingAction do
    use Jido.Action,
      name: "failing_action",
      schema: [should_fail: [type: :boolean]]

    def run(params, _context) do
      if params.should_fail do
        {:error, "Intentional failure for testing"}
      else
        {:ok, %{success: true}}
      end
    end
  end

  defmodule RandomOutcomeAction do
    use Jido.Action,
      name: "random_outcome",
      schema: [seed: [type: :integer]]

    def run(params, _context) do
      :rand.seed(:exsplus, {params.seed, params.seed, params.seed})
      random_value = :rand.uniform(100)

      {:ok, %{value: random_value, random: true}}
    end
  end

  defmodule PredictableAction do
    use Jido.Action,
      name: "predictable",
      schema: [value: [type: :integer]]

    def run(params, _context) do
      {:ok, %{result: params.value * 2, predictable: true}}
    end
  end
end
