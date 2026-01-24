defmodule Jido.AI.Accuracy.Estimators.AttentionConfidenceTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.Estimators.AttentionConfidence
  alias Jido.AI.Accuracy.{Candidate, ConfidenceEstimate}

  @moduletag :capture_log

  describe "new/1" do
    test "creates estimator with defaults" do
      assert {:ok, estimator} = AttentionConfidence.new([])
      assert estimator.aggregation == :product
      assert estimator.token_threshold == 0.01
    end

    test "creates estimator with custom aggregation" do
      assert {:ok, estimator} = AttentionConfidence.new(aggregation: :mean)
      assert estimator.aggregation == :mean
    end

    test "creates estimator with custom threshold" do
      assert {:ok, estimator} = AttentionConfidence.new(token_threshold: 0.05)
      assert estimator.token_threshold == 0.05
    end

    test "creates estimator with all options" do
      assert {:ok, estimator} =
               AttentionConfidence.new(aggregation: :min, token_threshold: 0.001)

      assert estimator.aggregation == :min
      assert estimator.token_threshold == 0.001
    end

    test "returns error for invalid aggregation" do
      assert {:error, :invalid_aggregation} = AttentionConfidence.new(aggregation: :invalid)
    end

    test "returns error for invalid threshold" do
      assert {:error, :invalid_token_threshold} = AttentionConfidence.new(token_threshold: 1.5)
      assert {:error, :invalid_token_threshold} = AttentionConfidence.new(token_threshold: -0.1)
    end
  end

  describe "new!/1" do
    test "creates estimator with valid options" do
      estimator = AttentionConfidence.new!(aggregation: :mean)
      assert estimator.aggregation == :mean
    end

    test "raises for invalid options" do
      assert_raise ArgumentError, ~r/Invalid/, fn ->
        AttentionConfidence.new!(aggregation: :invalid)
      end
    end
  end

  describe "estimate/3" do
    setup do
      estimator = AttentionConfidence.new!([])
      {:ok, estimator: estimator}
    end

    test "estimates confidence from logprobs using product aggregation", %{estimator: estimator} do
      candidate =
        Candidate.new!(%{
          content: "The answer is 42",
          metadata: %{logprobs: [-0.1, -0.2, -0.05, -0.3]}
        })

      assert {:ok, estimate} = AttentionConfidence.estimate(estimator, candidate, %{})

      # Product: exp(-0.1) * exp(-0.2) * exp(-0.05) * exp(-0.3)
      # = 0.905 * 0.819 * 0.951 * 0.741 ≈ 0.52
      assert estimate.score > 0.5
      assert estimate.score < 0.6
      assert estimate.method == :attention
      assert estimate.token_level_confidence != nil
    end

    test "estimates confidence using mean aggregation" do
      estimator = AttentionConfidence.new!(aggregation: :mean)

      candidate =
        Candidate.new!(%{
          content: "Test",
          metadata: %{logprobs: [-0.1, -0.1, -0.1]}
        })

      assert {:ok, estimate} = AttentionConfidence.estimate(estimator, candidate, %{})

      # Mean: (exp(-0.1) + exp(-0.1) + exp(-0.1)) / 3 = 0.905
      assert_in_delta estimate.score, 0.905, 0.01
    end

    test "estimates confidence using min aggregation" do
      estimator = AttentionConfidence.new!(aggregation: :min)

      candidate =
        Candidate.new!(%{
          content: "Test",
          metadata: %{logprobs: [-0.1, -0.5, -0.05]}
        })

      assert {:ok, estimate} = AttentionConfidence.estimate(estimator, candidate, %{})

      # Min: exp(-0.5) = 0.606 (worst token)
      assert_in_delta estimate.score, 0.606, 0.01
    end

    test "returns error when logprobs are missing", %{estimator: estimator} do
      candidate = Candidate.new!(%{content: "Test"})

      assert {:error, :no_logprobs} = AttentionConfidence.estimate(estimator, candidate, %{})
    end

    test "returns error when logprobs are empty", %{estimator: estimator} do
      candidate =
        Candidate.new!(%{
          content: "Test",
          metadata: %{logprobs: []}
        })

      assert {:error, :empty_logprobs} = AttentionConfidence.estimate(estimator, candidate, %{})
    end

    test "returns error when logprobs contain positive values", %{estimator: estimator} do
      # Log probabilities must be <= 0 (probabilities are 0-1, so log space is non-positive)
      candidate =
        Candidate.new!(%{
          content: "Test",
          metadata: %{logprobs: [0.1, -0.2, -0.3]}
          # 0.1 is positive, which is invalid for log probabilities
        })

      assert {:error, :invalid_logprobs} = AttentionConfidence.estimate(estimator, candidate, %{})
    end

    test "returns error when logprobs contain non-numeric values", %{estimator: estimator} do
      candidate =
        Candidate.new!(%{
          content: "Test",
          metadata: %{logprobs: [-0.1, "invalid", -0.3]}
        })

      assert {:error, :invalid_logprobs} = AttentionConfidence.estimate(estimator, candidate, %{})
    end

    test "accepts zero logprobs (probability of 1.0)", %{estimator: estimator} do
      # A logprob of 0.0 corresponds to probability of 1.0 (certainty)
      candidate =
        Candidate.new!(%{
          content: "Test",
          metadata: %{logprobs: [0.0, -0.1, -0.2]}
        })

      assert {:ok, _estimate} = AttentionConfidence.estimate(estimator, candidate, %{})
    end

    test "applies token threshold to low probabilities" do
      estimator = AttentionConfidence.new!(token_threshold: 0.1)

      candidate =
        Candidate.new!(%{
          content: "Test",
          metadata: %{logprobs: [-0.5, -2.5, -0.1]}
          # exp(-2.5) = 0.082 < 0.1 threshold
        })

      assert {:ok, estimate} = AttentionConfidence.estimate(estimator, candidate, %{})

      # With threshold applied, min prob is 0.1 instead of 0.082
      # Product: 0.606 * 0.1 * 0.905 ≈ 0.055
      assert estimate.score > 0.05
    end

    test "includes reasoning in estimate", %{estimator: estimator} do
      candidate =
        Candidate.new!(%{
          content: "Test",
          metadata: %{logprobs: [-0.1, -0.2]}
        })

      assert {:ok, estimate} = AttentionConfidence.estimate(estimator, candidate, %{})
      assert is_binary(estimate.reasoning)
      assert String.contains?(estimate.reasoning, "Confidence")
    end

    test "includes metadata with aggregation info", %{estimator: estimator} do
      candidate =
        Candidate.new!(%{
          content: "Test",
          metadata: %{logprobs: [-0.1, -0.2, -0.05]}
        })

      assert {:ok, estimate} = AttentionConfidence.estimate(estimator, candidate, %{})
      assert estimate.metadata.aggregation == :product
      assert estimate.metadata.token_count == 3
      assert is_number(estimate.metadata.min_token_prob)
      assert is_number(estimate.metadata.max_token_prob)
    end

    test "overrides aggregation from context", %{estimator: estimator} do
      candidate =
        Candidate.new!(%{
          content: "Test",
          metadata: %{logprobs: [-0.1, -0.1]}
        })

      assert {:ok, estimate} =
               AttentionConfidence.estimate(estimator, candidate, %{aggregation: :min})

      # Min aggregation with same logprobs should equal the value itself
      assert_in_delta estimate.score, :math.exp(-0.1), 0.01
    end
  end

  describe "estimate_batch/3" do
    test "estimates confidence for multiple candidates" do
      estimator = AttentionConfidence.new!([])

      candidates = [
        Candidate.new!(%{
          content: "Test 1",
          metadata: %{logprobs: [-0.1, -0.1]}
        }),
        Candidate.new!(%{
          content: "Test 2",
          metadata: %{logprobs: [-0.5, -0.5]}
        }),
        Candidate.new!(%{
          content: "Test 3",
          metadata: %{logprobs: [-0.05, -0.05]}
        })
      ]

      assert {:ok, estimates} = AttentionConfidence.estimate_batch(estimator, candidates, %{})
      assert length(estimates) == 3

      # Higher logprobs (closer to 0) = higher confidence
      assert Enum.at(estimates, 2).score > Enum.at(estimates, 0).score
      assert Enum.at(estimates, 0).score > Enum.at(estimates, 1).score
    end

    test "returns error if any candidate fails" do
      estimator = AttentionConfidence.new!([])

      candidates = [
        Candidate.new!(%{
          content: "Test 1",
          metadata: %{logprobs: [-0.1]}
        }),
        Candidate.new!(%{content: "No logprobs"})
        # This one will fail
      ]

      assert {:error, :batch_estimation_failed} =
               AttentionConfidence.estimate_batch(estimator, candidates, %{})
    end
  end

  describe "token_confidences/1" do
    test "extracts token confidences from estimate" do
      candidate =
        Candidate.new!(%{
          content: "Test",
          metadata: %{logprobs: [-0.1, -0.2, -0.3]}
        })

      estimator = AttentionConfidence.new!([])
      assert {:ok, estimate} = AttentionConfidence.estimate(estimator, candidate, %{})

      token_confs = AttentionConfidence.token_confidences(estimate)
      assert is_list(token_confs)
      assert length(token_confs) == 3
    end

    test "returns nil for estimate without token confidences" do
      estimate = ConfidenceEstimate.new!(%{score: 0.5, method: :test})
      assert AttentionConfidence.token_confidences(estimate) == nil
    end
  end

  describe "confidence levels" do
    test "high confidence for good logprobs" do
      estimator = AttentionConfidence.new!([])

      candidate =
        Candidate.new!(%{
          content: "Test",
          metadata: %{logprobs: [-0.01, -0.01, -0.01]}
          # All very high confidence
        })

      assert {:ok, estimate} = AttentionConfidence.estimate(estimator, candidate, %{})
      assert estimate.score >= 0.7
    end

    test "low confidence for poor logprobs" do
      estimator = AttentionConfidence.new!([])

      candidate =
        Candidate.new!(%{
          content: "Test",
          metadata: %{logprobs: [-2.0, -2.0, -2.0]}
          # All very low confidence
        })

      assert {:ok, estimate} = AttentionConfidence.estimate(estimator, candidate, %{})
      assert estimate.score < 0.4
    end
  end
end
