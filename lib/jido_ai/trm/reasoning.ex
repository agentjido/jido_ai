defmodule Jido.AI.TRM.Reasoning do
  @moduledoc """
  Recursive Reasoning Engine for TRM (Tiny-Recursive-Model) strategy.

  This module provides structured prompt construction and result parsing for the
  reasoning phase of the TRM recursive improvement cycle. It handles:

  - Building reasoning prompts that guide the LLM to analyze current answers
  - Parsing LLM responses to extract key insights
  - Calculating confidence scores from response quality
  - Formatting reasoning traces for inclusion in subsequent prompts

  ## Overview

  The TRM reasoning phase takes a question and current answer, then generates
  structured analysis that identifies:
  - Key insights that are correct
  - Areas needing improvement
  - Missing considerations
  - Logical gaps or errors

  ## Usage

      context = %{
        question: "What is 2+2?",
        current_answer: "The answer is 4",
        latent_state: %{reasoning_trace: [], step_count: 1}
      }

      {system_prompt, user_prompt} = Reasoning.build_reasoning_prompt(context)
      # Use prompts to create LLM directive

      # After LLM response:
      result = Reasoning.parse_reasoning_result(llm_response)
      # %{insights: [...], issues: [...], confidence: 0.85}
  """

  import Jido.AI.TRM.Helpers, only: [clamp: 3, parse_float_safe: 1, sanitize_user_input: 1]

  @type reasoning_context :: %{
          question: String.t(),
          current_answer: String.t() | nil,
          latent_state: map()
        }

  @type reasoning_result :: %{
          insights: [String.t()],
          issues: [String.t()],
          suggestions: [String.t()],
          confidence: float(),
          raw_text: String.t()
        }

  @type parsed_insight :: %{
          type: :correct | :issue | :missing | :suggestion,
          content: String.t(),
          importance: :high | :medium | :low
        }

  # Import shared helpers

  # Confidence markers that indicate certainty
  @high_confidence_markers ~w(
    clearly definitely certainly absolutely obviously
    without doubt undoubtedly unquestionably
    proven confirmed verified correct accurate
  )

  # Uncertainty markers that reduce confidence
  @low_confidence_markers ~w(
    maybe perhaps possibly might could
    uncertain unclear unsure ambiguous
    potentially arguably questionable
    seems appears likely
  )

  # Issue markers in LLM responses
  @issue_markers ~w(
    incorrect wrong error mistake flaw
    problem issue gap missing incomplete
    inaccurate inconsistent contradicts
  )

  # ============================================================================
  # Prompt Building
  # ============================================================================

  @doc """
  Builds the reasoning prompt for the TRM reasoning phase.

  Returns a tuple of `{system_prompt, user_prompt}` that can be used to create
  an LLM directive.

  ## Parameters

  - `context` - A map containing:
    - `:question` - The original question being answered
    - `:current_answer` - The current answer (nil for first reasoning step)
    - `:latent_state` - Map with reasoning trace and other state

  ## Returns

  A tuple `{system_prompt, user_prompt}` where:
  - `system_prompt` - Instructions for the LLM's reasoning behavior
  - `user_prompt` - The specific prompt for this reasoning step

  ## Examples

      iex> context = %{question: "What is AI?", current_answer: nil, latent_state: %{}}
      iex> {system, user} = Reasoning.build_reasoning_prompt(context)
      iex> is_binary(system) and is_binary(user)
      true
  """
  @spec build_reasoning_prompt(reasoning_context()) :: {String.t(), String.t()}
  def build_reasoning_prompt(context) do
    system = default_reasoning_system_prompt()
    user = build_user_prompt(context)
    {system, user}
  end

  @doc """
  Returns the default system prompt for guiding recursive reasoning.

  The prompt instructs the LLM to:
  - Analyze the current answer thoroughly
  - Identify correct insights and errors
  - Provide structured analysis that can be parsed
  - Use explicit markers for different types of findings
  """
  @spec default_reasoning_system_prompt() :: String.t()
  def default_reasoning_system_prompt do
    """
    You are a recursive reasoning assistant that analyzes problems through iterative thinking.

    Your task is to examine the current answer and provide structured analysis with:

    1. **CORRECT INSIGHTS**: What is correct and should be preserved
       Format: "INSIGHT: [description of correct insight]"

    2. **ISSUES FOUND**: What needs improvement or is incorrect
       Format: "ISSUE: [description of problem]"

    3. **MISSING ELEMENTS**: What is missing or incomplete
       Format: "MISSING: [description of what's missing]"

    4. **SUGGESTIONS**: Specific improvements to make
       Format: "SUGGESTION: [specific improvement recommendation]"

    5. **CONFIDENCE**: Your assessment of the current answer quality
       Format: "CONFIDENCE: [0.0-1.0]"

    Be thorough, constructive, and use the exact format markers above for each point.
    This structured format helps with iterative improvement.
    """
  end

  @doc """
  Builds a prompt for updating latent state from reasoning insights.

  This prompt asks the LLM to summarize the key learnings from the reasoning
  step in a format suitable for carrying forward to subsequent iterations.
  """
  @spec build_latent_update_prompt(String.t(), String.t(), map()) :: String.t()
  def build_latent_update_prompt(question, reasoning_output, latent_state) do
    previous_trace = format_reasoning_trace(latent_state)
    safe_question = sanitize_user_input(question)

    """
    Based on the following reasoning analysis, extract the key learnings to carry forward:

    Question: #{safe_question}

    Previous Reasoning Trace:
    #{previous_trace}

    New Reasoning Analysis:
    #{reasoning_output}

    Summarize in 2-3 sentences the most important insights discovered that should inform the next iteration.
    Focus on: what we learned, what needs attention, and confidence level.
    """
  end

  @doc """
  Formats the reasoning trace from latent state for inclusion in prompts.

  Handles various formats of the reasoning trace (list, string, nil) and
  returns a formatted string suitable for prompt inclusion.
  """
  @spec format_reasoning_trace(map() | nil) :: String.t()
  def format_reasoning_trace(nil), do: "(none)"

  def format_reasoning_trace(%{reasoning_trace: trace}) when is_list(trace) do
    if Enum.empty?(trace) do
      "(none)"
    else
      trace
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {entry, idx} -> "Step #{idx}: #{entry}" end)
    end
  end

  def format_reasoning_trace(%{reasoning_trace: trace}) when is_binary(trace) do
    if String.trim(trace) == "" do
      "(none)"
    else
      trace
    end
  end

  def format_reasoning_trace(_), do: "(none)"

  # ============================================================================
  # Result Parsing
  # ============================================================================

  @doc """
  Parses an LLM reasoning response to extract structured insights.

  Looks for formatted markers in the response:
  - `INSIGHT:` - Correct insights to preserve
  - `ISSUE:` - Problems found in the answer
  - `MISSING:` - Missing elements
  - `SUGGESTION:` - Improvement recommendations
  - `CONFIDENCE:` - Explicit confidence score

  ## Parameters

  - `response` - The raw LLM response text

  ## Returns

  A map with:
  - `:insights` - List of correct insights found
  - `:issues` - List of problems identified
  - `:suggestions` - List of improvement suggestions (includes MISSING items)
  - `:confidence` - Calculated confidence score (0.0-1.0)
  - `:raw_text` - The original response text

  ## Examples

      iex> response = "INSIGHT: The math is correct\\nISSUE: Missing explanation\\nCONFIDENCE: 0.7"
      iex> result = Reasoning.parse_reasoning_result(response)
      iex> length(result.insights)
      1
  """
  @spec parse_reasoning_result(String.t()) :: reasoning_result()
  def parse_reasoning_result(response) when is_binary(response) do
    insights = extract_marked_items(response, "INSIGHT")
    issues = extract_marked_items(response, "ISSUE")
    missing = extract_marked_items(response, "MISSING")
    suggestions = extract_marked_items(response, "SUGGESTION")

    # Combine missing and suggestions
    all_suggestions = missing ++ suggestions

    # Calculate confidence from explicit marker or heuristics
    confidence = extract_or_calculate_confidence(response, insights, issues)

    %{
      insights: insights,
      issues: issues,
      suggestions: all_suggestions,
      confidence: confidence,
      raw_text: response
    }
  end

  def parse_reasoning_result(_), do: empty_result()

  @doc """
  Extracts key insights from a reasoning response.

  Identifies the most important points from the reasoning, prioritizing
  by relevance and impact. Returns a list of parsed insight structures.

  ## Parameters

  - `response` - The raw LLM response text

  ## Returns

  A list of `parsed_insight` maps, each containing:
  - `:type` - The type of insight (:correct, :issue, :missing, :suggestion)
  - `:content` - The insight text
  - `:importance` - Estimated importance (:high, :medium, :low)
  """
  @spec extract_key_insights(String.t()) :: [parsed_insight()]
  def extract_key_insights(response) when is_binary(response) do
    # Extract all marked items with their types
    insights =
      extract_marked_items(response, "INSIGHT")
      |> Enum.map(&build_insight(:correct, &1))

    issues =
      extract_marked_items(response, "ISSUE")
      |> Enum.map(&build_insight(:issue, &1))

    missing =
      extract_marked_items(response, "MISSING")
      |> Enum.map(&build_insight(:missing, &1))

    suggestions =
      extract_marked_items(response, "SUGGESTION")
      |> Enum.map(&build_insight(:suggestion, &1))

    # Combine and sort by importance
    (insights ++ issues ++ missing ++ suggestions)
    |> Enum.sort_by(&importance_rank/1, :desc)
  end

  def extract_key_insights(_), do: []

  @doc """
  Calculates a confidence score from the reasoning response quality.

  Uses multiple heuristics to estimate confidence:
  - Presence of explicit confidence marker
  - Ratio of insights to issues
  - Presence of uncertainty/certainty language
  - Response structure and completeness

  ## Parameters

  - `response` - The raw LLM response text

  ## Returns

  A float between 0.0 and 1.0 representing the confidence score.
  """
  @spec calculate_reasoning_confidence(String.t()) :: float()
  def calculate_reasoning_confidence(response) when is_binary(response) do
    result = parse_reasoning_result(response)
    result.confidence
  end

  def calculate_reasoning_confidence(_), do: 0.5

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp build_user_prompt(%{current_answer: nil} = context) do
    safe_question = sanitize_user_input(context[:question])

    """
    Question: #{safe_question}

    This is the first reasoning step. Analyze the question and provide an initial answer
    with your reasoning. Use the structured format with INSIGHT, ISSUE, MISSING, SUGGESTION markers.

    Consider:
    1. What is being asked
    2. Key concepts involved
    3. Step-by-step reasoning approach
    4. Initial answer with confidence level

    Provide your analysis using the structured format.
    """
  end

  defp build_user_prompt(context) do
    trace = format_reasoning_trace(context[:latent_state])
    safe_question = sanitize_user_input(context[:question])
    safe_answer = sanitize_user_input(context[:current_answer])

    """
    Question: #{safe_question}

    Current answer:
    #{safe_answer}

    Previous reasoning trace:
    #{trace}

    Analyze this answer using the structured format. Identify:
    - INSIGHT: What is correct and should be preserved
    - ISSUE: What needs improvement or is incorrect
    - MISSING: What is missing or incomplete
    - SUGGESTION: Specific improvements to make
    - CONFIDENCE: Your assessment (0.0-1.0)

    Provide your detailed reasoning analysis.
    """
  end

  defp extract_marked_items(text, marker) do
    # Match lines starting with the marker (case-insensitive)
    pattern = ~r/#{marker}:\s*(.+?)(?=\n(?:INSIGHT|ISSUE|MISSING|SUGGESTION|CONFIDENCE):|$)/is

    Regex.scan(pattern, text)
    |> Enum.map(fn [_, content] -> String.trim(content) end)
    |> Enum.reject(&(String.length(&1) == 0))
  end

  defp extract_or_calculate_confidence(response, insights, issues) do
    # Try to extract explicit confidence first
    case extract_explicit_confidence(response) do
      {:ok, confidence} ->
        confidence

      :not_found ->
        calculate_heuristic_confidence(response, insights, issues)
    end
  end

  defp extract_explicit_confidence(response) do
    case Regex.run(~r/CONFIDENCE:\s*(\d+(?:\.\d+)?)/i, response) do
      [_, score_str] ->
        score = parse_float_safe(score_str)
        {:ok, clamp(score, 0.0, 1.0)}

      _ ->
        :not_found
    end
  end

  defp calculate_heuristic_confidence(response, insights, issues) do
    base = 0.5

    # Adjust based on insight/issue ratio
    insight_count = length(insights)
    issue_count = length(issues)

    ratio_adjustment =
      cond do
        insight_count > 0 and issue_count == 0 -> 0.2
        insight_count > issue_count -> 0.1
        issue_count > insight_count -> -0.1
        true -> 0.0
      end

    # Adjust based on confidence language
    language_adjustment = calculate_language_confidence(response)

    # Adjust based on structure
    structure_adjustment =
      if has_good_structure?(response) do
        0.05
      else
        -0.05
      end

    clamp(base + ratio_adjustment + language_adjustment + structure_adjustment, 0.0, 1.0)
  end

  defp calculate_language_confidence(response) do
    response_lower = String.downcase(response)

    high_count =
      @high_confidence_markers
      |> Enum.count(&String.contains?(response_lower, &1))

    low_count =
      @low_confidence_markers
      |> Enum.count(&String.contains?(response_lower, &1))

    cond do
      high_count > low_count * 2 -> 0.15
      high_count > low_count -> 0.05
      low_count > high_count * 2 -> -0.15
      low_count > high_count -> -0.05
      true -> 0.0
    end
  end

  defp has_good_structure?(response) do
    # Check if response has at least 2 different marker types
    markers = ["INSIGHT:", "ISSUE:", "MISSING:", "SUGGESTION:", "CONFIDENCE:"]
    marker_count = Enum.count(markers, &String.contains?(response, &1))
    marker_count >= 2
  end

  defp build_insight(type, content) do
    %{
      type: type,
      content: content,
      importance: estimate_importance(type, content)
    }
  end

  defp estimate_importance(type, content) do
    content_lower = String.downcase(content)

    has_issue_marker =
      @issue_markers
      |> Enum.any?(&String.contains?(content_lower, &1))

    cond do
      # Issues and missing items are high importance
      type in [:issue, :missing] -> :high
      # Suggestions with issue markers are high
      type == :suggestion and has_issue_marker -> :high
      # Long, detailed insights are medium
      String.length(content) > 100 -> :medium
      # Everything else is low
      true -> :low
    end
  end

  defp importance_rank(%{importance: :high}), do: 3
  defp importance_rank(%{importance: :medium}), do: 2
  defp importance_rank(%{importance: :low}), do: 1

  defp empty_result do
    %{
      insights: [],
      issues: [],
      suggestions: [],
      confidence: 0.5,
      raw_text: ""
    }
  end
end
