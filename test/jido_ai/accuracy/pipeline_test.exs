defmodule Jido.AI.Accuracy.PipelineTest do
  @moduledoc """
  Tests for the Pipeline module.
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Pipeline, PipelineConfig, PipelineResult, Candidate}

  @moduletag :pipeline

  describe "new/1" do
    test "creates pipeline with default config" do
      assert {:ok, pipeline} = Pipeline.new(%{})
      assert %Pipeline{} = pipeline
      assert %PipelineConfig{} = pipeline.config
    end

    test "creates pipeline with custom config" do
      assert {:ok, pipeline} = Pipeline.new(%{
        config: %{stages: [:generation, :calibration]}
      })

      assert pipeline.config.stages == [:generation, :calibration]
    end

    test "creates pipeline with PipelineConfig struct" do
      config = PipelineConfig.new!(%{stages: [:generation, :calibration]})
      assert {:ok, pipeline} = Pipeline.new(%{config: config})

      assert pipeline.config.stages == [:generation, :calibration]
    end

    test "creates pipeline with telemetry disabled" do
      assert {:ok, pipeline} = Pipeline.new(%{telemetry_enabled: false})
      assert pipeline.telemetry_enabled == false
    end

    test "returns error for invalid config" do
      assert {:error, _reason} = Pipeline.new(%{
        config: %{stages: []}
      })
    end
  end

  describe "new!/1" do
    test "creates pipeline or raises" do
      pipeline = Pipeline.new!(%{})
      assert %Pipeline{} = pipeline

      assert_raise ArgumentError, ~r/Invalid Pipeline/, fn ->
        Pipeline.new!(%{config: %{stages: []}})
      end
    end
  end

  describe "run/3" do
    setup do
      # Simple generator that returns a candidate
      generator = fn query, _context ->
        {:ok, Candidate.new!(%{content: "Answer to: #{query}"})}
      end

      {:ok, generator: generator}
    end

    test "runs pipeline with minimal stages", %{generator: generator} do
      {:ok, pipeline} = Pipeline.new(%{
        config: %{stages: [:generation, :calibration]}
      })

      {:ok, result} = Pipeline.run(pipeline, "What is 2+2?", generator: generator)

      assert %PipelineResult{} = result
      assert is_binary(result.answer)
      assert result.confidence >= 0.0 and result.confidence <= 1.0
      assert is_list(result.trace)
    end

    test "runs pipeline with all stages enabled", %{generator: generator} do
      {:ok, pipeline} = Pipeline.new(%{
        config: %{stages: PipelineConfig.all_stages()}
      })

      {:ok, result} = Pipeline.run(pipeline, "What is 2+2?", generator: generator)

      assert %PipelineResult{} = result
      assert length(result.trace) > 0
    end

    test "returns error for empty query", %{generator: generator} do
      {:ok, pipeline} = Pipeline.new(%{})

      assert {:error, :empty_query} = Pipeline.run(pipeline, "", generator: generator)
    end

    test "returns error when no generator provided" do
      {:ok, pipeline} = Pipeline.new(%{})

      assert {:error, :generator_required} = Pipeline.run(pipeline, "test")
    end

    test "returns error for invalid generator" do
      {:ok, pipeline} = Pipeline.new(%{})

      assert {:error, :invalid_generator} = Pipeline.run(pipeline, "test", generator: "not_a_function")
    end

    test "accepts 2-arity generator", %{generator: generator} do
      {:ok, pipeline} = Pipeline.new(%{
        config: %{stages: [:generation, :calibration]}
      })

      {:ok, result} = Pipeline.run(pipeline, "test", generator: generator)
      assert %PipelineResult{} = result
    end

    test "accepts 1-arity generator" do
      generator = fn query ->
        {:ok, Candidate.new!(%{content: "Answer: #{query}"})}
      end

      {:ok, pipeline} = Pipeline.new(%{
        config: %{stages: [:generation, :calibration]}
      })

      {:ok, result} = Pipeline.run(pipeline, "test", generator: generator)
      assert %PipelineResult{} = result
    end

    test "includes context in pipeline execution", %{generator: generator} do
      {:ok, pipeline} = Pipeline.new(%{
        config: %{stages: [:generation, :calibration]}
      })

      context = %{model: "test-model", temperature: 0.7}

      {:ok, result} = Pipeline.run(pipeline, "test", generator: generator, context: context)
      assert %PipelineResult{} = result
    end

    test "applies timeout to pipeline execution", %{generator: generator} do
      # Create a slow generator
      slow_generator = fn _query, _context ->
        Process.sleep(200)
        {:ok, Candidate.new!(%{content: "Slow answer"})}
      end

      {:ok, pipeline} = Pipeline.new(%{
        config: %{stages: [:generation, :calibration]}
      })

      # Set timeout lower than generation time
      assert {:error, :timeout} = Pipeline.run(pipeline, "test", generator: slow_generator, timeout: 50)
    end
  end

  describe "run_stream/3" do
    test "returns enumerable for streaming" do
      generator = fn query, _context ->
        {:ok, Candidate.new!(%{content: "Answer: #{query}"})}
      end

      {:ok, pipeline} = Pipeline.new(%{})

      stream = Pipeline.run_stream(pipeline, "test", generator: generator)
      assert Enumerable.impl_for(stream)
    end
  end

  describe "default_config/0" do
    test "returns default configuration map" do
      config = Pipeline.default_config()

      assert is_map(config)
      assert is_list(config.stages)
      assert :generation in config.stages
      assert :calibration in config.stages
    end
  end

  describe "integration: difficulty_estimation to calibration" do
    test "full pipeline from difficulty to final answer" do
      # Create a generator that varies output
      call_count = :counters.new(1, [])

      generator = fn query, _context ->
        count = :counters.add(call_count, 1, 1)
        {:ok, Candidate.new!(%{content: "Candidate #{count}: #{query}", score: 0.8})}
      end

      {:ok, pipeline} = Pipeline.new(%{})

      {:ok, result} = Pipeline.run(pipeline, "What is 2+2?", generator: generator)

      # Verify result structure
      assert %PipelineResult{} = result
      assert is_binary(result.answer)
      assert result.confidence >= 0.0 and result.confidence <= 1.0
      assert result.action in [:direct, :with_verification, :with_citations, :abstain, :escalate]

      # Verify trace
      assert length(result.trace) > 0
      assert is_list(result.metadata.stages_completed)
    end

    test "pipeline with abstention on low confidence" do
      # Create a generator that returns low-score candidates
      generator = fn query, _context ->
        {:ok, Candidate.new!(%{content: "Uncertain: #{query}", score: 0.2})}
      end

      {:ok, pipeline} = Pipeline.new(%{
        config: %{
          stages: [:generation, :calibration],
          calibration_config: %{
            low_threshold: 0.4,
            low_action: :abstain
          }
        }
      })

      {:ok, result} = Pipeline.run(pipeline, "complex question", generator: generator)

      assert result.action == :abstain
      assert PipelineResult.abstained?(result)
    end

    test "pipeline with direct routing on high confidence" do
      # Create a generator that returns high-score candidates
      generator = fn query, _context ->
        {:ok, Candidate.new!(%{content: "Certain: #{query}", score: 0.95})}
      end

      {:ok, pipeline} = Pipeline.new(%{
        config: %{
          stages: [:generation, :calibration],
          calibration_config: %{
            high_threshold: 0.8
          }
        }
      })

      {:ok, result} = Pipeline.run(pipeline, "simple question", generator: generator)

      assert result.action == :direct
      assert PipelineResult.direct?(result)
    end
  end
end
