defmodule Jido.AI.TRM.Supervision do
  @moduledoc """
  Deep Supervision Module for TRM (Tiny-Recursive-Model) strategy.

  This module provides structured prompt construction and feedback parsing for the
  supervision and improvement phases of the TRM recursive improvement cycle. It handles:

  - Building supervision prompts for critical answer evaluation
  - Parsing LLM feedback to extract issues, suggestions, and quality scores
  - Building improvement prompts that incorporate feedback
  - Supporting iterative refinement with previous feedback context

  ## Overview

  The TRM supervision phase takes a question and current answer, then generates
  critical evaluation that identifies:
  - Issues with accuracy, completeness, clarity, and relevance
  - Specific suggestions for improvement
  - An overall quality score (0.0-1.0)

  The improvement phase then applies this feedback to generate an improved answer.

  ## Usage

      # Build supervision prompt
      context = %{
        question: "What is machine learning?",
        answer: "ML is a type of AI",
        step: 1,
        previous_feedback: nil
      }

      {system, user} = Supervision.build_supervision_prompt(context)

      # Parse supervision response
      feedback = Supervision.parse_supervision_result(llm_response)
      # %{issues: [...], suggestions: [...], quality_score: 0.65}

      # Build improvement prompt
      {system, user} = Supervision.build_improvement_prompt(
        context.question,
        context.answer,
        feedback
      )
  """

  import Jido.AI.TRM.Helpers, only: [clamp: 3, parse_float_safe: 1, sanitize_user_input: 1]

  @type feedback :: %{
          issues: [String.t()],
          suggestions: [String.t()],
          quality_score: float(),
          strengths: [String.t()],
          raw_text: String.t()
        }

  @type supervision_context :: %{
          question: String.t(),
          answer: String.t(),
          step: pos_integer(),
          previous_feedback: feedback() | nil
        }

  @type prioritized_suggestion :: %{
          content: String.t(),
          impact: :high | :medium | :low,
          category: atom()
        }

  # Import shared helpers

  # Issue markers in LLM responses
  @issue_markers ~w(
    ISSUE PROBLEM ERROR INCORRECT WRONG FLAW
    WEAKNESS MISSING INCOMPLETE UNCLEAR INACCURATE
  )

  # Suggestion markers in LLM responses
  @suggestion_markers ~w(
    SUGGESTION RECOMMEND IMPROVE ADD INCLUDE
    CONSIDER SHOULD COULD ENHANCE FIX
  )

  # Strength markers in LLM responses
  @strength_markers ~w(
    STRENGTH CORRECT GOOD ACCURATE CLEAR
    COMPLETE WELL PROPERLY EFFECTIVELY
  )

  # High impact keywords
  @high_impact_keywords ~w(
    critical essential must important fundamental
    key core necessary required vital
  )

  # ============================================================================
  # Supervision Prompt Construction
  # ============================================================================

  @doc """
  Builds the supervision prompt for critical answer evaluation.

  Returns a tuple of `{system_prompt, user_prompt}` that can be used to create
  an LLM directive for the supervision phase.

  ## Parameters

  - `context` - A map containing:
    - `:question` - The original question being answered
    - `:answer` - The current answer to evaluate
    - `:step` - The current supervision step number
    - `:previous_feedback` - Optional feedback from previous supervision (for iterative improvement)

  ## Returns

  A tuple `{system_prompt, user_prompt}` for LLM evaluation.

  ## Examples

      iex> context = %{question: "What is AI?", answer: "AI is...", step: 1, previous_feedback: nil}
      iex> {system, user} = Supervision.build_supervision_prompt(context)
      iex> is_binary(system) and is_binary(user)
      true
  """
  @spec build_supervision_prompt(supervision_context()) :: {String.t(), String.t()}
  def build_supervision_prompt(context) do
    system = default_supervision_system_prompt()
    user = build_supervision_user_prompt(context)
    {system, user}
  end

  @doc """
  Returns the default system prompt for critical answer supervision.

  The prompt instructs the LLM to:
  - Evaluate the answer across multiple quality dimensions
  - Identify specific issues and weaknesses
  - Provide actionable suggestions for improvement
  - Assign a quality score from 0.0 to 1.0
  """
  @spec default_supervision_system_prompt() :: String.t()
  def default_supervision_system_prompt do
    """
    You are a critical evaluator providing feedback on answers. Your task is to thoroughly evaluate the given answer and provide structured feedback.

    Evaluate across these dimensions:
    #{format_quality_criteria()}

    Provide your evaluation using this exact format:

    **STRENGTHS** (what is correct and well-done):
    - STRENGTH: [specific strength]

    **ISSUES** (problems that need to be fixed):
    - ISSUE: [specific issue with the answer]

    **SUGGESTIONS** (how to improve):
    - SUGGESTION: [specific actionable improvement]

    **SCORE**: [0.0-1.0] (overall quality score)

    Be specific, constructive, and actionable in your feedback.
    Higher scores (0.8+) mean the answer is mostly correct and complete.
    Lower scores (below 0.5) mean significant issues need addressing.
    """
  end

  @doc """
  Formats the quality criteria for inclusion in prompts.

  Lists the evaluation dimensions with brief descriptions.
  """
  @spec format_quality_criteria() :: String.t()
  def format_quality_criteria do
    """
    1. **Accuracy**: Is the answer factually correct? Are there any errors?
    2. **Completeness**: Does it fully address the question? Is anything missing?
    3. **Clarity**: Is the explanation clear and well-organized?
    4. **Relevance**: Does it stay focused on the question asked?
    """
  end

  @doc """
  Includes previous feedback context for iterative improvement.

  Formats the previous feedback for inclusion in the supervision prompt,
  allowing the evaluator to see what was already addressed.
  """
  @spec include_previous_feedback(String.t(), feedback() | nil) :: String.t()
  def include_previous_feedback(base_prompt, nil), do: base_prompt

  def include_previous_feedback(base_prompt, previous_feedback) do
    previous_context = """

    **Previous Feedback (from earlier evaluation)**:
    Issues identified: #{format_list(previous_feedback.issues)}
    Suggestions given: #{format_list(previous_feedback.suggestions)}
    Previous score: #{previous_feedback.quality_score}

    Evaluate whether these issues have been addressed in the current answer.
    """

    base_prompt <> previous_context
  end

  # ============================================================================
  # Feedback Parsing
  # ============================================================================

  @doc """
  Parses a supervision LLM response to extract structured feedback.

  Looks for formatted markers in the response:
  - `STRENGTH:` - Things done well
  - `ISSUE:` - Problems identified
  - `SUGGESTION:` - Improvement recommendations
  - `SCORE:` - Overall quality score (0.0-1.0)

  ## Parameters

  - `response` - The raw LLM response text

  ## Returns

  A feedback map with:
  - `:issues` - List of issues identified
  - `:suggestions` - List of improvement suggestions
  - `:strengths` - List of things done well
  - `:quality_score` - Overall score (0.0-1.0)
  - `:raw_text` - The original response

  ## Examples

      iex> response = "ISSUE: Missing explanation\\nSUGGESTION: Add details\\nSCORE: 0.6"
      iex> feedback = Supervision.parse_supervision_result(response)
      iex> length(feedback.issues)
      1
  """
  @spec parse_supervision_result(String.t()) :: feedback()
  def parse_supervision_result(response) when is_binary(response) do
    issues = extract_issues(response)
    suggestions = extract_suggestions(response)
    strengths = extract_strengths(response)
    quality_score = calculate_quality_score(response, issues, strengths)

    %{
      issues: issues,
      suggestions: suggestions,
      strengths: strengths,
      quality_score: quality_score,
      raw_text: response
    }
  end

  def parse_supervision_result(_), do: empty_feedback()

  @doc """
  Extracts issues from a supervision response.

  Looks for lines starting with issue markers (ISSUE:, PROBLEM:, etc.)
  and returns them as a list of strings.
  """
  @spec extract_issues(String.t()) :: [String.t()]
  def extract_issues(response) when is_binary(response) do
    extract_marked_items(response, @issue_markers)
  end

  def extract_issues(_), do: []

  @doc """
  Extracts improvement suggestions from a supervision response.

  Looks for lines starting with suggestion markers (SUGGESTION:, RECOMMEND:, etc.)
  and returns them as a list of strings.
  """
  @spec extract_suggestions(String.t()) :: [String.t()]
  def extract_suggestions(response) when is_binary(response) do
    extract_marked_items(response, @suggestion_markers)
  end

  def extract_suggestions(_), do: []

  @doc """
  Extracts strengths from a supervision response.

  Looks for lines starting with strength markers (STRENGTH:, CORRECT:, etc.)
  and returns them as a list of strings.
  """
  @spec extract_strengths(String.t()) :: [String.t()]
  def extract_strengths(response) when is_binary(response) do
    extract_marked_items(response, @strength_markers)
  end

  def extract_strengths(_), do: []

  @doc """
  Calculates the quality score from a supervision response.

  First tries to extract an explicit SCORE marker. If not found,
  calculates a heuristic score based on the ratio of strengths to issues.

  ## Parameters

  - `response` - The raw LLM response text

  ## Returns

  A float between 0.0 and 1.0 representing the quality score.
  """
  @spec calculate_quality_score(String.t()) :: float()
  def calculate_quality_score(response) when is_binary(response) do
    issues = extract_issues(response)
    strengths = extract_strengths(response)
    calculate_quality_score(response, issues, strengths)
  end

  def calculate_quality_score(_), do: 0.5

  @spec calculate_quality_score(String.t(), [String.t()], [String.t()]) :: float()
  defp calculate_quality_score(response, issues, strengths) do
    case extract_explicit_score(response) do
      {:ok, score} ->
        score

      :not_found ->
        calculate_heuristic_score(issues, strengths)
    end
  end

  # ============================================================================
  # Improvement Prompt Construction
  # ============================================================================

  @doc """
  Builds the improvement prompt for applying feedback.

  Returns a tuple of `{system_prompt, user_prompt}` that can be used to create
  an LLM directive for the improvement phase.

  ## Parameters

  - `question` - The original question
  - `answer` - The current answer to improve
  - `feedback` - The feedback from supervision (issues, suggestions, score)

  ## Returns

  A tuple `{system_prompt, user_prompt}` for generating an improved answer.
  """
  @spec build_improvement_prompt(String.t(), String.t(), feedback()) ::
          {String.t(), String.t()}
  def build_improvement_prompt(question, answer, feedback) do
    system = default_improvement_system_prompt()
    user = build_improvement_user_prompt(question, answer, feedback)
    {system, user}
  end

  @doc """
  Returns the default system prompt for applying feedback to improve answers.

  The prompt instructs the LLM to:
  - Address all identified issues
  - Implement the suggested improvements
  - Preserve what was already correct
  - Produce a complete, improved answer
  """
  @spec default_improvement_system_prompt() :: String.t()
  def default_improvement_system_prompt do
    """
    You are an assistant that improves answers based on feedback. Your task is to create an improved version of the answer that:

    1. **Addresses all issues**: Fix every problem identified in the feedback
    2. **Implements suggestions**: Apply the improvement recommendations
    3. **Preserves strengths**: Keep what was already correct and well-done
    4. **Maintains focus**: Stay on topic and answer the original question

    Provide a complete, improved answer that incorporates all the feedback.
    Do not just list changes - write the full improved answer.
    """
  end

  @doc """
  Prioritizes suggestions by estimated impact.

  Analyzes each suggestion to estimate its impact on answer quality,
  then returns them sorted from highest to lowest impact.

  ## Parameters

  - `suggestions` - List of suggestion strings

  ## Returns

  A list of prioritized suggestion maps with `:content`, `:impact`, and `:category`.
  """
  @spec prioritize_suggestions([String.t()]) :: [prioritized_suggestion()]
  def prioritize_suggestions(suggestions) when is_list(suggestions) do
    suggestions
    |> Enum.map(&analyze_suggestion/1)
    |> Enum.sort_by(&impact_rank/1, :desc)
  end

  def prioritize_suggestions(_), do: []

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp build_supervision_user_prompt(context) do
    safe_question = sanitize_user_input(context.question)
    safe_answer = sanitize_user_input(context.answer)

    base_prompt = """
    **Question**: #{safe_question}

    **Answer to evaluate**:
    #{safe_answer}

    **Evaluation step**: #{context.step}

    Please evaluate this answer using the structured format with STRENGTH, ISSUE, SUGGESTION markers, and provide an overall SCORE.
    """

    include_previous_feedback(base_prompt, context[:previous_feedback])
  end

  defp build_improvement_user_prompt(question, answer, feedback) do
    safe_question = sanitize_user_input(question)
    safe_answer = sanitize_user_input(answer)
    prioritized = prioritize_suggestions(feedback.suggestions)

    suggestions_text =
      if Enum.empty?(prioritized) do
        "(none specified)"
      else
        prioritized
        |> Enum.map_join("\n", fn s -> "- [#{s.impact}] #{s.content}" end)
      end

    issues_text =
      if Enum.empty?(feedback.issues) do
        "(none identified)"
      else
        feedback.issues
        |> Enum.map_join("\n", &("- " <> &1))
      end

    strengths_text =
      if Enum.empty?(feedback.strengths) do
        "(none identified)"
      else
        feedback.strengths
        |> Enum.map_join("\n", &("- " <> &1))
      end

    """
    **Original Question**: #{safe_question}

    **Current Answer**:
    #{safe_answer}

    **Current Quality Score**: #{feedback.quality_score}

    **Strengths to preserve**:
    #{strengths_text}

    **Issues to address**:
    #{issues_text}

    **Suggestions (prioritized by impact)**:
    #{suggestions_text}

    Please provide a complete, improved answer that addresses all issues and implements the suggestions while preserving the strengths.
    """
  end

  defp extract_marked_items(text, markers) do
    # Build a pattern that matches any of the markers we're looking for
    marker_pattern = Enum.join(markers, "|")

    # All possible markers that could end a section
    all_markers = @issue_markers ++ @suggestion_markers ++ @strength_markers ++ ["SCORE"]
    all_marker_pattern = Enum.join(all_markers, "|")

    # Match lines with any of the markers (case-insensitive)
    # Stop at any marker type, not just the same type we're matching
    pattern = ~r/(?:#{marker_pattern})[:\s]+(.+?)(?=\n(?:#{all_marker_pattern})[:\s]|\n\n|\n\*\*|$)/is

    Regex.scan(pattern, text)
    |> Enum.map(fn [_, content] -> String.trim(content) end)
    |> Enum.reject(&(String.length(&1) == 0))
    |> Enum.uniq()
  end

  defp extract_explicit_score(response) do
    case Regex.run(~r/\*?\*?SCORE\*?\*?[:\s]+(\d+(?:\.\d+)?)/i, response) do
      [_, score_str] ->
        score = parse_float_safe(score_str)
        {:ok, clamp(score, 0.0, 1.0)}

      _ ->
        :not_found
    end
  end

  defp calculate_heuristic_score(issues, strengths) do
    issue_count = length(issues)
    strength_count = length(strengths)
    total = issue_count + strength_count

    cond do
      total == 0 ->
        0.5

      strength_count > issue_count * 2 ->
        0.8

      strength_count > issue_count ->
        0.65

      issue_count > strength_count * 2 ->
        0.3

      issue_count > strength_count ->
        0.45

      true ->
        0.5
    end
  end

  defp analyze_suggestion(suggestion) do
    content_lower = String.downcase(suggestion)

    %{
      content: suggestion,
      impact: determine_impact(content_lower, suggestion),
      category: categorize_suggestion(content_lower)
    }
  end

  defp determine_impact(content_lower, suggestion) do
    has_high_impact =
      Enum.any?(@high_impact_keywords, &String.contains?(content_lower, &1))

    cond do
      has_high_impact -> :high
      String.length(suggestion) > 100 -> :medium
      true -> :low
    end
  end

  defp categorize_suggestion(content_lower) do
    cond do
      contains_any?(content_lower, ["accura", "correct"]) -> :accuracy
      contains_any?(content_lower, ["complet", "missing"]) -> :completeness
      contains_any?(content_lower, ["clear", "explain"]) -> :clarity
      contains_any?(content_lower, ["relevan", "focus"]) -> :relevance
      true -> :general
    end
  end

  defp contains_any?(content, patterns) do
    Enum.any?(patterns, &String.contains?(content, &1))
  end

  defp impact_rank(%{impact: :high}), do: 3
  defp impact_rank(%{impact: :medium}), do: 2
  defp impact_rank(%{impact: :low}), do: 1

  defp empty_feedback do
    %{
      issues: [],
      suggestions: [],
      strengths: [],
      quality_score: 0.5,
      raw_text: ""
    }
  end

  defp format_list([]), do: "(none)"
  defp format_list(items), do: Enum.join(items, "; ")
end
