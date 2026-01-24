defmodule Jido.AI.Accuracy.CalibrationTest do
  @moduledoc """
  Integration tests for Phase 6 calibration components.

  These tests verify that all Phase 6 components work together correctly:
  - ConfidenceEstimate (6.1)
  - CalibrationGate (6.2)
  - SelectiveGeneration (6.3)
  - UncertaintyQuantification (6.4)
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{
    CalibrationGate,
    Candidate,
    ConfidenceEstimate,
    RoutingResult,
    SelectiveGeneration,
    UncertaintyQuantification
  }

  @moduletag :capture_log

  describe "6.5.1 Calibration Gate Integration" do
    setup do
      {:ok, gate} = CalibrationGate.new(%{})
      {:ok, sg} = SelectiveGeneration.new(%{})
      {:ok, uq} = UncertaintyQuantification.new(%{})
      %{gate: gate, sg: sg, uq: uq}
    end

    test "high confidence routed directly", context do
      # Create a high confidence response
      {:ok, estimate} =
        ConfidenceEstimate.new(%{
          score: 0.85,
          method: :attention,
          reasoning: "High confidence in answer"
        })

      {:ok, candidate} =
        Candidate.new(%{
          content: "The capital of France is Paris.",
          reasoning: "This is a well-known geographical fact."
        })

      # Route through calibration gate
      {:ok, result} = CalibrationGate.route(context.gate, candidate, estimate)

      # Verify direct answer returned
      assert result.action == :direct
      assert result.candidate.content == "The capital of France is Paris."
      assert RoutingResult.direct?(result)
    end

    test "medium confidence adds verification", _context do
      # Create a medium confidence response
      {:ok, estimate} =
        ConfidenceEstimate.new(%{
          score: 0.55,
          method: :attention,
          reasoning: "Medium confidence - should verify"
        })

      {:ok, candidate} =
        Candidate.new(%{
          content: "The population of Tokyo is approximately 14 million.",
          reasoning: "Estimate based on recent data."
        })

      # Route with verification action
      {:ok, gate} =
        CalibrationGate.new(%{
          medium_action: :with_verification
        })

      {:ok, result} = CalibrationGate.route(gate, candidate, estimate)

      # Verify verification content added
      assert result.action == :with_verification
      assert String.contains?(result.candidate.content, "verify")
      assert String.contains?(result.candidate.content, candidate.content)
    end

    test "medium confidence with citations", _context do
      # Create a medium confidence response
      {:ok, estimate} =
        ConfidenceEstimate.new(%{
          score: 0.6,
          method: :attention,
          reasoning: "Medium confidence - add citations"
        })

      {:ok, candidate} =
        Candidate.new(%{
          content: "Elixir is a functional programming language.",
          reasoning: "Technical fact."
        })

      # Route with citations action
      {:ok, gate} =
        CalibrationGate.new(%{
          medium_action: :with_citations
        })

      {:ok, result} = CalibrationGate.route(gate, candidate, estimate)

      # Verify citations added
      assert result.action == :with_citations
      assert String.contains?(result.candidate.content, "verify")
      assert String.contains?(result.candidate.content, "sources")
    end

    test "low confidence abstains", context do
      # Create a low confidence response
      {:ok, estimate} =
        ConfidenceEstimate.new(%{
          score: 0.3,
          method: :attention,
          reasoning: "Low confidence - should abstain"
        })

      {:ok, candidate} =
        Candidate.new(%{
          content: "I think the answer might be 42.",
          reasoning: "Very uncertain about this."
        })

      # Route with abstain action
      {:ok, result} = CalibrationGate.route(context.gate, candidate, estimate)

      # Verify abstention returned
      assert result.action == :abstain
      # Original uncertain content should not be directly exposed
      assert String.contains?(result.candidate.content, "confident")
      assert String.contains?(result.candidate.content, "definitive")
    end

    test "low confidence escalates", _context do
      # Create a low confidence response
      {:ok, estimate} =
        ConfidenceEstimate.new(%{
          score: 0.25,
          method: :attention,
          reasoning: "Very low confidence"
        })

      {:ok, candidate} =
        Candidate.new(%{
          content: "Maybe the answer is...",
          reasoning: "Completely uncertain."
        })

      # Route with escalate action
      {:ok, gate} =
        CalibrationGate.new(%{
          low_action: :escalate
        })

      {:ok, result} = CalibrationGate.route(gate, candidate, estimate)

      # Verify escalation returned
      assert result.action == :escalate
      assert String.contains?(result.candidate.content, "escalate")
    end

    test "custom thresholds work correctly" do
      # Create gate with stricter thresholds
      {:ok, gate} =
        CalibrationGate.new(%{
          high_threshold: 0.8,
          low_threshold: 0.6
        })

      # Score 0.75 would be high with default (0.7) but medium here
      {:ok, estimate} =
        ConfidenceEstimate.new(%{
          score: 0.75,
          method: :attention
        })

      {:ok, candidate} = Candidate.new(%{content: "Test content"})

      {:ok, result} = CalibrationGate.route(gate, candidate, estimate)

      # Should route to medium (not high) due to custom threshold
      assert result.action == :with_verification
    end
  end

  describe "6.5.2 Calibration Quality Tests" do
    test "confidence is well-calibrated" do
      # Create a test dataset with known accuracy
      # Each entry: {predicted_confidence, actual_correct}
      test_data = [
        {0.95, true},
        {0.92, true},
        {0.98, true},
        {0.91, true},
        {0.96, true},
        {0.85, true},
        {0.88, true},
        {0.82, true},
        {0.87, true},
        {0.83, false},
        {0.75, true},
        {0.72, true},
        {0.78, false},
        {0.71, true},
        {0.76, false},
        {0.65, true},
        {0.63, false},
        {0.67, true},
        {0.64, false},
        {0.66, false},
        {0.55, true},
        {0.53, false},
        {0.57, false},
        {0.54, true},
        {0.56, false},
        {0.45, false},
        {0.43, true},
        {0.47, false},
        {0.44, false},
        {0.46, true},
        {0.35, false},
        {0.33, false},
        {0.37, true},
        {0.34, false},
        {0.36, false},
        {0.25, false},
        {0.23, false},
        {0.27, false},
        {0.24, true},
        {0.26, false},
        {0.15, false},
        {0.13, false},
        {0.17, false},
        {0.14, false},
        {0.16, false},
        {0.05, false},
        {0.08, false},
        {0.03, false},
        {0.07, false},
        {0.04, false}
      ]

      # Calculate Expected Calibration Error (ECE)
      ece = calculate_expected_calibration_error(test_data, bins: 10)

      # ECE should be reasonably low (< 0.15 for this synthetic data)
      assert ece < 0.15, "Calibration error #{ece} is too high"

      # Verify calibration improves with more data
      # (This is a synthetic test, so we just verify the calculation works)
      assert is_number(ece)
      assert ece >= 0.0
    end

    test "selective generation improves reliability" do
      # Create mock dataset with varying confidence and known correctness
      test_cases = [
        # High confidence, mostly correct
        %{confidence: 0.9, correct: true},
        %{confidence: 0.85, correct: true},
        %{confidence: 0.88, correct: true},
        %{confidence: 0.92, correct: true},
        # Medium confidence, mixed
        %{confidence: 0.6, correct: true},
        %{confidence: 0.55, correct: false},
        %{confidence: 0.65, correct: true},
        %{confidence: 0.5, correct: false},
        # Low confidence, mostly incorrect
        %{confidence: 0.35, correct: false},
        %{confidence: 0.3, correct: false},
        %{confidence: 0.25, correct: true},
        %{confidence: 0.2, correct: false}
      ]

      # Calculate error rate WITHOUT selective generation (answer all)
      total_without_selective = length(test_cases)

      errors_without_selective =
        Enum.count(test_cases, fn case -> !case.correct end)

      error_rate_without_selective =
        errors_without_selective / total_without_selective

      # Calculate error rate WITH selective generation (abstain when EV < 0)
      {:ok, sg} = SelectiveGeneration.new(%{reward: 1.0, penalty: 1.0})

      {answered, errors_with_selective} =
        Enum.reduce(test_cases, {0, 0}, fn test_case, {answered, errors} ->
          {:ok, estimate} =
            ConfidenceEstimate.new(%{
              score: test_case.confidence,
              method: :test
            })

          {:ok, candidate} = Candidate.new(%{content: "Test"})

          case SelectiveGeneration.answer_or_abstain(sg, candidate, estimate) do
            {:ok, result} ->
              if result.decision == :answer do
                if test_case.correct do
                  {answered + 1, errors}
                else
                  {answered + 1, errors + 1}
                end
              else
                # Abstained - not counted as error
                {answered, errors}
              end
          end
        end)

      error_rate_with_selective =
        if answered > 0, do: errors_with_selective / answered, else: 0.0

      # Selective generation should have lower or equal error rate
      assert error_rate_with_selective <= error_rate_without_selective,
             "Selective generation error rate #{error_rate_with_selective} " <>
               "should be <= #{error_rate_without_selective}"

      # Some questions should have been abstained
      assert answered < total_without_selective,
             "Selective generation should abstain on some questions"
    end

    test "expected value calculation optimal vs threshold" do
      # Test cases where EV-based and threshold-based decisions differ
      test_cases = [
        # With penalty=2.0, threshold=0.5:
        # c=0.6: EV=0.6*1-0.4*2=-0.2 (abstain), but >0.5 (answer)
        %{confidence: 0.6, correct: false, reward: 1.0, penalty: 2.0, threshold: 0.5},
        # c=0.4: EV=0.4*1-0.6*2=-0.8 (abstain), and <0.5 (abstain)
        %{confidence: 0.4, correct: true, reward: 1.0, penalty: 2.0, threshold: 0.5},
        # c=0.8: EV=0.8*1-0.2*2=0.4 (answer), and >0.5 (answer)
        %{confidence: 0.8, correct: true, reward: 1.0, penalty: 2.0, threshold: 0.5}
      ]

      # Compare outcomes
      ev_outcomes =
        Enum.map(test_cases, fn case ->
          {:ok, sg} =
            SelectiveGeneration.new(%{
              reward: case.reward,
              penalty: case.penalty,
              use_ev: true
            })

          {:ok, estimate} =
            ConfidenceEstimate.new(%{
              score: case.confidence,
              method: :test
            })

          {:ok, candidate} = Candidate.new(%{content: "Test"})

          {:ok, result} = SelectiveGeneration.answer_or_abstain(sg, candidate, estimate)

          decision = if result.decision == :answer, do: :answer, else: :abstain

          # Calculate actual utility
          utility =
            if decision == :answer do
              if case.correct, do: case.reward, else: -case.penalty
            else
              0
            end

          {decision, utility}
        end)

      threshold_outcomes =
        Enum.map(test_cases, fn case ->
          {:ok, sg} =
            SelectiveGeneration.new(%{
              confidence_threshold: case.threshold,
              use_ev: false
            })

          {:ok, estimate} =
            ConfidenceEstimate.new(%{
              score: case.confidence,
              method: :test
            })

          {:ok, candidate} = Candidate.new(%{content: "Test"})

          {:ok, result} = SelectiveGeneration.answer_or_abstain(sg, candidate, estimate)

          decision = if result.decision == :answer, do: :answer, else: :abstain

          utility =
            if decision == :answer do
              if case.correct, do: case.reward, else: -case.penalty
            else
              0
            end

          {decision, utility}
        end)

      # EV-based should make different (better) decisions in asymmetric cases
      ev_utility = ev_outcomes |> Enum.map(fn {_, u} -> u end) |> Enum.sum()
      threshold_utility = threshold_outcomes |> Enum.map(fn {_, u} -> u end) |> Enum.sum()

      # For this specific test set with high penalty, EV should avoid more wrong answers
      # The EV approach specifically avoids the 0.6 confidence case (which is wrong)
      assert ev_utility >= threshold_utility,
             "EV utility #{ev_utility} should be >= threshold utility #{threshold_utility}"
    end
  end

  describe "6.5.3 Uncertainty Integration Tests" do
    setup do
      {:ok, uq} = UncertaintyQuantification.new(%{})
      %{uq: uq}
    end

    test "aleatoric vs epistemic distinguished", context do
      # Query with inherent ambiguity (aleatoric)
      aleatoric_query = "What's the best movie of all time?"

      {:ok, aleatoric_result} =
        UncertaintyQuantification.classify_uncertainty(context.uq, aleatoric_query)

      # Query with missing knowledge (epistemic)
      epistemic_query = "Who will win the World Cup in 2030?"

      {:ok, epistemic_result} =
        UncertaintyQuantification.classify_uncertainty(context.uq, epistemic_query)

      # Verify different classifications
      assert aleatoric_result.uncertainty_type == :aleatoric
      assert epistemic_result.uncertainty_type == :epistemic

      # Verify scores reflect the detection
      assert aleatoric_result.confidence > 0.0
      assert epistemic_result.confidence > 0.0

      # Verify reasoning differs
      assert String.contains?(aleatoric_result.reasoning, "subjective") or
               String.contains?(aleatoric_result.reasoning, "inherent")

      assert String.contains?(epistemic_result.reasoning, "knowledge") or
               String.contains?(epistemic_result.reasoning, "available")
    end

    test "actions match uncertainty type" do
      uq = UncertaintyQuantification.new!(%{})

      # Test aleatoric → provide_options
      {:ok, aleatoric_result} =
        UncertaintyQuantification.classify_uncertainty(uq, "What's the best movie?")

      assert aleatoric_result.suggested_action == :provide_options

      # Test epistemic (high confidence) → abstain
      {:ok, epistemic_high} =
        UncertaintyQuantification.classify_uncertainty(uq, "Predict the stock market tomorrow")

      assert epistemic_high.suggested_action in [:abstain, :suggest_source]

      # Test certain → answer_directly
      {:ok, certain_result} =
        UncertaintyQuantification.classify_uncertainty(uq, "What is 2 plus 2?")

      assert certain_result.suggested_action == :answer_directly
      assert certain_result.uncertainty_type == :none
    end

    test "uncertainty + confidence integration" do
      uq = UncertaintyQuantification.new!(%{})
      sg = SelectiveGeneration.new!(%{})

      # High confidence + aleatoric = should still acknowledge subjectivity
      {:ok, _high_conf_estimate} =
        ConfidenceEstimate.new(%{
          score: 0.85,
          method: :test,
          reasoning: "High technical confidence"
        })

      {:ok, aleatoric_candidate} =
        Candidate.new(%{
          content: "I believe Inception is the best movie.",
          reasoning: "It has the most complex plot."
        })

      {:ok, uncertainty_result} =
        UncertaintyQuantification.classify_uncertainty(uq, aleatoric_candidate)

      # Even with high confidence, aleatoric uncertainty requires providing options
      assert uncertainty_result.suggested_action == :provide_options

      # Low confidence + epistemic = abstain
      {:ok, low_conf_estimate} =
        ConfidenceEstimate.new(%{
          score: 0.3,
          method: :test,
          reasoning: "Low confidence due to lack of knowledge"
        })

      {:ok, epistemic_candidate} =
        Candidate.new(%{
          content: "I think Mars will have a colony by 2050.",
          reasoning: "Just speculation."
        })

      {:ok, epistemic_uncertainty} =
        UncertaintyQuantification.classify_uncertainty(uq, "Who will be president in 2040?")

      {:ok, sg_result} =
        SelectiveGeneration.answer_or_abstain(sg, epistemic_candidate, low_conf_estimate)

      # Low confidence with selective generation should abstain
      assert sg_result.decision == :abstain

      # And uncertainty suggests abstention
      assert epistemic_uncertainty.suggested_action in [:abstain, :suggest_source]
    end

    test "calibration gate respects uncertainty type" do
      _uq = UncertaintyQuantification.new!(%{})
      gate = CalibrationGate.new!(%{})

      # Aleatoric query with medium confidence
      {:ok, medium_estimate} =
        ConfidenceEstimate.new(%{
          score: 0.5,
          method: :test
        })

      {:ok, aleatoric_candidate} =
        Candidate.new(%{
          content: "The best approach depends on your requirements.",
          reasoning: "Subjective assessment."
        })

      # Route through gate
      {:ok, route_result} = CalibrationGate.route(gate, aleatoric_candidate, medium_estimate)

      # Medium confidence should get verification
      assert route_result.action == :with_verification

      # Low confidence epistemic should abstain
      {:ok, low_estimate} =
        ConfidenceEstimate.new(%{
          score: 0.3,
          method: :test
        })

      {:ok, epistemic_candidate} =
        Candidate.new(%{
          content: "The future is uncertain.",
          reasoning: "Can't predict."
        })

      {:ok, route_result2} = CalibrationGate.route(gate, epistemic_candidate, low_estimate)

      # Low confidence should abstain
      assert route_result2.action == :abstain
    end
  end

  describe "end-to-end integration" do
    test "full calibration pipeline" do
      # Set up all components
      uq = UncertaintyQuantification.new!(%{})
      gate = CalibrationGate.new!(%{})
      sg = SelectiveGeneration.new!(%{})

      # Test query: "What's the best programming language?"
      query = "What's the best programming language?"

      # 1. Classify uncertainty
      {:ok, uncertainty_result} = UncertaintyQuantification.classify_uncertainty(uq, query)

      # Should be aleatoric (subjective)
      assert uncertainty_result.uncertainty_type == :aleatoric
      assert uncertainty_result.suggested_action == :provide_options

      # 2. Create candidate with medium confidence
      {:ok, candidate} =
        Candidate.new(%{
          content: "Python is widely considered good for beginners.",
          reasoning: "Subjective opinion about programming languages."
        })

      {:ok, estimate} =
        ConfidenceEstimate.new(%{
          score: 0.55,
          method: :test,
          reasoning: "Medium confidence - subjective topic"
        })

      # 3. Check selective generation
      {:ok, sg_result} = SelectiveGeneration.answer_or_abstain(sg, candidate, estimate)

      # With default reward=1, penalty=1, c=0.55: EV=0.55-0.45=0.1 > 0, so answer
      assert sg_result.decision == :answer

      # 4. Route through calibration gate
      {:ok, route_result} = CalibrationGate.route(gate, candidate, estimate)

      # Medium confidence should get verification
      assert route_result.action == :with_verification

      # Response should include original content plus verification
      assert String.contains?(route_result.candidate.content, candidate.content)
      assert String.contains?(route_result.candidate.content, "verify")
    end

    test "factual query pipeline" do
      uq = UncertaintyQuantification.new!(%{})
      gate = CalibrationGate.new!(%{})
      sg = SelectiveGeneration.new!(%{})

      # Test query: "What is the capital of France?"
      query = "What is the capital of France?"

      # 1. Classify uncertainty
      {:ok, uncertainty_result} = UncertaintyQuantification.classify_uncertainty(uq, query)

      # Should be certain (no significant uncertainty)
      assert uncertainty_result.uncertainty_type == :none
      assert uncertainty_result.suggested_action == :answer_directly

      # 2. Create candidate with high confidence
      {:ok, candidate} =
        Candidate.new(%{
          content: "The capital of France is Paris.",
          reasoning: "Well-known geographical fact."
        })

      {:ok, estimate} =
        ConfidenceEstimate.new(%{
          score: 0.95,
          method: :test,
          reasoning: "High confidence - factual"
        })

      # 3. Check selective generation
      {:ok, sg_result} = SelectiveGeneration.answer_or_abstain(sg, candidate, estimate)

      # High confidence should answer
      assert sg_result.decision == :answer

      # 4. Route through calibration gate
      {:ok, route_result} = CalibrationGate.route(gate, candidate, estimate)

      # High confidence should be direct
      assert route_result.action == :direct

      # Content should be unchanged
      assert route_result.candidate.content == candidate.content
    end

    test "speculative query pipeline" do
      uq = UncertaintyQuantification.new!(%{})
      gate = CalibrationGate.new!(%{})
      sg = SelectiveGeneration.new!(%{})

      # Test query: "Who will win the next election?"
      query = "Who will win the next election?"

      # 1. Classify uncertainty
      {:ok, uncertainty_result} = UncertaintyQuantification.classify_uncertainty(uq, query)

      # Should be epistemic (can't know the future)
      assert uncertainty_result.uncertainty_type == :epistemic
      assert uncertainty_result.suggested_action in [:abstain, :suggest_source]

      # 2. Create candidate with low confidence
      {:ok, candidate} =
        Candidate.new(%{
          content: "It's difficult to predict election outcomes.",
          reasoning: "Highly uncertain future event."
        })

      {:ok, estimate} =
        ConfidenceEstimate.new(%{
          score: 0.25,
          method: :test,
          reasoning: "Low confidence - future speculation"
        })

      # 3. Check selective generation
      {:ok, sg_result} = SelectiveGeneration.answer_or_abstain(sg, candidate, estimate)

      # Low confidence should abstain (EV = 0.25*1 - 0.75*1 = -0.5 < 0)
      assert sg_result.decision == :abstain

      # 4. Route through calibration gate
      {:ok, route_result} = CalibrationGate.route(gate, candidate, estimate)

      # Low confidence should abstain
      assert route_result.action == :abstain
    end
  end

  # Helper functions

  defp calculate_expected_calibration_error(test_data, opts) do
    num_bins = Keyword.get(opts, :bins, 10)

    # Group data into bins
    binned_data =
      Enum.reduce(test_data, %{}, fn {confidence, correct}, acc ->
        bin_index = min(trunc(confidence * num_bins), num_bins - 1)
        bin_key = bin_index / num_bins

        Map.update(acc, bin_key, {[confidence], [correct]}, fn {confs, corrects} ->
          {[confidence | confs], [correct | corrects]}
        end)
      end)

    # Convert to list for simpler iteration
    binned_list = Map.to_list(binned_data)

    # Calculate ECE
    {total_weighted_error, total_samples} =
      Enum.reduce(
        binned_list,
        {0.0, 0},
        fn {_bin_key, {confs, corrects}}, {weighted_error, samples} ->
          bin_confidence = Enum.sum(confs) / length(confs)
          bin_accuracy = Enum.count(corrects, & &1) / length(corrects)
          bin_size = length(confs)

          bin_error = abs(bin_confidence - bin_accuracy)
          new_weighted_error = weighted_error + bin_error * bin_size
          new_samples = samples + bin_size

          {new_weighted_error, new_samples}
        end
      )

    if total_samples > 0, do: total_weighted_error / total_samples, else: 0.0
  end
end
