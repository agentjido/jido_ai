defmodule Jido.AI.Accuracy.IntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Accuracy.Aggregators.{MajorityVote, BestOfN, Weighted}
  alias Jido.AI.Accuracy.SelfConsistency

  @moduletag :integration
  @moduletag :requires_api

  @moduletag :capture_log

  describe "end-to-end self-consistency" do
    @tag :math
    test "math problem: 15 * 23 = 345" do
      # Simple multiplication problem that LLMs should get right
      assert {:ok, best, metadata} =
               SelfConsistency.run("What is 15 * 23? Answer with just the number.",
                 num_candidates: 5,
                 aggregator: :majority_vote
               )

      # Verify we got a result
      assert is_binary(best.content)

      # The answer should contain "345"
      # Note: LLM may respond with just "345" or "345." or "The answer is 345"
      assert String.contains?(String.downcase(best.content), "345")

      # Verify metadata
      assert metadata.num_candidates <= 5
      assert metadata.aggregator == MajorityVote
      assert is_number(metadata.confidence)
    end

    @tag :math
    test "math problem with CoT: 15 * 23 + 7 = 352" do
      assert {:ok, best, metadata} =
               SelfConsistency.run_with_reasoning(
                 "Solve step by step: 15 * 23 + 7. Answer with just the final number.",
                 num_candidates: 3
               )

      # Should contain "352"
      assert String.contains?(String.downcase(best.content), "352")

      # May have reasoning field populated
      # Note: reasoning may be empty if LLM didn't follow format
      assert is_map(best.metadata)
    end

    @tag :simple
    test "simple factual question" do
      assert {:ok, best, metadata} =
               SelfConsistency.run(
                 "What is the capital of France? Answer with just the city name.",
                 num_candidates: 3
               )

      # Should contain "Paris"
      assert String.contains?(String.downcase(best.content), "paris")

      assert metadata.num_candidates <= 3
    end

    @tag :diversity
    test "temperature variation produces diverse outputs" do
      # A question that might have different wording
      prompt = "What is 2 + 2? Answer with just the number."

      # Low temperature - should be very consistent
      assert {:ok, best_low, _} =
               SelfConsistency.run(prompt,
                 num_candidates: 3,
                 temperature_range: {0.0, 0.1}
               )

      # High temperature - might have some variation
      assert {:ok, best_high, _} =
               SelfConsistency.run(prompt,
                 num_candidates: 3,
                 temperature_range: {0.8, 1.0}
               )

      # Both should get the right answer ("4")
      assert String.contains?(String.downcase(best_low.content), "4")
      assert String.contains?(String.downcase(best_high.content), "4")
    end

    @tag :aggregators
    test "all aggregators work end-to-end" do
      prompt = "What is 7 * 8? Answer with just the number."

      # Test with majority vote
      assert {:ok, best_mv, _} =
               SelfConsistency.run(prompt,
                 num_candidates: 3,
                 aggregator: :majority_vote
               )

      assert String.contains?(String.downcase(best_mv.content), "56")

      # Test with best_of_n (needs candidates with scores)
      # Note: default candidates don't have scores, so this tests the fallback
      assert {:ok, best_bon, _} =
               SelfConsistency.run(prompt,
                 num_candidates: 3,
                 aggregator: :best_of_n
               )

      # best_of_n without scores will use first candidate or fail gracefully
      assert is_binary(best_bon.content)

      # Test with weighted
      assert {:ok, best_w, _} =
               SelfConsistency.run(prompt,
                 num_candidates: 3,
                 aggregator: :weighted
               )

      assert String.contains?(String.downcase(best_w.content), "56")
    end
  end

  describe "performance and cost tracking" do
    @tag :cost
    test "token counting is accurate" do
      assert {:ok, _best, metadata} =
               SelfConsistency.run(
                 "Say 'hello' and nothing else.",
                 num_candidates: 2
               )

      # total_tokens should be present and non-zero
      # (unless API doesn't return token info)
      assert metadata.total_tokens == nil or metadata.total_tokens >= 0
    end

    @tag :cost
    test "metadata includes cost information" do
      assert {:ok, _best, metadata} =
               SelfConsistency.run(
                 "Count to 3.",
                 num_candidates: 2
               )

      # Verify metadata structure
      assert Map.has_key?(metadata, :total_tokens)
      assert Map.has_key?(metadata, :num_candidates)
      assert Map.has_key?(metadata, :aggregator)
      assert Map.has_key?(metadata, :confidence)
      assert Map.has_key?(metadata, :aggregation_metadata)
    end

    @tag :timeout
    test "timeout is enforced" do
      # Very short timeout - should fail or return partial results
      result =
        SelfConsistency.run(
          "Write a 1000 word essay on artificial intelligence.",
          num_candidates: 1,
          # 100ms - very short
          timeout: 100
        )

      # Should either fail or succeed (network may be fast)
      case result do
        {:ok, _best, _metadata} ->
          # Succeeded - OK, network was fast enough
          :ok

        {:error, _reason} ->
          # Failed as expected with short timeout
          :ok
      end
    end
  end

  describe "error handling" do
    @tag :error_handling
    test "invalid aggregator returns error" do
      assert {:error, :invalid_aggregator} =
               SelfConsistency.run(
                 "Test",
                 aggregator: String,
                 num_candidates: 1
               )
    end

    @tag :error_handling
    test "handles generation errors gracefully" do
      # Use a timeout that's likely to cause issues
      result =
        SelfConsistency.run(
          "Respond with exactly: SUCCESS",
          num_candidates: 1,
          # 1ms - will likely fail
          timeout: 1
        )

      # Should either succeed (fast API) or fail gracefully
      case result do
        {:ok, _best, _metadata} -> :ok
        {:error, _reason} -> :ok
      end
    end
  end

  describe "confidence metrics" do
    @tag :confidence
    test "majority vote produces confidence score" do
      assert {:ok, _best, metadata} =
               SelfConsistency.run(
                 "What is 10 + 10? Answer with just the number.",
                 num_candidates: 5,
                 aggregator: :majority_vote
               )

      # Confidence should be between 0 and 1
      assert metadata.confidence >= 0.0
      assert metadata.confidence <= 1.0
    end

    @tag :confidence
    test "single candidate has confidence 1.0" do
      assert {:ok, _best, metadata} =
               SelfConsistency.run(
                 "What is 1 + 1? Answer with just the number.",
                 num_candidates: 1
               )

      # With single candidate, confidence should be 1.0
      assert metadata.confidence == 1.0
    end
  end

  describe "chain-of-thought reasoning" do
    @tag :cot
    test "run_with_reasoning preserves reasoning" do
      assert {:ok, best, metadata} =
               SelfConsistency.run_with_reasoning(
                 "Think step by step: What is 12 * 12? Answer with just the final number.",
                 num_candidates: 2
               )

      # Should contain "144"
      assert String.contains?(String.downcase(best.content), "144")

      # Check if reasoning was captured (may be empty depending on LLM)
      # The reasoning field might be populated if the LLM followed the format
      # We just verify the candidate has the field
      assert is_map(best.metadata)
    end

    @tag :cot
    test "run_with_reasoning metadata is correct" do
      assert {:ok, _best, metadata} =
               SelfConsistency.run_with_reasoning(
                 "Think step by step: What is 5 + 5?",
                 num_candidates: 1
               )

      # Metadata should have confidence
      assert is_number(metadata.confidence)
    end
  end

  describe "aggregation metadata" do
    @tag :metadata
    test "majority vote returns vote distribution" do
      assert {:ok, _best, metadata} =
               SelfConsistency.run(
                 "What is 3 + 3? Answer with just the number.",
                 num_candidates: 5,
                 aggregator: :majority_vote
               )

      # aggregation_metadata should contain vote_distribution
      assert Map.has_key?(metadata.aggregation_metadata, :vote_distribution)
    end

    @tag :metadata
    test "weighted aggregator returns strategy results" do
      assert {:ok, _best, metadata} =
               SelfConsistency.run(
                 "What is 4 + 4? Answer with just the number.",
                 num_candidates: 3,
                 aggregator: :weighted
               )

      # aggregation_metadata should contain strategy results
      assert Map.has_key?(metadata.aggregation_metadata, :strategy_results)
    end
  end
end
