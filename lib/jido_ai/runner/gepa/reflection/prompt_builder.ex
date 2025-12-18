defmodule Jido.AI.Runner.GEPA.Reflection.PromptBuilder do
  @moduledoc """
  Builds structured reflection prompts for LLM analysis (Task 1.3.2.1).

  This module formats trajectory analysis into prompts that request specific,
  actionable improvement suggestions from the LLM. The prompts present failure
  context, analysis findings, and constraints to guide the LLM toward generating
  useful suggestions.

  ## Prompt Structure

  1. **Context Section**: Failed execution details (prompt, task, outcome)
  2. **Analysis Section**: Trajectory analyzer findings (failures, reasoning issues)
  3. **Request Section**: Specific improvements needed
  4. **Constraints Section**: Response format and quality guidelines

  ## Usage

      analysis = TrajectoryAnalyzer.analyze(trajectory)
      request = %ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Solve step by step",
        verbosity: :normal
      }

      prompt = PromptBuilder.build_reflection_prompt(request)
      system_prompt = PromptBuilder.system_prompt()
  """

  alias Jido.AI.Runner.GEPA.Reflector

  @doc """
  System prompt defining the LLM's role and response format.

  This prompt establishes the LLM as an expert prompt engineer analyzing
  failures and guides it to provide structured JSON responses.

  ## Returns

  String containing the system prompt.

  ## Examples

      system = PromptBuilder.system_prompt()
  """
  @spec system_prompt() :: String.t()
  def system_prompt do
    """
    You are an expert prompt engineer analyzing failed LLM executions to suggest improvements.

    Your goal is to identify why a prompt failed and provide specific, actionable suggestions
    to fix the issues. Analyze the execution trajectory, identify root causes, and recommend
    targeted modifications.

    ## Response Format

    Provide your analysis in JSON format with this exact structure:

    ```json
    {
      "analysis": "Brief 2-3 sentence analysis of what went wrong",
      "root_causes": [
        "Primary cause 1",
        "Primary cause 2"
      ],
      "suggestions": [
        {
          "type": "add|modify|remove|restructure",
          "category": "clarity|constraint|example|structure|reasoning",
          "description": "Clear description of what to change",
          "rationale": "Why this change will help",
          "priority": "high|medium|low",
          "specific_text": "Exact text to add/modify (if applicable)",
          "target_section": "Which part of prompt to modify (if applicable)"
        }
      ],
      "expected_improvement": "What should improve if changes are applied"
    }
    ```

    ## Guidelines

    - Be specific and actionable - provide exact text when possible
    - Prioritize suggestions by expected impact
    - Focus on root causes, not symptoms
    - Preserve successful patterns while fixing failures
    - Suggest 3-7 concrete improvements
    - Use the exact JSON structure specified above
    """
  end

  @doc """
  Builds a reflection prompt from a reflection request.

  Formats the trajectory analysis, original prompt, and context into a structured
  prompt that guides the LLM to analyze failures and suggest improvements.

  ## Parameters

  - `request` - `ReflectionRequest` with trajectory analysis and context
  - `opts` - Options:
    - `:include_comparative` - Include comparative analysis if available (default: true)
    - `:include_success_patterns` - Include success indicators (default: true)

  ## Returns

  String containing the formatted reflection prompt.

  ## Examples

      request = %ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Solve this",
        task_description: "Math problem"
      }

      prompt = PromptBuilder.build_reflection_prompt(request)
  """
  @spec build_reflection_prompt(Reflector.ReflectionRequest.t(), keyword()) :: String.t()
  def build_reflection_prompt(%Reflector.ReflectionRequest{} = request, opts \\ []) do
    include_comparative = Keyword.get(opts, :include_comparative, true)
    include_success = Keyword.get(opts, :include_success_patterns, true)

    """
    # Failed Prompt Execution Analysis

    #{format_context_section(request)}

    #{format_analysis_section(request, include_comparative, include_success)}

    #{format_request_section(request)}

    #{format_constraints_section(request)}
    """
    |> String.trim()
  end

  @doc """
  Builds a follow-up prompt for multi-turn reflection.

  Creates a prompt that continues the conversation with a specific question
  or request for clarification based on previous reflection.

  ## Parameters

  - `initial_request` - Original reflection request
  - `previous_reflection` - Previous parsed reflection
  - `follow_up_question` - Specific question or clarification request

  ## Returns

  String containing the follow-up prompt.

  ## Examples

      follow_up = PromptBuilder.build_follow_up_prompt(
        request,
        reflection,
        "Can you elaborate on the reasoning failure in step 3?"
      )
  """
  @spec build_follow_up_prompt(
          Reflector.ReflectionRequest.t(),
          Reflector.ParsedReflection.t(),
          String.t()
        ) :: String.t()
  def build_follow_up_prompt(initial_request, previous_reflection, follow_up_question) do
    """
    # Continuing Reflection Analysis

    ## Previous Analysis
    #{previous_reflection.analysis}

    ## Follow-Up Question
    #{follow_up_question}

    ## Context Reminder
    Original Prompt: #{initial_request.original_prompt}
    Task: #{initial_request.task_description || "N/A"}

    Please provide additional analysis addressing the follow-up question.
    Use the same JSON format as before for any new suggestions.
    """
    |> String.trim()
  end

  # Private formatting functions

  defp format_context_section(request) do
    """
    ## Context

    **Original Prompt Being Evaluated:**
    ```
    #{request.original_prompt}
    ```

    **Task Description:** #{request.task_description || "General reasoning task"}

    **Execution Outcome:**
    #{format_outcome(request.trajectory_analysis)}

    **Key Metrics:**
    #{format_metrics(request.trajectory_analysis)}
    """
  end

  defp format_analysis_section(request, include_comparative, include_success) do
    analysis = request.trajectory_analysis

    base_analysis = """
    ## Trajectory Analysis

    ### Failure Points (#{length(analysis.failure_points)} detected)
    #{format_failure_points(analysis.failure_points)}

    ### Reasoning Issues (#{length(analysis.reasoning_issues)} found)
    #{format_reasoning_issues(analysis.reasoning_issues)}
    """

    success_section =
      if include_success and length(analysis.success_indicators) > 0 do
        """

        ### Success Indicators to Preserve
        #{format_success_indicators(analysis.success_indicators)}
        """
      else
        ""
      end

    comparative_section =
      if include_comparative and Map.get(analysis.metadata, :comparative_analysis) do
        """

        ### Comparative Analysis
        #{format_comparative_analysis(Map.get(analysis.metadata, :comparative_analysis))}
        """
      else
        ""
      end

    base_analysis <> success_section <> comparative_section
  end

  defp format_request_section(request) do
    focus_text =
      if length(request.focus_areas) > 0 do
        areas = Enum.map_join(request.focus_areas, ", ", &to_string/1)
        "\n**Focus Areas:** #{areas}\n"
      else
        ""
      end

    """
    ## Your Task

    Analyze this failed execution and provide specific, actionable suggestions to improve the prompt.
    #{focus_text}
    **Key Questions:**
    1. What are the root causes of the failures?
    2. What specific changes should be made to the prompt?
    3. What should be added to prevent these failures?
    4. What should be removed if it's causing issues?
    5. How should the prompt structure be improved?

    Focus on addressing the root causes while preserving any successful patterns identified.
    """
  end

  defp format_constraints_section(_request) do
    """
    ## Response Requirements

    - Provide 3-7 specific, actionable suggestions
    - Use the exact JSON structure specified in the system prompt
    - Prioritize by expected impact (high/medium/low)
    - Include specific text for additions/modifications when possible
    - Focus on root causes, not surface symptoms
    - Be concrete and implementable
    """
  end

  defp format_outcome(analysis) do
    outcome =
      case analysis.outcome do
        :success -> "✅ Success"
        :failure -> "❌ Failure"
        :timeout -> "⏱ Timeout"
        :error -> "⚠️ Error"
        :partial -> "⚡ Partial Success"
        _ -> "❓ Unknown"
      end

    outcome <> " (Overall Quality: #{analysis.overall_quality})"
  end

  defp format_metrics(analysis) do
    """
    - Duration: #{analysis.duration_ms || 0}ms
    - Steps: #{analysis.step_count}
    - Failure Points: #{length(analysis.failure_points)}
    - Reasoning Issues: #{length(analysis.reasoning_issues)}
    """
  end

  defp format_failure_points(failure_points) do
    if Enum.empty?(failure_points) do
      "None detected."
    else
      failure_points
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {fp, idx} ->
        severity_icon =
          case fp.severity do
            :critical -> "🔴"
            :high -> "🟠"
            :medium -> "🟡"
            :low -> "🟢"
          end

        """
        #{idx}. #{severity_icon} **#{fp.category}** (#{fp.severity})
           Description: #{fp.description}
           Step: #{fp.step_index || "N/A"}
        """
      end)
    end
  end

  defp format_reasoning_issues(reasoning_issues) do
    if Enum.empty?(reasoning_issues) do
      "None detected."
    else
      reasoning_issues
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {issue, idx} ->
        """
        #{idx}. **#{issue.type}**
           Description: #{issue.description}
           Steps: #{inspect(issue.step_ids)}
           Severity: #{issue.severity}
        """
      end)
    end
  end

  defp format_success_indicators(success_indicators) do
    if Enum.empty?(success_indicators) do
      "None identified."
    else
      success_indicators
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {indicator, idx} ->
        """
        #{idx}. ✅ **#{indicator.type}**
           Description: #{indicator.description}
           Impact: #{indicator.impact}
        """
      end)
    end
  end

  defp format_comparative_analysis(nil), do: "Not available."

  defp format_comparative_analysis(comparison) do
    """
    **Success Advantages:**
    #{Enum.map_join(comparison.success_advantages, "\n", fn adv -> "- #{adv}" end)}

    **Failure Disadvantages:**
    #{Enum.map_join(comparison.failure_disadvantages, "\n", fn disadv -> "- #{disadv}" end)}

    **Key Insights:**
    #{Enum.map_join(comparison.key_insights, "\n", fn insight -> "- #{insight}" end)}

    **Differences:**
    #{format_differences(comparison.differences)}
    """
  end

  defp format_differences(differences) when is_list(differences) do
    differences
    |> Enum.map_join("\n", fn diff ->
      "- #{diff.aspect}: #{diff.description} (#{diff.significance})"
    end)
  end

  defp format_differences(_), do: "None identified."
end
