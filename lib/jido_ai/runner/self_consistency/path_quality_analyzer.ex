defmodule Jido.AI.Runner.SelfConsistency.PathQualityAnalyzer do
  @moduledoc """
  Analyzes and scores the quality of reasoning paths.

  Quality analysis helps filter low-quality paths before voting, improving
  the reliability of self-consistency results. The analyzer considers:

  ## Quality Factors

  - **Reasoning Coherence**: Logical flow and consistency
  - **Completeness**: All steps present and explained
  - **Confidence**: Expressed certainty in conclusions
  - **Length**: Neither too brief nor excessively verbose
  - **Structure**: Clear organization and formatting

  ## Outlier Detection

  Identifies paths that are likely incorrect:
  - Extremely short or long compared to others
  - Low confidence scores
  - Contradictory statements
  - Missing key reasoning steps

  ## Calibration

  Adjusts confidence scores based on quality:
  - High quality path → maintain or boost confidence
  - Low quality path → reduce confidence weight
  - Outlier path → marked for potential exclusion
  """

  require Logger

  @type reasoning_path :: %{
          reasoning: String.t(),
          answer: term(),
          confidence: float(),
          quality_score: float() | nil
        }

  @type quality_analysis :: %{
          score: float(),
          factors: map(),
          outlier: boolean(),
          reasons: list(String.t())
        }

  @default_coherence_weight 0.3
  @default_completeness_weight 0.25
  @default_confidence_weight 0.2
  @default_length_weight 0.15
  @default_structure_weight 0.1

  @doc """
  Analyzes the quality of a reasoning path.

  ## Parameters

  - `path` - The reasoning path to analyze
  - `opts` - Options:
    - `:weights` - Custom weights for quality factors
    - `:context` - Other paths for comparison (for outlier detection)
    - `:min_length` - Minimum expected length
    - `:max_length` - Maximum expected length

  ## Returns

  Quality score from 0.0 to 1.0

  ## Examples

      score = PathQualityAnalyzer.analyze(%{
        reasoning: "Step 1... Step 2... Therefore...",
        answer: 42,
        confidence: 0.8
      })
      # => 0.75
  """
  @spec analyze(reasoning_path(), keyword()) :: float()
  def analyze(path, opts \\ []) do
    weights = Keyword.get(opts, :weights, default_weights())
    context = Keyword.get(opts, :context, [])

    factors = %{
      coherence: analyze_coherence(path),
      completeness: analyze_completeness(path),
      confidence: path.confidence || 0.5,
      length: analyze_length(path, opts),
      structure: analyze_structure(path)
    }

    # Calculate weighted score
    score =
      factors.coherence * weights.coherence +
        factors.completeness * weights.completeness +
        factors.confidence * weights.confidence +
        factors.length * weights.length +
        factors.structure * weights.structure

    # Adjust for outliers if context provided
    adjusted_score =
      if Enum.empty?(context) do
        score
      else
        outlier_penalty = detect_outlier_penalty(path, context)
        max(0.0, score - outlier_penalty)
      end

    adjusted_score
  end

  @doc """
  Performs detailed quality analysis with breakdown.

  Returns full analysis including individual factor scores,
  outlier detection, and reasons for the quality assessment.

  ## Parameters

  - `path` - The reasoning path to analyze
  - `opts` - Options (same as analyze/2)

  ## Returns

  Map with detailed quality analysis

  ## Examples

      analysis = PathQualityAnalyzer.detailed_analysis(path)
      # => %{
      #   score: 0.75,
      #   factors: %{coherence: 0.8, completeness: 0.7, ...},
      #   outlier: false,
      #   reasons: ["Good logical flow", "Complete reasoning steps"]
      # }
  """
  @spec detailed_analysis(reasoning_path(), keyword()) :: quality_analysis()
  def detailed_analysis(path, opts \\ []) do
    weights = Keyword.get(opts, :weights, default_weights())
    context = Keyword.get(opts, :context, [])

    factors = %{
      coherence: analyze_coherence(path),
      completeness: analyze_completeness(path),
      confidence: path.confidence || 0.5,
      length: analyze_length(path, opts),
      structure: analyze_structure(path)
    }

    score =
      factors.coherence * weights.coherence +
        factors.completeness * weights.completeness +
        factors.confidence * weights.confidence +
        factors.length * weights.length +
        factors.structure * weights.structure

    {outlier?, outlier_reasons} = detect_outlier(path, context)

    adjusted_score =
      if outlier? do
        outlier_penalty = detect_outlier_penalty(path, context)
        max(0.0, score - outlier_penalty)
      else
        score
      end

    reasons = build_quality_reasons(factors, outlier?, outlier_reasons)

    %{
      score: adjusted_score,
      factors: factors,
      outlier: outlier?,
      reasons: reasons
    }
  end

  @doc """
  Detects if a path is an outlier compared to others.

  ## Parameters

  - `path` - Path to check
  - `paths` - Other paths for comparison

  ## Returns

  `{true, reasons}` if outlier, `{false, []}` otherwise
  """
  @spec detect_outlier(reasoning_path(), list(reasoning_path())) ::
          {boolean(), list(String.t())}
  def detect_outlier(path, paths) when is_list(paths) and length(paths) > 0 do
    reasons = []

    # Check length outlier
    {is_outlier, reasons} = check_length_outlier(path, paths, reasons)

    # Check confidence outlier
    {is_outlier, reasons} = check_confidence_outlier(path, paths, is_outlier, reasons)

    # Check coherence outlier
    {is_outlier, reasons} = check_coherence_outlier(path, paths, is_outlier, reasons)

    {is_outlier, reasons}
  end

  def detect_outlier(_path, _paths), do: {false, []}

  @doc """
  Calibrates confidence based on quality.

  Adjusts the confidence score of a path based on its quality,
  reducing confidence for low-quality paths and maintaining or
  boosting confidence for high-quality paths.

  ## Parameters

  - `path` - The reasoning path
  - `opts` - Options for quality analysis

  ## Returns

  Calibrated confidence score (0.0 to 1.0)
  """
  @spec calibrate_confidence(reasoning_path(), keyword()) :: float()
  def calibrate_confidence(path, opts \\ []) do
    quality_score = analyze(path, opts)
    original_confidence = path.confidence || 0.5

    # Adjust confidence based on quality
    # High quality (>0.7): boost confidence slightly
    # Medium quality (0.4-0.7): maintain confidence
    # Low quality (<0.4): reduce confidence

    calibrated =
      cond do
        quality_score >= 0.7 ->
          # Boost confidence by up to 10%
          min(1.0, original_confidence * (1.0 + (quality_score - 0.7) * 0.33))

        quality_score >= 0.4 ->
          # Maintain confidence with slight adjustment
          original_confidence * (0.9 + quality_score * 0.2)

        true ->
          # Reduce confidence proportionally to low quality
          original_confidence * (quality_score / 0.4)
      end

    calibrated
  end

  # Private functions

  defp default_weights do
    %{
      coherence: @default_coherence_weight,
      completeness: @default_completeness_weight,
      confidence: @default_confidence_weight,
      length: @default_length_weight,
      structure: @default_structure_weight
    }
  end

  defp analyze_coherence(path) do
    reasoning = path.reasoning || ""

    # Coherence indicators
    has_therefore = String.contains?(reasoning, ["therefore", "thus", "hence"])
    has_because = String.contains?(reasoning, ["because", "since", "as"])
    has_steps = String.contains?(reasoning, ["step", "first", "second", "then", "next"])

    # Count logical connectors
    connector_count =
      if(has_therefore, do: 1, else: 0) +
        if(has_because, do: 1, else: 0) +
        if has_steps, do: 1, else: 0

    # Check for contradictions (simple heuristic)
    has_contradiction =
      String.contains?(reasoning, ["but", "however"]) and
        String.contains?(reasoning, ["not", "cannot", "impossible"])

    base_score = min(1.0, connector_count / 3.0 * 1.2)

    if has_contradiction do
      base_score * 0.7
    else
      base_score
    end
  end

  defp analyze_completeness(path) do
    reasoning = path.reasoning || ""

    # Completeness indicators
    has_answer = path.answer != nil
    has_conclusion = String.contains?(reasoning, ["answer", "result", "conclusion", "therefore"])
    has_reasoning_steps = String.length(reasoning) > 50

    # Check for question marks (might indicate incomplete reasoning)
    excessive_questions = length(Regex.scan(~r/\?/, reasoning)) > 2

    score =
      if(has_answer, do: 0.4, else: 0.0) +
        if(has_conclusion, do: 0.3, else: 0.0) +
        if has_reasoning_steps, do: 0.3, else: 0.0

    if excessive_questions do
      score * 0.8
    else
      score
    end
  end

  defp analyze_length(path, opts) do
    reasoning = path.reasoning || ""
    length = String.length(reasoning)

    min_length = Keyword.get(opts, :min_length, 50)
    max_length = Keyword.get(opts, :max_length, 2000)
    ideal_length = (min_length + max_length) / 2

    cond do
      length < min_length ->
        # Too short - penalize
        length / min_length

      length > max_length ->
        # Too long - penalize
        max(0.0, 1.0 - (length - max_length) / max_length)

      true ->
        # In acceptable range - score based on proximity to ideal
        1.0 - abs(length - ideal_length) / ideal_length * 0.3
    end
  end

  defp analyze_structure(path) do
    reasoning = path.reasoning || ""

    # Structure indicators
    has_paragraphs = String.contains?(reasoning, "\n\n")
    has_numbered_steps = Regex.match?(~r/\d+[.):]\s/, reasoning)
    has_sections = String.contains?(reasoning, ["Step", "Given", "Solution"])

    structure_score =
      if(has_paragraphs, do: 0.3, else: 0.0) +
        if(has_numbered_steps, do: 0.4, else: 0.0) +
        if has_sections, do: 0.3, else: 0.0

    max(0.3, structure_score)

    # Minimum score for unstructured but coherent reasoning
  end

  defp check_length_outlier(path, paths, reasons) do
    path_length = String.length(path.reasoning || "")

    lengths = Enum.map(paths, fn p -> String.length(p.reasoning || "") end)
    avg_length = Enum.sum(lengths) / length(lengths)
    std_dev = calculate_std_dev(lengths, avg_length)

    # Outlier if more than 2 standard deviations from mean
    if std_dev > 0 and abs(path_length - avg_length) > 2 * std_dev do
      reason =
        if path_length > avg_length do
          "Unusually long reasoning (#{path_length} vs avg #{trunc(avg_length)})"
        else
          "Unusually short reasoning (#{path_length} vs avg #{trunc(avg_length)})"
        end

      {true, [reason | reasons]}
    else
      {false, reasons}
    end
  end

  defp check_confidence_outlier(path, paths, current_outlier, reasons) do
    path_confidence = path.confidence || 0.5

    confidences = Enum.map(paths, fn p -> p.confidence || 0.5 end)
    avg_confidence = Enum.sum(confidences) / length(confidences)

    # Low confidence outlier (significantly below average)
    if path_confidence < avg_confidence * 0.5 do
      reason =
        "Very low confidence (#{Float.round(path_confidence, 2)} vs avg #{Float.round(avg_confidence, 2)})"

      {true, [reason | reasons]}
    else
      {current_outlier, reasons}
    end
  end

  defp check_coherence_outlier(path, _paths, current_outlier, reasons) do
    coherence = analyze_coherence(path)

    # Very low coherence is an outlier
    if coherence < 0.3 do
      {true, ["Poor reasoning coherence" | reasons]}
    else
      {current_outlier, reasons}
    end
  end

  defp detect_outlier_penalty(path, paths) do
    {is_outlier, _reasons} = detect_outlier(path, paths)

    if is_outlier do
      0.2
    else
      # 20% penalty for outliers
      0.0
    end
  end

  defp calculate_std_dev(values, mean) do
    variance =
      values
      |> Enum.map(fn v -> :math.pow(v - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(length(values))

    :math.sqrt(variance)
  end

  defp build_quality_reasons(factors, outlier?, outlier_reasons) do
    reasons = []

    # Add factor-based reasons
    reasons =
      if factors.coherence >= 0.7 do
        ["Good logical flow and coherence" | reasons]
      else
        reasons
      end

    reasons =
      if factors.completeness >= 0.7 do
        ["Complete reasoning with clear conclusion" | reasons]
      else
        reasons
      end

    reasons =
      if factors.confidence >= 0.7 do
        ["High confidence in conclusion" | reasons]
      else
        reasons
      end

    reasons =
      if factors.structure >= 0.7 do
        ["Well-structured reasoning" | reasons]
      else
        reasons
      end

    # Add outlier reasons if applicable
    if outlier? do
      reasons ++ outlier_reasons
    else
      reasons
    end
  end
end
