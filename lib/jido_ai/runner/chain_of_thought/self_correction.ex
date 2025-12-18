defmodule Jido.AI.Runner.ChainOfThought.SelfCorrection do
  @moduledoc """
  Self-correction mechanisms for Chain-of-Thought reasoning.

  This module implements self-correction that enables agents to detect reasoning
  errors and generate corrected approaches. Self-correction is triggered when
  outcomes don't match expectations or when validation criteria fail.

  ## Features

  - **Outcome Validation**: Compare actual vs. expected results
  - **Mismatch Detection**: Classify divergence levels (minor, moderate, critical)
  - **Correction Strategies**: Select appropriate correction approach based on failure type
  - **Iterative Refinement**: Repeatedly attempt reasoning until success or iteration limit
  - **Quality Thresholds**: Determine when results are acceptable vs. requiring refinement

  ## Usage

      # Basic self-correction
      {:ok, result} = SelfCorrection.iterative_execute(
        fn -> perform_reasoning() end,
        validator: &validate_result/1,
        max_iterations: 3
      )

      # With custom quality threshold
      {:ok, result} = SelfCorrection.iterative_execute(
        reasoning_fn,
        validator: validator_fn,
        quality_threshold: 0.8,
        max_iterations: 5
      )

      # Validate outcome mismatch
      divergence = SelfCorrection.validate_outcome(expected, actual)
      # => :minor | :moderate | :critical | :match

  ## Correction Strategies

  - `:retry_adjusted` - Retry with adjusted parameters
  - `:backtrack_alternative` - Backtrack and try alternative approach
  - `:clarify_requirements` - Request clarification when ambiguous
  - `:accept_partial` - Accept partial success

  ## Iteration Limits

  Default max iterations: 3
  Configurable per execution to prevent infinite loops
  """

  require Logger

  @default_max_iterations 3
  @default_quality_threshold 0.7

  @type divergence_level :: :match | :minor | :moderate | :critical
  @type correction_strategy ::
          :retry_adjusted | :backtrack_alternative | :clarify_requirements | :accept_partial
  @type validation_result :: {:ok, term()} | {:error, term(), divergence_level()}
  @type quality_score :: float()

  # Private struct to group iteration context parameters
  defmodule CorrectionContext do
    @moduledoc false
    defstruct [
      :reasoning_fn,
      :validator,
      :max_iter,
      :threshold,
      :callback,
      :iteration,
      :history
    ]

    @type t :: %__MODULE__{
            reasoning_fn: fun(),
            validator: fun(),
            max_iter: pos_integer(),
            threshold: float(),
            callback: fun() | nil,
            iteration: pos_integer(),
            history: list()
          }
  end

  @doc """
  Validates outcome by comparing expected vs. actual results.

  Returns divergence classification based on similarity between
  expected and actual outcomes using fixed thresholds:
  - Match: similarity > 0.95
  - Minor: similarity >= 0.8
  - Moderate: similarity >= 0.5
  - Critical: similarity < 0.5

  ## Parameters

  - `expected` - Expected outcome
  - `actual` - Actual outcome
  - `opts` - Options:
    - `:validator` - Custom validation function

  ## Returns

  - `:match` - Outcomes match closely enough
  - `:minor` - Small divergence, likely acceptable
  - `:moderate` - Noticeable divergence, correction recommended
  - `:critical` - Major divergence, correction required

  ## Examples

      validate_outcome(42, 42)
      # => :match

      validate_outcome(42, 40)
      # => :minor

      validate_outcome("hello", "goodbye")
      # => :critical
  """
  @spec validate_outcome(term(), term(), keyword()) :: divergence_level()
  def validate_outcome(expected, actual, opts \\ []) do
    custom_validator = Keyword.get(opts, :validator)

    if custom_validator do
      custom_validator.(expected, actual)
    else
      default_validate_outcome(expected, actual, opts)
    end
  end

  @doc """
  Calculates similarity score between expected and actual outcomes.

  Returns a float between 0.0 (completely different) and 1.0 (identical).

  ## Parameters

  - `expected` - Expected outcome
  - `actual` - Actual outcome

  ## Returns

  Float between 0.0 and 1.0 representing similarity

  ## Examples

      similarity_score(42, 42)
      # => 1.0

      similarity_score(100, 90)
      # => 0.9

      similarity_score("test", "test")
      # => 1.0
  """
  @spec similarity_score(term(), term()) :: float()
  def similarity_score(expected, actual) when expected == actual, do: 1.0

  def similarity_score(expected, actual) when is_number(expected) and is_number(actual) do
    # Numeric similarity based on relative difference
    diff = abs(expected - actual)
    max_val = max(abs(expected), abs(actual))

    if max_val == 0 do
      1.0
    else
      max(0.0, 1.0 - diff / max_val)
    end
  end

  def similarity_score(expected, actual) when is_binary(expected) and is_binary(actual) do
    # String similarity using Jaro distance approximation
    string_similarity(expected, actual)
  end

  def similarity_score(expected, actual) when is_list(expected) and is_list(actual) do
    # List similarity based on common elements
    list_similarity(expected, actual)
  end

  def similarity_score(_expected, _actual), do: 0.0

  @doc """
  Selects correction strategy based on failure type and iteration history.

  ## Parameters

  - `divergence` - Divergence level from validation
  - `iteration` - Current iteration number
  - `history` - Previous iteration results

  ## Returns

  Correction strategy atom

  ## Examples

      select_correction_strategy(:minor, 1, [])
      # => :retry_adjusted

      select_correction_strategy(:critical, 2, [...])
      # => :backtrack_alternative
  """
  @spec select_correction_strategy(divergence_level(), non_neg_integer(), list()) ::
          correction_strategy()
  def select_correction_strategy(:match, _iteration, _history), do: :accept_partial

  def select_correction_strategy(:minor, iteration, _history) when iteration <= 2 do
    :retry_adjusted
  end

  def select_correction_strategy(:moderate, iteration, history) do
    if iteration <= 1 or repeated_failure?(history) do
      :backtrack_alternative
    else
      :retry_adjusted
    end
  end

  def select_correction_strategy(:critical, _iteration, history) do
    if ambiguous_requirements?(history) do
      :clarify_requirements
    else
      :backtrack_alternative
    end
  end

  def select_correction_strategy(_divergence, _iteration, _history), do: :accept_partial

  @doc """
  Executes reasoning function iteratively with self-correction until success or max iterations.

  ## Parameters

  - `reasoning_fn` - Function that performs reasoning and returns result
  - `opts` - Options:
    - `:validator` - Function to validate results (required)
    - `:max_iterations` - Maximum iterations (default: 3)
    - `:quality_threshold` - Minimum quality score (default: 0.7)
    - `:on_correction` - Callback for each correction attempt

  ## Returns

  - `{:ok, result}` - Successful result meeting quality threshold
  - `{:ok, result, :partial}` - Partial success after max iterations
  - `{:error, reason}` - Failed to produce acceptable result

  ## Examples

      {:ok, result} = iterative_execute(
        fn -> calculate_answer() end,
        validator: &validate_calculation/1,
        max_iterations: 5
      )
  """
  @spec iterative_execute(fun(), keyword()) ::
          {:ok, term()} | {:ok, term(), :partial} | {:error, term()}
  def iterative_execute(reasoning_fn, opts) do
    max_iterations = Keyword.get(opts, :max_iterations, @default_max_iterations)
    validator = Keyword.get(opts, :validator)
    quality_threshold = Keyword.get(opts, :quality_threshold, @default_quality_threshold)
    on_correction = Keyword.get(opts, :on_correction)

    unless validator do
      raise ArgumentError, "validator function is required"
    end

    context = %CorrectionContext{
      reasoning_fn: reasoning_fn,
      validator: validator,
      max_iter: max_iterations,
      threshold: quality_threshold,
      callback: on_correction,
      iteration: 1,
      history: []
    }

    do_iterative_execute(context)
  end

  @doc """
  Calculates quality score for a given result.

  Quality score combines multiple factors:
  - Outcome match quality
  - Reasoning coherence
  - Confidence level

  ## Parameters

  - `result` - Result to score
  - `opts` - Scoring options

  ## Returns

  Float between 0.0 and 1.0

  ## Examples

      quality_score(%{answer: 42, confidence: 0.9}, expected: 42)
      # => 0.95
  """
  @spec quality_score(term(), keyword()) :: quality_score()
  def quality_score(result, opts \\ []) do
    expected = Keyword.get(opts, :expected)

    # Base score from result confidence if available
    base_score = extract_confidence(result)

    # Adjust based on expected match if provided
    if expected do
      actual = extract_answer(result)
      similarity = similarity_score(expected, actual)
      (base_score + similarity) / 2.0
    else
      base_score
    end
  end

  @doc """
  Checks if quality threshold is met.

  ## Parameters

  - `score` - Quality score to check
  - `threshold` - Minimum threshold (default: 0.7)

  ## Returns

  Boolean indicating if threshold is met
  """
  @spec quality_threshold_met?(quality_score(), float()) :: boolean()
  def quality_threshold_met?(score, threshold \\ @default_quality_threshold) do
    score >= threshold
  end

  @doc """
  Adapts quality threshold based on task criticality.

  ## Parameters

  - `base_threshold` - Base quality threshold
  - `criticality` - Task criticality (:low, :medium, :high)

  ## Returns

  Adjusted threshold

  ## Examples

      adapt_threshold(0.7, :high)
      # => 0.9

      adapt_threshold(0.7, :low)
      # => 0.5
  """
  @spec adapt_threshold(float(), :low | :medium | :high) :: float()
  def adapt_threshold(base_threshold, :low), do: max(0.5, base_threshold - 0.2)
  def adapt_threshold(base_threshold, :medium), do: base_threshold
  def adapt_threshold(base_threshold, :high), do: min(0.95, base_threshold + 0.2)

  # Private helper functions

  defp default_validate_outcome(expected, actual, _opts) do
    score = similarity_score(expected, actual)

    cond do
      score > 0.95 -> :match
      score >= 0.8 -> :minor
      score >= 0.5 -> :moderate
      true -> :critical
    end
  end

  defp string_similarity(str1, str2) do
    # Simple character-based similarity
    set1 = String.graphemes(str1) |> MapSet.new()
    set2 = String.graphemes(str2) |> MapSet.new()

    intersection = MapSet.intersection(set1, set2) |> MapSet.size()
    union = MapSet.union(set1, set2) |> MapSet.size()

    if union == 0, do: 1.0, else: intersection / union
  end

  defp list_similarity(list1, list2) do
    set1 = MapSet.new(list1)
    set2 = MapSet.new(list2)

    intersection = MapSet.intersection(set1, set2) |> MapSet.size()
    union = MapSet.union(set1, set2) |> MapSet.size()

    if union == 0, do: 1.0, else: intersection / union
  end

  defp do_iterative_execute(%CorrectionContext{iteration: iteration, max_iter: max_iter})
       when iteration > max_iter do
    {:error, :max_iterations_exceeded}
  end

  defp do_iterative_execute(%CorrectionContext{} = context) do
    Logger.debug("Self-correction iteration #{context.iteration}/#{context.max_iter}")

    # Execute reasoning
    result = context.reasoning_fn.()

    # Validate result
    case context.validator.(result) do
      {:ok, validated_result} ->
        # Check quality
        score = quality_score(validated_result, [])

        if quality_threshold_met?(score, context.threshold) do
          Logger.info(
            "Self-correction succeeded at iteration #{context.iteration} with quality #{score}"
          )

          {:ok, validated_result}
        else
          # Quality not met, try correction
          handle_quality_failure(context, result, score)
        end

      {:error, reason, divergence} ->
        # Validation failed
        handle_validation_failure(context, result, reason, divergence)

      {:error, reason} ->
        # Validation error without divergence classification
        handle_validation_failure(context, result, reason, :critical)
    end
  end

  defp handle_quality_failure(%CorrectionContext{} = context, result, score) do
    Logger.warning("Quality threshold not met: #{score} < #{context.threshold}")

    if context.iteration >= context.max_iter do
      Logger.warning("Max iterations reached, accepting partial result")
      {:ok, result, :partial}
    else
      # Try correction
      strategy = select_correction_strategy(:minor, context.iteration, context.history)
      new_history = [{context.iteration, result, score, strategy} | context.history]

      if context.callback,
        do: context.callback.({:correction, context.iteration, strategy, score})

      new_context = %{context | iteration: context.iteration + 1, history: new_history}
      do_iterative_execute(new_context)
    end
  end

  defp handle_validation_failure(%CorrectionContext{} = context, result, reason, divergence) do
    Logger.warning("Validation failed: #{inspect(reason)}, divergence: #{divergence}")

    if context.iteration >= context.max_iter do
      {:error, reason}
    else
      strategy = select_correction_strategy(divergence, context.iteration, context.history)
      new_history = [{context.iteration, result, reason, divergence, strategy} | context.history]

      if context.callback,
        do: context.callback.({:correction, context.iteration, strategy, divergence})

      new_context = %{context | iteration: context.iteration + 1, history: new_history}
      do_iterative_execute(new_context)
    end
  end

  defp repeated_failure?(history) do
    # Check if same error appears multiple times
    failures =
      Enum.map(history, fn
        {_iter, _result, reason, _div, _strat} -> reason
        _ -> nil
      end)
      |> Enum.filter(&(&1 != nil))

    length(Enum.uniq(failures)) < length(failures)
  end

  defp ambiguous_requirements?(history) do
    # Check if errors suggest unclear requirements
    Enum.any?(history, fn
      {_iter, _result, reason, _div, _strat} when is_binary(reason) ->
        String.contains?(reason, ["unclear", "ambiguous", "undefined", "missing"])

      _ ->
        false
    end)
  end

  defp extract_confidence(result) when is_map(result) do
    Map.get(result, :confidence, Map.get(result, "confidence", 0.7))
  end

  defp extract_confidence(_result), do: 0.7

  defp extract_answer(result) when is_map(result) do
    Map.get(result, :answer, Map.get(result, "answer", result))
  end

  defp extract_answer(result), do: result
end
