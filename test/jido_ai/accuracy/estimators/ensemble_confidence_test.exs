defmodule Jido.AI.Accuracy.Estimators.EnsembleConfidenceTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Candidate, ConfidenceEstimate}
  alias Jido.AI.Accuracy.Estimators.{EnsembleConfidence, AttentionConfidence}

  @moduletag :capture_log

  # Mock estimator for testing
  defmodule MockEstimator do
    defstruct [:score]

    def estimate(%__MODULE__{score: score}, _candidate, _context) do
      {:ok,
       ConfidenceEstimate.new!(%{
         score: score,
         method: :mock
       })}
    end
  end

  describe "new/1" do
    test "creates estimator with estimators list" do
      estimators = [{MockEstimator, [score: 0.8]}]

      assert {:ok, estimator} = EnsembleConfidence.new(estimators: estimators)
      assert estimator.estimators == estimators
      assert estimator.combination_method == :weighted_mean
    end

    test "creates estimator with all options" do
      estimators = [
        {MockEstimator, [score: 0.7]},
        {MockEstimator, [score: 0.9]}
      ]

      assert {:ok, estimator} =
               EnsembleConfidence.new(
                 estimators: estimators,
                 weights: [0.6, 0.4],
                 combination_method: :weighted_mean
               )

      assert estimator.weights == [0.6, 0.4]
    end

    test "returns error for empty estimators" do
      assert {:error, :no_estimators} = EnsembleConfidence.new(estimators: [])
    end

    test "returns error for invalid estimators" do
      assert {:error, :invalid_estimators} = EnsembleConfidence.new(estimators: "not a list")
      assert {:error, :invalid_estimator_format} =
               EnsembleConfidence.new(estimators: [:not_a_tuple])
    end

    test "returns error for weights length mismatch" do
      estimators = [
        {MockEstimator, [score: 0.7]},
        {MockEstimator, [score: 0.9]}
      ]

      assert {:error, :weights_length_mismatch} =
               EnsembleConfidence.new(
                 estimators: estimators,
                 weights: [0.5]
               )
    end

    test "returns error for invalid combination method" do
      assert {:error, :invalid_combination_method} =
               EnsembleConfidence.new(
                 estimators: [{MockEstimator, []}],
                 combination_method: :invalid
               )
    end
  end

  describe "new!/1" do
    test "creates estimator with valid options" do
      estimator = EnsembleConfidence.new!(estimators: [{MockEstimator, []}])
      assert length(estimator.estimators) == 1
    end

    test "raises for invalid options" do
      assert_raise ArgumentError, ~r/Invalid/, fn ->
        EnsembleConfidence.new!(estimators: [])
      end
    end
  end

  describe "estimate/3" do
    setup do
      estimators = [
        {MockEstimator, [score: 0.8]},
        {MockEstimator, [score: 0.6]},
        {MockEstimator, [score: 0.9]}
      ]

      estimator = EnsembleConfidence.new!(estimators: estimators)
      candidate = Candidate.new!(%{content: "Test"})
      {:ok, estimator: estimator, candidate: candidate}
    end

    test "combines estimates using weighted mean", context do
      weights = [0.5, 0.3, 0.2]

      assert {:ok, estimate} =
               EnsembleConfidence.estimate(
                 context.estimator,
                 context.candidate,
                 %{weights: weights}
               )

      # Weighted mean: 0.8*0.5 + 0.6*0.3 + 0.9*0.2 = 0.4 + 0.18 + 0.18 = 0.76
      assert_in_delta estimate.score, 0.76, 0.01
      assert estimate.method == :ensemble
    end

    test "combines estimates using equal weights when no weights provided", context do
      assert {:ok, estimate} =
               EnsembleConfidence.estimate(context.estimator, context.candidate, %{})

      # Mean: (0.8 + 0.6 + 0.9) / 3 = 0.767
      assert_in_delta estimate.score, 0.767, 0.01
    end

    test "combines estimates using mean combination" do
      estimators = [
        {MockEstimator, [score: 0.7]},
        {MockEstimator, [score: 0.9]}
      ]

      estimator = EnsembleConfidence.new!(
        estimators: estimators,
        combination_method: :mean
      )

      candidate = Candidate.new!(%{content: "Test"})

      assert {:ok, estimate} = EnsembleConfidence.estimate(estimator, candidate, %{})
      # Mean: (0.7 + 0.9) / 2 = 0.8
      assert_in_delta estimate.score, 0.8, 0.01
    end

    test "combines estimates using voting" do
      estimators = [
        {MockEstimator, [score: 0.8]},  # high
        {MockEstimator, [score: 0.75]},  # high
        {MockEstimator, [score: 0.5]},  # medium
        {MockEstimator, [score: 0.3]}  # low
      ]

      estimator =
        EnsembleConfidence.new!(
          estimators: estimators,
          combination_method: :voting
        )

      candidate = Candidate.new!(%{content: "Test"})

      assert {:ok, estimate} = EnsembleConfidence.estimate(estimator, candidate, %{})

      # 2 high, 1 medium, 1 low -> high wins
      # Midpoint of high [0.7, 1.0] is 0.85
      assert estimate.score >= 0.7
    end

    test "includes reasoning with individual scores", context do
      assert {:ok, estimate} =
               EnsembleConfidence.estimate(context.estimator, context.candidate, %{})

      assert String.contains?(estimate.reasoning, "Ensemble")
      assert String.contains?(estimate.reasoning, "0.8")
      assert String.contains?(estimate.reasoning, "0.6")
      assert String.contains?(estimate.reasoning, "0.9")
    end

    test "includes metadata with disagreement", context do
      assert {:ok, estimate} =
               EnsembleConfidence.estimate(context.estimator, context.candidate, %{})

      assert Map.has_key?(estimate.metadata, :disagreement)
      assert Map.has_key?(estimate.metadata, :individual_scores)
      assert Map.has_key?(estimate.metadata, :estimator_count)
    end
  end

  describe "estimate/3 with AttentionConfidence" do
    test "combines real estimators" do
      # Create two AttentionConfidence estimators with different aggregations
      estimators = [
        {AttentionConfidence, [aggregation: :product]},
        {AttentionConfidence, [aggregation: :mean]}
      ]

      estimator = EnsembleConfidence.new!(estimators: estimators)

      candidate =
        Candidate.new!(%{
          content: "Test",
          metadata: %{logprobs: [-0.1, -0.2, -0.05]}
        })

      assert {:ok, estimate} = EnsembleConfidence.estimate(estimator, candidate, %{})
      assert estimate.method == :ensemble
      assert estimate.score > 0.0
      assert estimate.score <= 1.0
    end
  end

  describe "estimate/3 error handling" do
    test "returns error when all estimators fail" do
      # Use invalid estimator module
      estimators = [{NonExistent, []}]
      estimator = EnsembleConfidence.new!(estimators: estimators)

      candidate = Candidate.new!(%{content: "Test"})

      assert {:error, :all_estimators_failed} =
               EnsembleConfidence.estimate(estimator, candidate, %{})
    end
  end

  describe "disagreement_score/2" do
    test "calculates disagreement for consistent estimates" do
      estimates = [
        ConfidenceEstimate.new!(%{score: 0.75, method: :m1}),
        ConfidenceEstimate.new!(%{score: 0.76, method: :m2}),
        ConfidenceEstimate.new!(%{score: 0.74, method: :m3})
      ]

      # Low disagreement (all close to 0.75)
      score = EnsembleConfidence.disagreement_score(estimates)
      assert score < 0.1
    end

    test "calculates disagreement for divergent estimates" do
      estimates = [
        ConfidenceEstimate.new!(%{score: 0.9, method: :m1}),
        ConfidenceEstimate.new!(%{score: 0.5, method: :m2}),
        ConfidenceEstimate.new!(%{score: 0.1, method: :m3})
      ]

      # High disagreement
      score = EnsembleConfidence.disagreement_score(estimates)
      assert score > 0.3
    end

    test "calculates disagreement with custom baseline" do
      estimates = [
        ConfidenceEstimate.new!(%{score: 0.8, method: :m1}),
        ConfidenceEstimate.new!(%{score: 0.6, method: :m2})
      ]

      # Baseline of 0.5
      score = EnsembleConfidence.disagreement_score(estimates, 0.5)
      # Mean deviation from 0.5: (0.3 + 0.1) / 2 = 0.2
      assert_in_delta score, 0.4, 0.01
    end
  end

  describe "estimate_with_disagreement/3" do
    setup do
      estimators = [
        {MockEstimator, [score: 0.8]},
        {MockEstimator, [score: 0.6]}
      ]

      estimator = EnsembleConfidence.new!(estimators: estimators)
      {:ok, estimator: estimator}
    end

    test "returns estimate and disagreement score", context do
      candidate = Candidate.new!(%{content: "Test"})

      assert {{:ok, estimate}, disagreement} =
               EnsembleConfidence.estimate_with_disagreement(
                 context.estimator,
                 candidate,
                 %{}
               )

      assert is_number(estimate.score)
      assert is_number(disagreement)
      assert disagreement >= 0.0
      assert disagreement <= 1.0
    end

    test "includes disagreement in estimate metadata", context do
      candidate = Candidate.new!(%{content: "Test"})

      assert {{:ok, estimate}, _disagreement} =
               EnsembleConfidence.estimate_with_disagreement(
                 context.estimator,
                 candidate,
                 %{}
               )

      assert Map.has_key?(estimate.metadata, :disagreement)
    end

    test "returns error and nil on failure", context do
      # Missing logprobs will cause MockEstimator to not work
      # So let's use a real scenario
      estimators = [{NonExistent, []}]
      estimator = EnsembleConfidence.new!(estimators: estimators)
      candidate = Candidate.new!(%{content: "Test"})

      assert {{:error, _reason}, nil} =
               EnsembleConfidence.estimate_with_disagreement(
                 estimator,
                 candidate,
                 %{}
               )
    end
  end

  describe "estimate_batch/3" do
    test "estimates for multiple candidates" do
      estimators = [
        {MockEstimator, [score: 0.7]},
        {MockEstimator, [score: 0.9]}
      ]

      estimator = EnsembleConfidence.new!(estimators: estimators)

      candidates = [
        Candidate.new!(%{content: "Test 1"}),
        Candidate.new!(%{content: "Test 2"})
      ]

      assert {:ok, estimates} =
               EnsembleConfidence.estimate_batch(estimator, candidates, %{})

      assert length(estimates) == 2
      assert Enum.all?(estimates, fn e -> e.method == :ensemble end)
    end
  end

  describe "confidence levels" do
    test "high confidence when all estimators agree on high" do
      estimators = [
        {MockEstimator, [score: 0.9]},
        {MockEstimator, [score: 0.85]},
        {MockEstimator, [score: 0.95]}
      ]

      estimator = EnsembleConfidence.new!(estimators: estimators)
      candidate = Candidate.new!(%{content: "Test"})

      assert {:ok, estimate} = EnsembleConfidence.estimate(estimator, candidate, %{})
      assert ConfidenceEstimate.high_confidence?(estimate)
    end

    test "low confidence when all estimators agree on low" do
      estimators = [
        {MockEstimator, [score: 0.2]},
        {MockEstimator, [score: 0.3]},
        {MockEstimator, [score: 0.1]}
      ]

      estimator = EnsembleConfidence.new!(estimators: estimators)
      candidate = Candidate.new!(%{content: "Test"})

      assert {:ok, estimate} = EnsembleConfidence.estimate(estimator, candidate, %{})
      assert ConfidenceEstimate.low_confidence?(estimate)
    end

    test "medium confidence with mixed estimates" do
      estimators = [
        {MockEstimator, [score: 0.5]},
        {MockEstimator, [score: 0.4]},
        {MockEstimator, [score: 0.6]}
      ]

      estimator = EnsembleConfidence.new!(estimators: estimators)
      candidate = Candidate.new!(%{content: "Test"})

      assert {:ok, estimate} = EnsembleConfidence.estimate(estimator, candidate, %{})
      assert ConfidenceEstimate.medium_confidence?(estimate)
    end
  end
end
