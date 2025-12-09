defmodule Jido.AI.Runner.GEPA.Evaluation.Strategies.ReasoningEvaluatorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Evaluation.Strategies.ReasoningEvaluator
  alias Jido.AI.Runner.GEPA.Evaluator

  describe "evaluate_prompt/2" do
    test "evaluates reasoning with correct answer and steps" do
      # Mock a successful evaluation with reasoning
      response = """
      Let me solve this step by step:
      1. First, convert 15% to decimal: 0.15
      2. Then multiply: 0.15 × 80 = 12
      Therefore, 12
      """

      task = %{
        type: :reasoning,
        expected_answer: "12",
        answer_type: :numeric,
        requires_steps: true
      }

      # We need to test with mocked Evaluator.evaluate_prompt
      # For now, test the internal evaluation logic directly
      metrics = ReasoningEvaluator.evaluate_reasoning(response, task)

      assert metrics.answer_correctness == 1.0
      assert metrics.reasoning_steps_present == true
      assert metrics.explanation_clarity > 0.5
      assert metrics.answer_format_valid == true
      assert metrics.extracted_answer == "12"
    end

    test "evaluates reasoning with missing steps" do
      response = "The answer is 12"

      task = %{
        type: :reasoning,
        expected_answer: "12",
        answer_type: :numeric
      }

      metrics = ReasoningEvaluator.evaluate_reasoning(response, task)

      assert metrics.answer_correctness == 1.0
      assert metrics.reasoning_steps_present == false
      assert metrics.explanation_clarity < 0.5
    end

    test "evaluates reasoning with incorrect answer" do
      response = """
      Step 1: 15% = 0.15
      Step 2: 0.15 × 80 = 10
      Answer: 10
      """

      task = %{
        type: :reasoning,
        expected_answer: "12",
        answer_type: :numeric
      }

      metrics = ReasoningEvaluator.evaluate_reasoning(response, task)

      assert metrics.answer_correctness == 0.0
      assert metrics.reasoning_steps_present == true
      assert metrics.extracted_answer == "10"
    end

    test "handles boolean reasoning tasks" do
      response = """
      Let's analyze this logically:
      1. All mammals are warm-blooded
      2. Whales are mammals
      Therefore, True
      """

      task = %{
        type: :reasoning,
        expected_answer: "true",
        answer_type: :boolean
      }

      metrics = ReasoningEvaluator.evaluate_reasoning(response, task)

      assert metrics.answer_correctness == 1.0
      assert metrics.answer_format_valid == true
    end
  end

  describe "extract_answer/1" do
    test "extracts answer from 'Answer:' pattern" do
      response = "Step 1: ...\nAnswer: 42"
      answer = ReasoningEvaluator.extract_answer(response)
      assert answer == "42"
    end

    test "extracts answer from 'Therefore' pattern" do
      response = "Step 1: ...\nTherefore, 42"
      answer = ReasoningEvaluator.extract_answer(response)
      assert answer == "42"
    end

    test "extracts numeric answer from end of response" do
      response = "The calculation gives us 42"
      answer = ReasoningEvaluator.extract_answer(response)
      assert answer == "42"
    end

    test "extracts boolean answer" do
      response = "After analysis, the answer is Yes"
      answer = ReasoningEvaluator.extract_answer(response)
      assert String.downcase(answer) == "yes"
    end

    test "returns full response if no pattern matches" do
      response = "complicated answer without clear markers"
      answer = ReasoningEvaluator.extract_answer(response)
      assert answer == response
    end
  end

  describe "check_answer_correctness/2" do
    test "returns 1.0 for exact match" do
      assert ReasoningEvaluator.check_answer_correctness("42", "42") == 1.0
    end

    test "returns 1.0 for case-insensitive match" do
      assert ReasoningEvaluator.check_answer_correctness("Yes", "yes") == 1.0
    end

    test "returns 0.7 for partial match" do
      correctness = ReasoningEvaluator.check_answer_correctness("The answer is 42", "42")
      assert correctness == 0.7
    end

    test "returns 1.0 for numerically similar answers" do
      correctness = ReasoningEvaluator.check_answer_correctness("12", "12.0")
      assert correctness == 1.0
    end

    test "returns 0.0 for wrong answer" do
      assert ReasoningEvaluator.check_answer_correctness("42", "24") == 0.0
    end

    test "returns 0.5 when expected answer is nil" do
      assert ReasoningEvaluator.check_answer_correctness("42", nil) == 0.5
    end
  end

  describe "has_reasoning_steps?/1" do
    test "detects numbered steps" do
      response = "1) First step\n2) Second step"
      assert ReasoningEvaluator.has_reasoning_steps?(response) == true
    end

    test "detects step keywords" do
      response = "First, we do this. Then, we do that. Finally, we conclude."
      assert ReasoningEvaluator.has_reasoning_steps?(response) == true
    end

    test "detects 'Step N' pattern" do
      response = "Step 1: Initialize. Step 2: Process."
      assert ReasoningEvaluator.has_reasoning_steps?(response) == true
    end

    test "detects multiple sentences" do
      response = "This is the first sentence. This is the second sentence."
      assert ReasoningEvaluator.has_reasoning_steps?(response) == true
    end

    test "returns false for single-line response" do
      response = "just the answer"
      assert ReasoningEvaluator.has_reasoning_steps?(response) == false
    end
  end

  describe "assess_clarity/1" do
    test "gives high score for well-structured response" do
      response = """
      Because the problem requires finding 15% of 80, we first convert the percentage.
      Therefore, 0.15 × 80 gives us the result. Thus, the answer is 12.
      """

      clarity = ReasoningEvaluator.assess_clarity(response)
      assert clarity > 0.7
    end

    test "gives low score for very short response" do
      response = "12"
      clarity = ReasoningEvaluator.assess_clarity(response)
      assert clarity < 0.5
    end

    test "gives medium score for response without connectors" do
      response =
        "The first step is conversion. The second step is multiplication. The final result is 12."

      clarity = ReasoningEvaluator.assess_clarity(response)
      assert clarity >= 0.3 && clarity <= 0.7
    end
  end

  describe "validate_answer_format/2" do
    test "validates numeric answers" do
      assert ReasoningEvaluator.validate_answer_format("42", :numeric) == true
      assert ReasoningEvaluator.validate_answer_format("42.5", :numeric) == true
      assert ReasoningEvaluator.validate_answer_format("not a number", :numeric) == false
    end

    test "validates boolean answers" do
      assert ReasoningEvaluator.validate_answer_format("true", :boolean) == true
      assert ReasoningEvaluator.validate_answer_format("false", :boolean) == true
      assert ReasoningEvaluator.validate_answer_format("yes", :boolean) == true
      assert ReasoningEvaluator.validate_answer_format("no", :boolean) == true
      assert ReasoningEvaluator.validate_answer_format("maybe", :boolean) == false
    end

    test "validates text answers" do
      assert ReasoningEvaluator.validate_answer_format("some text", :text) == true
      assert ReasoningEvaluator.validate_answer_format("", :text) == false
      assert ReasoningEvaluator.validate_answer_format("   ", :text) == false
    end

    test "returns true when type is nil" do
      assert ReasoningEvaluator.validate_answer_format("anything", nil) == true
    end
  end

  describe "calculate_reasoning_fitness/2" do
    test "calculates fitness with perfect scores" do
      metrics = %{
        answer_correctness: 1.0,
        reasoning_steps_present: true,
        explanation_clarity: 1.0
      }

      fitness = ReasoningEvaluator.calculate_reasoning_fitness(0.8, metrics)

      # Should be: 0.6*1.0 + 0.25*1.0 + 0.15*1.0 = 1.0
      assert fitness == 1.0
    end

    test "calculates fitness with correct answer but no steps" do
      metrics = %{
        answer_correctness: 1.0,
        reasoning_steps_present: false,
        explanation_clarity: 0.5
      }

      fitness = ReasoningEvaluator.calculate_reasoning_fitness(0.8, metrics)

      # Should be: 0.6*1.0 + 0.25*0.0 + 0.15*0.5 = 0.675
      assert_in_delta fitness, 0.675, 0.01
    end

    test "calculates fitness with wrong answer but good reasoning" do
      metrics = %{
        answer_correctness: 0.0,
        reasoning_steps_present: true,
        explanation_clarity: 0.8
      }

      fitness = ReasoningEvaluator.calculate_reasoning_fitness(0.8, metrics)

      # Should be: 0.6*0.0 + 0.25*1.0 + 0.15*0.8 = 0.37
      assert_in_delta fitness, 0.37, 0.01
    end

    test "prioritizes correctness over other factors" do
      perfect_metrics = %{
        answer_correctness: 1.0,
        reasoning_steps_present: false,
        explanation_clarity: 0.0
      }

      poor_metrics = %{
        answer_correctness: 0.0,
        reasoning_steps_present: true,
        explanation_clarity: 1.0
      }

      perfect_fitness = ReasoningEvaluator.calculate_reasoning_fitness(0.5, perfect_metrics)
      poor_fitness = ReasoningEvaluator.calculate_reasoning_fitness(0.5, poor_metrics)

      # Correct answer (0.6) should score higher than perfect steps+clarity (0.4)
      assert perfect_fitness > poor_fitness
    end
  end

  describe "numeric_similarity/2" do
    test "returns 1.0 for identical numbers" do
      assert ReasoningEvaluator.numeric_similarity("42", "42") == 1.0
    end

    test "returns 1.0 for very close numbers" do
      similarity = ReasoningEvaluator.numeric_similarity("42.0", "42.001")
      assert similarity > 0.99
    end

    test "returns 0.0 for very different numbers" do
      similarity = ReasoningEvaluator.numeric_similarity("100", "1")
      assert similarity == 0.0
    end

    test "returns 0.0 for non-numeric strings" do
      assert ReasoningEvaluator.numeric_similarity("abc", "def") == 0.0
    end

    test "handles division by zero" do
      assert ReasoningEvaluator.numeric_similarity("0", "0") == 1.0
      assert ReasoningEvaluator.numeric_similarity("5", "0") == 0.0
    end
  end

  describe "normalize_answer/1" do
    test "normalizes to lowercase" do
      assert ReasoningEvaluator.normalize_answer("YES") == "yes"
    end

    test "removes whitespace" do
      assert ReasoningEvaluator.normalize_answer("  42  ") == "42"
    end

    test "removes special characters except dots" do
      assert ReasoningEvaluator.normalize_answer("$42.50!") == "42.50"
    end

    test "handles complex strings" do
      normalized = ReasoningEvaluator.normalize_answer("  The Answer Is: 42! ")
      assert normalized == "theansweris42"
    end
  end
end
