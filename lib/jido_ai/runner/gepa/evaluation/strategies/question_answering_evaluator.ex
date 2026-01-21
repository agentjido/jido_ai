defmodule Jido.AI.Runner.GEPA.Evaluation.Strategies.QuestionAnsweringEvaluator do
  @moduledoc """
  Question answering task evaluator for GEPA.

  Evaluates prompts for QA and information retrieval tasks by:
  1. Generating an answer using the LLM
  2. Assessing answer accuracy
  3. Evaluating relevance to the question
  4. Checking completeness
  5. Calculating QA-specific metrics

  ## Task Configuration

      task: %{
        type: :question_answering,
        question: "What is the capital of France?",
        expected_answer: "Paris",  # optional, for accuracy checking
        context: "France is a country in Europe...",  # optional, source text
        question_type: :what,  # optional, :who, :what, :when, :where, :why, :how
        test_cases: [
          %{input: "What is 2+2?", expected: "4"}
        ]
      }

  ## Evaluation Process

  1. **Answer Generation**: Use LLM with prompt to generate answer
  2. **Accuracy Check**: Compare answer to expected result (if provided)
  3. **Relevance Assessment**: Check if answer addresses the question
  4. **Completeness Check**: Verify answer provides sufficient detail
  5. **Question Type Match**: Ensure answer matches question type
  6. **Metric Calculation**:
     - Answer accuracy: correctness (0-1)
     - Relevance: addresses question (0-1)
     - Completeness: sufficient detail (0-1)
     - Fitness: weighted combination (60% accuracy, 25% relevance, 15% completeness)

  ## Metrics

  - **answer_accuracy**: Answer correctness (0-1)
  - **relevance_score**: Answer relevance to question (0-1)
  - **completeness_score**: Answer completeness (0-1)
  - **question_type_match**: Answer format matches question type (boolean)
  - **contains_hallucination**: Detected hallucinated info (boolean)
  - **fitness**: Overall score incorporating all metrics
  """

  require Logger

  alias Jido.AI.Runner.GEPA.Evaluator

  @type task_config :: map()
  @type prompt :: String.t()
  @type evaluation_result :: Evaluator.EvaluationResult.t()

  @doc """
  Evaluates a prompt for question answering tasks.

  Generates an answer using the LLM, assesses quality metrics,
  and calculates QA-specific fitness.

  ## Examples

      QuestionAnsweringEvaluator.evaluate_prompt(
        "What is the capital of France?",
        task: %{
          type: :question_answering,
          question: "What is the capital of France?",
          expected_answer: "Paris"
        }
      )
  """
  @spec evaluate_prompt(prompt(), keyword()) :: {:ok, evaluation_result()} | {:error, term()}
  def evaluate_prompt(prompt, opts) when is_binary(prompt) and is_list(opts) do
    task = Keyword.get(opts, :task, %{})

    Logger.debug(
      "QA evaluation starting (question_type: #{task[:question_type]}, has_context: #{!is_nil(task[:context])})"
    )

    # First, do generic evaluation to get LLM response
    case Evaluator.evaluate_prompt(prompt, opts) do
      {:ok, generic_result} ->
        # Extract answer from response
        answer = extract_response_from_result(generic_result)

        # Perform QA-specific evaluation
        qa_metrics = evaluate_qa(answer, task)

        # Combine generic and QA-specific metrics
        enhanced_result = enhance_result_with_qa_metrics(generic_result, qa_metrics)

        Logger.debug(
          "QA evaluation complete (accuracy: #{qa_metrics.answer_accuracy}, relevance: #{qa_metrics.relevance_score})"
        )

        {:ok, enhanced_result}

      {:error, reason} = error ->
        Logger.warning("QA evaluation failed during generation: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Evaluates multiple prompts in batch for QA tasks.
  """
  @spec evaluate_batch(list(prompt()), keyword()) :: list(evaluation_result())
  def evaluate_batch(prompts, opts) when is_list(prompts) and is_list(opts) do
    Logger.info("Batch QA evaluation for #{length(prompts)} prompts")

    # Use generic batch evaluation, then enhance each result
    generic_results = Evaluator.evaluate_batch(prompts, opts)
    task = Keyword.get(opts, :task, %{})

    Enum.map(generic_results, fn result ->
      if is_nil(result.error) do
        answer = extract_response_from_result(result)
        qa_metrics = evaluate_qa(answer, task)
        enhance_result_with_qa_metrics(result, qa_metrics)
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
  def evaluate_qa(answer, task) do
    question = task[:question] || ""
    expected_answer = task[:expected_answer]
    context = task[:context]
    question_type = task[:question_type] || detect_question_type(question)

    # Assess answer accuracy
    answer_accuracy = assess_answer_accuracy(answer, expected_answer, context)

    # Evaluate relevance
    relevance_score = assess_relevance(answer, question, question_type)

    # Check completeness
    completeness_score = assess_completeness(answer, question_type)

    # Verify question type match
    question_type_match = check_question_type_match(answer, question_type)

    # Detect hallucinations (if context provided)
    contains_hallucination = detect_hallucination(answer, context)

    %{
      answer_accuracy: answer_accuracy,
      relevance_score: relevance_score,
      completeness_score: completeness_score,
      question_type_match: question_type_match,
      contains_hallucination: contains_hallucination,
      detected_question_type: question_type,
      answer: answer
    }
  end

  @doc false
  def detect_question_type(question) do
    question_lower = String.downcase(question)

    cond do
      String.starts_with?(question_lower, "who") -> :who
      String.starts_with?(question_lower, "what") -> :what
      String.starts_with?(question_lower, "when") -> :when
      String.starts_with?(question_lower, "where") -> :where
      String.starts_with?(question_lower, "why") -> :why
      String.starts_with?(question_lower, "how") -> :how
      String.contains?(question_lower, "which") -> :which
      true -> :unknown
    end
  end

  @doc false
  def assess_answer_accuracy(_answer, nil, _context), do: 0.5

  def assess_answer_accuracy(answer, expected_answer, context) do
    # Normalize for comparison
    normalized_answer = normalize_text(answer)
    normalized_expected = normalize_text(expected_answer)

    cond do
      # Empty answer
      String.trim(answer) == "" ->
        0.0

      # Exact match
      normalized_answer == normalized_expected ->
        1.0

      # Partial match (answer contains expected or vice versa)
      String.contains?(normalized_answer, normalized_expected) ||
          String.contains?(normalized_expected, normalized_answer) ->
        0.8

      # Check word overlap
      overlap_score(answer, expected_answer) >= 0.6 ->
        0.7

      # If context provided, check if answer is grounded in context
      context && grounded_in_context?(answer, context) ->
        0.6

      # No match
      true ->
        0.0
    end
  end

  @doc false
  def normalize_text(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/[^\w\s]/, "")
  end

  def normalize_text(_), do: ""

  @doc false
  def overlap_score(answer, expected) do
    answer_words = extract_words(answer)
    expected_words = extract_words(expected)

    if Enum.empty?(expected_words) do
      0.0
    else
      overlap_count =
        Enum.count(expected_words, fn word ->
          word in answer_words
        end)

      overlap_count / length(expected_words)
    end
  end

  @doc false
  def extract_words(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.split(~r/\s+/)
    |> Enum.reject(&(&1 == ""))
  end

  def extract_words(_), do: []

  @doc false
  def grounded_in_context?(_answer, nil), do: false

  def grounded_in_context?(answer, context) do
    # Check if answer content comes from context
    answer_words = extract_words(answer)
    context_words = extract_words(context)

    if Enum.empty?(answer_words) do
      false
    else
      grounded_count =
        Enum.count(answer_words, fn word ->
          word in context_words
        end)

      grounded_count / length(answer_words) >= 0.7
    end
  end

  @doc false
  def assess_relevance(answer, question, question_type) do
    # Check if answer is relevant to the question

    cond do
      # Empty answer
      String.trim(answer) == "" ->
        0.0

      # Check if answer addresses the question type appropriately
      addresses_question_type?(answer, question_type) ->
        # Also check for shared keywords between question and answer
        keyword_overlap = overlap_score(answer, question)

        if keyword_overlap > 0.3 do
          1.0
        else
          0.8
        end

      # Some keyword overlap
      overlap_score(answer, question) > 0.2 ->
        0.6

      # Generic response
      true ->
        0.4
    end
  end

  @doc false
  def addresses_question_type?(answer, question_type) do
    answer_lower = String.downcase(answer)

    case question_type do
      :who ->
        # Should contain person names or pronouns
        Regex.match?(~r/\b(he|she|they|person|people|[A-Z][a-z]+\s[A-Z][a-z]+)\b/, answer) ||
          String.contains?(answer_lower, ["scientist", "author", "president", "doctor"])

      :what ->
        # Should define or describe something
        String.length(answer) > 10 &&
          (Regex.match?(~r/\b(is|are|was|were)\b/, answer_lower) ||
             String.contains?(answer_lower, ["refers to", "means", "describes"]))

      :when ->
        # Should contain time references
        Regex.match?(~r/\b\d{4}\b/, answer) ||
          String.contains?(answer_lower, [
            "year",
            "day",
            "month",
            "century",
            "ago",
            "during",
            "in",
            "at"
          ])

      :where ->
        # Should contain location references
        String.contains?(answer_lower, [
          "in",
          "at",
          "on",
          "near",
          "city",
          "country",
          "place",
          "located"
        ]) || Regex.match?(~r/\b[A-Z][a-z]+(?:,|\sin\s)/, answer)

      :why ->
        # Should contain explanations or reasons
        String.contains?(answer_lower, [
          "because",
          "since",
          "due to",
          "reason",
          "cause",
          "result",
          "therefore"
        ])

      :how ->
        # Should contain process or method descriptions
        String.contains?(answer_lower, ["by", "through", "via", "using", "method", "process"]) ||
          Regex.match?(~r/\b(first|then|next|finally)\b/, answer_lower)

      _ ->
        # Unknown question type, can't verify
        true
    end
  end

  @doc false
  def assess_completeness(answer, question_type) do
    # Check if answer provides sufficient detail

    word_count = answer |> String.split() |> length()

    # Minimum expected lengths by question type
    min_words =
      case question_type do
        :why -> 15
        :how -> 20
        :what -> 10
        _ -> 5
      end

    cond do
      # Empty answer
      word_count == 0 ->
        0.0

      # Very short answer
      word_count < 3 ->
        0.3

      # Meets minimum length
      word_count >= min_words ->
        1.0

      # Partial length
      true ->
        min(word_count / min_words, 0.9)
    end
  end

  @doc false
  def check_question_type_match(answer, question_type) do
    addresses_question_type?(answer, question_type)
  end

  @doc false
  def detect_hallucination(_answer, nil), do: false

  def detect_hallucination(answer, context) do
    # Simple heuristic: if answer contains many words NOT in context, potential hallucination
    answer_words = extract_words(answer)
    context_words = extract_words(context)

    if Enum.empty?(answer_words) do
      false
    else
      not_in_context =
        Enum.count(answer_words, fn word ->
          word not in context_words
        end)

      # If more than 50% of answer words are not in context, flag as potential hallucination
      not_in_context / length(answer_words) > 0.5
    end
  end

  @doc false
  @spec enhance_result_with_qa_metrics(evaluation_result(), map()) :: evaluation_result()
  defp enhance_result_with_qa_metrics(%Evaluator.EvaluationResult{} = result, qa_metrics) do
    # Calculate enhanced fitness that incorporates QA metrics
    enhanced_fitness = calculate_qa_fitness(result.fitness, qa_metrics)

    # Merge QA metrics into result
    enhanced_metrics =
      Map.merge(result.metrics, %{
        question_answering: %{
          answer_accuracy: qa_metrics.answer_accuracy,
          relevance_score: qa_metrics.relevance_score,
          completeness_score: qa_metrics.completeness_score,
          question_type_match: qa_metrics.question_type_match,
          contains_hallucination: qa_metrics.contains_hallucination,
          detected_question_type: qa_metrics.detected_question_type
        }
      })

    %{result | fitness: enhanced_fitness, metrics: enhanced_metrics}
  end

  @doc false
  def calculate_qa_fitness(_generic_fitness, qa_metrics) do
    # Weight QA-specific metrics
    # 60% answer accuracy, 25% relevance, 15% completeness
    accuracy_weight = 0.6
    relevance_weight = 0.25
    completeness_weight = 0.15

    accuracy_score = qa_metrics.answer_accuracy
    relevance_score = qa_metrics.relevance_score
    completeness_score = qa_metrics.completeness_score

    # Penalize hallucinations
    hallucination_penalty = if qa_metrics.contains_hallucination, do: 0.5, else: 1.0

    base_fitness =
      accuracy_weight * accuracy_score +
        relevance_weight * relevance_score +
        completeness_weight * completeness_score

    base_fitness * hallucination_penalty
  end
end
