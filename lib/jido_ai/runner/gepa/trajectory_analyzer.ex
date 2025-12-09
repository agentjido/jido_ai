defmodule Jido.AI.Runner.GEPA.TrajectoryAnalyzer do
  @moduledoc """
  Trajectory analysis system for GEPA reflection and feedback generation.

  This module implements Section 1.3.1 of the GEPA implementation plan, providing
  comprehensive trajectory analysis that extracts actionable insights for LLM-guided
  reflection. It identifies failure points, detects logical inconsistencies, extracts
  success patterns, and performs comparative analysis between trajectories.

  ## Key Features

  - **Failure Point Identification**: Pinpoints where and why execution failed
  - **Reasoning Analysis**: Detects logical inconsistencies in reasoning chains
  - **Success Pattern Extraction**: Identifies characteristics of high-performing trajectories
  - **Comparative Analysis**: Highlights differences between successful and failed attempts

  ## Architecture

  The analyzer produces structured analysis results that serve as input to LLM reflection:

  1. **TrajectoryAnalysis**: Complete analysis of a single trajectory
  2. **FailurePoint**: Specific locations where failures occurred
  3. **ReasoningIssue**: Detected logical inconsistencies
  4. **SuccessIndicator**: Patterns from successful executions
  5. **ComparativeAnalysis**: Differences between trajectory pairs

  ## Usage

      # Analyze a single trajectory
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      # Extract success patterns from high-performing trajectories
      patterns = TrajectoryAnalyzer.extract_success_patterns([trajectory1, trajectory2])

      # Compare successful vs failed trajectories
      comparison = TrajectoryAnalyzer.compare_trajectories(success_traj, failure_traj)

      # Generate natural language summary for LLM
      summary = TrajectoryAnalyzer.summarize(analysis)

  ## Implementation Status

  - [x] 1.3.1.1 Trajectory analyzer identifying failure points and error patterns
  - [x] 1.3.1.2 Reasoning step analysis detecting logical inconsistencies
  - [x] 1.3.1.3 Success pattern extraction from high-performing executions
  - [x] 1.3.1.4 Comparative analysis between successful and failed attempts
  """

  use TypedStruct
  require Logger

  alias Jido.AI.Runner.GEPA.Trajectory

  # Type definitions

  @type failure_category ::
          :timeout
          | :error
          | :logical_error
          | :incomplete
          | :tool_failure
          | :state_error
          | :unknown

  @type reasoning_issue_type ::
          :contradiction
          | :circular_reasoning
          | :incomplete_logic
          | :unsupported_conclusion
          | :missing_step

  @type success_indicator_type ::
          :efficient_path
          | :clear_reasoning
          | :proper_tool_use
          | :good_decomposition
          | :effective_recovery

  typedstruct module: FailurePoint do
    @moduledoc """
    Identification of a specific failure point in trajectory execution.

    Captures where the failure occurred, what type of failure it was,
    and contextual information for reflection.
    """

    field(:step_id, String.t() | nil)
    field(:step_index, non_neg_integer() | nil)
    field(:category, Jido.AI.Runner.GEPA.TrajectoryAnalyzer.failure_category(), enforce: true)
    field(:description, String.t(), enforce: true)
    field(:context, map(), default: %{})
    field(:severity, :low | :medium | :high | :critical, default: :medium)
    field(:timestamp, DateTime.t())
  end

  typedstruct module: ReasoningIssue do
    @moduledoc """
    Detected logical inconsistency or problem in reasoning steps.

    Identifies issues in the chain of reasoning that may have
    contributed to failures or suboptimal outcomes.
    """

    field(
      :type,
      Jido.AI.Runner.GEPA.TrajectoryAnalyzer.reasoning_issue_type(),
      enforce: true
    )

    field(:description, String.t(), enforce: true)
    field(:step_ids, list(String.t()), default: [])
    field(:evidence, String.t())
    field(:severity, :low | :medium | :high, default: :medium)
  end

  typedstruct module: SuccessIndicator do
    @moduledoc """
    Pattern or characteristic from a successful trajectory.

    Captures what went well in high-performing executions that
    could be encouraged in future prompts.
    """

    field(
      :type,
      Jido.AI.Runner.GEPA.TrajectoryAnalyzer.success_indicator_type(),
      enforce: true
    )

    field(:description, String.t(), enforce: true)
    field(:evidence, String.t())
    field(:impact, :low | :medium | :high, default: :medium)
    field(:step_ids, list(String.t()), default: [])
  end

  typedstruct module: Difference do
    @moduledoc """
    Specific difference between two trajectories.

    Used in comparative analysis to highlight what differs
    between successful and failed attempts.
    """

    field(:aspect, atom(), enforce: true)
    field(:successful_value, term())
    field(:failed_value, term())
    field(:description, String.t(), enforce: true)
    field(:significance, :low | :medium | :high, default: :medium)
  end

  typedstruct module: ComparativeAnalysis do
    @moduledoc """
    Comparative analysis between successful and failed trajectories.

    Highlights key differences that may explain performance variation.
    """

    field(:differences, list(Difference.t()), default: [])
    field(:success_advantages, list(String.t()), default: [])
    field(:failure_disadvantages, list(String.t()), default: [])
    field(:key_insights, list(String.t()), default: [])
  end

  typedstruct module: TrajectoryAnalysis do
    @moduledoc """
    Complete analysis result for a trajectory.

    Aggregates all analysis dimensions: failures, reasoning issues,
    success patterns, and metadata for LLM reflection.
    """

    field(:trajectory_id, String.t(), enforce: true)
    field(:outcome, Trajectory.outcome(), enforce: true)

    field(:failure_points, list(FailurePoint.t()),
      default: []
    )

    field(:reasoning_issues, list(ReasoningIssue.t()),
      default: []
    )

    field(:success_indicators, list(SuccessIndicator.t()),
      default: []
    )

    field(:overall_quality, :poor | :fair | :good | :excellent)
    field(:duration_ms, non_neg_integer())
    field(:step_count, non_neg_integer())
    field(:metadata, map(), default: %{})
  end

  # Public API

  @doc """
  Analyzes a single trajectory to extract insights for reflection.

  Returns a complete `TrajectoryAnalysis` struct containing:
  - Failure points (if outcome is not success)
  - Reasoning issues detected in steps
  - Success indicators (if outcome is success)
  - Overall quality assessment

  ## Options

  - `:min_severity` - Minimum severity to include (default: :low)
  - `:include_reasoning_analysis` - Whether to analyze reasoning (default: true)
  - `:include_success_patterns` - Whether to extract success patterns (default: true)

  ## Examples

      iex> analysis = TrajectoryAnalyzer.analyze(trajectory)
      %TrajectoryAnalysis{
        trajectory_id: "traj_123",
        outcome: :failure,
        failure_points: [%FailurePoint{...}],
        reasoning_issues: [%ReasoningIssue{...}]
      }
  """
  @spec analyze(Trajectory.t(), keyword()) :: TrajectoryAnalysis.t()
  def analyze(%Trajectory{} = trajectory, opts \\ []) do
    include_reasoning = Keyword.get(opts, :include_reasoning_analysis, true)
    include_success = Keyword.get(opts, :include_success_patterns, true)

    # Build analysis
    analysis = %TrajectoryAnalysis{
      trajectory_id: trajectory.id,
      outcome: trajectory.outcome || :unknown,
      duration_ms: trajectory.duration_ms,
      step_count: length(trajectory.steps),
      metadata: trajectory.metadata
    }

    # Add failure analysis if not successful
    analysis =
      if trajectory.outcome in [:success, nil] do
        analysis
      else
        failure_points = identify_failure_points(trajectory)
        %{analysis | failure_points: failure_points}
      end

    # Add reasoning analysis if requested
    analysis =
      if include_reasoning do
        issues = analyze_reasoning_steps(trajectory)
        %{analysis | reasoning_issues: issues}
      else
        analysis
      end

    # Add success patterns if successful and requested
    analysis =
      if trajectory.outcome == :success and include_success do
        indicators = extract_success_indicators(trajectory)
        %{analysis | success_indicators: indicators}
      else
        analysis
      end

    # Calculate overall quality
    quality = assess_overall_quality(analysis, trajectory)
    %{analysis | overall_quality: quality}
  end

  @doc """
  Finds common error patterns across multiple trajectories.

  Aggregates failure points from multiple trajectories to identify
  recurring patterns that indicate systemic issues with prompts.

  ## Options

  - `:min_frequency` - Minimum occurrences to be considered a pattern (default: 2)
  - `:group_by` - How to group failures (default: :category)

  ## Examples

      iex> patterns = TrajectoryAnalyzer.find_error_patterns([traj1, traj2, traj3])
      %{
        timeout: 5,
        tool_failure: 2,
        logical_error: 1
      }
  """
  @spec find_error_patterns(list(Trajectory.t()), keyword()) :: map()
  def find_error_patterns(trajectories, opts \\ []) when is_list(trajectories) do
    min_frequency = Keyword.get(opts, :min_frequency, 2)

    trajectories
    |> Enum.flat_map(fn trajectory ->
      identify_failure_points(trajectory)
    end)
    |> Enum.group_by(& &1.category)
    |> Enum.map(fn {category, failures} ->
      {category, length(failures)}
    end)
    |> Enum.filter(fn {_category, count} -> count >= min_frequency end)
    |> Map.new()
  end

  @doc """
  Analyzes reasoning steps in a trajectory for logical issues.

  Detects contradictions, circular reasoning, incomplete logic,
  and other reasoning problems that may indicate prompt weaknesses.

  ## Examples

      iex> issues = TrajectoryAnalyzer.analyze_reasoning_steps(trajectory)
      [
        %ReasoningIssue{type: :contradiction, description: "..."},
        %ReasoningIssue{type: :incomplete_logic, description: "..."}
      ]
  """
  @spec analyze_reasoning_steps(Trajectory.t()) :: list(ReasoningIssue.t())
  def analyze_reasoning_steps(%Trajectory{} = trajectory) do
    reasoning_steps =
      trajectory.steps
      |> Enum.filter(&(&1.type == :reasoning))

    issues = []

    # Check for contradictions
    issues = issues ++ detect_contradictions(reasoning_steps)

    # Check for circular reasoning
    issues = issues ++ detect_circular_reasoning(reasoning_steps)

    # Check for incomplete logic
    issues = issues ++ detect_incomplete_logic(reasoning_steps)

    # Check for unsupported conclusions
    issues = issues ++ detect_unsupported_conclusions(reasoning_steps)

    issues
  end

  @doc """
  Extracts success patterns from high-performing trajectories.

  Analyzes successful executions to identify what made them effective,
  such as efficient paths, clear reasoning, or proper tool usage.

  ## Options

  - `:min_quality` - Minimum quality threshold (default: :good)

  ## Examples

      iex> patterns = TrajectoryAnalyzer.extract_success_patterns([success1, success2])
      [
        %SuccessIndicator{type: :efficient_path, description: "..."},
        %SuccessIndicator{type: :clear_reasoning, description: "..."}
      ]
  """
  @spec extract_success_patterns(list(Trajectory.t()), keyword()) ::
          list(SuccessIndicator.t())
  def extract_success_patterns(trajectories, opts \\ []) when is_list(trajectories) do
    min_quality = Keyword.get(opts, :min_quality, :good)

    trajectories
    |> Enum.filter(&(&1.outcome == :success))
    |> Enum.flat_map(&extract_success_indicators/1)
    |> Enum.filter(&filter_by_quality(&1, min_quality))
    |> deduplicate_indicators()
  end

  @doc """
  Compares successful and failed trajectories to identify key differences.

  Performs comparative analysis highlighting what differed between
  successful and failed attempts, providing insights for improvement.

  ## Examples

      iex> comparison = TrajectoryAnalyzer.compare_trajectories(success_traj, failure_traj)
      %ComparativeAnalysis{
        differences: [%Difference{...}],
        key_insights: ["Successful trajectory had clearer reasoning steps"]
      }
  """
  @spec compare_trajectories(Trajectory.t(), Trajectory.t(), keyword()) ::
          ComparativeAnalysis.t()
  def compare_trajectories(
        %Trajectory{} = successful,
        %Trajectory{} = failed,
        _opts \\ []
      ) do
    differences = []

    # Compare step counts
    differences =
      if length(successful.steps) != length(failed.steps) do
        [
          %Difference{
            aspect: :step_count,
            successful_value: length(successful.steps),
            failed_value: length(failed.steps),
            description:
              "Successful trajectory had #{length(successful.steps)} steps vs #{length(failed.steps)}",
            significance: :medium
          }
          | differences
        ]
      else
        differences
      end

    # Compare durations
    differences =
      if successful.duration_ms && failed.duration_ms do
        ratio = successful.duration_ms / max(failed.duration_ms, 1)

        if abs(ratio - 1.0) > 0.2 do
          [
            %Difference{
              aspect: :duration,
              successful_value: successful.duration_ms,
              failed_value: failed.duration_ms,
              description: "Execution time differed significantly",
              significance: :medium
            }
            | differences
          ]
        else
          differences
        end
      else
        differences
      end

    # Compare reasoning step patterns
    success_reasoning = Enum.filter(successful.steps, &(&1.type == :reasoning))
    failed_reasoning = Enum.filter(failed.steps, &(&1.type == :reasoning))

    differences =
      if length(success_reasoning) != length(failed_reasoning) do
        [
          %Difference{
            aspect: :reasoning_steps,
            successful_value: length(success_reasoning),
            failed_value: length(failed_reasoning),
            description:
              "Different number of reasoning steps: #{length(success_reasoning)} vs #{length(failed_reasoning)}",
            significance: :high
          }
          | differences
        ]
      else
        differences
      end

    # Compare tool usage
    success_actions = Enum.filter(successful.steps, &(&1.type in [:action, :tool_call]))
    failed_actions = Enum.filter(failed.steps, &(&1.type in [:action, :tool_call]))

    differences =
      if length(success_actions) != length(failed_actions) do
        [
          %Difference{
            aspect: :tool_usage,
            successful_value: length(success_actions),
            failed_value: length(failed_actions),
            description:
              "Different tool usage patterns: #{length(success_actions)} vs #{length(failed_actions)} calls",
            significance: :high
          }
          | differences
        ]
      else
        differences
      end

    # Generate insights
    insights = generate_comparative_insights(differences, successful, failed)

    %ComparativeAnalysis{
      differences: differences,
      success_advantages: extract_success_advantages(differences),
      failure_disadvantages: extract_failure_disadvantages(differences),
      key_insights: insights
    }
  end

  @doc """
  Generates a natural language summary of trajectory analysis.

  Produces a structured summary suitable for LLM reflection, highlighting
  the most important findings in a readable format.

  ## Options

  - `:format` - Output format (default: :structured)
  - `:verbosity` - Detail level :brief | :normal | :detailed (default: :normal)

  ## Examples

      iex> summary = TrajectoryAnalyzer.summarize(analysis)
      "Trajectory traj_123 failed with 2 critical issues..."
  """
  @spec summarize(TrajectoryAnalysis.t(), keyword()) :: String.t()
  def summarize(%TrajectoryAnalysis{} = analysis, opts \\ []) do
    verbosity = Keyword.get(opts, :verbosity, :normal)

    sections = []

    # Overview
    overview = """
    Trajectory #{analysis.trajectory_id} - Outcome: #{analysis.outcome}
    Duration: #{analysis.duration_ms}ms, Steps: #{analysis.step_count}
    Overall Quality: #{analysis.overall_quality}
    """

    sections = [overview | sections]

    # Failure points
    sections =
      if analysis.failure_points != [] do
        failure_summary = """

        Failure Points (#{length(analysis.failure_points)}):
        #{Enum.map_join(analysis.failure_points, "\n", &format_failure_point(&1, verbosity))}
        """

        [failure_summary | sections]
      else
        sections
      end

    # Reasoning issues
    sections =
      if analysis.reasoning_issues != [] do
        reasoning_summary = """

        Reasoning Issues (#{length(analysis.reasoning_issues)}):
        #{Enum.map_join(analysis.reasoning_issues, "\n", &format_reasoning_issue(&1, verbosity))}
        """

        [reasoning_summary | sections]
      else
        sections
      end

    # Success indicators
    sections =
      if analysis.success_indicators != [] do
        success_summary = """

        Success Indicators (#{length(analysis.success_indicators)}):
        #{Enum.map_join(analysis.success_indicators, "\n", &format_success_indicator(&1, verbosity))}
        """

        [success_summary | sections]
      else
        sections
      end

    sections
    |> Enum.reverse()
    |> Enum.join()
    |> String.trim()
  end

  # Private Functions

  defp identify_failure_points(%Trajectory{} = trajectory) do
    failures = []

    # Check for timeout
    failures =
      if trajectory.outcome == :timeout do
        [
          %FailurePoint{
            category: :timeout,
            description: "Execution exceeded time limit",
            severity: :high,
            context: %{duration_ms: trajectory.duration_ms}
          }
          | failures
        ]
      else
        failures
      end

    # Check for errors in trajectory
    failures =
      if trajectory.error do
        [
          %FailurePoint{
            category: categorize_error(trajectory.error),
            description: "Error: #{inspect(trajectory.error)}",
            severity: :critical,
            context: %{error: trajectory.error}
          }
          | failures
        ]
      else
        failures
      end

    # Check for incomplete execution
    failures =
      if trajectory.outcome == :partial and trajectory.completed_at == nil do
        [
          %FailurePoint{
            category: :incomplete,
            description: "Execution did not complete",
            severity: :high,
            step_index: length(trajectory.steps)
          }
          | failures
        ]
      else
        failures
      end

    # Check for tool failures in steps (but only if not already captured at trajectory level)
    # This prevents double-counting when trajectory.error indicates tool_failure
    has_trajectory_tool_error =
      trajectory.error != nil && categorize_error(trajectory.error) == :tool_failure

    tool_failures =
      if has_trajectory_tool_error do
        []
      else
        trajectory.steps
        |> Enum.with_index()
        |> Enum.filter(fn {step, _idx} ->
          step.type in [:action, :tool_call] and
            (step.metadata[:error] == true || step.metadata[:failed] == true)
        end)
        |> Enum.map(fn {step, idx} ->
          %FailurePoint{
            step_id: step.id,
            step_index: idx,
            category: :tool_failure,
            description: "Tool/action failed: #{step.content}",
            severity: :medium,
            timestamp: step.timestamp,
            context: step.metadata
          }
        end)
      end

    failures ++ tool_failures
  end

  defp detect_contradictions(reasoning_steps) do
    # Simple pattern: look for negation words in consecutive steps
    reasoning_steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.filter(fn [step1, step2] ->
      content1 = extract_content_string(step1.content)
      content2 = extract_content_string(step2.content)
      appears_contradictory?(content1, content2)
    end)
    |> Enum.map(fn [step1, step2] ->
      %ReasoningIssue{
        type: :contradiction,
        description: "Potential contradiction between consecutive reasoning steps",
        step_ids: [step1.id, step2.id],
        evidence: "Step #{step1.id} and #{step2.id} may contradict each other",
        severity: :high
      }
    end)
  end

  defp detect_circular_reasoning(reasoning_steps) do
    # Look for repeated similar content
    step_contents =
      Enum.map(reasoning_steps, fn step ->
        {step.id, extract_content_string(step.content)}
      end)

    step_contents
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.filter(fn chunk ->
      contents = Enum.map(chunk, fn {_id, content} -> content end)
      has_repetition?(contents)
    end)
    |> Enum.map(fn chunk ->
      step_ids = Enum.map(chunk, fn {id, _content} -> id end)

      %ReasoningIssue{
        type: :circular_reasoning,
        description: "Reasoning appears circular or repetitive",
        step_ids: step_ids,
        evidence: "Steps #{Enum.join(step_ids, ", ")} show similar reasoning patterns",
        severity: :medium
      }
    end)
  end

  defp detect_incomplete_logic(reasoning_steps) do
    # Look for steps with very short content AND lacking conclusions
    reasoning_steps
    |> Enum.filter(fn step ->
      content = extract_content_string(step.content)
      String.length(content) < 15 and not has_conclusion_marker?(content)
    end)
    |> Enum.map(fn step ->
      %ReasoningIssue{
        type: :incomplete_logic,
        description: "Reasoning step appears incomplete or too brief",
        step_ids: [step.id],
        evidence: "Step #{step.id} lacks detail or conclusion",
        severity: :low
      }
    end)
  end

  defp detect_unsupported_conclusions(reasoning_steps) do
    # Look for conclusion keywords without supporting reasoning
    reasoning_steps
    |> Enum.filter(fn step ->
      content = extract_content_string(step.content)
      has_conclusion_marker?(content) and String.length(content) < 50
    end)
    |> Enum.map(fn step ->
      %ReasoningIssue{
        type: :unsupported_conclusion,
        description: "Conclusion stated without sufficient reasoning",
        step_ids: [step.id],
        evidence: "Step #{step.id} jumps to conclusion",
        severity: :medium
      }
    end)
  end

  defp extract_success_indicators(%Trajectory{} = trajectory) do
    indicators = []

    # Check for efficient execution
    indicators =
      if (trajectory.duration_ms && trajectory.duration_ms < 5000) and
           length(trajectory.steps) < 10 do
        [
          %SuccessIndicator{
            type: :efficient_path,
            description: "Completed efficiently with minimal steps",
            impact: :high,
            evidence: "#{length(trajectory.steps)} steps in #{trajectory.duration_ms}ms"
          }
          | indicators
        ]
      else
        indicators
      end

    # Check for clear reasoning chain
    reasoning_steps = Enum.filter(trajectory.steps, &(&1.type == :reasoning))

    indicators =
      if length(reasoning_steps) >= 2 do
        [
          %SuccessIndicator{
            type: :clear_reasoning,
            description: "Demonstrates clear reasoning chain",
            impact: :high,
            evidence: "#{length(reasoning_steps)} reasoning steps",
            step_ids: Enum.map(reasoning_steps, & &1.id)
          }
          | indicators
        ]
      else
        indicators
      end

    # Check for proper tool usage
    tool_steps = Enum.filter(trajectory.steps, &(&1.type in [:action, :tool_call]))

    indicators =
      if length(tool_steps) > 0 and
           Enum.all?(tool_steps, fn step ->
             not (step.metadata[:error] == true || step.metadata[:failed] == true)
           end) do
        [
          %SuccessIndicator{
            type: :proper_tool_use,
            description: "Successful tool usage without errors",
            impact: :medium,
            evidence: "#{length(tool_steps)} tool calls, all successful",
            step_ids: Enum.map(tool_steps, & &1.id)
          }
          | indicators
        ]
      else
        indicators
      end

    indicators
  end

  defp assess_overall_quality(analysis, trajectory) do
    score = 0

    # Penalty for failures
    score = score - length(analysis.failure_points) * 10

    # Penalty for reasoning issues (increased weight)
    score = score - length(analysis.reasoning_issues) * 8

    # Bonus for success indicators
    score = score + length(analysis.success_indicators) * 10

    # Bonus for successful outcome
    score =
      if trajectory.outcome == :success do
        score + 30
      else
        score
      end

    # Bonus for efficiency
    score =
      if trajectory.duration_ms && trajectory.duration_ms < 5000 do
        score + 10
      else
        score
      end

    # Additional penalty: if there are reasoning issues in a successful trajectory,
    # prevent it from being excellent
    has_quality_issues =
      length(analysis.reasoning_issues) > 0 or length(analysis.failure_points) > 0

    cond do
      score >= 40 and not has_quality_issues -> :excellent
      score >= 20 -> :good
      score >= 0 -> :fair
      true -> :poor
    end
  end

  defp filter_by_quality(indicator, min_quality) do
    quality_levels = [:low, :medium, :high]
    min_index = Enum.find_index(quality_levels, &(&1 == min_quality)) || 0
    indicator_index = Enum.find_index(quality_levels, &(&1 == indicator.impact)) || 0
    indicator_index >= min_index
  end

  defp deduplicate_indicators(indicators) do
    indicators
    |> Enum.group_by(&{&1.type, &1.description})
    |> Enum.map(fn {_key, [first | _rest]} -> first end)
  end

  defp generate_comparative_insights(differences, _successful, _failed) do
    differences
    |> Enum.filter(&(&1.significance == :high))
    |> Enum.map(fn diff ->
      case diff.aspect do
        :reasoning_steps ->
          "Successful trajectory had more structured reasoning (#{diff.successful_value} steps vs #{diff.failed_value})"

        :tool_usage ->
          "Tool usage patterns differed: successful used #{diff.successful_value} calls vs #{diff.failed_value}"

        :duration ->
          "Execution efficiency varied significantly"

        _ ->
          diff.description
      end
    end)
  end

  defp extract_success_advantages(differences) do
    differences
    |> Enum.filter(&(&1.significance in [:high, :medium]))
    |> Enum.map(& &1.description)
  end

  defp extract_failure_disadvantages(differences) do
    differences
    |> Enum.filter(&(&1.significance == :high))
    |> Enum.map(&"Failed trajectory: #{&1.description}")
  end

  defp categorize_error(error) when is_atom(error), do: error
  defp categorize_error({:error, reason}) when is_atom(reason), do: reason
  defp categorize_error(_), do: :unknown

  defp extract_content_string(content) when is_binary(content), do: content
  defp extract_content_string(content) when is_map(content), do: inspect(content)
  defp extract_content_string(content), do: to_string(content)

  defp appears_contradictory?(content1, content2) do
    negation_words = ["not", "no", "never", "cannot", "isn't", "won't", "didn't"]
    lower1 = String.downcase(content1)
    lower2 = String.downcase(content2)

    Enum.any?(negation_words, fn word ->
      (String.contains?(lower1, word) and not String.contains?(lower2, word)) or
        (String.contains?(lower2, word) and not String.contains?(lower1, word))
    end)
  end

  defp has_repetition?(contents) do
    # Check if any two contents are very similar
    contents
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn [c1, c2] ->
      similarity = string_similarity(c1, c2)
      similarity > 0.7
    end)
  end

  defp has_conclusion_marker?(content) do
    markers = ["therefore", "thus", "so", "hence", "conclude", "result"]
    lower = String.downcase(content)
    Enum.any?(markers, &String.contains?(lower, &1))
  end

  defp string_similarity(str1, str2) do
    # Simple Jaccard similarity on words
    words1 = String.split(str1) |> MapSet.new()
    words2 = String.split(str2) |> MapSet.new()

    intersection = MapSet.intersection(words1, words2) |> MapSet.size()
    union = MapSet.union(words1, words2) |> MapSet.size()

    if union == 0, do: 0.0, else: intersection / union
  end

  defp format_failure_point(failure, _verbosity) do
    "  - [#{failure.severity}] #{failure.category}: #{failure.description}"
  end

  defp format_reasoning_issue(issue, _verbosity) do
    "  - [#{issue.severity}] #{issue.type}: #{issue.description}"
  end

  defp format_success_indicator(indicator, _verbosity) do
    "  - [#{indicator.impact}] #{indicator.type}: #{indicator.description}"
  end
end
