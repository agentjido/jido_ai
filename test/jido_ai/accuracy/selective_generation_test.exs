defmodule Jido.AI.Accuracy.SelectiveGenerationTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Candidate, ConfidenceEstimate, DecisionResult, SelectiveGeneration}

  @moduletag :capture_log

  describe "new/1" do
    test "creates with default values" do
      assert {:ok, sg} = SelectiveGeneration.new(%{})

      assert sg.reward == 1.0
      assert sg.penalty == 1.0
      assert sg.use_ev == true
      assert sg.confidence_threshold == nil
    end

    test "creates with custom reward and penalty" do
      assert {:ok, sg} = SelectiveGeneration.new(%{reward: 2.0, penalty: 5.0})

      assert sg.reward == 2.0
      assert sg.penalty == 5.0
    end

    test "creates with confidence threshold" do
      assert {:ok, sg} = SelectiveGeneration.new(%{confidence_threshold: 0.6})

      assert sg.confidence_threshold == 0.6
    end

    test "creates with use_ev false" do
      assert {:ok, sg} = SelectiveGeneration.new(%{use_ev: false})

      assert sg.use_ev == false
    end

    test "returns error for invalid reward" do
      assert {:error, :invalid_reward} = SelectiveGeneration.new(%{reward: -1.0})
      assert {:error, :invalid_reward} = SelectiveGeneration.new(%{reward: 0})
    end

    test "returns error for invalid penalty" do
      assert {:error, :invalid_penalty} = SelectiveGeneration.new(%{penalty: -1.0})
    end

    test "returns error for excessive reward" do
      assert {:error, :invalid_reward} = SelectiveGeneration.new(%{reward: 1001.0})
      assert {:error, :invalid_reward} = SelectiveGeneration.new(%{reward: 10_000.0})
    end

    test "returns error for excessive penalty" do
      assert {:error, :invalid_penalty} = SelectiveGeneration.new(%{penalty: 1001.0})
      assert {:error, :invalid_penalty} = SelectiveGeneration.new(%{penalty: 10_000.0})
    end

    test "accepts maximum allowed values" do
      assert {:ok, sg} = SelectiveGeneration.new(%{reward: 1000.0, penalty: 1000.0})
      assert sg.reward == 1000.0
      assert sg.penalty == 1000.0
    end

    test "returns error for invalid threshold" do
      assert {:error, :invalid_threshold} = SelectiveGeneration.new(%{confidence_threshold: 1.5})
      assert {:error, :invalid_threshold} = SelectiveGeneration.new(%{confidence_threshold: -0.1})
    end
  end

  describe "new!/1" do
    test "creates with valid attributes" do
      sg = SelectiveGeneration.new!(%{})
      assert sg.reward == 1.0
    end

    test "raises for invalid attributes" do
      assert_raise ArgumentError, ~r/Invalid/, fn ->
        SelectiveGeneration.new!(%{reward: -1.0})
      end
    end
  end

  describe "calculate_ev/2" do
    test "calculates EV for high confidence" do
      sg = SelectiveGeneration.new!(%{reward: 1.0, penalty: 1.0})

      {ev_answer, ev_abstain} = SelectiveGeneration.calculate_ev(sg, 0.8)

      # 0.8 * 1.0 - 0.2 * 1.0 = 0.6
      assert_in_delta ev_answer, 0.6, 0.001
      assert ev_abstain == 0.0
    end

    test "calculates EV for low confidence" do
      sg = SelectiveGeneration.new!(%{reward: 1.0, penalty: 1.0})

      {ev_answer, ev_abstain} = SelectiveGeneration.calculate_ev(sg, 0.3)

      # 0.3 * 1.0 - 0.7 * 1.0 = -0.4
      assert_in_delta ev_answer, -0.4, 0.001
      assert ev_abstain == 0.0
    end

    test "calculates EV for even confidence" do
      sg = SelectiveGeneration.new!(%{reward: 1.0, penalty: 1.0})

      {ev_answer, _ev_abstain} = SelectiveGeneration.calculate_ev(sg, 0.5)

      # 0.5 * 1.0 - 0.5 * 1.0 = 0.0
      assert_in_delta ev_answer, 0.0, 0.001
    end

    test "calculates EV with custom reward" do
      sg = SelectiveGeneration.new!(%{reward: 2.0, penalty: 1.0})

      {ev_answer, _ev_abstain} = SelectiveGeneration.calculate_ev(sg, 0.4)

      # 0.4 * 2.0 - 0.6 * 1.0 = 0.2
      assert_in_delta ev_answer, 0.2, 0.001
    end

    test "calculates EV with custom penalty" do
      sg = SelectiveGeneration.new!(%{reward: 1.0, penalty: 5.0})

      {ev_answer, _ev_abstain} = SelectiveGeneration.calculate_ev(sg, 0.7)

      # 0.7 * 1.0 - 0.3 * 5.0 = -0.8
      assert_in_delta ev_answer, -0.8, 0.001
    end
  end

  describe "answer_or_abstain/3" do
    setup do
      sg = SelectiveGeneration.new!(%{})
      candidate = Candidate.new!(%{content: "The answer is 42"})
      {:ok, sg: sg, candidate: candidate}
    end

    test "answers when confidence is high (positive EV)", context do
      estimate = ConfidenceEstimate.new!(%{score: 0.8, method: :test})

      assert {:ok, result} = SelectiveGeneration.answer_or_abstain(context.sg, context.candidate, estimate)

      assert result.decision == :answer
      assert DecisionResult.answered?(result)
      refute DecisionResult.abstained?(result)
      assert result.ev_answer > 0
    end

    test "abstains when confidence is low (negative EV)", context do
      estimate = ConfidenceEstimate.new!(%{score: 0.3, method: :test})

      assert {:ok, result} = SelectiveGeneration.answer_or_abstain(context.sg, context.candidate, estimate)

      assert result.decision == :abstain
      assert DecisionResult.abstained?(result)
      refute DecisionResult.answered?(result)
      assert result.ev_answer < 0
    end

    test "abstains when EV is exactly zero", context do
      estimate = ConfidenceEstimate.new!(%{score: 0.5, method: :test})

      assert {:ok, result} = SelectiveGeneration.answer_or_abstain(context.sg, context.candidate, estimate)

      # EV = 0.5*1 - 0.5*1 = 0.0, should abstain
      assert result.decision == :abstain
    end

    test "includes reasoning in result", context do
      estimate = ConfidenceEstimate.new!(%{score: 0.8, method: :test})

      assert {:ok, result} = SelectiveGeneration.answer_or_abstain(context.sg, context.candidate, estimate)

      assert is_binary(result.reasoning)
      assert String.contains?(result.reasoning, "Positive expected value")
    end

    test "generates abstention message for low confidence", context do
      estimate = ConfidenceEstimate.new!(%{score: 0.2, method: :test})

      assert {:ok, result} = SelectiveGeneration.answer_or_abstain(context.sg, context.candidate, estimate)

      assert String.contains?(result.candidate.content, "not confident enough")
      assert result.candidate.metadata.abstained == true
    end

    test "includes EV values in result", context do
      estimate = ConfidenceEstimate.new!(%{score: 0.8, method: :test})

      assert {:ok, result} = SelectiveGeneration.answer_or_abstain(context.sg, context.candidate, estimate)

      assert is_number(result.ev_answer)
      assert result.ev_abstain == 0.0
    end

    test "includes metadata with reward/penalty", context do
      estimate = ConfidenceEstimate.new!(%{score: 0.8, method: :test})

      assert {:ok, result} = SelectiveGeneration.answer_or_abstain(context.sg, context.candidate, estimate)

      assert result.metadata.reward == 1.0
      assert result.metadata.penalty == 1.0
    end
  end

  describe "answer_or_abstain/3 with custom reward/penalty" do
    test "answers with lower threshold when reward is high" do
      sg = SelectiveGeneration.new!(%{reward: 2.0, penalty: 1.0})
      candidate = Candidate.new!(%{content: "Test"})

      # With reward=2, penalty=1: 0.4*2 - 0.6*1 = 0.2 > 0, should answer
      estimate = ConfidenceEstimate.new!(%{score: 0.4, method: :test})

      assert {:ok, result} = SelectiveGeneration.answer_or_abstain(sg, candidate, estimate)

      assert result.decision == :answer
      assert result.ev_answer > 0
    end

    test "abstains with higher threshold when penalty is high" do
      sg = SelectiveGeneration.new!(%{reward: 1.0, penalty: 5.0})
      candidate = Candidate.new!(%{content: "Test"})

      # With reward=1, penalty=5: 0.7*1 - 0.3*5 = -0.8 < 0, should abstain
      estimate = ConfidenceEstimate.new!(%{score: 0.7, method: :test})

      assert {:ok, result} = SelectiveGeneration.answer_or_abstain(sg, candidate, estimate)

      assert result.decision == :abstain
      assert result.ev_answer < 0
    end
  end

  describe "answer_or_abstain/3 with confidence threshold" do
    test "uses threshold when use_ev is false" do
      sg = SelectiveGeneration.new!(%{use_ev: false, confidence_threshold: 0.6})
      candidate = Candidate.new!(%{content: "Test"})

      # Above threshold
      estimate_high = ConfidenceEstimate.new!(%{score: 0.7, method: :test})

      assert {:ok, result} = SelectiveGeneration.answer_or_abstain(sg, candidate, estimate_high)

      assert result.decision == :answer

      # Below threshold
      estimate_low = ConfidenceEstimate.new!(%{score: 0.5, method: :test})

      assert {:ok, result} = SelectiveGeneration.answer_or_abstain(sg, candidate, estimate_low)

      assert result.decision == :abstain
    end

    test "uses threshold at boundary" do
      sg = SelectiveGeneration.new!(%{use_ev: false, confidence_threshold: 0.5})
      candidate = Candidate.new!(%{content: "Test"})

      # At threshold - should answer
      estimate = ConfidenceEstimate.new!(%{score: 0.5, method: :test})

      assert {:ok, result} = SelectiveGeneration.answer_or_abstain(sg, candidate, estimate)

      assert result.decision == :answer
    end
  end

  describe "EV calculation examples" do
    test "correctly calculates various confidence levels with default settings" do
      sg = SelectiveGeneration.new!(%{reward: 1.0, penalty: 1.0})

      # From the doc examples
      test_cases = [
        # 0.9*1 - 0.1*1 = 0.8
        {0.9, 0.8},
        # 0.7*1 - 0.3*1 = 0.4
        {0.7, 0.4},
        # 0.5*1 - 0.5*1 = 0.0
        {0.5, 0.0},
        # 0.3*1 - 0.7*1 = -0.4
        {0.3, -0.4},
        # 0.1*1 - 0.9*1 = -0.8
        {0.1, -0.8}
      ]

      Enum.each(test_cases, fn {confidence, expected_ev} ->
        {ev_answer, _ev_abstain} = SelectiveGeneration.calculate_ev(sg, confidence)
        assert_in_delta ev_answer, expected_ev, 0.001
      end)
    end

    test "correctly calculates with high reward" do
      sg = SelectiveGeneration.new!(%{reward: 2.0, penalty: 1.0})

      # 0.4*2 - 0.6*1 = 0.2
      {ev_answer, _ev_abstain} = SelectiveGeneration.calculate_ev(sg, 0.4)
      assert_in_delta ev_answer, 0.2, 0.001
    end
  end

  describe "decision making with various penalties" do
    test "medical domain (high penalty)" do
      sg = SelectiveGeneration.new!(%{reward: 1.0, penalty: 10.0})
      candidate = Candidate.new!(%{content: "Medical advice"})

      # Even at 0.9 confidence: 0.9*1 - 0.1*10 = -0.1, should abstain
      estimate = ConfidenceEstimate.new!(%{score: 0.9, method: :test})

      assert {:ok, result} = SelectiveGeneration.answer_or_abstain(sg, candidate, estimate)

      assert result.decision == :abstain
      assert result.ev_answer < 0
    end

    test "creative domain (low penalty)" do
      sg = SelectiveGeneration.new!(%{reward: 1.0, penalty: 0.5})
      candidate = Candidate.new!(%{content: "Creative suggestion"})

      # At 0.4 confidence: 0.4*1 - 0.6*0.5 = 0.1, should answer
      estimate = ConfidenceEstimate.new!(%{score: 0.4, method: :test})

      assert {:ok, result} = SelectiveGeneration.answer_or_abstain(sg, candidate, estimate)

      assert result.decision == :answer
      assert result.ev_answer > 0
    end

    test "legal domain (very high penalty)" do
      sg = SelectiveGeneration.new!(%{reward: 1.0, penalty: 20.0})
      candidate = Candidate.new!(%{content: "Legal advice"})

      # At 0.95 confidence: 0.95*1 - 0.05*20 = -0.05, should abstain
      estimate = ConfidenceEstimate.new!(%{score: 0.95, method: :test})

      assert {:ok, result} = SelectiveGeneration.answer_or_abstain(sg, candidate, estimate)

      assert result.decision == :abstain
    end
  end

  describe "abstention message" do
    test "includes confidence and EV in abstention message" do
      sg = SelectiveGeneration.new!(%{})
      candidate = Candidate.new!(%{content: "Test"})
      estimate = ConfidenceEstimate.new!(%{score: 0.3, method: :test})

      assert {:ok, result} = SelectiveGeneration.answer_or_abstain(sg, candidate, estimate)

      content = result.candidate.content
      assert String.contains?(content, "Confidence:")
      assert String.contains?(content, "Expected value:")
    end

    test "includes suggestions in abstention message" do
      sg = SelectiveGeneration.new!(%{})
      candidate = Candidate.new!(%{content: "Test"})
      estimate = ConfidenceEstimate.new!(%{score: 0.2, method: :test})

      assert {:ok, result} = SelectiveGeneration.answer_or_abstain(sg, candidate, estimate)

      content = result.candidate.content
      assert String.contains?(content, "Rephrasing")
      assert String.contains?(content, "context")
    end
  end
end
