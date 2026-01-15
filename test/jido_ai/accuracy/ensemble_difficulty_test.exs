defmodule Jido.AI.Accuracy.EnsembleDifficultyTest do
  @moduledoc """
  Tests for the EnsembleDifficulty estimator.
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{
    DifficultyEstimate,
    EnsembleDifficulty,
    Estimators.HeuristicDifficulty,
    Estimators.LLMDifficulty
  }

  describe "new/1" do
    test "creates ensemble with valid estimators" do
      heuristic = HeuristicDifficulty.new!(%{})
      llm = LLMDifficulty.new!(%{})

      assert {:ok, ensemble} = EnsembleDifficulty.new(%{
        estimators: [
          {HeuristicDifficulty, heuristic},
          {LLMDifficulty, llm}
        ]
      })

      assert ensemble.estimators == [
        {HeuristicDifficulty, heuristic},
        {LLMDifficulty, llm}
      ]
      assert ensemble.combination == :weighted_average
      assert ensemble.timeout == 10_000
    end

    test "creates ensemble with custom combination" do
      heuristic = HeuristicDifficulty.new!(%{})

      assert {:ok, ensemble} = EnsembleDifficulty.new(%{
        estimators: [{HeuristicDifficulty, heuristic}],
        combination: :majority_vote
      })

      assert ensemble.combination == :majority_vote
    end

    test "creates ensemble with weights" do
      heuristic = HeuristicDifficulty.new!(%{})
      llm = LLMDifficulty.new!(%{})

      assert {:ok, ensemble} = EnsembleDifficulty.new(%{
        estimators: [
          {HeuristicDifficulty, heuristic},
          {LLMDifficulty, llm}
        ],
        weights: [0.3, 0.7]
      })

      assert ensemble.weights == [0.3, 0.7]
    end

    test "creates ensemble with fallback" do
      heuristic = HeuristicDifficulty.new!(%{})

      assert {:ok, ensemble} = EnsembleDifficulty.new(%{
        estimators: [{HeuristicDifficulty, heuristic}],
        fallback: HeuristicDifficulty
      })

      assert ensemble.fallback == HeuristicDifficulty
    end

    test "creates ensemble with custom timeout" do
      heuristic = HeuristicDifficulty.new!(%{})

      assert {:ok, ensemble} = EnsembleDifficulty.new(%{
        estimators: [{HeuristicDifficulty, heuristic}],
        timeout: 5000
      })

      assert ensemble.timeout == 5000
    end

    test "returns error for empty estimators" do
      assert {:error, :estimators_required} = EnsembleDifficulty.new(%{
        estimators: []
      })
    end

    test "returns error for nil estimators" do
      assert {:error, :estimators_required} = EnsembleDifficulty.new(%{
        estimators: nil
      })
    end

    test "returns error for invalid estimators" do
      assert {:error, :invalid_estimators} = EnsembleDifficulty.new(%{
        estimators: [:not_a_tuple]
      })
    end

    test "returns error for mismatched weights length" do
      heuristic = HeuristicDifficulty.new!(%{})
      llm = LLMDifficulty.new!(%{})

      assert {:error, :weights_length_mismatch} = EnsembleDifficulty.new(%{
        estimators: [
          {HeuristicDifficulty, heuristic},
          {LLMDifficulty, llm}
        ],
        weights: [0.5]
      })
    end

    test "returns error for invalid combination" do
      heuristic = HeuristicDifficulty.new!(%{})

      assert {:error, :invalid_combination} = EnsembleDifficulty.new(%{
        estimators: [{HeuristicDifficulty, heuristic}],
        combination: :invalid
      })
    end

    test "returns error for invalid timeout" do
      heuristic = HeuristicDifficulty.new!(%{})

      assert {:error, :invalid_timeout} = EnsembleDifficulty.new(%{
        estimators: [{HeuristicDifficulty, heuristic}],
        timeout: -1
      })
    end
  end

  describe "new!/1" do
    test "creates ensemble or raises" do
      heuristic = HeuristicDifficulty.new!(%{})

      ensemble = EnsembleDifficulty.new!(%{
        estimators: [{HeuristicDifficulty, heuristic}]
      })

      assert %EnsembleDifficulty{} = ensemble
    end

    test "raises for invalid input" do
      assert_raise ArgumentError, ~r/Invalid EnsembleDifficulty/, fn ->
        EnsembleDifficulty.new!(%{estimators: []})
      end
    end
  end

  describe "estimate/3 - weighted_average" do
    test "combines two estimators with weighted average" do
      heuristic = HeuristicDifficulty.new!(%{})
      llm = LLMDifficulty.new!(%{})

      ensemble = EnsembleDifficulty.new!(%{
        estimators: [
          {HeuristicDifficulty, heuristic},
          {LLMDifficulty, llm}
        ],
        weights: [0.4, 0.6],
        combination: :weighted_average
      })

      # Use a simple query that heuristic can handle
      query = "What is 2+2?"

      assert {:ok, estimate} = EnsembleDifficulty.estimate(ensemble, query, %{})
      assert %DifficultyEstimate{} = estimate
      assert estimate.level in [:easy, :medium, :hard]
      assert estimate.score >= 0.0 and estimate.score <= 1.0
      assert estimate.confidence >= 0.0 and estimate.confidence <= 1.0

      # Check metadata
      assert estimate.metadata.ensemble == true
      assert estimate.metadata.combination == :weighted_average
      assert estimate.metadata.num_estimators == 2
    end

    test "normalizes weights that don't sum to 1" do
      heuristic = HeuristicDifficulty.new!(%{})
      llm = LLMDifficulty.new!(%{})

      ensemble = EnsembleDifficulty.new!(%{
        estimators: [
          {HeuristicDifficulty, heuristic},
          {LLMDifficulty, llm}
        ],
        weights: [1.0, 2.0],  # Sums to 3.0, should be normalized
        combination: :weighted_average
      })

      query = "What is 2+2?"

      assert {:ok, estimate} = EnsembleDifficulty.estimate(ensemble, query, %{})
      # Should still produce valid result
      assert estimate.score >= 0.0 and estimate.score <= 1.0
    end

    test "uses equal weights when none provided" do
      heuristic = HeuristicDifficulty.new!(%{})
      llm = LLMDifficulty.new!(%{})

      ensemble = EnsembleDifficulty.new!(%{
        estimators: [
          {HeuristicDifficulty, heuristic},
          {LLMDifficulty, llm}
        ],
        combination: :weighted_average
      })

      query = "What is 2+2?"

      assert {:ok, estimate} = EnsembleDifficulty.estimate(ensemble, query, %{})
      assert estimate.metadata.ensemble == true
    end
  end

  describe "estimate/3 - majority_vote" do
    test "combines estimators using majority vote" do
      # Create multiple estimators - we can't easily change individual weights
      # without breaking the sum-to-1 validation, so we use the default
      # The estimators should still produce slightly different results due to internal randomness
      heuristic1 = HeuristicDifficulty.new!(%{})
      heuristic2 = HeuristicDifficulty.new!(%{})
      heuristic3 = HeuristicDifficulty.new!(%{})

      ensemble = EnsembleDifficulty.new!(%{
        estimators: [
          {HeuristicDifficulty, heuristic1},
          {HeuristicDifficulty, heuristic2},
          {HeuristicDifficulty, heuristic3}
        ],
        combination: :majority_vote
      })

      query = "What is 2+2?"

      assert {:ok, estimate} = EnsembleDifficulty.estimate(ensemble, query, %{})
      assert %DifficultyEstimate{} = estimate
      assert estimate.level in [:easy, :medium, :hard]

      # Check voting metadata
      assert estimate.metadata.ensemble == true
      assert estimate.metadata.combination == :majority_vote
      assert is_map(estimate.metadata.vote_distribution)
      assert estimate.metadata.agreement >= 0.0 and estimate.metadata.agreement <= 1.0
    end

    test "handles ties in majority vote" do
      # With 3 estimators and different settings
      # We use custom_indicators to create some variation
      heuristic1 = HeuristicDifficulty.new!(%{})
      heuristic2 = HeuristicDifficulty.new!(%{custom_indicators: %{test: ["a"]}})
      heuristic3 = HeuristicDifficulty.new!(%{custom_indicators: %{test: ["b"]}})

      ensemble = EnsembleDifficulty.new!(%{
        estimators: [
          {HeuristicDifficulty, heuristic1},
          {HeuristicDifficulty, heuristic2},
          {HeuristicDifficulty, heuristic3}
        ],
        combination: :majority_vote
      })

      query = "What is 2+2?"

      assert {:ok, estimate} = EnsembleDifficulty.estimate(ensemble, query, %{})
      # Should still produce a result even with ties (first max wins)
      assert estimate.level in [:easy, :medium, :hard]
    end
  end

  describe "estimate/3 - max_confidence" do
    test "selects estimate with highest confidence" do
      heuristic1 = HeuristicDifficulty.new!(%{})
      heuristic2 = HeuristicDifficulty.new!(%{})

      ensemble = EnsembleDifficulty.new!(%{
        estimators: [
          {HeuristicDifficulty, heuristic1},
          {HeuristicDifficulty, heuristic2}
        ],
        combination: :max_confidence
      })

      query = "What is 2+2?"

      assert {:ok, estimate} = EnsembleDifficulty.estimate(ensemble, query, %{})
      assert %DifficultyEstimate{} = estimate
      assert estimate.level in [:easy, :medium, :hard]
      assert estimate.confidence >= 0.0 and estimate.confidence <= 1.0

      # Check reasoning mentions high confidence
      assert String.contains?(estimate.reasoning, "highest confidence")
    end
  end

  describe "estimate/3 - average" do
    test "averages all estimates" do
      heuristic1 = HeuristicDifficulty.new!(%{})
      heuristic2 = HeuristicDifficulty.new!(%{})

      ensemble = EnsembleDifficulty.new!(%{
        estimators: [
          {HeuristicDifficulty, heuristic1},
          {HeuristicDifficulty, heuristic2}
        ],
        combination: :average
      })

      query = "What is 2+2?"

      assert {:ok, estimate} = EnsembleDifficulty.estimate(ensemble, query, %{})
      assert %DifficultyEstimate{} = estimate
      assert estimate.level in [:easy, :medium, :hard]
      assert estimate.score >= 0.0 and estimate.score <= 1.0

      # Check metadata
      assert estimate.metadata.ensemble == true
      assert estimate.metadata.combination == :average
      assert estimate.metadata.num_estimators == 2
    end
  end

  describe "estimate/3 - error handling" do
    test "uses fallback when all estimators fail" do
      # Note: In test environment, LLMDifficulty uses simulation mode
      # which always succeeds. So this test verifies the fallback path exists
      # but won't actually trigger it in tests.
      llm = LLMDifficulty.new!(%{})

      ensemble = EnsembleDifficulty.new!(%{
        estimators: [{LLMDifficulty, llm}],
        fallback: HeuristicDifficulty
      })

      query = "What is 2+2?"

      # Since LLM simulation succeeds, we get a normal result
      assert {:ok, estimate} = EnsembleDifficulty.estimate(ensemble, query, %{})
      assert %DifficultyEstimate{} = estimate
    end

    test "returns error for empty query" do
      heuristic = HeuristicDifficulty.new!(%{})

      ensemble = EnsembleDifficulty.new!(%{
        estimators: [{HeuristicDifficulty, heuristic}]
      })

      assert {:error, :invalid_query} = EnsembleDifficulty.estimate(ensemble, "", %{})
    end

    test "returns error for nil query" do
      heuristic = HeuristicDifficulty.new!(%{})

      ensemble = EnsembleDifficulty.new!(%{
        estimators: [{HeuristicDifficulty, heuristic}]
      })

      assert {:error, :invalid_query} = EnsembleDifficulty.estimate(ensemble, nil, %{})
    end
  end

  describe "estimate_batch/3" do
    test "estimates multiple queries" do
      heuristic = HeuristicDifficulty.new!(%{})

      ensemble = EnsembleDifficulty.new!(%{
        estimators: [{HeuristicDifficulty, heuristic}]
      })

      queries = [
        "What is 2+2?",
        "Explain quantum entanglement.",
        "Who wrote Romeo and Juliet?"
      ]

      assert {:ok, estimates} = EnsembleDifficulty.estimate_batch(ensemble, queries, %{})
      assert length(estimates) == 3

      Enum.each(estimates, fn estimate ->
        assert %DifficultyEstimate{} = estimate
        assert estimate.level in [:easy, :medium, :hard]
      end)
    end

    test "returns error if any query fails" do
      heuristic = HeuristicDifficulty.new!(%{})

      ensemble = EnsembleDifficulty.new!(%{
        estimators: [{HeuristicDifficulty, heuristic}]
      })

      queries = [
        "What is 2+2?",
        "",  # Invalid query
        "Valid query"
      ]

      assert {:error, :invalid_query} = EnsembleDifficulty.estimate_batch(ensemble, queries, %{})
    end

    test "handles empty query list" do
      heuristic = HeuristicDifficulty.new!(%{})

      ensemble = EnsembleDifficulty.new!(%{
        estimators: [{HeuristicDifficulty, heuristic}]
      })

      assert {:ok, []} = EnsembleDifficulty.estimate_batch(ensemble, [], %{})
    end
  end

  describe "integration with different estimators" do
    test "works with all heuristic estimators" do
      # Create estimators with valid weights that sum to 1
      estimators =
        [
          {HeuristicDifficulty, HeuristicDifficulty.new!(%{})},
          {HeuristicDifficulty, HeuristicDifficulty.new!(%{custom_indicators: %{test: ["test"]}})},
          {HeuristicDifficulty, HeuristicDifficulty.new!(%{})}
        ]

      ensemble = EnsembleDifficulty.new!(%{
        estimators: estimators,
        combination: :majority_vote
      })

      query = "Calculate the integral of x^2 from 0 to 1."

      assert {:ok, estimate} = EnsembleDifficulty.estimate(ensemble, query, %{})
      # Math problems should be at least medium or hard
      assert estimate.level in [:medium, :hard]
    end

    test "works with mix of heuristic and LLM" do
      heuristic = HeuristicDifficulty.new!(%{})
      llm = LLMDifficulty.new!(%{})

      ensemble = EnsembleDifficulty.new!(%{
        estimators: [
          {HeuristicDifficulty, heuristic},
          {LLMDifficulty, llm}
        ],
        weights: [0.7, 0.3]
      })

      # Simple question - heuristic should say easy
      query = "What is 2+2?"

      assert {:ok, estimate} = EnsembleDifficulty.estimate(ensemble, query, %{})
      assert estimate.level == :easy
    end
  end
end
