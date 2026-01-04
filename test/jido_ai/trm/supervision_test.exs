defmodule Jido.AI.TRM.SupervisionTest do
  use ExUnit.Case, async: true

  alias Jido.AI.TRM.Supervision

  describe "build_supervision_prompt/1" do
    test "returns system and user prompts" do
      context = %{
        question: "What is machine learning?",
        answer: "ML is a type of AI",
        step: 1,
        previous_feedback: nil
      }

      {system, user} = Supervision.build_supervision_prompt(context)

      assert is_binary(system)
      assert is_binary(user)
    end

    test "includes question and answer in user prompt" do
      context = %{
        question: "What is 2+2?",
        answer: "The answer is 4",
        step: 1,
        previous_feedback: nil
      }

      {_system, user} = Supervision.build_supervision_prompt(context)

      assert user =~ "What is 2+2?"
      assert user =~ "The answer is 4"
    end

    test "includes step number" do
      context = %{
        question: "Test",
        answer: "Answer",
        step: 3,
        previous_feedback: nil
      }

      {_system, user} = Supervision.build_supervision_prompt(context)

      assert user =~ "3"
    end

    test "includes previous feedback when provided" do
      previous = %{
        issues: ["Missing explanation"],
        suggestions: ["Add more detail"],
        strengths: [],
        quality_score: 0.5,
        raw_text: ""
      }

      context = %{
        question: "Test",
        answer: "Answer",
        step: 2,
        previous_feedback: previous
      }

      {_system, user} = Supervision.build_supervision_prompt(context)

      assert user =~ "Previous Feedback"
      assert user =~ "Missing explanation"
      assert user =~ "Add more detail"
      assert user =~ "0.5"
    end

    test "system prompt includes quality criteria" do
      context = %{question: "Test", answer: "Answer", step: 1, previous_feedback: nil}
      {system, _user} = Supervision.build_supervision_prompt(context)

      assert system =~ "Accuracy"
      assert system =~ "Completeness"
      assert system =~ "Clarity"
      assert system =~ "Relevance"
    end

    test "system prompt includes format markers" do
      context = %{question: "Test", answer: "Answer", step: 1, previous_feedback: nil}
      {system, _user} = Supervision.build_supervision_prompt(context)

      assert system =~ "STRENGTH"
      assert system =~ "ISSUE"
      assert system =~ "SUGGESTION"
      assert system =~ "SCORE"
    end
  end

  describe "default_supervision_system_prompt/0" do
    test "returns non-empty prompt" do
      prompt = Supervision.default_supervision_system_prompt()

      assert is_binary(prompt)
      assert String.length(prompt) > 100
    end

    test "includes evaluation instructions" do
      prompt = Supervision.default_supervision_system_prompt()

      assert prompt =~ "critical evaluator"
      assert prompt =~ "evaluate"
    end
  end

  describe "format_quality_criteria/0" do
    test "includes all dimensions" do
      criteria = Supervision.format_quality_criteria()

      assert criteria =~ "Accuracy"
      assert criteria =~ "Completeness"
      assert criteria =~ "Clarity"
      assert criteria =~ "Relevance"
    end
  end

  describe "include_previous_feedback/2" do
    test "returns base prompt unchanged when feedback is nil" do
      base = "Base prompt"
      result = Supervision.include_previous_feedback(base, nil)

      assert result == base
    end

    test "appends feedback context when provided" do
      base = "Base prompt"

      feedback = %{
        issues: ["Issue 1", "Issue 2"],
        suggestions: ["Suggestion 1"],
        strengths: [],
        quality_score: 0.6,
        raw_text: ""
      }

      result = Supervision.include_previous_feedback(base, feedback)

      assert result =~ base
      assert result =~ "Previous Feedback"
      assert result =~ "Issue 1"
      assert result =~ "Issue 2"
      assert result =~ "Suggestion 1"
      assert result =~ "0.6"
    end
  end

  describe "parse_supervision_result/1" do
    test "extracts issues from formatted response" do
      response = """
      ISSUE: The answer is incomplete
      ISSUE: Missing key concept
      STRENGTH: Good structure
      """

      feedback = Supervision.parse_supervision_result(response)

      assert length(feedback.issues) == 2
      assert "The answer is incomplete" in feedback.issues
      assert "Missing key concept" in feedback.issues
    end

    test "extracts suggestions from formatted response" do
      response = """
      SUGGESTION: Add more examples
      RECOMMENDATION: Clarify the definition
      """

      feedback = Supervision.parse_supervision_result(response)

      assert length(feedback.suggestions) >= 1
      assert Enum.any?(feedback.suggestions, &(&1 =~ "Add more examples"))
    end

    test "extracts strengths from formatted response" do
      response = """
      STRENGTH: Clear explanation
      CORRECT: The formula is right
      """

      feedback = Supervision.parse_supervision_result(response)

      assert length(feedback.strengths) >= 1
    end

    test "extracts explicit score" do
      response = """
      ISSUE: Minor issue
      SCORE: 0.75
      """

      feedback = Supervision.parse_supervision_result(response)

      assert feedback.quality_score == 0.75
    end

    test "calculates heuristic score when no explicit score" do
      response = """
      STRENGTH: Good
      STRENGTH: Very good
      ISSUE: Minor issue
      """

      feedback = Supervision.parse_supervision_result(response)

      # More strengths than issues should give higher score
      assert feedback.quality_score > 0.5
    end

    test "preserves raw text" do
      response = "Some response text"
      feedback = Supervision.parse_supervision_result(response)

      assert feedback.raw_text == response
    end

    test "handles non-string input" do
      feedback = Supervision.parse_supervision_result(nil)

      assert feedback.issues == []
      assert feedback.suggestions == []
      assert feedback.strengths == []
      assert feedback.quality_score == 0.5
    end

    test "handles case-insensitive markers" do
      response = """
      issue: lowercase issue
      ISSUE: uppercase issue
      Issue: mixed case issue
      """

      feedback = Supervision.parse_supervision_result(response)

      assert length(feedback.issues) == 3
    end
  end

  describe "extract_issues/1" do
    test "extracts issue markers" do
      response = "ISSUE: Problem found\nPROBLEM: Another problem"
      issues = Supervision.extract_issues(response)

      assert length(issues) >= 1
    end

    test "handles empty response" do
      assert Supervision.extract_issues("") == []
    end

    test "handles nil" do
      assert Supervision.extract_issues(nil) == []
    end
  end

  describe "extract_suggestions/1" do
    test "extracts suggestion markers" do
      response = "SUGGESTION: Add detail\nRECOMMEND: Improve clarity"
      suggestions = Supervision.extract_suggestions(response)

      assert length(suggestions) >= 1
    end

    test "handles empty response" do
      assert Supervision.extract_suggestions("") == []
    end
  end

  describe "extract_strengths/1" do
    test "extracts strength markers" do
      response = "STRENGTH: Well organized\nCORRECT: Formula is right"
      strengths = Supervision.extract_strengths(response)

      assert length(strengths) >= 1
    end

    test "handles empty response" do
      assert Supervision.extract_strengths("") == []
    end
  end

  describe "calculate_quality_score/1" do
    test "extracts explicit score" do
      response = "SCORE: 0.8"
      assert Supervision.calculate_quality_score(response) == 0.8
    end

    test "clamps score to valid range" do
      response = "SCORE: 1.5"
      assert Supervision.calculate_quality_score(response) == 1.0
    end

    test "returns heuristic for unstructured response" do
      response = "Some unstructured feedback"
      score = Supervision.calculate_quality_score(response)

      assert is_float(score)
      assert score >= 0.0
      assert score <= 1.0
    end

    test "returns default for non-string" do
      assert Supervision.calculate_quality_score(nil) == 0.5
    end
  end

  describe "build_improvement_prompt/3" do
    test "returns system and user prompts" do
      feedback = %{
        issues: ["Missing detail"],
        suggestions: ["Add examples"],
        strengths: ["Good structure"],
        quality_score: 0.6,
        raw_text: ""
      }

      {system, user} = Supervision.build_improvement_prompt(
        "What is AI?",
        "AI is artificial intelligence",
        feedback
      )

      assert is_binary(system)
      assert is_binary(user)
    end

    test "includes question and answer" do
      feedback = %{
        issues: [],
        suggestions: [],
        strengths: [],
        quality_score: 0.7,
        raw_text: ""
      }

      {_system, user} = Supervision.build_improvement_prompt(
        "What is 2+2?",
        "The answer is 4",
        feedback
      )

      assert user =~ "What is 2+2?"
      assert user =~ "The answer is 4"
    end

    test "includes issues to address" do
      feedback = %{
        issues: ["Missing explanation", "Incorrect formula"],
        suggestions: [],
        strengths: [],
        quality_score: 0.4,
        raw_text: ""
      }

      {_system, user} = Supervision.build_improvement_prompt("Q", "A", feedback)

      assert user =~ "Missing explanation"
      assert user =~ "Incorrect formula"
    end

    test "includes prioritized suggestions" do
      feedback = %{
        issues: [],
        suggestions: ["Add critical information", "Minor tweak"],
        strengths: [],
        quality_score: 0.6,
        raw_text: ""
      }

      {_system, user} = Supervision.build_improvement_prompt("Q", "A", feedback)

      assert user =~ "critical information"
    end

    test "includes strengths to preserve" do
      feedback = %{
        issues: [],
        suggestions: [],
        strengths: ["Clear explanation", "Good examples"],
        quality_score: 0.8,
        raw_text: ""
      }

      {_system, user} = Supervision.build_improvement_prompt("Q", "A", feedback)

      assert user =~ "Clear explanation"
      assert user =~ "Good examples"
    end

    test "includes quality score" do
      feedback = %{
        issues: [],
        suggestions: [],
        strengths: [],
        quality_score: 0.65,
        raw_text: ""
      }

      {_system, user} = Supervision.build_improvement_prompt("Q", "A", feedback)

      assert user =~ "0.65"
    end
  end

  describe "default_improvement_system_prompt/0" do
    test "returns non-empty prompt" do
      prompt = Supervision.default_improvement_system_prompt()

      assert is_binary(prompt)
      assert String.length(prompt) > 50
    end

    test "includes improvement instructions" do
      prompt = Supervision.default_improvement_system_prompt()

      assert prompt =~ "improve"
      assert prompt =~ "Address"
    end
  end

  describe "prioritize_suggestions/1" do
    test "returns prioritized suggestions" do
      suggestions = ["Add critical information", "Minor fix"]
      prioritized = Supervision.prioritize_suggestions(suggestions)

      assert length(prioritized) == 2
      assert Enum.all?(prioritized, &is_map/1)
    end

    test "assigns impact levels" do
      suggestions = [
        "This is essential for understanding",
        "Minor improvement"
      ]

      prioritized = Supervision.prioritize_suggestions(suggestions)

      # First should be high impact due to "essential"
      high_impact = Enum.find(prioritized, &(&1.impact == :high))
      assert high_impact != nil
      assert high_impact.content =~ "essential"
    end

    test "assigns categories" do
      suggestions = [
        "Improve accuracy of the calculation",
        "Add missing information for completeness",
        "Clarify the explanation"
      ]

      prioritized = Supervision.prioritize_suggestions(suggestions)

      categories = Enum.map(prioritized, & &1.category)
      assert :accuracy in categories or :completeness in categories or :clarity in categories
    end

    test "sorts by impact (high first)" do
      suggestions = [
        "Minor tweak",
        "Critical fundamental change needed",
        "Medium importance fix"
      ]

      prioritized = Supervision.prioritize_suggestions(suggestions)

      # High impact should come first
      first = hd(prioritized)
      assert first.impact == :high or first.content =~ "Critical"
    end

    test "handles empty list" do
      assert Supervision.prioritize_suggestions([]) == []
    end

    test "handles non-list input" do
      assert Supervision.prioritize_suggestions(nil) == []
    end
  end

  describe "integration scenarios" do
    test "full supervision cycle" do
      # Build supervision prompt
      context = %{
        question: "What is photosynthesis?",
        answer: "Plants make food from sunlight",
        step: 1,
        previous_feedback: nil
      }

      {system, user} = Supervision.build_supervision_prompt(context)
      assert system =~ "evaluator"
      assert user =~ "photosynthesis"

      # Simulate LLM response
      llm_response = """
      **STRENGTHS**:
      STRENGTH: Correctly identifies sunlight as a key component

      **ISSUES**:
      ISSUE: Missing explanation of chlorophyll
      ISSUE: Does not mention CO2 and water as inputs

      **SUGGESTIONS**:
      SUGGESTION: Add essential details about chlorophyll's role
      SUGGESTION: Include the complete chemical equation

      **SCORE**: 0.55
      """

      # Parse feedback
      feedback = Supervision.parse_supervision_result(llm_response)

      assert length(feedback.strengths) >= 1
      assert length(feedback.issues) >= 2
      assert length(feedback.suggestions) >= 2
      assert feedback.quality_score == 0.55

      # Build improvement prompt
      {imp_system, imp_user} = Supervision.build_improvement_prompt(
        context.question,
        context.answer,
        feedback
      )

      assert imp_system =~ "improve"
      assert imp_user =~ "chlorophyll"
      assert imp_user =~ "essential"
    end

    test "iterative supervision with previous feedback" do
      # First round feedback
      first_feedback = %{
        issues: ["Missing explanation"],
        suggestions: ["Add more detail"],
        strengths: ["Good start"],
        quality_score: 0.5,
        raw_text: ""
      }

      # Second round context includes previous feedback
      context = %{
        question: "What is gravity?",
        answer: "Gravity is a force that attracts objects. It depends on mass and distance.",
        step: 2,
        previous_feedback: first_feedback
      }

      {_system, user} = Supervision.build_supervision_prompt(context)

      # Should include previous feedback context
      assert user =~ "Previous Feedback"
      assert user =~ "Missing explanation"
      assert user =~ "Add more detail"
    end
  end
end
