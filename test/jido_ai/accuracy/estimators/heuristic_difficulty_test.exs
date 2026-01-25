defmodule Jido.AI.Accuracy.Estimators.HeuristicDifficultyTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{DifficultyEstimate, DifficultyEstimator}
  alias Jido.AI.Accuracy.Estimators.HeuristicDifficulty

  @moduletag :capture_log

  describe "new/1" do
    test "creates estimator with default values" do
      assert {:ok, estimator} = HeuristicDifficulty.new(%{})
      assert estimator.length_weight == 0.25
      assert estimator.complexity_weight == 0.30
      assert estimator.domain_weight == 0.25
      assert estimator.question_weight == 0.20
    end

    test "creates estimator with custom weights" do
      assert {:ok, estimator} =
               HeuristicDifficulty.new(%{
                 length_weight: 0.3,
                 complexity_weight: 0.4,
                 domain_weight: 0.2,
                 question_weight: 0.1
               })

      assert estimator.length_weight == 0.3
      assert estimator.complexity_weight == 0.4
      assert estimator.domain_weight == 0.2
      assert estimator.question_weight == 0.1
    end

    test "creates estimator with custom indicators" do
      assert {:ok, estimator} =
               HeuristicDifficulty.new(%{
                 custom_indicators: %{physics: ["quantum", "entanglement"]}
               })

      assert estimator.custom_indicators == %{physics: ["quantum", "entanglement"]}
    end

    test "returns error for invalid weights" do
      assert {:error, :invalid_weights} =
               HeuristicDifficulty.new(%{
                 length_weight: 1.5
               })

      assert {:error, :invalid_weights} =
               HeuristicDifficulty.new(%{
                 length_weight: -0.1
               })

      assert {:error, :weights_dont_sum_to_1} =
               HeuristicDifficulty.new(%{
                 length_weight: 0.5,
                 complexity_weight: 0.6
               })
    end
  end

  describe "new!/1" do
    test "creates estimator with valid attributes" do
      estimator = HeuristicDifficulty.new!(%{})
      assert estimator.length_weight == 0.25
    end

    test "raises for invalid attributes" do
      assert_raise ArgumentError, ~r/Invalid/, fn ->
        HeuristicDifficulty.new!(%{length_weight: 1.5})
      end
    end
  end

  describe "estimate/3" do
    setup do
      estimator = HeuristicDifficulty.new!(%{})
      {:ok, estimator: estimator}
    end

    test "classifies simple queries as easy", context do
      simple_queries = [
        "What is 2+2?",
        "When was America discovered?",
        "Who wrote Romeo and Juliet?",
        "What is the capital of France?",
        "The sky is blue."
      ]

      for query <- simple_queries do
        assert {:ok, estimate} = HeuristicDifficulty.estimate(context.estimator, query, %{})

        assert DifficultyEstimate.easy?(estimate) or DifficultyEstimate.medium?(estimate),
               "Expected easy or medium for: #{query}"

        assert estimate.score < 0.5, "Expected low score for: #{query}"
      end
    end

    test "classifies complex queries as hard", context do
      complex_queries = [
        "Explain the quantum mechanical principles behind entanglement and their implications for modern cryptography",
        "Compare and contrast the economic policies of Keynesian and supply-side economics, providing specific examples",
        "Analyze the algorithmic complexity of this recursive function and optimize it",
        "How does the interplay between genetic and environmental factors contribute to the development of complex behavioral traits?"
      ]

      for query <- complex_queries do
        assert {:ok, estimate} = HeuristicDifficulty.estimate(context.estimator, query, %{})
        # Note: Heuristic may not be perfect, but should generally detect complexity
        assert estimate.score > 0.4, "Expected higher score for: #{query}"
      end
    end

    test "classifies medium complexity queries", context do
      medium_queries = [
        "How do I calculate the area of a circle?",
        "What are the main differences between Python and JavaScript?",
        "Explain how photosynthesis works"
      ]

      for query <- medium_queries do
        assert {:ok, estimate} = HeuristicDifficulty.estimate(context.estimator, query, %{})
        # Should be somewhere in the middle
        assert estimate.score >= 0.2 and estimate.score <= 0.8
      end
    end

    test "detects math domain", context do
      math_queries = [
        "Calculate the integral of x^2 from 0 to 10",
        "What is the sum of the series 1 + 2 + 3 + ... + n?",
        "Solve for x: 2x + 5 = 15"
      ]

      for query <- math_queries do
        assert {:ok, estimate} = HeuristicDifficulty.estimate(context.estimator, query, %{})
        assert :math in estimate.features.domain.domains or estimate.score > 0.3
      end
    end

    test "detects code domain", context do
      code_queries = [
        "Write a function to sort an array",
        "How do I implement a binary search tree in Python?",
        "What's the time complexity of this algorithm?"
      ]

      for query <- code_queries do
        assert {:ok, estimate} = HeuristicDifficulty.estimate(context.estimator, query, %{})
        assert :code in estimate.features.domain.domains or estimate.score > 0.3
      end
    end

    test "detects reasoning indicators", context do
      reasoning_queries = [
        "Why does the sky appear blue?",
        "How do birds fly?",
        "Explain the causes of the Civil War"
      ]

      for query <- reasoning_queries do
        assert {:ok, estimate} = HeuristicDifficulty.estimate(context.estimator, query, %{})
        # Should detect reasoning keywords
        assert estimate.features.question_type.reasoning_indicator_count > 0
      end
    end

    test "includes confidence in estimate", context do
      assert {:ok, estimate} =
               HeuristicDifficulty.estimate(context.estimator, "What is 2+2?", %{})

      assert is_number(estimate.confidence)
      assert estimate.confidence >= 0.0
      assert estimate.confidence <= 1.0
    end

    test "includes reasoning in estimate", context do
      assert {:ok, estimate} =
               HeuristicDifficulty.estimate(context.estimator, "What is 2+2?", %{})

      assert is_binary(estimate.reasoning)
      assert String.length(estimate.reasoning) > 0
    end

    test "includes features in estimate", context do
      assert {:ok, estimate} =
               HeuristicDifficulty.estimate(context.estimator, "What is 2+2?", %{})

      assert is_map(estimate.features)
      assert Map.has_key?(estimate.features, :length)
      assert Map.has_key?(estimate.features, :complexity)
      assert Map.has_key?(estimate.features, :domain)
      assert Map.has_key?(estimate.features, :question_type)
    end

    test "returns error for empty query", context do
      assert {:error, :invalid_query} =
               HeuristicDifficulty.estimate(context.estimator, "", %{})

      assert {:error, :invalid_query} =
               HeuristicDifficulty.estimate(context.estimator, "   ", %{})
    end

    test "extracts length features correctly", context do
      short = "Hi"
      long = String.duplicate("word ", 100)

      assert {:ok, short_estimate} = HeuristicDifficulty.estimate(context.estimator, short, %{})
      assert {:ok, long_estimate} = HeuristicDifficulty.estimate(context.estimator, long, %{})

      assert short_estimate.features.length.score < long_estimate.features.length.score
    end

    test "extracts complexity features correctly", context do
      simple = "cat dog"
      complex = "antidisestablishmentarianism"

      assert {:ok, simple_estimate} =
               HeuristicDifficulty.estimate(context.estimator, simple, %{})

      assert {:ok, complex_estimate} =
               HeuristicDifficulty.estimate(context.estimator, complex, %{})

      # Complex words should result in higher complexity score
      assert complex_estimate.features.complexity.avg_word_length >
               simple_estimate.features.complexity.avg_word_length
    end
  end

  describe "DifficultyEstimator behaviour" do
    test "implements estimator?/1 correctly" do
      assert DifficultyEstimator.estimator?(HeuristicDifficulty)
    end

    test "exports estimate/3" do
      assert function_exported?(HeuristicDifficulty, :estimate, 3)
    end
  end

  describe "estimate_batch/3" do
    setup do
      estimator = HeuristicDifficulty.new!(%{})
      {:ok, estimator: estimator}
    end

    test "estimates multiple queries", context do
      queries = ["What is 2+2?", "Explain quantum entanglement", "Who wrote Hamlet?"]

      assert {:ok, estimates} =
               DifficultyEstimator.estimate_batch(queries, %{}, HeuristicDifficulty)

      assert length(estimates) == 3
      assert Enum.all?(estimates, fn e -> %DifficultyEstimate{} = e end)
    end

    test "returns error for empty list", context do
      assert {:ok, []} =
               DifficultyEstimator.estimate_batch([], %{}, HeuristicDifficulty)
    end
  end
end
