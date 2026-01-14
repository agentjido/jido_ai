defmodule Jido.AI.Accuracy.UncertaintyQuantificationTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Candidate, UncertaintyQuantification, UncertaintyResult}

  @moduletag :capture_log

  describe "new/1" do
    test "creates with default patterns" do
      assert {:ok, uq} = UncertaintyQuantification.new(%{})

      assert is_list(uq.aleatoric_patterns)
      assert is_list(uq.epistemic_patterns)
      assert length(uq.aleatoric_patterns) > 0
      assert length(uq.epistemic_patterns) > 0
    end

    test "creates with custom patterns" do
      custom_patterns = [~r/custom/i]

      assert {:ok, uq} =
               UncertaintyQuantification.new(%{
                 aleatoric_patterns: custom_patterns
               })

      assert uq.aleatoric_patterns == custom_patterns
    end

    test "returns error for invalid patterns" do
      assert {:error, :invalid_patterns} =
               UncertaintyQuantification.new(%{
                 aleatoric_patterns: ["not a regex"]
               })
    end
  end

  describe "classify_uncertainty/2" do
    setup do
      uq = UncertaintyQuantification.new!(%{})
      {:ok, uq: uq}
    end

    test "classifies subjective question as aleatoric", context do
      query = "What's the best movie of all time?"

      assert {:ok, result} = UncertaintyQuantification.classify_uncertainty(context.uq, query)

      assert result.uncertainty_type == :aleatoric
      assert UncertaintyResult.aleatoric?(result)
    end

    test "classifies factual question as certain", context do
      query = "What is the capital of France?"

      assert {:ok, result} = UncertaintyQuantification.classify_uncertainty(context.uq, query)

      assert result.uncertainty_type == :none
      assert UncertaintyResult.certain?(result)
    end

    test "classifies future speculation as epistemic", context do
      query = "Who will be president in 2030?"

      assert {:ok, result} = UncertaintyQuantification.classify_uncertainty(context.uq, query)

      assert result.uncertainty_type == :epistemic
      assert UncertaintyResult.epistemic?(result)
    end

    test "classifies ambiguous question as aleatoric", context do
      query = "Maybe we should consider the options?"

      assert {:ok, result} = UncertaintyQuantification.classify_uncertainty(context.uq, query)

      assert result.uncertainty_type == :aleatoric
    end

    test "works with Candidate struct", context do
      candidate = Candidate.new!(%{content: "What's your favorite color?"})

      assert {:ok, result} = UncertaintyQuantification.classify_uncertainty(context.uq, candidate)

      assert result.uncertainty_type == :aleatoric
    end

    test "includes confidence score", context do
      query = "What's the best movie?"

      assert {:ok, result} = UncertaintyQuantification.classify_uncertainty(context.uq, query)

      assert is_number(result.confidence)
      assert result.confidence >= 0.0
      assert result.confidence <= 1.0
    end

    test "includes reasoning", context do
      query = "What's the best movie?"

      assert {:ok, result} = UncertaintyQuantification.classify_uncertainty(context.uq, query)

      assert is_binary(result.reasoning)
      assert String.length(result.reasoning) > 0
    end

    test "includes suggested action", context do
      query = "What's the best movie?"

      assert {:ok, result} = UncertaintyQuantification.classify_uncertainty(context.uq, query)

      assert is_atom(result.suggested_action)
    end
  end

  describe "detect_aleatoric/2" do
    setup do
      {:ok, uq: UncertaintyQuantification.new!(%{})}
    end

    test "detects subjective adjectives", context do
      score = UncertaintyQuantification.detect_aleatoric(context.uq, "What is the best option?")

      assert score > 0.3
    end

    test "detects ambiguity markers", context do
      score = UncertaintyQuantification.detect_aleatoric(context.uq, "Maybe we could try this?")

      assert score > 0.3
    end

    test "detects opinion words", context do
      score = UncertaintyQuantification.detect_aleatoric(context.uq, "What do you think about this?")

      assert score > 0.3
    end

    test "returns low score for factual queries", context do
      score = UncertaintyQuantification.detect_aleatoric(context.uq, "What is 2 plus 2?")

      assert score < 0.3
    end

    test "detects comparative language", context do
      score = UncertaintyQuantification.detect_aleatoric(context.uq, "Is this better than that?")

      assert score > 0.3
    end
  end

  describe "detect_epistemic/2" do
    setup do
      {:ok, uq: UncertaintyQuantification.new!(%{})}
    end

    test "detects future speculation", context do
      score = UncertaintyQuantification.detect_epistemic(context.uq, "What will happen tomorrow?")

      assert score > 0.3
    end

    test "detects prediction language", context do
      score = UncertaintyQuantification.detect_epistemic(context.uq, "Predict the election results")

      assert score > 0.3
    end

    test "returns low score for current factual", context do
      score = UncertaintyQuantification.detect_epistemic(context.uq, "What is the capital of France?")

      assert score < 0.3
    end
  end

  describe "recommend_action/2" do
    test "returns provide_options for aleatoric" do
      action = UncertaintyQuantification.recommend_action(:aleatoric, 0.8)

      assert action == :provide_options
    end

    test "returns abstain for high epistemic" do
      action = UncertaintyQuantification.recommend_action(:epistemic, 0.8)

      assert action == :abstain
    end

    test "returns suggest_source for low epistemic" do
      action = UncertaintyQuantification.recommend_action(:epistemic, 0.3)

      assert action == :suggest_source
    end

    test "returns answer_directly for certain" do
      action = UncertaintyQuantification.recommend_action(:none, 1.0)

      assert action == :answer_directly
    end
  end

  describe "classification examples" do
    setup do
      {:ok, uq: UncertaintyQuantification.new!(%{})}
    end

    test "best questions are aleatoric", context do
      queries = [
        "What's the best movie?",
        "Who is the greatest athlete?",
        "What's the worst programming language?"
      ]

      Enum.each(queries, fn query ->
        {:ok, result} = UncertaintyQuantification.classify_uncertainty(context.uq, query)
        assert result.uncertainty_type == :aleatoric, "#{query} should be aleatoric"
      end)
    end

    test "favorite questions are aleatoric", context do
      queries = [
        "What's your favorite color?",
        "Which food do you prefer?",
        "What kind of music do you like?"
      ]

      Enum.each(queries, fn query ->
        {:ok, result} = UncertaintyQuantification.classify_uncertainty(context.uq, query)
        assert result.uncertainty_type == :aleatoric, "#{query} should be aleatoric"
      end)
    end

    test "factual questions are certain", context do
      queries = [
        "What is the capital of France?",
        "Who wrote Romeo and Juliet?",
        "What is 2 plus 2?"
      ]

      Enum.each(queries, fn query ->
        {:ok, result} = UncertaintyQuantification.classify_uncertainty(context.uq, query)
        assert result.uncertainty_type == :none, "#{query} should be certain"
      end)
    end

    test "future questions are epistemic", context do
      queries = [
        "Who will win the World Cup?",
        "What will the stock market do tomorrow?",
        "Predict the weather next week"
      ]

      Enum.each(queries, fn query ->
        {:ok, result} = UncertaintyQuantification.classify_uncertainty(context.uq, query)
        assert result.uncertainty_type in [:epistemic, :aleatoric], "#{query} should have uncertainty"
      end)
    end
  end

  describe "custom patterns" do
    test "uses custom aleatoric patterns" do
      uq =
        UncertaintyQuantification.new!(%{
          aleatoric_patterns: [~r/\bspicier\s+\w+/i]
        })

      # "Spicier level" should match our custom pattern
      {:ok, result} = UncertaintyQuantification.classify_uncertainty(uq, "What is the spicier level?")

      assert UncertaintyResult.uncertain?(result)
    end

    test "uses custom epistemic patterns" do
      uq =
        UncertaintyQuantification.new!(%{
          epistemic_patterns: [~r/\bXYZ-123\b/i]
        })

      {:ok, result} = UncertaintyQuantification.classify_uncertainty(uq, "Tell me about XYZ-123")

      assert result.uncertainty_type in [:epistemic, :aleatoric]
    end
  end
end
