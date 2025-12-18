defmodule Jido.AI.Runner.GEPA.Evaluation.Strategies.SummarizationEvaluator do
  @moduledoc """
  Summarization task evaluator for GEPA.

  Evaluates prompts for text summarization tasks by:
  1. Generating a summary using the LLM
  2. Assessing factual consistency with source
  3. Evaluating conciseness and length appropriateness
  4. Checking coherence and flow
  5. Calculating summarization-specific metrics

  ## Task Configuration

      task: %{
        type: :summarization,
        source_text: "Long article or document to summarize...",
        expected_summary: "Reference summary for comparison",  # optional
        max_length: 100,  # optional, maximum words in summary
        min_length: 20,   # optional, minimum words in summary
        key_points: ["point 1", "point 2"],  # optional, important points to cover
        test_cases: [
          %{input: "Text to summarize", expected: "Expected summary"}
        ]
      }

  ## Evaluation Process

  1. **Summary Generation**: Use LLM with prompt to generate summary
  2. **Length Assessment**: Check if summary is appropriately concise
  3. **Factual Consistency**: Verify summary content matches source
  4. **Coherence Check**: Assess logical flow and structure
  5. **Coverage Check**: Verify key points are included
  6. **Metric Calculation**:
     - Factual consistency: content accuracy (0-1)
     - Conciseness: length appropriateness (0-1)
     - Coherence: logical flow score (0-1)
     - Coverage: key points captured (0-1)
     - Fitness: weighted combination (40% consistency, 30% conciseness, 20% coherence, 10% coverage)

  ## Metrics

  - **factual_consistency**: Summary reflects source content accurately (0-1)
  - **conciseness_score**: Appropriate length relative to source (0-1)
  - **coherence_score**: Logical flow and structure (0-1)
  - **key_points_coverage**: Important points captured (0-1)
  - **length_ratio**: Summary length / source length
  - **is_truncation**: Summary appears to be simple truncation (boolean)
  - **fitness**: Overall score incorporating all metrics
  """

  require Logger

  alias Jido.AI.Runner.GEPA.Evaluator

  @type task_config :: map()
  @type prompt :: String.t()
  @type evaluation_result :: Evaluator.EvaluationResult.t()

  @doc """
  Evaluates a prompt for summarization tasks.

  Generates a summary using the LLM, assesses quality metrics,
  and calculates summarization-specific fitness.

  ## Examples

      SummarizationEvaluator.evaluate_prompt(
        "Summarize the following: [long text]",
        task: %{
          type: :summarization,
          source_text: "Long article text...",
          max_length: 100
        }
      )
  """
  @spec evaluate_prompt(prompt(), keyword()) :: {:ok, evaluation_result()} | {:error, term()}
  def evaluate_prompt(prompt, opts) when is_binary(prompt) and is_list(opts) do
    task = Keyword.get(opts, :task, %{})

    Logger.debug(
      "Summarization evaluation starting (source_length: #{word_count(task[:source_text] || "")}, max_length: #{task[:max_length]})"
    )

    # First, do generic evaluation to get LLM response
    case Evaluator.evaluate_prompt(prompt, opts) do
      {:ok, generic_result} ->
        # Extract summary from response
        summary = extract_response_from_result(generic_result)

        # Perform summarization-specific evaluation
        summarization_metrics = evaluate_summarization(summary, task)

        # Combine generic and summarization-specific metrics
        enhanced_result =
          enhance_result_with_summarization_metrics(generic_result, summarization_metrics)

        Logger.debug(
          "Summarization evaluation complete (consistency: #{summarization_metrics.factual_consistency}, coherence: #{summarization_metrics.coherence_score})"
        )

        {:ok, enhanced_result}

      {:error, reason} = error ->
        Logger.warning("Summarization evaluation failed during generation: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Evaluates multiple prompts in batch for summarization tasks.
  """
  @spec evaluate_batch(list(prompt()), keyword()) :: list(evaluation_result())
  def evaluate_batch(prompts, opts) when is_list(prompts) and is_list(opts) do
    Logger.info("Batch summarization evaluation for #{length(prompts)} prompts")

    # Use generic batch evaluation, then enhance each result
    generic_results = Evaluator.evaluate_batch(prompts, opts)
    task = Keyword.get(opts, :task, %{})

    Enum.map(generic_results, fn result ->
      if is_nil(result.error) do
        summary = extract_response_from_result(result)
        summarization_metrics = evaluate_summarization(summary, task)
        enhance_result_with_summarization_metrics(result, summarization_metrics)
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
  def evaluate_summarization(summary, task) do
    source_text = task[:source_text] || ""

    # Calculate length metrics
    summary_words = word_count(summary)
    source_words = word_count(source_text)
    length_ratio = if source_words > 0, do: summary_words / source_words, else: 0.0

    # Assess factual consistency
    factual_consistency = assess_factual_consistency(summary, source_text)

    # Evaluate conciseness
    conciseness_score = assess_conciseness(summary_words, source_words, task)

    # Check coherence
    coherence_score = assess_coherence(summary)

    # Check key points coverage
    key_points_coverage = assess_key_points_coverage(summary, task[:key_points])

    # Detect if it's just truncation
    is_truncation = detect_truncation(summary, source_text)

    %{
      factual_consistency: factual_consistency,
      conciseness_score: conciseness_score,
      coherence_score: coherence_score,
      key_points_coverage: key_points_coverage,
      length_ratio: length_ratio,
      is_truncation: is_truncation,
      summary: summary,
      summary_word_count: summary_words,
      source_word_count: source_words
    }
  end

  @doc false
  def word_count(text) when is_binary(text) do
    text
    |> String.trim()
    |> String.split(~r/\s+/)
    |> Enum.reject(&(&1 == ""))
    |> length()
  end

  def word_count(_), do: 0

  @doc false
  def assess_factual_consistency(summary, source_text) do
    # Heuristic: Check if major content words from summary appear in source
    # More sophisticated: Would use semantic similarity, ROUGE scores, etc.

    summary_words = extract_content_words(summary)
    source_words = extract_content_words(source_text)

    if Enum.empty?(summary_words) do
      0.0
    else
      # Calculate overlap ratio
      overlap_count =
        Enum.count(summary_words, fn word ->
          word in source_words
        end)

      overlap_ratio = overlap_count / length(summary_words)

      cond do
        # High overlap, low hallucination
        overlap_ratio >= 0.8 -> 1.0
        overlap_ratio >= 0.6 -> 0.8
        overlap_ratio >= 0.4 -> 0.6
        # Low overlap suggests hallucination or poor summarization
        true -> max(0.0, overlap_ratio)
      end
    end
  end

  @doc false
  def extract_content_words(text) when is_binary(text) do
    # Extract content words (nouns, verbs, adjectives, numbers)
    # For now, simple filtering of stop words

    stop_words = ~w(
      the a an and or but if then else when where who what which
      is are was were be been being have has had do does did
      will would could should may might must can
      to of in on at by for with from as
      this that these those it its
      i you he she we they me him her us them
    )

    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.split(~r/\s+/)
    |> Enum.reject(&(&1 in stop_words || &1 == ""))
    |> Enum.uniq()
  end

  def extract_content_words(_), do: []

  @doc false
  def assess_conciseness(summary_words, source_words, task) do
    # Check if summary length is appropriate

    cond do
      # Empty summary
      summary_words == 0 ->
        0.0

      # Summary longer than source (bad!)
      source_words > 0 && summary_words >= source_words ->
        0.0

      # Check against max_length if provided
      task[:max_length] && summary_words > task[:max_length] ->
        # Penalize but not zero
        max(0.3, 1.0 - (summary_words - task[:max_length]) / task[:max_length])

      # Check against min_length if provided
      task[:min_length] && summary_words < task[:min_length] ->
        # Too short, but not as bad as too long
        max(0.5, summary_words / task[:min_length])

      # Good compression ratio (5-25% of original)
      source_words > 0 ->
        ratio = summary_words / source_words

        cond do
          ratio >= 0.05 && ratio <= 0.25 -> 1.0
          ratio > 0.25 && ratio < 0.5 -> 0.8
          ratio >= 0.5 -> 0.5
          ratio < 0.05 -> 0.7
          true -> 0.6
        end

      # No source text to compare against
      true ->
        0.7
    end
  end

  @doc false
  def assess_coherence(summary) do
    # Heuristic assessment of summary coherence
    # Check for: sentence structure, connectors, logical flow

    score = 0.0

    # Check for reasonable length (not just a fragment)
    word_count = word_count(summary)

    length_score =
      cond do
        word_count < 10 -> 0.3
        word_count > 500 -> 0.6
        true -> 1.0
      end

    score = score + length_score * 0.4

    # Check for sentence structure (periods, proper capitalization)
    has_sentences = Regex.match?(~r/[A-Z][^.!?]*[.!?]/, summary)
    score = score + if has_sentences, do: 0.3, else: 0.0

    # Check for logical connectors
    connectors = [
      "however",
      "therefore",
      "moreover",
      "furthermore",
      "additionally",
      "consequently",
      "thus",
      "hence",
      "also",
      "first",
      "second",
      "finally"
    ]

    has_connectors =
      Enum.any?(connectors, &String.contains?(String.downcase(summary), &1))

    score = score + if has_connectors, do: 0.2, else: 0.0

    # Check it's not just a list of keywords
    is_keyword_list = Regex.match?(~r/^[\w\s,]+$/, summary) && String.contains?(summary, ",")
    score = if is_keyword_list, do: score * 0.5, else: score

    # Check for complete sentences (not ending mid-sentence)
    ends_properly = Regex.match?(~r/[.!?]$/, String.trim(summary))
    score = score + if ends_properly, do: 0.1, else: 0.0

    min(score, 1.0)
  end

  @doc false
  def assess_key_points_coverage(_summary, nil), do: 1.0
  def assess_key_points_coverage(_summary, []), do: 1.0

  def assess_key_points_coverage(summary, key_points) when is_list(key_points) do
    normalized_summary = String.downcase(summary)

    covered_points =
      Enum.count(key_points, fn point ->
        # Check if key point (or close match) appears in summary
        normalized_point = String.downcase(to_string(point))
        String.contains?(normalized_summary, normalized_point)
      end)

    covered_points / length(key_points)
  end

  @doc false
  def detect_truncation(summary, source_text) do
    # Check if summary is just the beginning of source text

    if String.length(source_text) < 50 || String.length(summary) < 20 do
      false
    else
      # Get beginning of source (first N words of summary length)
      summary_length = String.length(summary)
      source_prefix = String.slice(source_text, 0, summary_length)

      # Check similarity
      similarity = string_similarity(summary, source_prefix)

      # If very similar, likely truncation
      similarity > 0.9
    end
  end

  @doc false
  def string_similarity(str1, str2) do
    # Simple character-level similarity (Jaccard-like)
    chars1 = String.graphemes(String.downcase(str1)) |> MapSet.new()
    chars2 = String.graphemes(String.downcase(str2)) |> MapSet.new()

    intersection = MapSet.intersection(chars1, chars2) |> MapSet.size()
    union = MapSet.union(chars1, chars2) |> MapSet.size()

    if union > 0 do
      intersection / union
    else
      0.0
    end
  end

  @doc false
  @spec enhance_result_with_summarization_metrics(evaluation_result(), map()) ::
          evaluation_result()
  defp enhance_result_with_summarization_metrics(
         %Evaluator.EvaluationResult{} = result,
         summarization_metrics
       ) do
    # Calculate enhanced fitness that incorporates summarization metrics
    enhanced_fitness = calculate_summarization_fitness(result.fitness, summarization_metrics)

    # Merge summarization metrics into result
    enhanced_metrics =
      Map.merge(result.metrics, %{
        summarization: %{
          factual_consistency: summarization_metrics.factual_consistency,
          conciseness_score: summarization_metrics.conciseness_score,
          coherence_score: summarization_metrics.coherence_score,
          key_points_coverage: summarization_metrics.key_points_coverage,
          length_ratio: summarization_metrics.length_ratio,
          is_truncation: summarization_metrics.is_truncation,
          summary_word_count: summarization_metrics.summary_word_count,
          source_word_count: summarization_metrics.source_word_count
        }
      })

    %{result | fitness: enhanced_fitness, metrics: enhanced_metrics}
  end

  @doc false
  def calculate_summarization_fitness(_generic_fitness, summarization_metrics) do
    # Weight summarization-specific metrics
    # 40% factual consistency, 30% conciseness, 20% coherence, 10% coverage
    consistency_weight = 0.4
    conciseness_weight = 0.3
    coherence_weight = 0.2
    coverage_weight = 0.1

    consistency_score = summarization_metrics.factual_consistency
    conciseness_score = summarization_metrics.conciseness_score
    coherence_score = summarization_metrics.coherence_score
    coverage_score = summarization_metrics.key_points_coverage

    # Penalize truncation heavily
    truncation_penalty = if summarization_metrics.is_truncation, do: 0.5, else: 1.0

    base_fitness =
      consistency_weight * consistency_score +
        conciseness_weight * conciseness_score +
        coherence_weight * coherence_score +
        coverage_weight * coverage_score

    base_fitness * truncation_penalty
  end
end
