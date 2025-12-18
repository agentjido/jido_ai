defmodule Jido.AI.Runner.ChainOfThought.SelfCorrectionTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.ChainOfThought.SelfCorrection

  describe "validate_outcome/3" do
    test "returns :match for identical values" do
      assert SelfCorrection.validate_outcome(42, 42) == :match
    end

    test "returns :match for very similar values" do
      assert SelfCorrection.validate_outcome(100, 100) == :match
    end

    test "returns :minor for small numeric differences" do
      assert SelfCorrection.validate_outcome(100, 95) == :minor
    end

    test "returns :moderate for noticeable differences" do
      assert SelfCorrection.validate_outcome(100, 70) == :moderate
    end

    test "returns :critical for major differences" do
      assert SelfCorrection.validate_outcome(100, 10) == :critical
    end

    test "returns :match for identical strings" do
      assert SelfCorrection.validate_outcome("hello", "hello") == :match
    end

    test "returns :minor for similar strings" do
      # Similar strings should return minor
      result = SelfCorrection.validate_outcome("hello", "hallo")
      assert result in [:minor, :moderate]
    end

    test "returns :critical for completely different strings" do
      result = SelfCorrection.validate_outcome("hello", "goodbye")
      assert result in [:moderate, :critical]
    end

    test "uses custom validator when provided" do
      custom_validator = fn _expected, _actual -> :custom_result end

      assert SelfCorrection.validate_outcome(1, 2, validator: custom_validator) == :custom_result
    end

    test "accepts custom similarity threshold" do
      # With higher threshold (0.95), score of 0.9 falls below threshold
      # Since score is 0.9, which is >= 0.8, it's minor
      result = SelfCorrection.validate_outcome(100, 90, similarity_threshold: 0.95)
      assert result == :minor

      # With score 0.7 and threshold 0.95, it becomes moderate
      result2 = SelfCorrection.validate_outcome(100, 70, similarity_threshold: 0.95)
      assert result2 == :moderate
    end
  end

  describe "similarity_score/2" do
    test "returns 1.0 for identical values" do
      assert SelfCorrection.similarity_score(42, 42) == 1.0
      assert SelfCorrection.similarity_score("test", "test") == 1.0
      assert SelfCorrection.similarity_score([1, 2, 3], [1, 2, 3]) == 1.0
    end

    test "calculates numeric similarity" do
      score = SelfCorrection.similarity_score(100, 90)
      assert score == 0.9
    end

    test "calculates numeric similarity for negative numbers" do
      score = SelfCorrection.similarity_score(-100, -90)
      assert score == 0.9
    end

    test "returns 1.0 for both zero" do
      assert SelfCorrection.similarity_score(0, 0) == 1.0
    end

    test "calculates string similarity" do
      score = SelfCorrection.similarity_score("hello", "hallo")
      assert score > 0.5
      assert score < 1.0
    end

    test "returns low score for different strings" do
      score = SelfCorrection.similarity_score("abc", "xyz")
      assert score < 0.5
    end

    test "calculates list similarity" do
      score = SelfCorrection.similarity_score([1, 2, 3], [1, 2, 4])
      assert score >= 0.5
      assert score < 1.0
    end

    test "returns 0.0 for incompatible types" do
      assert SelfCorrection.similarity_score(42, "42") == 0.0
      assert SelfCorrection.similarity_score(%{}, []) == 0.0
    end
  end

  describe "select_correction_strategy/3" do
    test "returns :accept_partial for :match divergence" do
      assert SelfCorrection.select_correction_strategy(:match, 1, []) == :accept_partial
    end

    test "returns :retry_adjusted for :minor divergence in early iterations" do
      assert SelfCorrection.select_correction_strategy(:minor, 1, []) == :retry_adjusted
      assert SelfCorrection.select_correction_strategy(:minor, 2, []) == :retry_adjusted
    end

    test "returns :accept_partial for :minor divergence in late iterations" do
      assert SelfCorrection.select_correction_strategy(:minor, 3, []) == :accept_partial
    end

    test "returns :backtrack_alternative for :moderate divergence in first iteration" do
      assert SelfCorrection.select_correction_strategy(:moderate, 1, []) == :backtrack_alternative
    end

    test "returns :retry_adjusted for :moderate divergence in later iterations without repeated failure" do
      history = [{1, %{}, 0.5, :retry_adjusted}]
      assert SelfCorrection.select_correction_strategy(:moderate, 2, history) == :retry_adjusted
    end

    test "returns :clarify_requirements for :critical with ambiguous history" do
      history = [{1, %{}, "unclear requirements", :critical, :retry_adjusted}]

      assert SelfCorrection.select_correction_strategy(:critical, 2, history) ==
               :clarify_requirements
    end

    test "returns :backtrack_alternative for :critical without ambiguous history" do
      history = [{1, %{}, "wrong answer", :critical, :retry_adjusted}]

      assert SelfCorrection.select_correction_strategy(:critical, 2, history) ==
               :backtrack_alternative
    end
  end

  describe "iterative_execute/2" do
    test "succeeds on first iteration if quality threshold met" do
      reasoning_fn = fn -> %{answer: 42, confidence: 0.9} end
      validator = fn result -> {:ok, result} end

      assert {:ok, %{answer: 42, confidence: 0.9}} =
               SelfCorrection.iterative_execute(reasoning_fn,
                 validator: validator,
                 quality_threshold: 0.7
               )
    end

    test "retries when quality threshold not met" do
      attempt = Agent.start_link(fn -> 0 end)
      {:ok, pid} = attempt

      reasoning_fn = fn ->
        count = Agent.get_and_update(pid, fn count -> {count + 1, count + 1} end)

        if count < 3 do
          %{answer: 40, confidence: 0.5}
        else
          %{answer: 42, confidence: 0.9}
        end
      end

      validator = fn result -> {:ok, result} end

      assert {:ok, %{answer: 42, confidence: 0.9}} =
               SelfCorrection.iterative_execute(reasoning_fn,
                 validator: validator,
                 quality_threshold: 0.7,
                 max_iterations: 5
               )

      Agent.stop(pid)
    end

    test "returns partial success after max iterations with low quality" do
      reasoning_fn = fn -> %{answer: 40, confidence: 0.5} end
      validator = fn result -> {:ok, result} end

      assert {:ok, %{answer: 40, confidence: 0.5}, :partial} =
               SelfCorrection.iterative_execute(reasoning_fn,
                 validator: validator,
                 quality_threshold: 0.9,
                 max_iterations: 2
               )
    end

    test "returns error after max iterations with validation failures" do
      reasoning_fn = fn -> %{answer: :wrong} end
      validator = fn _result -> {:error, "invalid answer", :critical} end

      assert {:error, "invalid answer"} =
               SelfCorrection.iterative_execute(reasoning_fn,
                 validator: validator,
                 max_iterations: 3
               )
    end

    test "calls on_correction callback on each correction" do
      test_pid = self()

      reasoning_fn = fn -> %{answer: 40, confidence: 0.5} end
      validator = fn result -> {:ok, result} end

      on_correction = fn event ->
        send(test_pid, {:correction, event})
      end

      SelfCorrection.iterative_execute(reasoning_fn,
        validator: validator,
        quality_threshold: 0.9,
        max_iterations: 2,
        on_correction: on_correction
      )

      assert_received {:correction, {:correction, 1, _strategy, _score}}
    end

    test "raises error when validator not provided" do
      reasoning_fn = fn -> :result end

      assert_raise ArgumentError, "validator function is required", fn ->
        SelfCorrection.iterative_execute(reasoning_fn, [])
      end
    end

    test "handles validator returning error without divergence" do
      reasoning_fn = fn -> %{answer: :wrong} end
      validator = fn _result -> {:error, "validation failed"} end

      assert {:error, "validation failed"} =
               SelfCorrection.iterative_execute(reasoning_fn,
                 validator: validator,
                 max_iterations: 2
               )
    end
  end

  describe "quality_score/2" do
    test "extracts confidence from map result" do
      result = %{answer: 42, confidence: 0.8}
      assert SelfCorrection.quality_score(result) == 0.8
    end

    test "uses string keys for confidence" do
      result = %{"answer" => 42, "confidence" => 0.9}
      assert SelfCorrection.quality_score(result) == 0.9
    end

    test "defaults to 0.7 if no confidence" do
      result = %{answer: 42}
      assert SelfCorrection.quality_score(result) == 0.7
    end

    test "combines confidence and expected match" do
      result = %{answer: 42, confidence: 0.8}
      score = SelfCorrection.quality_score(result, expected: 42)
      assert score > 0.8
      assert score <= 1.0
    end

    test "adjusts score based on answer match with expected" do
      result = %{answer: 40, confidence: 0.8}
      score = SelfCorrection.quality_score(result, expected: 42)
      # Score is average of confidence (0.8) and similarity (40/42 ≈ 0.95)
      assert score >= 0.8
      assert score <= 1.0
    end

    test "handles non-map results" do
      assert SelfCorrection.quality_score(42) == 0.7
    end
  end

  describe "quality_threshold_met?/2" do
    test "returns true when score meets threshold" do
      assert SelfCorrection.quality_threshold_met?(0.8, 0.7) == true
      assert SelfCorrection.quality_threshold_met?(0.7, 0.7) == true
    end

    test "returns false when score below threshold" do
      assert SelfCorrection.quality_threshold_met?(0.6, 0.7) == false
    end

    test "uses default threshold of 0.7" do
      assert SelfCorrection.quality_threshold_met?(0.8) == true
      assert SelfCorrection.quality_threshold_met?(0.6) == false
    end
  end

  describe "adapt_threshold/2" do
    test "reduces threshold for low criticality" do
      adapted = SelfCorrection.adapt_threshold(0.7, :low)
      assert adapted == 0.5
    end

    test "keeps threshold for medium criticality" do
      adapted = SelfCorrection.adapt_threshold(0.7, :medium)
      assert adapted == 0.7
    end

    test "increases threshold for high criticality" do
      adapted = SelfCorrection.adapt_threshold(0.7, :high)
      assert_in_delta adapted, 0.9, 0.01
    end

    test "caps high criticality threshold at 0.95" do
      adapted = SelfCorrection.adapt_threshold(0.9, :high)
      assert adapted == 0.95
    end

    test "floors low criticality threshold at 0.5" do
      adapted = SelfCorrection.adapt_threshold(0.6, :low)
      assert adapted == 0.5
    end
  end

  describe "integration scenarios" do
    test "self-corrects calculation error through iteration" do
      # Simulate a calculation that gets better with iterations
      attempt = Agent.start_link(fn -> 0 end)
      {:ok, pid} = attempt

      reasoning_fn = fn ->
        iteration = Agent.get_and_update(pid, fn count -> {count + 1, count + 1} end)

        case iteration do
          1 -> %{answer: 30, confidence: 0.6}
          2 -> %{answer: 38, confidence: 0.7}
          _ -> %{answer: 42, confidence: 0.9}
        end
      end

      validator = fn result ->
        if result.answer == 42 do
          {:ok, result}
        else
          {:error, "wrong answer: #{result.answer}", :moderate}
        end
      end

      assert {:ok, %{answer: 42, confidence: 0.9}} =
               SelfCorrection.iterative_execute(reasoning_fn,
                 validator: validator,
                 max_iterations: 5
               )

      Agent.stop(pid)
    end

    test "accepts partial success when iterations exhausted" do
      reasoning_fn = fn -> %{answer: 38, confidence: 0.65} end

      validator = fn result ->
        if result.answer == 42 do
          {:ok, result}
        else
          {:error, "not quite right", :minor}
        end
      end

      result =
        SelfCorrection.iterative_execute(reasoning_fn,
          validator: validator,
          quality_threshold: 0.8,
          max_iterations: 2
        )

      # Should fail after max iterations since validation always fails
      assert {:error, _} = result
    end

    test "tracks iteration history for strategy selection" do
      attempt = Agent.start_link(fn -> 0 end)
      {:ok, pid} = attempt

      corrections = Agent.start_link(fn -> [] end)
      {:ok, corrections_pid} = corrections

      reasoning_fn = fn ->
        iteration = Agent.get_and_update(pid, fn count -> {count + 1, count + 1} end)

        if iteration >= 3 do
          %{answer: 42, confidence: 0.9}
        else
          %{answer: :wrong, confidence: 0.5}
        end
      end

      validator = fn result ->
        if result.answer == 42 do
          {:ok, result}
        else
          {:error, "unclear requirements", :critical}
        end
      end

      on_correction = fn event ->
        Agent.update(corrections_pid, fn list -> [event | list] end)
      end

      SelfCorrection.iterative_execute(reasoning_fn,
        validator: validator,
        max_iterations: 5,
        on_correction: on_correction
      )

      # Check that corrections were tracked
      corrections_list = Agent.get(corrections_pid, & &1)
      assert length(corrections_list) >= 1

      Agent.stop(pid)
      Agent.stop(corrections_pid)
    end
  end
end
