defmodule Jido.AI.Runner.GEPA.Evaluation.Strategies.ReasoningEvaluator do
  @moduledoc """
  Reasoning task evaluator for GEPA.

  Evaluates prompts for mathematical and logical reasoning tasks by:
  1. Generating a response with reasoning steps
  2. Validating answer correctness
  3. Assessing reasoning quality
  4. Calculating reasoning-specific metrics

  ## Task Configuration

      task: %{
        type: :reasoning,
        problem: "What is 15% of 80?",
        expected_answer: "12",
        answer_type: :numeric,  # :numeric, :boolean, :text
        requires_steps: true,   # whether step-by-step reasoning is required
        test_cases: [
          %{input: "15% of 80", expected: "12"},
          %{input: "20% of 50", expected: "10"}
        ]
      }

  ## Evaluation Process

  1. **Response Generation**: Use LLM with prompt to generate reasoning
  2. **Answer Extraction**: Extract final answer from response
  3. **Correctness Check**: Compare answer to expected result
  4. **Reasoning Quality**: Assess presence and clarity of steps
  5. **Metric Calculation**:
     - Correctness: answer matches expected (0-1)
     - Reasoning quality: presence of clear steps (0-1)
     - Clarity: explanation coherence (0-1)
     - Fitness: weighted combination (60% correctness, 25% quality, 15% clarity)

  ## Metrics

  - **answer_correctness**: Answer matches expected result (0-1)
  - **reasoning_steps_present**: Response includes step-by-step reasoning (boolean)
  - **explanation_clarity**: Reasoning is clear and well-structured (0-1)
  - **answer_format_valid**: Answer matches expected type (boolean)
  - **fitness**: Overall score incorporating all metrics
  """

  require Logger

  alias Jido.AI.Runner.GEPA.Evaluator

  @type task_config :: map()
  @type prompt :: String.t()
  @type evaluation_result :: Evaluator.EvaluationResult.t()

  @doc """
  Evaluates a prompt for reasoning tasks.

  Generates a response using the LLM, extracts the answer, validates correctness,
  and calculates reasoning-specific fitness metrics.

  ## Examples

      ReasoningEvaluator.evaluate_prompt(
        "Solve step by step: What is 15% of 80?",
        task: %{
          type: :reasoning,
          expected_answer: "12",
          answer_type: :numeric
        }
      )
  """
  @spec evaluate_prompt(prompt(), keyword()) :: {:ok, evaluation_result()} | {:error, term()}
  def evaluate_prompt(prompt, opts) when is_binary(prompt) and is_list(opts) do
    task = Keyword.get(opts, :task, %{})

    Logger.debug(
      "Reasoning evaluation starting (type: #{task[:answer_type]}, requires_steps: #{task[:requires_steps]})"
    )

    # First, do generic evaluation to get LLM response
    case Evaluator.evaluate_prompt(prompt, opts) do
      {:ok, generic_result} ->
        # Extract reasoning response
        reasoning_response = extract_response_from_result(generic_result)

        # Perform reasoning-specific evaluation
        reasoning_metrics = evaluate_reasoning(reasoning_response, task)

        # Combine generic and reasoning-specific metrics
        enhanced_result = enhance_result_with_reasoning_metrics(generic_result, reasoning_metrics)

        Logger.debug(
          "Reasoning evaluation complete (correctness: #{reasoning_metrics.answer_correctness}, steps: #{reasoning_metrics.reasoning_steps_present})"
        )

        {:ok, enhanced_result}

      {:error, reason} = error ->
        Logger.warning("Reasoning evaluation failed during generation: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Evaluates multiple prompts in batch for reasoning tasks.
  """
  @spec evaluate_batch(list(prompt()), keyword()) :: list(evaluation_result())
  def evaluate_batch(prompts, opts) when is_list(prompts) and is_list(opts) do
    Logger.info("Batch reasoning evaluation for #{length(prompts)} prompts")

    # Use generic batch evaluation, then enhance each result
    generic_results = Evaluator.evaluate_batch(prompts, opts)
    task = Keyword.get(opts, :task, %{})

    Enum.map(generic_results, fn result ->
      if is_nil(result.error) do
        reasoning_response = extract_response_from_result(result)
        reasoning_metrics = evaluate_reasoning(reasoning_response, task)
        enhance_result_with_reasoning_metrics(result, reasoning_metrics)
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
  def evaluate_reasoning(response, task) do
    # Extract final answer from response
    extracted_answer = extract_answer(response)

    # Check answer correctness
    answer_correctness = check_answer_correctness(extracted_answer, task[:expected_answer])

    # Check for reasoning steps
    reasoning_steps_present = has_reasoning_steps?(response)

    # Assess explanation clarity
    explanation_clarity = assess_clarity(response)

    # Validate answer format
    answer_format_valid = validate_answer_format(extracted_answer, task[:answer_type])

    %{
      answer_correctness: answer_correctness,
      reasoning_steps_present: reasoning_steps_present,
      explanation_clarity: explanation_clarity,
      answer_format_valid: answer_format_valid,
      extracted_answer: extracted_answer,
      response: response
    }
  end

  @doc false
  def extract_answer(response) do
    # Try to extract final answer from common patterns
    patterns = [
      # "Answer: 12" or "The answer is 12"
      ~r/(?:answer|result)(?:\s+is)?:\s*([^\n\.]+)/i,
      # "Therefore, 12" or "Thus, 12"
      ~r/(?:therefore|thus|so|hence),?\s+([^\n\.]+)/i,
      # Numbers at end of response
      ~r/([0-9]+(?:\.[0-9]+)?)\s*$/,
      # Yes/No at end
      ~r/(yes|no|true|false)\s*$/i
    ]

    answer =
      Enum.find_value(patterns, fn pattern ->
        case Regex.run(pattern, response) do
          [_, captured] -> String.trim(captured)
          _ -> nil
        end
      end)

    answer || String.trim(response)
  end

  @doc false
  def check_answer_correctness(_extracted, nil), do: 0.5

  def check_answer_correctness(extracted, expected) do
    # Normalize both answers for comparison
    normalized_extracted = normalize_answer(extracted)
    normalized_expected = normalize_answer(expected)

    cond do
      # Exact match
      normalized_extracted == normalized_expected ->
        1.0

      # Numeric tolerance check (for floating point) - check before partial match
      numeric_similarity(normalized_extracted, normalized_expected) > 0.95 ->
        1.0

      # Partial match (answer contains expected or vice versa)
      String.contains?(normalized_extracted, normalized_expected) ||
          String.contains?(normalized_expected, normalized_extracted) ->
        0.7

      # No match
      true ->
        0.0
    end
  end

  @doc false
  def normalize_answer(answer) do
    answer
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/[^\w\d\.]/, "")
  end

  @doc false
  def numeric_similarity(str1, str2) do
    case {Float.parse(str1), Float.parse(str2)} do
      {{num1, _}, {num2, _}} ->
        if num2 == 0.0 do
          if num1 == 0.0, do: 1.0, else: 0.0
        else
          1.0 - min(abs(num1 - num2) / abs(num2), 1.0)
        end

      _ ->
        0.0
    end
  end

  @doc false
  def has_reasoning_steps?(response) do
    # Check for indicators of step-by-step reasoning
    step_indicators = [
      # Numbered steps
      ~r/\d+[\.)]\s+/,
      # "First", "Second", "Then", "Next", "Finally"
      ~r/\b(first|second|third|then|next|finally)\b/i,
      # "Step 1", "Step 2"
      ~r/step\s+\d+/i,
      # Multiple sentences (basic heuristic)
      ~r/\.\s+[A-Z]/
    ]

    Enum.any?(step_indicators, fn pattern ->
      Regex.match?(pattern, response)
    end)
  end

  @doc false
  def assess_clarity(response) do
    # Heuristic assessment of explanation clarity
    score = 0.0

    # Check for reasonable length (too short or too long reduces clarity)
    word_count = response |> String.split() |> length()

    length_score =
      cond do
        word_count < 10 -> 0.3
        word_count > 500 -> 0.5
        true -> 1.0
      end

    score = score + length_score * 0.4

    # Check for logical connectors
    has_connectors =
      Regex.match?(
        ~r/\b(because|since|therefore|thus|so|however|moreover|furthermore)\b/i,
        response
      )

    score = score + if has_connectors, do: 0.3, else: 0.0

    # Check for proper sentence structure
    has_proper_sentences = Regex.match?(~r/[A-Z][^.!?]*[.!?]/, response)
    score = score + if has_proper_sentences, do: 0.3, else: 0.0

    min(score, 1.0)
  end

  @doc false
  def validate_answer_format(_answer, nil), do: true

  def validate_answer_format(answer, answer_type) do
    case answer_type do
      :numeric ->
        match?({_, _}, Float.parse(answer)) || match?({_, _}, Integer.parse(answer))

      :boolean ->
        normalized = String.downcase(String.trim(answer))
        normalized in ["true", "false", "yes", "no"]

      :text ->
        String.length(String.trim(answer)) > 0

      _ ->
        true
    end
  end

  @doc false
  @spec enhance_result_with_reasoning_metrics(evaluation_result(), map()) ::
          evaluation_result()
  defp enhance_result_with_reasoning_metrics(
         %Evaluator.EvaluationResult{} = result,
         reasoning_metrics
       ) do
    # Calculate enhanced fitness that incorporates reasoning metrics
    enhanced_fitness = calculate_reasoning_fitness(result.fitness, reasoning_metrics)

    # Merge reasoning metrics into result
    enhanced_metrics =
      Map.merge(result.metrics, %{
        reasoning: %{
          answer_correctness: reasoning_metrics.answer_correctness,
          reasoning_steps_present: reasoning_metrics.reasoning_steps_present,
          explanation_clarity: reasoning_metrics.explanation_clarity,
          answer_format_valid: reasoning_metrics.answer_format_valid,
          extracted_answer: reasoning_metrics.extracted_answer
        }
      })

    %{result | fitness: enhanced_fitness, metrics: enhanced_metrics}
  end

  @doc false
  def calculate_reasoning_fitness(_generic_fitness, reasoning_metrics) do
    # Weight reasoning-specific metrics
    # 60% correctness, 25% reasoning quality (steps), 15% clarity
    correctness_weight = 0.6
    reasoning_weight = 0.25
    clarity_weight = 0.15

    correctness_score = reasoning_metrics.answer_correctness
    reasoning_score = if reasoning_metrics.reasoning_steps_present, do: 1.0, else: 0.0
    clarity_score = reasoning_metrics.explanation_clarity

    # Calculate weighted score
    correctness_weight * correctness_score +
      reasoning_weight * reasoning_score +
      clarity_weight * clarity_score
  end
end
