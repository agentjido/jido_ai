defmodule Jido.AI.Runner.GEPA.Reflection.PromptBuilderTest do
  @moduledoc """
  Comprehensive tests for reflection prompt building (Task 1.3.2.1).

  Tests:
  - System prompt generation
  - Reflection prompt formatting
  - Context section formatting
  - Analysis section formatting
  - Follow-up prompt generation
  - Verbosity level handling
  - Focus area handling
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Reflection.PromptBuilder
  alias Jido.AI.Runner.GEPA.{Reflector, Trajectory, TrajectoryAnalyzer}
  alias Jido.AI.Runner.GEPA.TestFixtures

  describe "system_prompt/0" do
    test "returns a non-empty system prompt" do
      prompt = PromptBuilder.system_prompt()

      assert is_binary(prompt)
      assert String.length(prompt) > 100
    end

    test "system prompt contains JSON format instructions" do
      prompt = PromptBuilder.system_prompt()

      assert prompt =~ "JSON"
      assert prompt =~ "analysis"
      assert prompt =~ "root_causes"
      assert prompt =~ "suggestions"
      assert prompt =~ "expected_improvement"
    end

    test "system prompt defines suggestion structure" do
      prompt = PromptBuilder.system_prompt()

      assert prompt =~ "type"
      assert prompt =~ "category"
      assert prompt =~ "description"
      assert prompt =~ "rationale"
      assert prompt =~ "priority"
    end

    test "system prompt mentions valid types" do
      prompt = PromptBuilder.system_prompt()

      assert prompt =~ "add"
      assert prompt =~ "modify"
      assert prompt =~ "remove"
      assert prompt =~ "restructure"
    end

    test "system prompt mentions valid categories" do
      prompt = PromptBuilder.system_prompt()

      assert prompt =~ "clarity"
      assert prompt =~ "constraint"
      assert prompt =~ "example"
      assert prompt =~ "structure"
      assert prompt =~ "reasoning"
    end
  end

  describe "build_reflection_prompt/2 - basic structure" do
    test "generates a complete prompt for a failed trajectory" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Solve this problem step by step"
      }

      prompt = PromptBuilder.build_reflection_prompt(request)

      assert is_binary(prompt)
      assert String.length(prompt) > 200
    end

    test "includes original prompt in context section" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt ABC123"
      }

      prompt = PromptBuilder.build_reflection_prompt(request)

      assert prompt =~ "Test prompt ABC123"
      assert prompt =~ "Original Prompt"
    end

    test "includes task description when provided" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt",
        task_description: "Mathematical reasoning task"
      }

      prompt = PromptBuilder.build_reflection_prompt(request)

      assert prompt =~ "Mathematical reasoning task"
    end

    test "includes execution outcome" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt"
      }

      prompt = PromptBuilder.build_reflection_prompt(request)

      assert prompt =~ "Execution Outcome"
      assert prompt =~ "Failure" or prompt =~ "❌"
    end
  end

  describe "build_reflection_prompt/2 - analysis section" do
    test "includes failure points section" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt"
      }

      prompt = PromptBuilder.build_reflection_prompt(request)

      assert prompt =~ "Failure Points"
      assert prompt =~ "detected"
    end

    test "includes reasoning issues section" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt"
      }

      prompt = PromptBuilder.build_reflection_prompt(request)

      assert prompt =~ "Reasoning Issues"
    end

    test "includes success indicators when available" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:partial)
      analysis = TrajectoryAnalyzer.analyze(trajectory, include_success_patterns: true)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt"
      }

      prompt = PromptBuilder.build_reflection_prompt(request, include_success_patterns: true)

      if length(analysis.success_indicators) > 0 do
        assert prompt =~ "Success Indicators"
      end
    end

    test "excludes success indicators when option is false" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:success)
      analysis = TrajectoryAnalyzer.analyze(trajectory, include_success_patterns: true)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt"
      }

      prompt = PromptBuilder.build_reflection_prompt(request, include_success_patterns: false)

      refute prompt =~ "Success Indicators to Preserve"
    end

    test "includes comparative analysis when available" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      # Add mock comparative analysis to metadata
      analysis = %{
        analysis
        | metadata:
            Map.put(analysis.metadata, :comparative_analysis, %{
              differences: [],
              success_advantages: ["Advantage 1", "Advantage 2"],
              failure_disadvantages: ["Disadvantage 1"],
              key_insights: ["Insight 1"]
            })
      }

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt"
      }

      prompt = PromptBuilder.build_reflection_prompt(request, include_comparative: true)

      assert prompt =~ "Comparative Analysis"
      assert prompt =~ "Success Advantages" or prompt =~ "Key Insights"
    end

    test "excludes comparative analysis when option is false" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt"
      }

      prompt = PromptBuilder.build_reflection_prompt(request, include_comparative: false)

      refute prompt =~ "Comparative Analysis"
    end
  end

  describe "build_reflection_prompt/2 - request section" do
    test "includes key analysis questions" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt"
      }

      prompt = PromptBuilder.build_reflection_prompt(request)

      assert prompt =~ "Your Task"
      assert prompt =~ "root causes"
      assert prompt =~ "specific changes"
    end

    test "includes focus areas when provided" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt",
        focus_areas: [:clarity, :reasoning]
      }

      prompt = PromptBuilder.build_reflection_prompt(request)

      assert prompt =~ "Focus Areas"
      assert prompt =~ "clarity"
      assert prompt =~ "reasoning"
    end

    test "omits focus areas section when empty" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt",
        focus_areas: []
      }

      prompt = PromptBuilder.build_reflection_prompt(request)

      refute prompt =~ "Focus Areas:"
    end
  end

  describe "build_reflection_prompt/2 - constraints section" do
    test "includes response requirements" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt"
      }

      prompt = PromptBuilder.build_reflection_prompt(request)

      assert prompt =~ "Response Requirements"
      assert prompt =~ "3-7 specific"
      assert prompt =~ "JSON structure"
    end

    test "emphasizes actionable suggestions" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt"
      }

      prompt = PromptBuilder.build_reflection_prompt(request)

      assert prompt =~ "actionable"
      assert prompt =~ "concrete"
      assert prompt =~ "implementable"
    end
  end

  describe "build_follow_up_prompt/3" do
    test "generates a follow-up prompt" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt"
      }

      reflection = %Reflector.ParsedReflection{
        analysis: "The prompt lacks specific constraints",
        root_causes: ["Insufficient guidance"],
        suggestions: []
      }

      follow_up =
        PromptBuilder.build_follow_up_prompt(
          request,
          reflection,
          "Can you elaborate on the constraint issues?"
        )

      assert is_binary(follow_up)
      assert follow_up =~ "Continuing Reflection"
      assert follow_up =~ "Can you elaborate on the constraint issues?"
      assert follow_up =~ "The prompt lacks specific constraints"
    end

    test "includes previous analysis in follow-up" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Original test prompt"
      }

      reflection = %Reflector.ParsedReflection{
        analysis: "Previous analysis ABC123",
        root_causes: [],
        suggestions: []
      }

      follow_up =
        PromptBuilder.build_follow_up_prompt(
          request,
          reflection,
          "Follow-up question"
        )

      assert follow_up =~ "Previous analysis ABC123"
      assert follow_up =~ "Original test prompt"
    end

    test "maintains context from initial request" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Solve math problem",
        task_description: "Algebra task"
      }

      reflection = %Reflector.ParsedReflection{
        analysis: "Analysis text",
        root_causes: [],
        suggestions: []
      }

      follow_up =
        PromptBuilder.build_follow_up_prompt(
          request,
          reflection,
          "Why did reasoning fail?"
        )

      assert follow_up =~ "Solve math problem"
      assert follow_up =~ "Algebra task"
    end

    test "requests same JSON format as initial" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test"
      }

      reflection = %Reflector.ParsedReflection{
        analysis: "Test analysis",
        root_causes: [],
        suggestions: []
      }

      follow_up = PromptBuilder.build_follow_up_prompt(request, reflection, "Question?")

      assert follow_up =~ "JSON format"
    end
  end

  describe "verbosity handling" do
    test "handles brief verbosity" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt",
        verbosity: :brief
      }

      prompt = PromptBuilder.build_reflection_prompt(request)

      assert is_binary(prompt)
      # Brief should still include all sections but may be less verbose
      assert prompt =~ "Failure Points"
    end

    test "handles normal verbosity" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt",
        verbosity: :normal
      }

      prompt = PromptBuilder.build_reflection_prompt(request)

      assert is_binary(prompt)
      assert prompt =~ "Trajectory Analysis"
    end

    test "handles detailed verbosity" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt",
        verbosity: :detailed
      }

      prompt = PromptBuilder.build_reflection_prompt(request)

      assert is_binary(prompt)
      # Detailed should include comprehensive information
      assert String.length(prompt) > 100
    end
  end

  describe "edge cases" do
    test "handles trajectory with no failure points" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:success)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt"
      }

      prompt = PromptBuilder.build_reflection_prompt(request)

      assert is_binary(prompt)
      assert prompt =~ "Failure Points"
      # Should handle empty failure points gracefully
    end

    test "handles trajectory with no reasoning issues" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:timeout)
      analysis = TrajectoryAnalyzer.analyze(trajectory, include_reasoning_analysis: false)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt"
      }

      prompt = PromptBuilder.build_reflection_prompt(request)

      assert is_binary(prompt)
      assert prompt =~ "Reasoning Issues"
    end

    test "handles missing task description" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt",
        task_description: nil
      }

      prompt = PromptBuilder.build_reflection_prompt(request)

      assert is_binary(prompt)
      # Should use default description
      assert prompt =~ "General reasoning task" or prompt =~ "N/A"
    end

    test "handles empty metadata" do
      trajectory = TestFixtures.build_trajectory_for_scenario(:failure)
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      request = %Reflector.ReflectionRequest{
        trajectory_analysis: analysis,
        original_prompt: "Test prompt",
        metadata: %{}
      }

      prompt = PromptBuilder.build_reflection_prompt(request)

      assert is_binary(prompt)
    end
  end
end
