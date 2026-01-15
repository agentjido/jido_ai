defmodule Jido.AI.Accuracy.PresetsTest do
  @moduledoc """
  Tests for the Presets module.
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Presets, PipelineConfig, Pipeline, Candidate}

  @moduletag :presets

  describe "list/0" do
    test "returns all preset names" do
      presets = Presets.list()

      assert is_list(presets)
      assert :fast in presets
      assert :balanced in presets
      assert :accurate in presets
      assert :coding in presets
      assert :research in presets
      assert length(presets) == 5
    end
  end

  describe "preset?/1" do
    test "returns true for valid presets" do
      assert Presets.preset?(:fast)
      assert Presets.preset?(:balanced)
      assert Presets.preset?(:accurate)
      assert Presets.preset?(:coding)
      assert Presets.preset?(:research)
    end

    test "returns false for invalid presets" do
      refute Presets.preset?(:unknown)
      refute Presets.preset?(:fast_and_accurate)
      refute Presets.preset?("fast")
      refute Presets.preset?(nil)
    end
  end

  describe "get/1" do
    test "returns valid PipelineConfig for :fast preset" do
      assert {:ok, config} = Presets.get(:fast)
      assert %PipelineConfig{} = config

      assert config.stages == [:generation, :calibration]
      assert config.generation_config.min_candidates == 1
      assert config.generation_config.max_candidates == 3
      refute config.verifier_config.use_outcome
      refute config.verifier_config.use_process
    end

    test "returns valid PipelineConfig for :balanced preset" do
      assert {:ok, config} = Presets.get(:balanced)
      assert %PipelineConfig{} = config

      assert :difficulty_estimation in config.stages
      assert :generation in config.stages
      assert :verification in config.stages
      assert :calibration in config.stages
      assert config.generation_config.min_candidates == 3
      assert config.generation_config.max_candidates == 5
      assert config.verifier_config.use_outcome
      assert config.verifier_config.use_process
    end

    test "returns valid PipelineConfig for :accurate preset" do
      assert {:ok, config} = Presets.get(:accurate)
      assert %PipelineConfig{} = config

      assert :difficulty_estimation in config.stages
      assert :generation in config.stages
      assert :verification in config.stages
      assert :search in config.stages
      assert :reflection in config.stages
      assert :calibration in config.stages
      assert :rag not in config.stages
      assert config.generation_config.min_candidates == 5
      assert config.generation_config.max_candidates == 10
      assert config.search_config.enabled
      assert config.reflection_config.enabled
    end

    test "returns valid PipelineConfig for :coding preset" do
      assert {:ok, config} = Presets.get(:coding)
      assert %PipelineConfig{} = config

      assert :difficulty_estimation in config.stages
      assert :rag in config.stages
      assert :generation in config.stages
      assert :verification in config.stages
      assert :reflection in config.stages
      assert :calibration in config.stages
      assert :search not in config.stages
      assert config.rag_config.enabled
      assert config.reflection_config.enabled
    end

    test "returns valid PipelineConfig for :research preset" do
      assert {:ok, config} = Presets.get(:research)
      assert %PipelineConfig{} = config

      assert :difficulty_estimation in config.stages
      assert :rag in config.stages
      assert :generation in config.stages
      assert :verification in config.stages
      assert :calibration in config.stages
      assert :search not in config.stages
      assert :reflection not in config.stages
      assert config.rag_config.enabled
      assert config.rag_config.correction
      assert config.calibration_config.medium_action == :with_citations
    end

    test "returns error for unknown preset" do
      assert {:error, :unknown_preset} = Presets.get(:unknown)
      assert {:error, :unknown_preset} = Presets.get(:non_existent)
    end
  end

  describe "get_config/1" do
    test "returns raw config map for :fast preset" do
      assert {:ok, config} = Presets.get_config(:fast)
      assert is_map(config)
      assert config[:stages] == [:generation, :calibration]
      assert is_map(config[:generation_config])
      assert is_map(config[:calibration_config])
    end

    test "returns error for unknown preset" do
      assert {:error, :unknown_preset} = Presets.get_config(:unknown)
    end
  end

  describe "validate/1" do
    test "validates all presets successfully" do
      assert :ok = Presets.validate(:fast)
      assert :ok = Presets.validate(:balanced)
      assert :ok = Presets.validate(:accurate)
      assert :ok = Presets.validate(:coding)
      assert :ok = Presets.validate(:research)
    end

    test "returns error for unknown preset" do
      assert {:error, :unknown_preset} = Presets.validate(:unknown)
    end
  end

  describe "customize/2" do
    test "customizes :fast preset with override" do
      # Note: customize replaces entire config sections, not deep merge
      assert {:ok, config} =
               Presets.customize(:fast, %{
                 generation_config: %{min_candidates: 1, max_candidates: 5}
               })

      assert config.generation_config.max_candidates == 5
      assert config.generation_config.min_candidates == 1
    end

    test "customizes :balanced preset to add search stage" do
      assert {:ok, config} =
               Presets.customize(:balanced, %{
                 stages: [:difficulty_estimation, :generation, :verification, :search, :calibration]
               })

      assert :search in config.stages
    end

    test "customizes accurate preset with higher candidate count" do
      # Note: customize replaces entire config sections, not deep merge
      assert {:ok, config} =
               Presets.customize(:accurate, %{
                 generation_config: %{min_candidates: 5, max_candidates: 15}
               })

      assert config.generation_config.max_candidates == 15
    end

    test "customizes coding preset with additional verifiers" do
      # Note: customize replaces entire config sections, not deep merge
      assert {:ok, config} =
               Presets.customize(:coding, %{
                 verifier_config: %{
                   use_outcome: true,
                   use_process: true,
                   verifiers: [:code_syntax, :code_execution],
                   parallel: false
                 }
               })

      assert :code_syntax in config.verifier_config.verifiers
      assert :code_execution in config.verifier_config.verifiers
    end

    test "customizes research preset with stricter calibration" do
      # Note: customize replaces entire config sections, not deep merge
      assert {:ok, config} =
               Presets.customize(:research, %{
                 calibration_config: %{
                   high_threshold: 0.9,
                   low_threshold: 0.5,
                   medium_action: :with_citations,
                   low_action: :abstain
                 }
               })

      assert config.calibration_config.high_threshold == 0.9
    end

    test "returns error for unknown preset" do
      assert {:error, :unknown_preset} = Presets.customize(:unknown, %{})
    end

    test "returns error for invalid override" do
      # Calibration config requires high_threshold > low_threshold
      assert {:error, _reason} =
               Presets.customize(:fast, %{calibration_config: %{high_threshold: 0.3, low_threshold: 0.5}})
    end
  end

  describe "Preset Stage Configurations" do
    test "fast preset has minimal stages for speed" do
      assert {:ok, config} = Presets.get(:fast)

      assert length(config.stages) == 2
      assert :generation in config.stages
      assert :calibration in config.stages
      refute :difficulty_estimation in config.stages
      refute :rag in config.stages
      refute :verification in config.stages
      refute :search in config.stages
      refute :reflection in config.stages
    end

    test "balanced preset includes verification but not search/reflection" do
      assert {:ok, config} = Presets.get(:balanced)

      assert :verification in config.stages
      refute :search in config.stages
      refute :reflection in config.stages
    end

    test "accurate preset includes all optional stages except RAG" do
      assert {:ok, config} = Presets.get(:accurate)

      assert :search in config.stages
      assert :reflection in config.stages
      refute :rag in config.stages
    end

    test "coding preset includes RAG and reflection but not search" do
      assert {:ok, config} = Presets.get(:coding)

      assert :rag in config.stages
      assert :reflection in config.stages
      refute :search in config.stages
    end

    test "research preset includes RAG but not search or reflection" do
      assert {:ok, config} = Presets.get(:research)

      assert :rag in config.stages
      refute :search in config.stages
      refute :reflection in config.stages
    end
  end

  describe "Preset Candidate Counts" do
    test "fast preset has lowest candidate count" do
      assert {:ok, config} = Presets.get(:fast)

      assert config.generation_config.min_candidates == 1
      assert config.generation_config.max_candidates == 3
    end

    test "balanced preset has moderate candidate count" do
      assert {:ok, config} = Presets.get(:balanced)

      assert config.generation_config.min_candidates == 3
      assert config.generation_config.max_candidates == 5
    end

    test "accurate preset has highest candidate count" do
      assert {:ok, config} = Presets.get(:accurate)

      assert config.generation_config.min_candidates == 5
      assert config.generation_config.max_candidates == 10
    end

    test "coding preset has same candidate count as balanced" do
      assert {:ok, config} = Presets.get(:coding)

      assert config.generation_config.min_candidates == 3
      assert config.generation_config.max_candidates == 5
    end

    test "research preset has same candidate count as balanced" do
      assert {:ok, config} = Presets.get(:research)

      assert config.generation_config.min_candidates == 3
      assert config.generation_config.max_candidates == 5
    end
  end

  describe "Preset Calibration Thresholds" do
    test "fast preset has more lenient thresholds" do
      assert {:ok, config} = Presets.get(:fast)

      assert config.calibration_config.high_threshold == 0.75
      assert config.calibration_config.low_threshold == 0.5
      assert config.calibration_config.medium_action == :with_verification
    end

    test "research preset has strictest thresholds for factuality" do
      assert {:ok, config} = Presets.get(:research)

      assert config.calibration_config.high_threshold == 0.85
      assert config.calibration_config.low_threshold == 0.5
      assert config.calibration_config.medium_action == :with_citations
    end

    test "accurate preset has stricter low threshold" do
      assert {:ok, config} = Presets.get(:accurate)

      assert config.calibration_config.high_threshold == 0.8
      assert config.calibration_config.low_threshold == 0.3
    end
  end

  describe "Integration with Pipeline" do
    setup do
      generator = fn query, _context ->
        {:ok, Candidate.new!(%{content: "Answer to: #{query}"})}
      end

      {:ok, generator: generator}
    end

    test "fast preset works with Pipeline.run/3", %{generator: generator} do
      {:ok, preset_config} = Presets.get(:fast)
      {:ok, pipeline} = Pipeline.new(%{config: preset_config})

      assert {:ok, result} = Pipeline.run(pipeline, "What is 2+2?", generator: generator)
      assert is_binary(result.answer)
    end

    test "balanced preset works with Pipeline.run/3", %{generator: generator} do
      {:ok, preset_config} = Presets.get(:balanced)
      {:ok, pipeline} = Pipeline.new(%{config: preset_config})

      assert {:ok, result} = Pipeline.run(pipeline, "What is 2+2?", generator: generator)
      assert is_binary(result.answer)
    end

    test "accurate preset works with Pipeline.run/3", %{generator: generator} do
      {:ok, preset_config} = Presets.get(:accurate)
      {:ok, pipeline} = Pipeline.new(%{config: preset_config})

      assert {:ok, result} = Pipeline.run(pipeline, "What is 2+2?", generator: generator)
      assert is_binary(result.answer)
    end

    test "coding preset works with Pipeline.run/3", %{generator: generator} do
      {:ok, preset_config} = Presets.get(:coding)
      {:ok, pipeline} = Pipeline.new(%{config: preset_config})

      assert {:ok, result} = Pipeline.run(pipeline, "Write a function", generator: generator)
      assert is_binary(result.answer)
    end

    test "research preset works with Pipeline.run/3", %{generator: generator} do
      {:ok, preset_config} = Presets.get(:research)
      {:ok, pipeline} = Pipeline.new(%{config: preset_config})

      assert {:ok, result} = Pipeline.run(pipeline, "What is the capital of France?", generator: generator)
      assert is_binary(result.answer)
    end
  end

  describe "Preset Config Validation" do
    test "all presets pass PipelineConfig validation" do
      for preset <- Presets.list() do
        assert {:ok, config} = Presets.get(preset)
        assert :ok = PipelineConfig.validate(config),
               "Preset #{preset} failed validation"
      end
    end

    test "all presets include required stages" do
      for preset <- Presets.list() do
        assert {:ok, config} = Presets.get(preset)
        assert :generation in config.stages,
               "Preset #{preset} missing required generation stage"
      end
    end
  end
end
