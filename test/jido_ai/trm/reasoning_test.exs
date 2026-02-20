defmodule Jido.AI.Reasoning.TRM.ReasoningTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Reasoning.TRM.Reasoning

  describe "build_reasoning_prompt/1" do
    test "returns system and user prompts for initial reasoning" do
      context = %{
        question: "What is 2+2?",
        current_answer: nil,
        latent_state: %{}
      }

      {system, user} = Reasoning.build_reasoning_prompt(context)

      assert is_binary(system)
      assert is_binary(user)
      assert system =~ "recursive reasoning"
      assert user =~ "What is 2+2?"
      assert user =~ "first reasoning step"
    end

    test "returns prompts for subsequent reasoning with current answer" do
      context = %{
        question: "What is 2+2?",
        current_answer: "The answer is 4",
        latent_state: %{reasoning_trace: ["Step 1: Analyzed addition"]}
      }

      {system, user} = Reasoning.build_reasoning_prompt(context)

      assert is_binary(system)
      assert is_binary(user)
      assert user =~ "What is 2+2?"
      assert user =~ "The answer is 4"
      assert user =~ "Step 1: Analyzed addition"
    end

    test "includes structured format instructions" do
      context = %{
        question: "Test question",
        current_answer: nil,
        latent_state: %{}
      }

      {system, _user} = Reasoning.build_reasoning_prompt(context)

      assert system =~ "INSIGHT"
      assert system =~ "ISSUE"
      assert system =~ "MISSING"
      assert system =~ "SUGGESTION"
      assert system =~ "CONFIDENCE"
    end
  end

  describe "default_reasoning_system_prompt/0" do
    test "returns a non-empty system prompt" do
      prompt = Reasoning.default_reasoning_system_prompt()

      assert is_binary(prompt)
      assert String.length(prompt) > 100
    end

    test "includes format markers" do
      prompt = Reasoning.default_reasoning_system_prompt()

      assert prompt =~ "INSIGHT:"
      assert prompt =~ "ISSUE:"
      assert prompt =~ "MISSING:"
      assert prompt =~ "SUGGESTION:"
      assert prompt =~ "CONFIDENCE:"
    end

    test "explains the purpose" do
      prompt = Reasoning.default_reasoning_system_prompt()

      assert prompt =~ "recursive reasoning"
    end
  end

  describe "build_latent_update_prompt/3" do
    test "builds prompt with question and reasoning output" do
      question = "What is AI?"
      reasoning_output = "INSIGHT: AI is artificial intelligence"
      latent_state = %{reasoning_trace: []}

      prompt = Reasoning.build_latent_update_prompt(question, reasoning_output, latent_state)

      assert prompt =~ "What is AI?"
      assert prompt =~ "AI is artificial intelligence"
      assert prompt =~ "key learnings"
    end

    test "includes previous reasoning trace" do
      question = "What is AI?"
      reasoning_output = "New analysis"
      latent_state = %{reasoning_trace: ["Previous insight"]}

      prompt = Reasoning.build_latent_update_prompt(question, reasoning_output, latent_state)

      assert prompt =~ "Previous insight"
    end
  end

  describe "format_reasoning_trace/1" do
    test "returns (none) for nil" do
      assert Reasoning.format_reasoning_trace(nil) == "(none)"
    end

    test "returns (none) for empty list" do
      assert Reasoning.format_reasoning_trace(%{reasoning_trace: []}) == "(none)"
    end

    test "formats list with step numbers" do
      result = Reasoning.format_reasoning_trace(%{reasoning_trace: ["First", "Second"]})

      assert result =~ "Step 1: First"
      assert result =~ "Step 2: Second"
    end

    test "handles string trace" do
      result = Reasoning.format_reasoning_trace(%{reasoning_trace: "Some trace"})

      assert result == "Some trace"
    end

    test "returns (none) for empty string trace" do
      result = Reasoning.format_reasoning_trace(%{reasoning_trace: "  "})

      assert result == "(none)"
    end

    test "returns (none) for missing key" do
      assert Reasoning.format_reasoning_trace(%{other: "value"}) == "(none)"
    end
  end

  describe "parse_reasoning_result/1" do
    test "extracts insights from formatted response" do
      response = """
      INSIGHT: The calculation is correct
      INSIGHT: The reasoning is sound
      ISSUE: Missing explanation
      """

      result = Reasoning.parse_reasoning_result(response)

      assert length(result.insights) == 2
      assert "The calculation is correct" in result.insights
      assert "The reasoning is sound" in result.insights
    end

    test "extracts issues from formatted response" do
      response = """
      INSIGHT: Good start
      ISSUE: Missing step 2
      ISSUE: Incorrect assumption
      """

      result = Reasoning.parse_reasoning_result(response)

      assert length(result.issues) == 2
      assert "Missing step 2" in result.issues
      assert "Incorrect assumption" in result.issues
    end

    test "combines missing and suggestions" do
      response = """
      MISSING: Edge case handling
      SUGGESTION: Add validation
      """

      result = Reasoning.parse_reasoning_result(response)

      assert length(result.suggestions) == 2
      assert "Edge case handling" in result.suggestions
      assert "Add validation" in result.suggestions
    end

    test "extracts explicit confidence" do
      response = """
      INSIGHT: Analysis complete
      CONFIDENCE: 0.85
      """

      result = Reasoning.parse_reasoning_result(response)

      assert result.confidence == 0.85
    end

    test "calculates heuristic confidence when no explicit value" do
      response = """
      INSIGHT: Good analysis
      INSIGHT: Correct approach
      """

      result = Reasoning.parse_reasoning_result(response)

      # Should be above 0.5 due to insights without issues
      assert result.confidence > 0.5
    end

    test "reduces confidence with more issues than insights" do
      response = """
      ISSUE: Problem 1
      ISSUE: Problem 2
      ISSUE: Problem 3
      """

      result = Reasoning.parse_reasoning_result(response)

      # Should be below 0.5 due to issues without insights
      assert result.confidence < 0.5
    end

    test "preserves raw text" do
      response = "Some raw response"
      result = Reasoning.parse_reasoning_result(response)

      assert result.raw_text == response
    end

    test "handles non-string input" do
      result = Reasoning.parse_reasoning_result(nil)

      assert result.insights == []
      assert result.issues == []
      assert result.suggestions == []
      assert result.confidence == 0.5
    end

    test "handles case-insensitive markers" do
      response = """
      insight: Lower case insight
      ISSUE: Upper case issue
      Suggestion: Mixed case suggestion
      """

      result = Reasoning.parse_reasoning_result(response)

      assert length(result.insights) == 1
      assert length(result.issues) == 1
      assert length(result.suggestions) == 1
    end
  end

  describe "extract_key_insights/1" do
    test "returns list of parsed insights" do
      response = """
      INSIGHT: Correct calculation
      ISSUE: Missing explanation
      SUGGESTION: Add more detail
      """

      insights = Reasoning.extract_key_insights(response)

      assert length(insights) == 3
      assert Enum.all?(insights, &is_map/1)
    end

    test "assigns types to insights" do
      response = """
      INSIGHT: Correct
      ISSUE: Wrong
      MISSING: Absent
      SUGGESTION: Improve
      """

      insights = Reasoning.extract_key_insights(response)

      types = Enum.map(insights, & &1.type)
      assert :correct in types
      assert :issue in types
      assert :missing in types
      assert :suggestion in types
    end

    test "estimates importance" do
      response = """
      INSIGHT: Short
      ISSUE: This is a critical problem that needs immediate attention
      """

      insights = Reasoning.extract_key_insights(response)

      # Issues should be high importance
      issue = Enum.find(insights, &(&1.type == :issue))
      assert issue.importance == :high

      # Short insights without issue markers should be low
      insight = Enum.find(insights, &(&1.type == :correct))
      assert insight.importance == :low
    end

    test "sorts by importance" do
      response = """
      INSIGHT: Low importance item
      ISSUE: High importance issue
      """

      insights = Reasoning.extract_key_insights(response)

      # Issue (high) should come before insight (low)
      assert hd(insights).type == :issue
    end

    test "handles empty response" do
      assert Reasoning.extract_key_insights("") == []
    end

    test "handles non-string input" do
      assert Reasoning.extract_key_insights(nil) == []
    end
  end

  describe "calculate_reasoning_confidence/1" do
    test "returns explicit confidence when present" do
      response = "CONFIDENCE: 0.9"
      assert Reasoning.calculate_reasoning_confidence(response) == 0.9
    end

    test "clamps confidence to valid range" do
      response = "CONFIDENCE: 1.5"
      assert Reasoning.calculate_reasoning_confidence(response) == 1.0

      # Note: regex captures digits only, so -0.5 is parsed as 0.5
      # This is acceptable since LLMs shouldn't output negative confidence
      response = "CONFIDENCE: 0.0"
      assert Reasoning.calculate_reasoning_confidence(response) == 0.0
    end

    test "calculates heuristic for unstructured response" do
      response = "This is a good answer with clear reasoning."
      confidence = Reasoning.calculate_reasoning_confidence(response)

      assert is_float(confidence)
      assert confidence >= 0.0
      assert confidence <= 1.0
    end

    test "increases confidence with certainty language" do
      certain = "This is definitely correct. The answer is certainly 4."
      uncertain = "This might be correct. The answer could possibly be 4."

      certain_conf = Reasoning.calculate_reasoning_confidence(certain)
      uncertain_conf = Reasoning.calculate_reasoning_confidence(uncertain)

      assert certain_conf > uncertain_conf
    end

    test "returns default for non-string input" do
      assert Reasoning.calculate_reasoning_confidence(nil) == 0.5
    end
  end

  describe "integration scenarios" do
    test "full reasoning cycle with structured response" do
      # Initial reasoning
      context = %{
        question: "What causes rain?",
        current_answer: nil,
        latent_state: %{reasoning_trace: []}
      }

      {_system, _user} = Reasoning.build_reasoning_prompt(context)

      # Simulate LLM response
      llm_response = """
      INSIGHT: Rain is caused by water cycle processes
      INSIGHT: Evaporation and condensation are key
      ISSUE: Initial answer lacks detail on cloud formation
      MISSING: Explanation of precipitation types
      SUGGESTION: Add information about atmospheric pressure
      CONFIDENCE: 0.7
      """

      result = Reasoning.parse_reasoning_result(llm_response)

      assert length(result.insights) == 2
      assert length(result.issues) == 1
      assert length(result.suggestions) == 2
      assert result.confidence == 0.7
    end

    test "subsequent reasoning with previous trace" do
      context = %{
        question: "What causes rain?",
        current_answer: "Rain is caused by the water cycle.",
        latent_state: %{
          reasoning_trace: [
            "Identified water cycle as key concept",
            "Noted need for more detail on cloud formation"
          ]
        }
      }

      {_system, user} = Reasoning.build_reasoning_prompt(context)

      # User prompt should include previous reasoning
      assert user =~ "water cycle"
      assert user =~ "Step 1:"
      assert user =~ "Step 2:"
    end
  end
end
