defmodule Jido.AI.Runner.GEPA.Evaluation.Strategies.ClassificationEvaluator do
  @moduledoc """
  Classification task evaluator for GEPA.

  Evaluates prompts for text classification and categorization tasks by:
  1. Generating a classification response
  2. Extracting label and confidence
  3. Validating label correctness
  4. Assessing confidence calibration
  5. Calculating classification-specific metrics

  ## Task Configuration

      task: %{
        type: :classification,
        text: "This movie was absolutely terrible!",
        expected_label: "negative",
        valid_labels: ["positive", "negative", "neutral"],  # optional
        requires_confidence: true,  # whether confidence score is required
        test_cases: [
          %{input: "Great product!", expected: "positive"},
          %{input: "Worst experience ever", expected: "negative"}
        ]
      }

  ## Evaluation Process

  1. **Response Generation**: Use LLM with prompt to generate classification
  2. **Label Extraction**: Extract classification label and confidence (if provided)
  3. **Label Validation**: Check if label is in valid set (if provided)
  4. **Accuracy Check**: Compare label to expected result
  5. **Confidence Calibration**: Assess if confidence matches accuracy
  6. **Metric Calculation**:
     - Label accuracy: label matches expected (0-1)
     - Confidence calibration: confidence aligns with correctness (0-1)
     - Consistency: similar inputs get similar labels (0-1)
     - Fitness: weighted combination (70% accuracy, 20% calibration, 10% consistency)

  ## Metrics

  - **label_accuracy**: Classification label matches expected (0-1)
  - **confidence_calibration**: Confidence score matches actual accuracy (0-1)
  - **classification_consistency**: Consistency score for similar inputs (0-1)
  - **valid_label**: Label is in valid set (boolean)
  - **confidence_score**: Extracted confidence value (0-1, or nil)
  - **fitness**: Overall score incorporating all metrics
  """

  require Logger

  alias Jido.AI.Runner.GEPA.Evaluator

  @type task_config :: map()
  @type prompt :: String.t()
  @type evaluation_result :: Evaluator.EvaluationResult.t()

  @doc """
  Evaluates a prompt for classification tasks.

  Generates a classification using the LLM, extracts label and confidence,
  validates correctness, and calculates classification-specific fitness metrics.

  ## Examples

      ClassificationEvaluator.evaluate_prompt(
        "Classify the sentiment: This movie was great!",
        task: %{
          type: :classification,
          expected_label: "positive",
          valid_labels: ["positive", "negative", "neutral"]
        }
      )
  """
  @spec evaluate_prompt(prompt(), keyword()) :: {:ok, evaluation_result()} | {:error, term()}
  def evaluate_prompt(prompt, opts) when is_binary(prompt) and is_list(opts) do
    task = Keyword.get(opts, :task, %{})

    Logger.debug(
      "Classification evaluation starting (valid_labels: #{length(task[:valid_labels] || [])}, requires_confidence: #{task[:requires_confidence]})"
    )

    # First, do generic evaluation to get LLM response
    case Evaluator.evaluate_prompt(prompt, opts) do
      {:ok, generic_result} ->
        # Extract classification response
        classification_response = extract_response_from_result(generic_result)

        # Perform classification-specific evaluation
        classification_metrics = evaluate_classification(classification_response, task)

        # Combine generic and classification-specific metrics
        enhanced_result =
          enhance_result_with_classification_metrics(generic_result, classification_metrics)

        Logger.debug(
          "Classification evaluation complete (accuracy: #{classification_metrics.label_accuracy}, valid: #{classification_metrics.valid_label})"
        )

        {:ok, enhanced_result}

      {:error, reason} = error ->
        Logger.warning("Classification evaluation failed during generation: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Evaluates multiple prompts in batch for classification tasks.
  """
  @spec evaluate_batch(list(prompt()), keyword()) :: list(evaluation_result())
  def evaluate_batch(prompts, opts) when is_list(prompts) and is_list(opts) do
    Logger.info("Batch classification evaluation for #{length(prompts)} prompts")

    # Use generic batch evaluation, then enhance each result
    generic_results = Evaluator.evaluate_batch(prompts, opts)
    task = Keyword.get(opts, :task, %{})

    Enum.map(generic_results, fn result ->
      if is_nil(result.error) do
        classification_response = extract_response_from_result(result)
        classification_metrics = evaluate_classification(classification_response, task)
        enhance_result_with_classification_metrics(result, classification_metrics)
      else
        # Keep error results as-is
        result
      end
    end)
  end

  # Private Functions

  @doc false
  @spec extract_response_from_result(evaluation_result()) :: String.t()
  defp extract_response_from_result(%Evaluator.EvaluationResult{} = result) do
    cond do
      # Check if trajectory has response data
      result.trajectory && result.trajectory.metadata[:response] ->
        to_string(result.trajectory.metadata[:response])

      # Check metrics for response data
      result.metrics[:response_data] ->
        to_string(result.metrics[:response_data])

      # Fallback to empty response
      true ->
        Logger.warning("Could not extract response from evaluation result")
        ""
    end
  end

  @doc false
  def evaluate_classification(response, task) do
    # Extract label and confidence from response
    {extracted_label, confidence_score} = extract_label_and_confidence(response)

    # Check label accuracy
    label_accuracy = check_label_accuracy(extracted_label, task[:expected_label])

    # Validate label against valid set
    valid_label = validate_label(extracted_label, task[:valid_labels])

    # Assess confidence calibration
    confidence_calibration =
      assess_confidence_calibration(confidence_score, label_accuracy, task[:requires_confidence])

    # Calculate consistency (heuristic for now)
    classification_consistency = calculate_consistency(response, extracted_label)

    %{
      label_accuracy: label_accuracy,
      confidence_calibration: confidence_calibration,
      classification_consistency: classification_consistency,
      valid_label: valid_label,
      extracted_label: extracted_label,
      confidence_score: confidence_score,
      response: response
    }
  end

  @doc false
  def extract_label_and_confidence(response) do
    # Try to extract both label and confidence
    # Common patterns:
    # "Label: positive (Confidence: 0.95)"
    # "Classification: negative\nConfidence: 0.8"
    # "positive - 95%"
    # Just "positive"

    # Try pattern with explicit confidence
    case Regex.run(
           ~r/(?:label|classification|category):\s*(\w+).*?(?:confidence|probability|certainty):\s*([0-9.]+)/is,
           response
         ) do
      [_, label, conf] ->
        {normalize_label(label), parse_confidence(conf)}

      nil ->
        # Try percentage pattern
        case Regex.run(~r/(\w+)\s*[-–]\s*([0-9]+)%/i, response) do
          [_, label, percent] ->
            {normalize_label(label), parse_confidence(percent)}

          nil ->
            # Try just label with separate confidence
            label = extract_label_only(response)
            confidence = extract_confidence_only(response)
            {label, confidence}
        end
    end
  end

  @doc false
  def extract_label_only(response) do
    # Try to extract just the label
    patterns = [
      # "Label: positive" or "Classification: negative"
      ~r/(?:label|classification|category):\s*(\w+)/i,
      # "The sentiment is positive"
      ~r/(?:sentiment|classification)\s+(?:is|:)\s*(\w+)/i,
      # First word that looks like a label
      ~r/^(\w+)$/m
    ]

    label =
      Enum.find_value(patterns, fn pattern ->
        case Regex.run(pattern, response) do
          [_, captured] -> captured
          _ -> nil
        end
      end)

    normalize_label(label || response)
  end

  @doc false
  def extract_confidence_only(response) do
    # Try to extract confidence score
    patterns = [
      # "Confidence: 0.95"
      ~r/(?:confidence|probability|certainty):\s*([0-9.]+)/i,
      # "95%" or "(95%)"
      ~r/\(?([0-9]+)%\)?/,
      # Decimal like 0.95
      ~r/\b0\.([0-9]+)\b/
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, response) do
        [_, captured] -> parse_confidence(captured)
        _ -> nil
      end
    end)
  end

  @doc false
  def normalize_label(label) when is_binary(label) do
    label
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/[^\w]/, "")
  end

  def normalize_label(_), do: ""

  @doc false
  def parse_confidence(conf_str) when is_binary(conf_str) do
    # Try parsing as float first
    case Float.parse(conf_str) do
      {value, _} when value >= 0.0 and value <= 1.0 ->
        value

      {value, _} when value > 1.0 and value <= 100.0 ->
        value / 100.0

      _ ->
        # Try parsing as integer
        case Integer.parse(conf_str) do
          {int_value, _} when int_value >= 0 and int_value <= 100 ->
            int_value / 100.0

          _ ->
            nil
        end
    end
  end

  def parse_confidence(_), do: nil

  @doc false
  def check_label_accuracy(_extracted, nil), do: 0.5

  def check_label_accuracy(extracted, expected) do
    normalized_extracted = normalize_label(extracted)
    normalized_expected = normalize_label(expected)

    cond do
      # Exact match
      normalized_extracted == normalized_expected ->
        1.0

      # Check for semantic equivalents (e.g., "pos" vs "positive") - before partial match
      semantic_similarity(normalized_extracted, normalized_expected) ->
        0.9

      # Partial match (label contains expected or vice versa)
      String.contains?(normalized_extracted, normalized_expected) ||
          String.contains?(normalized_expected, normalized_extracted) ->
        0.7

      # No match
      true ->
        0.0
    end
  end

  @doc false
  def semantic_similarity(label1, label2) do
    # Check for common abbreviations and synonyms
    equivalents = %{
      "pos" => "positive",
      "neg" => "negative",
      "neut" => "neutral",
      "spam" => "spam",
      "ham" => "notspam",
      "relevant" => "relevant",
      "irrelevant" => "notrelevant"
    }

    expanded1 = Map.get(equivalents, label1, label1)
    expanded2 = Map.get(equivalents, label2, label2)

    expanded1 == label2 || expanded2 == label1 || expanded1 == expanded2
  end

  @doc false
  def validate_label(_label, nil), do: true
  def validate_label(_label, []), do: true

  def validate_label(label, valid_labels) when is_list(valid_labels) do
    normalized_label = normalize_label(label)
    normalized_valid = Enum.map(valid_labels, &normalize_label/1)

    normalized_label in normalized_valid
  end

  @doc false
  def assess_confidence_calibration(nil, _accuracy, false), do: 1.0
  def assess_confidence_calibration(nil, _accuracy, true), do: 0.0

  def assess_confidence_calibration(confidence, accuracy, _requires) when is_float(confidence) do
    # Well-calibrated: high confidence with high accuracy, low confidence with low accuracy
    # Poorly-calibrated: high confidence with low accuracy, or low confidence with high accuracy

    cond do
      # Perfect calibration: confidence matches accuracy closely
      abs(confidence - accuracy) < 0.1 ->
        1.0

      # Good calibration: within 0.2
      abs(confidence - accuracy) < 0.2 ->
        0.8

      # Moderate calibration: within 0.3
      abs(confidence - accuracy) < 0.3 ->
        0.6

      # Poor calibration: confidence and accuracy diverge significantly
      true ->
        max(0.0, 0.5 - abs(confidence - accuracy))
    end
  end

  def assess_confidence_calibration(_, _, _), do: 0.5

  @doc false
  def calculate_consistency(response, label) do
    # Heuristic: check if the response has consistent language
    # For now, simple heuristic based on response characteristics

    normalized_label = normalize_label(label)
    normalized_response = String.downcase(response)

    # Positive indicators
    positive_words = ["good", "great", "excellent", "positive", "happy", "love"]
    negative_words = ["bad", "terrible", "awful", "negative", "sad", "hate"]
    neutral_words = ["okay", "average", "neutral", "moderate"]

    has_positive = Enum.any?(positive_words, &String.contains?(normalized_response, &1))
    has_negative = Enum.any?(negative_words, &String.contains?(normalized_response, &1))
    has_neutral = Enum.any?(neutral_words, &String.contains?(normalized_response, &1))

    cond do
      # Label and supporting words align
      normalized_label =~ ~r/pos/ && has_positive -> 1.0
      normalized_label =~ ~r/neg/ && has_negative -> 1.0
      normalized_label =~ ~r/neut/ && has_neutral -> 1.0
      # Label and supporting words conflict
      normalized_label =~ ~r/pos/ && has_negative -> 0.3
      normalized_label =~ ~r/neg/ && has_positive -> 0.3
      # No strong indicators either way
      true -> 0.6
    end
  end

  @doc false
  @spec enhance_result_with_classification_metrics(evaluation_result(), map()) ::
          evaluation_result()
  defp enhance_result_with_classification_metrics(
         %Evaluator.EvaluationResult{} = result,
         classification_metrics
       ) do
    # Calculate enhanced fitness that incorporates classification metrics
    enhanced_fitness = calculate_classification_fitness(result.fitness, classification_metrics)

    # Merge classification metrics into result
    enhanced_metrics =
      Map.merge(result.metrics, %{
        classification: %{
          label_accuracy: classification_metrics.label_accuracy,
          confidence_calibration: classification_metrics.confidence_calibration,
          classification_consistency: classification_metrics.classification_consistency,
          valid_label: classification_metrics.valid_label,
          extracted_label: classification_metrics.extracted_label,
          confidence_score: classification_metrics.confidence_score
        }
      })

    %{result | fitness: enhanced_fitness, metrics: enhanced_metrics}
  end

  @doc false
  def calculate_classification_fitness(_generic_fitness, classification_metrics) do
    # Weight classification-specific metrics
    # 70% label accuracy, 20% confidence calibration, 10% consistency
    accuracy_weight = 0.7
    calibration_weight = 0.2
    consistency_weight = 0.1

    accuracy_score = classification_metrics.label_accuracy
    calibration_score = classification_metrics.confidence_calibration
    consistency_score = classification_metrics.classification_consistency

    # Calculate weighted score
    accuracy_weight * accuracy_score +
      calibration_weight * calibration_score +
      consistency_weight * consistency_score
  end
end
