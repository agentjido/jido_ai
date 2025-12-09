defmodule Jido.AI.Runner.GEPA.Evaluation.Strategies.ClassificationEvaluatorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Evaluation.Strategies.ClassificationEvaluator

  describe "evaluate_classification/2" do
    test "evaluates classification with correct label and confidence" do
      response = """
      Classification: positive
      Confidence: 0.95
      """

      task = %{
        type: :classification,
        expected_label: "positive",
        valid_labels: ["positive", "negative", "neutral"],
        requires_confidence: true
      }

      metrics = ClassificationEvaluator.evaluate_classification(response, task)

      assert metrics.label_accuracy == 1.0
      assert metrics.valid_label == true
      assert metrics.confidence_score == 0.95
      assert metrics.confidence_calibration > 0.8
      assert metrics.extracted_label == "positive"
    end

    test "evaluates classification with correct label but no confidence" do
      response = "positive"

      task = %{
        type: :classification,
        expected_label: "positive",
        requires_confidence: false
      }

      metrics = ClassificationEvaluator.evaluate_classification(response, task)

      assert metrics.label_accuracy == 1.0
      assert metrics.confidence_score == nil
      assert metrics.confidence_calibration == 1.0
    end

    test "evaluates classification with incorrect label" do
      response = "negative"

      task = %{
        type: :classification,
        expected_label: "positive"
      }

      metrics = ClassificationEvaluator.evaluate_classification(response, task)

      assert metrics.label_accuracy == 0.0
    end

    test "penalizes missing confidence when required" do
      response = "positive"

      task = %{
        type: :classification,
        expected_label: "positive",
        requires_confidence: true
      }

      metrics = ClassificationEvaluator.evaluate_classification(response, task)

      assert metrics.confidence_calibration == 0.0
    end
  end

  describe "extract_label_and_confidence/1" do
    test "extracts label and confidence from standard format" do
      response = "Label: positive\nConfidence: 0.95"
      {label, confidence} = ClassificationEvaluator.extract_label_and_confidence(response)

      assert label == "positive"
      assert confidence == 0.95
    end

    test "extracts label and confidence from percentage format" do
      response = "positive - 85%"
      {label, confidence} = ClassificationEvaluator.extract_label_and_confidence(response)

      assert label == "positive"
      assert confidence == 0.85
    end

    test "extracts just label when no confidence present" do
      response = "Classification: negative"
      {label, confidence} = ClassificationEvaluator.extract_label_and_confidence(response)

      assert label == "negative"
      assert is_nil(confidence)
    end

    test "handles case-insensitive extraction" do
      response = "CLASSIFICATION: POSITIVE\nCONFIDENCE: 0.9"
      {label, confidence} = ClassificationEvaluator.extract_label_and_confidence(response)

      assert label == "positive"
      assert confidence == 0.9
    end
  end

  describe "extract_label_only/1" do
    test "extracts label from 'Label:' pattern" do
      response = "Label: positive"
      label = ClassificationEvaluator.extract_label_only(response)
      assert label == "positive"
    end

    test "extracts label from 'Classification:' pattern" do
      response = "Classification: negative"
      label = ClassificationEvaluator.extract_label_only(response)
      assert label == "negative"
    end

    test "extracts label from sentence pattern" do
      response = "The sentiment is neutral"
      label = ClassificationEvaluator.extract_label_only(response)
      assert label == "neutral"
    end

    test "handles single-word response" do
      response = "positive"
      label = ClassificationEvaluator.extract_label_only(response)
      assert label == "positive"
    end
  end

  describe "extract_confidence_only/1" do
    test "extracts confidence from explicit format" do
      response = "Confidence: 0.95"
      confidence = ClassificationEvaluator.extract_confidence_only(response)
      assert confidence == 0.95
    end

    test "extracts confidence from percentage" do
      response = "85%"
      confidence = ClassificationEvaluator.extract_confidence_only(response)
      assert confidence == 0.85
    end

    test "extracts confidence from decimal" do
      response = "The probability is 0.92"
      confidence = ClassificationEvaluator.extract_confidence_only(response)
      assert confidence == 0.92
    end

    test "returns nil when no confidence found" do
      response = "positive"
      confidence = ClassificationEvaluator.extract_confidence_only(response)
      assert is_nil(confidence)
    end
  end

  describe "normalize_label/1" do
    test "normalizes to lowercase" do
      assert ClassificationEvaluator.normalize_label("POSITIVE") == "positive"
    end

    test "removes whitespace" do
      assert ClassificationEvaluator.normalize_label("  positive  ") == "positive"
    end

    test "removes special characters" do
      assert ClassificationEvaluator.normalize_label("positive!") == "positive"
    end

    test "handles complex strings" do
      normalized = ClassificationEvaluator.normalize_label("  Positive! ")
      assert normalized == "positive"
    end

    test "returns empty string for nil" do
      assert ClassificationEvaluator.normalize_label(nil) == ""
    end
  end

  describe "parse_confidence/1" do
    test "parses decimal confidence (0-1 range)" do
      assert ClassificationEvaluator.parse_confidence("0.95") == 0.95
    end

    test "parses percentage confidence (converts to 0-1)" do
      assert ClassificationEvaluator.parse_confidence("85") == 0.85
    end

    test "handles edge case 0" do
      assert ClassificationEvaluator.parse_confidence("0") == 0.0
    end

    test "handles edge case 1" do
      assert ClassificationEvaluator.parse_confidence("1") == 1.0
    end

    test "handles edge case 100" do
      assert ClassificationEvaluator.parse_confidence("100") == 1.0
    end

    test "returns nil for invalid input" do
      assert is_nil(ClassificationEvaluator.parse_confidence("invalid"))
    end

    test "returns nil for out of range" do
      assert is_nil(ClassificationEvaluator.parse_confidence("150"))
    end
  end

  describe "check_label_accuracy/2" do
    test "returns 1.0 for exact match" do
      assert ClassificationEvaluator.check_label_accuracy("positive", "positive") == 1.0
    end

    test "returns 1.0 for case-insensitive match" do
      assert ClassificationEvaluator.check_label_accuracy("Positive", "positive") == 1.0
    end

    test "returns 0.7 for partial match" do
      accuracy = ClassificationEvaluator.check_label_accuracy("very positive", "positive")
      assert accuracy == 0.7
    end

    test "returns 0.9 for semantic equivalents" do
      accuracy = ClassificationEvaluator.check_label_accuracy("pos", "positive")
      assert accuracy == 0.9
    end

    test "returns 0.0 for wrong label" do
      assert ClassificationEvaluator.check_label_accuracy("positive", "negative") == 0.0
    end

    test "returns 0.5 when expected label is nil" do
      assert ClassificationEvaluator.check_label_accuracy("positive", nil) == 0.5
    end
  end

  describe "semantic_similarity/2" do
    test "detects pos/positive equivalence" do
      assert ClassificationEvaluator.semantic_similarity("pos", "positive") == true
    end

    test "detects neg/negative equivalence" do
      assert ClassificationEvaluator.semantic_similarity("neg", "negative") == true
    end

    test "detects neut/neutral equivalence" do
      assert ClassificationEvaluator.semantic_similarity("neut", "neutral") == true
    end

    test "returns false for non-equivalent labels" do
      assert ClassificationEvaluator.semantic_similarity("positive", "negative") == false
    end

    test "handles bidirectional equivalence" do
      assert ClassificationEvaluator.semantic_similarity("positive", "pos") == true
    end
  end

  describe "validate_label/2" do
    test "returns true when valid_labels is nil" do
      assert ClassificationEvaluator.validate_label("anything", nil) == true
    end

    test "returns true when valid_labels is empty" do
      assert ClassificationEvaluator.validate_label("anything", []) == true
    end

    test "returns true when label is in valid set" do
      assert ClassificationEvaluator.validate_label("positive", ["positive", "negative"]) == true
    end

    test "returns false when label is not in valid set" do
      assert ClassificationEvaluator.validate_label("unknown", ["positive", "negative"]) == false
    end

    test "handles case-insensitive validation" do
      assert ClassificationEvaluator.validate_label("Positive", ["positive", "negative"]) == true
    end
  end

  describe "assess_confidence_calibration/3" do
    test "returns 1.0 for perfect calibration" do
      calibration = ClassificationEvaluator.assess_confidence_calibration(0.95, 1.0, true)
      assert calibration == 1.0
    end

    test "returns high score for good calibration" do
      calibration = ClassificationEvaluator.assess_confidence_calibration(0.85, 1.0, true)
      assert calibration == 0.8
    end

    test "returns low score for poor calibration" do
      calibration = ClassificationEvaluator.assess_confidence_calibration(0.95, 0.0, true)
      assert calibration < 0.3
    end

    test "returns 1.0 when confidence not required and not provided" do
      calibration = ClassificationEvaluator.assess_confidence_calibration(nil, 1.0, false)
      assert calibration == 1.0
    end

    test "returns 0.0 when confidence required but not provided" do
      calibration = ClassificationEvaluator.assess_confidence_calibration(nil, 1.0, true)
      assert calibration == 0.0
    end

    test "handles overconfidence" do
      # High confidence but low accuracy
      calibration = ClassificationEvaluator.assess_confidence_calibration(0.9, 0.0, true)
      assert calibration < 0.5
    end

    test "handles underconfidence" do
      # Low confidence but high accuracy
      calibration = ClassificationEvaluator.assess_confidence_calibration(0.3, 1.0, true)
      assert calibration < 0.8
    end
  end

  describe "calculate_consistency/2" do
    test "returns high score for consistent positive classification" do
      response = "This is great and excellent"
      consistency = ClassificationEvaluator.calculate_consistency(response, "positive")
      assert consistency == 1.0
    end

    test "returns high score for consistent negative classification" do
      response = "This is terrible and bad"
      consistency = ClassificationEvaluator.calculate_consistency(response, "negative")
      assert consistency == 1.0
    end

    test "returns low score for inconsistent classification" do
      response = "This is terrible and bad"
      consistency = ClassificationEvaluator.calculate_consistency(response, "positive")
      assert consistency == 0.3
    end

    test "returns medium score when no strong indicators" do
      response = "This is something"
      consistency = ClassificationEvaluator.calculate_consistency(response, "neutral")
      assert consistency == 0.6
    end
  end

  describe "calculate_classification_fitness/2" do
    test "calculates fitness with perfect scores" do
      metrics = %{
        label_accuracy: 1.0,
        confidence_calibration: 1.0,
        classification_consistency: 1.0
      }

      fitness = ClassificationEvaluator.calculate_classification_fitness(0.8, metrics)

      # Should be: 0.7*1.0 + 0.2*1.0 + 0.1*1.0 = 1.0
      assert_in_delta fitness, 1.0, 0.01
    end

    test "calculates fitness with correct label but poor calibration" do
      metrics = %{
        label_accuracy: 1.0,
        confidence_calibration: 0.0,
        classification_consistency: 1.0
      }

      fitness = ClassificationEvaluator.calculate_classification_fitness(0.8, metrics)

      # Should be: 0.7*1.0 + 0.2*0.0 + 0.1*1.0 = 0.8
      assert_in_delta fitness, 0.8, 0.01
    end

    test "calculates fitness with wrong label but good calibration" do
      metrics = %{
        label_accuracy: 0.0,
        confidence_calibration: 1.0,
        classification_consistency: 0.8
      }

      fitness = ClassificationEvaluator.calculate_classification_fitness(0.8, metrics)

      # Should be: 0.7*0.0 + 0.2*1.0 + 0.1*0.8 = 0.28
      assert_in_delta fitness, 0.28, 0.01
    end

    test "prioritizes label accuracy over other factors" do
      perfect_accuracy = %{
        label_accuracy: 1.0,
        confidence_calibration: 0.0,
        classification_consistency: 0.0
      }

      poor_accuracy = %{
        label_accuracy: 0.0,
        confidence_calibration: 1.0,
        classification_consistency: 1.0
      }

      fitness_perfect =
        ClassificationEvaluator.calculate_classification_fitness(0.5, perfect_accuracy)

      fitness_poor = ClassificationEvaluator.calculate_classification_fitness(0.5, poor_accuracy)

      # Correct label (0.7) should score higher than perfect calibration+consistency (0.3)
      assert fitness_perfect > fitness_poor
    end
  end
end
