defmodule Jido.AI.Runner.GEPA.TrajectoryAnalyzerTest do
  @moduledoc """
  Comprehensive tests for trajectory analysis functionality.

  Tests all four requirements from Section 1.3.1:
  - Failure point identification
  - Reasoning step analysis
  - Success pattern extraction
  - Comparative analysis
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Trajectory
  alias Jido.AI.Runner.GEPA.TrajectoryAnalyzer

  describe "analyze/2 - basic trajectory analysis" do
    test "analyzes a successful trajectory" do
      trajectory = build_successful_trajectory()

      analysis = TrajectoryAnalyzer.analyze(trajectory)

      assert analysis.trajectory_id == trajectory.id
      assert analysis.outcome == :success
      assert analysis.overall_quality in [:good, :excellent]
      assert analysis.failure_points == []
      assert length(analysis.success_indicators) > 0
      assert analysis.step_count == length(trajectory.steps)
    end

    test "analyzes a failed trajectory" do
      trajectory = build_failed_trajectory()

      analysis = TrajectoryAnalyzer.analyze(trajectory)

      assert analysis.trajectory_id == trajectory.id
      assert analysis.outcome == :failure
      assert analysis.overall_quality in [:poor, :fair]
      assert length(analysis.failure_points) > 0
      assert analysis.success_indicators == []
    end

    test "analyzes a timeout trajectory" do
      trajectory = build_timeout_trajectory()

      analysis = TrajectoryAnalyzer.analyze(trajectory)

      assert analysis.outcome == :timeout
      assert Enum.any?(analysis.failure_points, &(&1.category == :timeout))
    end

    test "respects include_reasoning_analysis option" do
      trajectory = build_trajectory_with_reasoning_issues()

      analysis_with = TrajectoryAnalyzer.analyze(trajectory, include_reasoning_analysis: true)
      analysis_without = TrajectoryAnalyzer.analyze(trajectory, include_reasoning_analysis: false)

      assert length(analysis_with.reasoning_issues) > 0
      assert analysis_without.reasoning_issues == []
    end

    test "respects include_success_patterns option" do
      trajectory = build_successful_trajectory()

      analysis_with = TrajectoryAnalyzer.analyze(trajectory, include_success_patterns: true)
      analysis_without = TrajectoryAnalyzer.analyze(trajectory, include_success_patterns: false)

      assert length(analysis_with.success_indicators) > 0
      assert analysis_without.success_indicators == []
    end
  end

  describe "identify_failure_points/1 - requirement 1.3.1.1" do
    test "identifies timeout failures" do
      trajectory = build_timeout_trajectory()

      analysis = TrajectoryAnalyzer.analyze(trajectory)

      timeout_failures = Enum.filter(analysis.failure_points, &(&1.category == :timeout))
      assert length(timeout_failures) > 0
      assert hd(timeout_failures).severity == :high
    end

    test "identifies error failures" do
      trajectory = build_error_trajectory(:runtime_error)

      analysis = TrajectoryAnalyzer.analyze(trajectory)

      error_failures = Enum.filter(analysis.failure_points, &(&1.category == :runtime_error))
      assert length(error_failures) > 0
      assert hd(error_failures).severity == :critical
    end

    test "identifies tool failures in steps" do
      trajectory = build_trajectory_with_tool_failures()

      analysis = TrajectoryAnalyzer.analyze(trajectory)

      tool_failures = Enum.filter(analysis.failure_points, &(&1.category == :tool_failure))
      assert length(tool_failures) > 0
      assert Enum.all?(tool_failures, &(&1.step_id != nil))
    end

    test "identifies incomplete execution" do
      trajectory = build_incomplete_trajectory()

      analysis = TrajectoryAnalyzer.analyze(trajectory)

      incomplete_failures = Enum.filter(analysis.failure_points, &(&1.category == :incomplete))
      assert length(incomplete_failures) > 0
    end

    test "includes context information in failure points" do
      trajectory = build_failed_trajectory()

      analysis = TrajectoryAnalyzer.analyze(trajectory)

      assert Enum.all?(analysis.failure_points, fn fp ->
               is_map(fp.context) and fp.description != nil
             end)
    end
  end

  describe "find_error_patterns/2 - batch error analysis" do
    test "identifies recurring error patterns" do
      trajectories = [
        build_timeout_trajectory(),
        build_timeout_trajectory(),
        build_error_trajectory(:tool_failure),
        build_error_trajectory(:tool_failure),
        build_error_trajectory(:tool_failure)
      ]

      patterns = TrajectoryAnalyzer.find_error_patterns(trajectories)

      assert patterns[:timeout] == 2
      assert patterns[:tool_failure] == 3
    end

    test "respects min_frequency option" do
      trajectories = [
        build_timeout_trajectory(),
        build_error_trajectory(:tool_failure),
        build_error_trajectory(:tool_failure)
      ]

      patterns_min_2 = TrajectoryAnalyzer.find_error_patterns(trajectories, min_frequency: 2)
      patterns_min_3 = TrajectoryAnalyzer.find_error_patterns(trajectories, min_frequency: 3)

      assert Map.has_key?(patterns_min_2, :tool_failure)
      refute Map.has_key?(patterns_min_3, :tool_failure)
    end

    test "returns empty map when no patterns meet threshold" do
      trajectories = [
        build_timeout_trajectory(),
        build_error_trajectory(:tool_failure)
      ]

      patterns = TrajectoryAnalyzer.find_error_patterns(trajectories, min_frequency: 3)

      assert patterns == %{}
    end
  end

  describe "analyze_reasoning_steps/1 - requirement 1.3.1.2" do
    test "detects contradictions in reasoning" do
      trajectory = build_trajectory_with_contradictions()

      issues = TrajectoryAnalyzer.analyze_reasoning_steps(trajectory)

      contradiction_issues = Enum.filter(issues, &(&1.type == :contradiction))
      assert length(contradiction_issues) > 0
      assert hd(contradiction_issues).severity == :high
    end

    test "detects circular reasoning" do
      trajectory = build_trajectory_with_circular_reasoning()

      issues = TrajectoryAnalyzer.analyze_reasoning_steps(trajectory)

      circular_issues = Enum.filter(issues, &(&1.type == :circular_reasoning))
      assert length(circular_issues) > 0
    end

    test "detects incomplete logic" do
      trajectory = build_trajectory_with_incomplete_logic()

      issues = TrajectoryAnalyzer.analyze_reasoning_steps(trajectory)

      incomplete_issues = Enum.filter(issues, &(&1.type == :incomplete_logic))
      assert length(incomplete_issues) > 0
    end

    test "detects unsupported conclusions" do
      trajectory = build_trajectory_with_unsupported_conclusions()

      issues = TrajectoryAnalyzer.analyze_reasoning_steps(trajectory)

      unsupported_issues = Enum.filter(issues, &(&1.type == :unsupported_conclusion))
      assert length(unsupported_issues) > 0
    end

    test "includes evidence for all detected issues" do
      trajectory = build_trajectory_with_reasoning_issues()

      issues = TrajectoryAnalyzer.analyze_reasoning_steps(trajectory)

      assert Enum.all?(issues, fn issue ->
               issue.evidence != nil and issue.step_ids != []
             end)
    end

    test "returns empty list for trajectory with good reasoning" do
      trajectory = build_trajectory_with_good_reasoning()

      issues = TrajectoryAnalyzer.analyze_reasoning_steps(trajectory)

      assert issues == []
    end
  end

  describe "extract_success_patterns/2 - requirement 1.3.1.3" do
    test "extracts efficient path indicators" do
      trajectory = build_efficient_trajectory()

      indicators = TrajectoryAnalyzer.extract_success_patterns([trajectory])

      efficient_indicators = Enum.filter(indicators, &(&1.type == :efficient_path))
      assert length(efficient_indicators) > 0
    end

    test "extracts clear reasoning indicators" do
      trajectory = build_trajectory_with_clear_reasoning()

      indicators = TrajectoryAnalyzer.extract_success_patterns([trajectory])

      reasoning_indicators = Enum.filter(indicators, &(&1.type == :clear_reasoning))
      assert length(reasoning_indicators) > 0
    end

    test "extracts proper tool use indicators" do
      trajectory = build_trajectory_with_proper_tool_use()

      indicators = TrajectoryAnalyzer.extract_success_patterns([trajectory])

      tool_indicators = Enum.filter(indicators, &(&1.type == :proper_tool_use))
      assert length(tool_indicators) > 0
    end

    test "filters by quality threshold" do
      trajectory = build_successful_trajectory()

      high_quality = TrajectoryAnalyzer.extract_success_patterns([trajectory], min_quality: :high)

      medium_quality =
        TrajectoryAnalyzer.extract_success_patterns([trajectory], min_quality: :medium)

      assert length(high_quality) <= length(medium_quality)
    end

    test "deduplicates similar patterns" do
      trajectories = [
        build_efficient_trajectory(),
        build_efficient_trajectory()
      ]

      indicators = TrajectoryAnalyzer.extract_success_patterns(trajectories)

      # Should not have duplicate indicators
      types = Enum.map(indicators, & &1.type)
      assert length(types) == length(Enum.uniq(types))
    end

    test "only analyzes successful trajectories" do
      trajectories = [
        build_successful_trajectory(),
        build_failed_trajectory(),
        build_timeout_trajectory()
      ]

      indicators = TrajectoryAnalyzer.extract_success_patterns(trajectories)

      # Should only extract from the one successful trajectory
      assert length(indicators) > 0
    end
  end

  describe "compare_trajectories/3 - requirement 1.3.1.4" do
    test "identifies step count differences" do
      successful = build_trajectory_with_steps(5)
      failed = build_trajectory_with_steps(10, outcome: :failure)

      comparison = TrajectoryAnalyzer.compare_trajectories(successful, failed)

      step_diff = Enum.find(comparison.differences, &(&1.aspect == :step_count))
      assert step_diff != nil
      assert step_diff.successful_value == 5
      assert step_diff.failed_value == 10
    end

    test "identifies reasoning step differences" do
      successful = build_trajectory_with_reasoning_steps(3)
      failed = build_trajectory_with_reasoning_steps(1, outcome: :failure)

      comparison = TrajectoryAnalyzer.compare_trajectories(successful, failed)

      reasoning_diff = Enum.find(comparison.differences, &(&1.aspect == :reasoning_steps))
      assert reasoning_diff != nil
      assert reasoning_diff.significance == :high
    end

    test "identifies tool usage differences" do
      successful = build_trajectory_with_tool_calls(5)
      failed = build_trajectory_with_tool_calls(2, outcome: :failure)

      comparison = TrajectoryAnalyzer.compare_trajectories(successful, failed)

      tool_diff = Enum.find(comparison.differences, &(&1.aspect == :tool_usage))
      assert tool_diff != nil
      assert tool_diff.significance == :high
    end

    test "identifies duration differences" do
      successful = build_trajectory_with_duration(1000)
      failed = build_trajectory_with_duration(5000, outcome: :failure)

      comparison = TrajectoryAnalyzer.compare_trajectories(successful, failed)

      duration_diff = Enum.find(comparison.differences, &(&1.aspect == :duration))
      assert duration_diff != nil
    end

    test "generates meaningful insights" do
      successful = build_successful_trajectory()
      failed = build_failed_trajectory()

      comparison = TrajectoryAnalyzer.compare_trajectories(successful, failed)

      assert length(comparison.key_insights) > 0
      assert is_binary(hd(comparison.key_insights))
    end

    test "extracts success advantages" do
      successful = build_successful_trajectory()
      failed = build_failed_trajectory()

      comparison = TrajectoryAnalyzer.compare_trajectories(successful, failed)

      assert length(comparison.success_advantages) > 0
    end

    test "extracts failure disadvantages" do
      successful = build_successful_trajectory()
      failed = build_failed_trajectory()

      comparison = TrajectoryAnalyzer.compare_trajectories(successful, failed)

      assert length(comparison.failure_disadvantages) > 0
    end
  end

  describe "summarize/2 - natural language summary generation" do
    test "generates overview section" do
      trajectory = build_successful_trajectory()
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      summary = TrajectoryAnalyzer.summarize(analysis)

      assert String.contains?(summary, trajectory.id)
      assert String.contains?(summary, "Outcome: success")
      assert String.contains?(summary, "Overall Quality:")
    end

    test "includes failure points in summary" do
      trajectory = build_failed_trajectory()
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      summary = TrajectoryAnalyzer.summarize(analysis)

      assert String.contains?(summary, "Failure Points")
    end

    test "includes reasoning issues in summary" do
      trajectory = build_trajectory_with_reasoning_issues()
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      summary = TrajectoryAnalyzer.summarize(analysis)

      assert String.contains?(summary, "Reasoning Issues")
    end

    test "includes success indicators in summary" do
      trajectory = build_successful_trajectory()
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      summary = TrajectoryAnalyzer.summarize(analysis)

      assert String.contains?(summary, "Success Indicators")
    end

    test "respects verbosity option" do
      trajectory = build_successful_trajectory()
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      brief = TrajectoryAnalyzer.summarize(analysis, verbosity: :brief)
      detailed = TrajectoryAnalyzer.summarize(analysis, verbosity: :detailed)

      assert is_binary(brief)
      assert is_binary(detailed)
    end
  end

  describe "overall quality assessment" do
    test "rates excellent trajectories correctly" do
      trajectory = build_excellent_trajectory()

      analysis = TrajectoryAnalyzer.analyze(trajectory)

      assert analysis.overall_quality == :excellent
    end

    test "rates poor trajectories correctly" do
      trajectory = build_poor_trajectory()

      analysis = TrajectoryAnalyzer.analyze(trajectory)

      assert analysis.overall_quality == :poor
    end

    test "considers multiple factors in quality score" do
      # Trajectory with mixed characteristics
      trajectory = build_mixed_quality_trajectory()

      analysis = TrajectoryAnalyzer.analyze(trajectory)

      assert analysis.overall_quality in [:fair, :good]
    end
  end

  # Helper Functions for Building Test Trajectories

  defp build_successful_trajectory do
    %Trajectory{
      id: "traj_success_#{:rand.uniform(10000)}",
      steps: [
        build_step(:reasoning, "Let me analyze this problem step by step"),
        build_step(:reasoning, "First, I'll break down the requirements"),
        build_step(:action, "Calling analysis tool"),
        build_step(:observation, "Tool returned results"),
        build_step(:reasoning, "Therefore, the solution is clear")
      ],
      outcome: :success,
      completed_at: DateTime.utc_now(),
      started_at: DateTime.add(DateTime.utc_now(), -3, :second),
      duration_ms: 3000,
      metadata: %{}
    }
  end

  defp build_failed_trajectory do
    %Trajectory{
      id: "traj_failed_#{:rand.uniform(10000)}",
      steps: [
        build_step(:reasoning, "Let me try this"),
        build_step(:action, "Calling tool"),
        build_step(:observation, "Tool failed")
      ],
      outcome: :failure,
      error: :tool_error,
      completed_at: DateTime.utc_now(),
      started_at: DateTime.add(DateTime.utc_now(), -2, :second),
      duration_ms: 2000,
      metadata: %{}
    }
  end

  defp build_timeout_trajectory do
    %Trajectory{
      id: "traj_timeout_#{:rand.uniform(10000)}",
      steps: [
        build_step(:reasoning, "Starting analysis"),
        build_step(:reasoning, "This is taking a while")
      ],
      outcome: :timeout,
      completed_at: nil,
      started_at: DateTime.add(DateTime.utc_now(), -10, :second),
      duration_ms: 10_000,
      metadata: %{}
    }
  end

  defp build_error_trajectory(error_type) do
    %Trajectory{
      id: "traj_error_#{:rand.uniform(10000)}",
      steps: [build_step(:action, "Tool call", %{error: true, failed: true})],
      outcome: :error,
      error: error_type,
      completed_at: DateTime.utc_now(),
      started_at: DateTime.add(DateTime.utc_now(), -1, :second),
      duration_ms: 1000,
      metadata: %{}
    }
  end

  defp build_incomplete_trajectory do
    %Trajectory{
      id: "traj_incomplete_#{:rand.uniform(10000)}",
      steps: [build_step(:reasoning, "Starting...")],
      outcome: :partial,
      completed_at: nil,
      started_at: DateTime.add(DateTime.utc_now(), -2, :second),
      duration_ms: nil,
      metadata: %{}
    }
  end

  defp build_trajectory_with_tool_failures do
    %Trajectory{
      id: "traj_tool_fail_#{:rand.uniform(10000)}",
      steps: [
        build_step(:reasoning, "Let me use a tool"),
        build_step(:tool_call, "Tool A", %{error: true}),
        build_step(:tool_call, "Tool B", %{failed: true})
      ],
      outcome: :failure,
      completed_at: DateTime.utc_now(),
      started_at: DateTime.add(DateTime.utc_now(), -2, :second),
      duration_ms: 2000,
      metadata: %{}
    }
  end

  defp build_trajectory_with_contradictions do
    %Trajectory{
      id: "traj_contradiction_#{:rand.uniform(10000)}",
      steps: [
        build_step(:reasoning, "The value is positive"),
        build_step(:reasoning, "The value is not positive")
      ],
      outcome: :success,
      completed_at: DateTime.utc_now(),
      started_at: DateTime.add(DateTime.utc_now(), -1, :second),
      duration_ms: 1000,
      metadata: %{}
    }
  end

  defp build_trajectory_with_circular_reasoning do
    %Trajectory{
      id: "traj_circular_#{:rand.uniform(10000)}",
      steps: [
        build_step(:reasoning, "First we analyze the data"),
        build_step(:reasoning, "First we analyze the data again"),
        build_step(:reasoning, "First we analyze the data once more")
      ],
      outcome: :success,
      completed_at: DateTime.utc_now(),
      started_at: DateTime.add(DateTime.utc_now(), -1, :second),
      duration_ms: 1000,
      metadata: %{}
    }
  end

  defp build_trajectory_with_incomplete_logic do
    %Trajectory{
      id: "traj_incomplete_logic_#{:rand.uniform(10000)}",
      steps: [
        build_step(:reasoning, "So"),
        build_step(:reasoning, "Then")
      ],
      outcome: :success,
      completed_at: DateTime.utc_now(),
      started_at: DateTime.add(DateTime.utc_now(), -1, :second),
      duration_ms: 1000,
      metadata: %{}
    }
  end

  defp build_trajectory_with_unsupported_conclusions do
    %Trajectory{
      id: "traj_unsupported_#{:rand.uniform(10000)}",
      steps: [
        build_step(:reasoning, "Therefore X is true")
      ],
      outcome: :success,
      completed_at: DateTime.utc_now(),
      started_at: DateTime.add(DateTime.utc_now(), -1, :second),
      duration_ms: 1000,
      metadata: %{}
    }
  end

  defp build_trajectory_with_reasoning_issues do
    %Trajectory{
      id: "traj_issues_#{:rand.uniform(10000)}",
      steps: [
        build_step(:reasoning, "The answer is X"),
        build_step(:reasoning, "The answer is not X"),
        build_step(:reasoning, "So")
      ],
      outcome: :success,
      completed_at: DateTime.utc_now(),
      started_at: DateTime.add(DateTime.utc_now(), -1, :second),
      duration_ms: 1000,
      metadata: %{}
    }
  end

  defp build_trajectory_with_good_reasoning do
    %Trajectory{
      id: "traj_good_reasoning_#{:rand.uniform(10000)}",
      steps: [
        build_step(
          :reasoning,
          "Let me carefully analyze this problem by breaking it down into smaller steps"
        ),
        build_step(
          :reasoning,
          "First, I observe that the input has certain characteristics that suggest approach A"
        ),
        build_step(
          :reasoning,
          "Second, considering the constraints, approach A is more efficient than B"
        ),
        build_step(
          :reasoning,
          "Therefore, based on the evidence, I will proceed with approach A"
        )
      ],
      outcome: :success,
      completed_at: DateTime.utc_now(),
      started_at: DateTime.add(DateTime.utc_now(), -3, :second),
      duration_ms: 3000,
      metadata: %{}
    }
  end

  defp build_efficient_trajectory do
    %Trajectory{
      id: "traj_efficient_#{:rand.uniform(10000)}",
      steps: [
        build_step(:reasoning, "Quick analysis"),
        build_step(:action, "Direct action"),
        build_step(:observation, "Success")
      ],
      outcome: :success,
      completed_at: DateTime.utc_now(),
      started_at: DateTime.add(DateTime.utc_now(), -1, :second),
      duration_ms: 1000,
      metadata: %{}
    }
  end

  defp build_trajectory_with_clear_reasoning do
    %Trajectory{
      id: "traj_clear_#{:rand.uniform(10000)}",
      steps: [
        build_step(:reasoning, "Step 1: Identify the problem"),
        build_step(:reasoning, "Step 2: Analyze options"),
        build_step(:reasoning, "Step 3: Choose best approach")
      ],
      outcome: :success,
      completed_at: DateTime.utc_now(),
      started_at: DateTime.add(DateTime.utc_now(), -2, :second),
      duration_ms: 2000,
      metadata: %{}
    }
  end

  defp build_trajectory_with_proper_tool_use do
    %Trajectory{
      id: "traj_tools_#{:rand.uniform(10000)}",
      steps: [
        build_step(:reasoning, "I need tool A"),
        build_step(:tool_call, "Using tool A", %{}),
        build_step(:observation, "Tool A succeeded")
      ],
      outcome: :success,
      completed_at: DateTime.utc_now(),
      started_at: DateTime.add(DateTime.utc_now(), -2, :second),
      duration_ms: 2000,
      metadata: %{}
    }
  end

  defp build_trajectory_with_steps(count, opts \\ []) do
    outcome = Keyword.get(opts, :outcome, :success)

    steps =
      Enum.map(1..count, fn i ->
        build_step(:reasoning, "Step #{i}")
      end)

    %Trajectory{
      id: "traj_#{count}_steps_#{:rand.uniform(10000)}",
      steps: steps,
      outcome: outcome,
      completed_at: DateTime.utc_now(),
      started_at: DateTime.add(DateTime.utc_now(), -count, :second),
      duration_ms: count * 1000,
      metadata: %{}
    }
  end

  defp build_trajectory_with_reasoning_steps(count, opts \\ []) do
    outcome = Keyword.get(opts, :outcome, :success)

    reasoning_steps =
      Enum.map(1..count, fn i ->
        build_step(:reasoning, "Reasoning step #{i}")
      end)

    %Trajectory{
      id: "traj_#{count}_reasoning_#{:rand.uniform(10000)}",
      steps: reasoning_steps,
      outcome: outcome,
      completed_at: DateTime.utc_now(),
      started_at: DateTime.add(DateTime.utc_now(), -count, :second),
      duration_ms: count * 1000,
      metadata: %{}
    }
  end

  defp build_trajectory_with_tool_calls(count, opts \\ []) do
    outcome = Keyword.get(opts, :outcome, :success)

    tool_steps =
      Enum.map(1..count, fn i ->
        build_step(:tool_call, "Tool #{i}")
      end)

    %Trajectory{
      id: "traj_#{count}_tools_#{:rand.uniform(10000)}",
      steps: tool_steps,
      outcome: outcome,
      completed_at: DateTime.utc_now(),
      started_at: DateTime.add(DateTime.utc_now(), -count, :second),
      duration_ms: count * 1000,
      metadata: %{}
    }
  end

  defp build_trajectory_with_duration(duration_ms, opts \\ []) do
    outcome = Keyword.get(opts, :outcome, :success)

    %Trajectory{
      id: "traj_#{duration_ms}ms_#{:rand.uniform(10000)}",
      steps: [build_step(:reasoning, "Working...")],
      outcome: outcome,
      completed_at: DateTime.utc_now(),
      started_at: DateTime.add(DateTime.utc_now(), -div(duration_ms, 1000), :second),
      duration_ms: duration_ms,
      metadata: %{}
    }
  end

  defp build_excellent_trajectory do
    %Trajectory{
      id: "traj_excellent_#{:rand.uniform(10000)}",
      steps: [
        build_step(:reasoning, "Detailed analysis with clear logical steps"),
        build_step(:reasoning, "Thorough consideration of all options"),
        build_step(:action, "Efficient tool use"),
        build_step(:observation, "Perfect result")
      ],
      outcome: :success,
      completed_at: DateTime.utc_now(),
      started_at: DateTime.add(DateTime.utc_now(), -2, :second),
      duration_ms: 2000,
      metadata: %{}
    }
  end

  defp build_poor_trajectory do
    %Trajectory{
      id: "traj_poor_#{:rand.uniform(10000)}",
      steps: [
        build_step(:reasoning, "X"),
        build_step(:reasoning, "Not X"),
        build_step(:action, "Tool", %{error: true})
      ],
      outcome: :failure,
      error: :multiple_errors,
      completed_at: DateTime.utc_now(),
      started_at: DateTime.add(DateTime.utc_now(), -10, :second),
      duration_ms: 10_000,
      metadata: %{}
    }
  end

  defp build_mixed_quality_trajectory do
    %Trajectory{
      id: "traj_mixed_#{:rand.uniform(10000)}",
      steps: [
        build_step(:reasoning, "Good reasoning here"),
        build_step(:reasoning, "So"),
        build_step(:action, "Tool use")
      ],
      outcome: :success,
      completed_at: DateTime.utc_now(),
      started_at: DateTime.add(DateTime.utc_now(), -5, :second),
      duration_ms: 5000,
      metadata: %{}
    }
  end

  defp build_step(type, content, metadata \\ %{}) do
    %Trajectory.Step{
      id: "step_#{:rand.uniform(100_000)}",
      type: type,
      content: content,
      timestamp: DateTime.utc_now(),
      metadata: metadata,
      importance: :medium
    }
  end
end
