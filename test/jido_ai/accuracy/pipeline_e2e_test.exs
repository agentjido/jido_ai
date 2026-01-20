defmodule Jido.AI.Accuracy.PipelineE2ETest do
  @moduledoc """
  End-to-end integration tests for the complete accuracy pipeline.

  These tests validate the full pipeline execution with realistic scenarios
  including math problems, coding tasks, and research questions.
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Pipeline, Presets, Candidate, PipelineResult}

  @moduletag :e2e
  @moduletag :pipeline

  # Mock generators for different query types
  defp math_generator(query, _context) do
    answer = solve_math(query)
    {:ok, Candidate.new!(%{content: answer, score: 0.9})}
  end

  defp coding_generator(query, _context) do
    code = generate_code(query)
    {:ok, Candidate.new!(%{content: code, score: 0.85})}
  end

  defp research_generator(query, _context) do
    answer = research_answer(query)
    {:ok, Candidate.new!(%{content: answer, score: 0.8})}
  end

  defp varied_generator(_query, _context) do
    # Generator that produces varied responses for self-consistency
    answers = ["The answer is 42", "42", "The result equals 42"]
    answer = Enum.random(answers)
    {:ok, Candidate.new!(%{content: answer, score: Enum.random(70..95) / 100})}
  end

  defp uncertain_generator(query, _context) do
    # Generator that produces low-confidence responses
    {:ok, Candidate.new!(%{content: "I'm not sure about #{query}", score: 0.3})}
  end

  # Simple math solver for testing
  defp solve_math(query) do
    cond do
      String.contains?(query, "2+2") ->
        "4"

      String.contains?(query, "15 * 23") ->
        "345"

      String.contains?(query, "10 * 10") ->
        "100"

      String.contains?(query, "7 * 8") ->
        "56"

      String.contains?(query, "12 * 12") ->
        "144"

      String.contains?(query, "+") ->
        parts = String.split(query, "+")

        if length(parts) == 2 do
          a = parts |> List.first() |> String.trim() |> Integer.parse() |> elem(0)
          b = parts |> List.last() |> String.trim() |> Integer.parse() |> elem(0)
          Integer.to_string(a + b)
        else
          "42"
        end

      true ->
        "42"
    end
  end

  defp generate_code(query) do
    cond do
      String.contains?(query, "factorial") ->
        """
        def factorial(n) when n <= 1, do: 1
        def factorial(n), do: n * factorial(n - 1)
        """

      String.contains?(query, "sum") ->
        """
        def sum_list(list), do: Enum.sum(list)
        """

      true ->
        """
        def solve(), do: :ok
        """
    end
  end

  defp research_answer(query) do
    cond do
      String.contains?(query, "capital of France") ->
        "The capital of France is Paris."

      String.contains?(query, "Eiffel Tower") ->
        "The Eiffel Tower is located in Paris, France."

      String.contains?(query, "Python") ->
        "Python is a high-level programming language created by Guido van Rossum."

      true ->
        "Based on available information, this is a factual response."
    end
  end

  describe "8.5.1 End-to-End Pipeline Tests" do
    test "complete pipeline on math problem" do
      {:ok, pipeline} = Pipeline.new(%{})

      {:ok, result} = Pipeline.run(pipeline, "What is 2+2?", generator: &math_generator/2)

      # Verify result structure
      assert %PipelineResult{} = result
      assert is_binary(result.answer)
      assert is_number(result.confidence)
      assert result.confidence >= 0.0 and result.confidence <= 1.0
      assert result.action in [:direct, :with_verification, :abstain, :escalate]

      # Verify trace completeness
      assert is_list(result.trace)
      refute Enum.empty?(result.trace)

      # Verify metadata
      assert is_map(result.metadata)
      assert is_list(result.metadata.stages_completed)
      refute Enum.empty?(result.metadata.stages_completed)
    end

    test "complete pipeline on coding problem" do
      {:ok, pipeline} =
        Pipeline.new(%{
          config: %{
            stages: [:generation, :verification, :calibration]
          }
        })

      {:ok, result} = Pipeline.run(pipeline, "Write a factorial function", generator: &coding_generator/2)

      # Verify code-like response
      assert %PipelineResult{} = result
      assert is_binary(result.answer)
      assert String.contains?(result.answer, "def")
    end

    test "complete pipeline on research question" do
      {:ok, pipeline} =
        Pipeline.new(%{
          config: %{
            stages: [:generation, :calibration]
          }
        })

      {:ok, result} =
        Pipeline.run(
          pipeline,
          "What is the capital of France?",
          generator: &research_generator/2
        )

      # Verify factual response
      assert %PipelineResult{} = result
      assert String.contains?(result.answer, "Paris")
    end

    test "pipeline with abstention on low confidence" do
      {:ok, pipeline} =
        Pipeline.new(%{
          config: %{
            stages: [:generation, :calibration],
            calibration_config: %{
              low_threshold: 0.5,
              low_action: :abstain
            }
          }
        })

      {:ok, result} = Pipeline.run(pipeline, "Complex question", generator: &uncertain_generator/2)

      # Should abstain due to low confidence
      assert result.action == :abstain
      assert PipelineResult.abstained?(result)
    end
  end

  describe "8.5.1.5 Preset Behavior Tests" do
    test ":fast preset uses minimal stages and candidates" do
      {:ok, config} = Presets.get(:fast)
      {:ok, pipeline} = Pipeline.new(%{config: config})

      # Verify stages
      assert config.stages == [:generation, :calibration]

      # Verify candidate limits
      assert config.generation_config.min_candidates == 1
      assert config.generation_config.max_candidates == 3

      # Run pipeline
      {:ok, result} = Pipeline.run(pipeline, "What is 2+2?", generator: &math_generator/2)

      assert %PipelineResult{} = result
      assert result.metadata.num_candidates <= 3
    end

    test ":balanced preset uses moderate stages and candidates" do
      {:ok, config} = Presets.get(:balanced)
      {:ok, pipeline} = Pipeline.new(%{config: config})

      # Verify stages include difficulty estimation and verification
      assert :difficulty_estimation in config.stages
      assert :verification in config.stages

      # Verify candidate limits
      assert config.generation_config.min_candidates == 3
      assert config.generation_config.max_candidates == 5

      # Run pipeline
      # Note: early stopping may reduce actual candidates if consensus is high
      {:ok, result} = Pipeline.run(pipeline, "What is 10*10?", generator: &math_generator/2)

      assert %PipelineResult{} = result
      # Actual candidates may be less than min due to early stopping
      assert result.metadata.num_candidates >= 1
      assert result.metadata.num_candidates <= 5
    end

    test ":accurate preset uses maximum candidates and all stages" do
      {:ok, config} = Presets.get(:accurate)
      {:ok, pipeline} = Pipeline.new(%{config: config})

      # Verify all stages included
      assert :difficulty_estimation in config.stages
      assert :generation in config.stages
      assert :verification in config.stages
      assert :search in config.stages
      assert :reflection in config.stages
      assert :calibration in config.stages

      # Verify higher candidate limits
      assert config.generation_config.min_candidates == 5
      assert config.generation_config.max_candidates == 10

      # Run pipeline
      {:ok, result} = Pipeline.run(pipeline, "What is 7*8?", generator: &math_generator/2)

      assert %PipelineResult{} = result
    end

    test ":coding preset includes RAG and reflection" do
      {:ok, config} = Presets.get(:coding)
      {:ok, pipeline} = Pipeline.new(%{config: config})

      # Verify coding-specific stages
      assert :rag in config.stages
      assert :reflection in config.stages

      # Verify RAG is enabled
      assert config.rag_config.enabled == true

      # Run pipeline
      {:ok, result} = Pipeline.run(pipeline, "Write a factorial function", generator: &coding_generator/2)

      assert %PipelineResult{} = result
    end

    test ":research preset includes RAG with correction" do
      {:ok, config} = Presets.get(:research)
      {:ok, pipeline} = Pipeline.new(%{config: config})

      # Verify research-specific stages
      assert :rag in config.stages

      # Verify RAG correction is enabled
      assert config.rag_config.correction == true

      # Verify calibration uses citations
      assert config.calibration_config.medium_action == :with_citations

      # Run pipeline
      {:ok, result} =
        Pipeline.run(
          pipeline,
          "What is the capital of France?",
          generator: &research_generator/2
        )

      assert %PipelineResult{} = result
    end

    test "presets can be compared for cost vs accuracy" do
      # All presets should produce valid configs
      for preset <- [:fast, :balanced, :accurate, :coding, :research] do
        assert {:ok, config} = Presets.get(preset)
        assert {:ok, pipeline} = Pipeline.new(%{config: config})
        assert {:ok, _result} = Pipeline.run(pipeline, "What is 2+2?", generator: &math_generator/2)
      end
    end

    test "preset candidate counts increase from fast to accurate" do
      {:ok, fast_config} = Presets.get(:fast)
      {:ok, balanced_config} = Presets.get(:balanced)
      {:ok, accurate_config} = Presets.get(:accurate)

      # Max candidates should increase: fast < balanced < accurate
      assert fast_config.generation_config.max_candidates <
               balanced_config.generation_config.max_candidates

      assert balanced_config.generation_config.max_candidates <=
               accurate_config.generation_config.max_candidates
    end
  end

  describe "trace completeness" do
    test "pipeline includes trace entries for each executed stage" do
      {:ok, pipeline} =
        Pipeline.new(%{
          config: %{stages: [:generation, :calibration]}
        })

      {:ok, result} = Pipeline.run(pipeline, "What is 2+2?", generator: &math_generator/2)

      # Trace should have entries for each stage
      refute Enum.empty?(result.trace)

      # Each trace entry should have required fields
      for entry <- result.trace do
        assert Map.has_key?(entry, :stage)
        assert Map.has_key?(entry, :status)
        assert Map.has_key?(entry, :duration_ms)
      end
    end

    test "pipeline trace includes timing information" do
      {:ok, pipeline} = Pipeline.new(%{})

      {:ok, result} = Pipeline.run(pipeline, "What is 2+2?", generator: &math_generator/2)

      # Total duration should be recorded
      assert is_integer(result.metadata.total_duration_ms) or
               is_float(result.metadata.total_duration_ms)

      # Each stage trace should have timing
      for entry <- result.trace do
        assert entry.duration_ms >= 0
      end
    end
  end

  describe "8.5.1.4 Self-consistency with varied responses" do
    test "pipeline aggregates multiple candidates" do
      {:ok, pipeline} =
        Pipeline.new(%{
          config: %{
            stages: [:generation, :calibration],
            generation_config: %{
              min_candidates: 3,
              max_candidates: 3,
              batch_size: 3
            }
          }
        })

      {:ok, result} = Pipeline.run(pipeline, "What is the ultimate answer?", generator: &varied_generator/2)

      # Should have processed multiple candidates
      assert result.metadata.num_candidates >= 1

      # Should have produced a final answer
      assert is_binary(result.answer)
    end
  end
end
