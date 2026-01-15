defmodule Jido.AI.Accuracy.PipelineConfigTest do
  @moduledoc """
  Tests for PipelineConfig.
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.PipelineConfig

  describe "new/1" do
    test "creates config with default stages" do
      assert {:ok, config} = PipelineConfig.new(%{})

      assert config.stages == [:difficulty_estimation, :generation, :verification, :calibration]
    end

    test "creates config with custom stages" do
      assert {:ok, config} = PipelineConfig.new(%{
        stages: [:generation, :calibration]
      })

      assert config.stages == [:generation, :calibration]
    end

    test "creates config with all stages" do
      assert {:ok, config} = PipelineConfig.new(%{
        stages: PipelineConfig.all_stages()
      })

      assert length(config.stages) == 7
      assert :rag in config.stages
      assert :search in config.stages
      assert :reflection in config.stages
    end

    test "returns error for empty stages list" do
      assert {:error, :no_stages} = PipelineConfig.new(%{stages: []})
    end

    test "returns error for missing required stage" do
      assert {:error, {:missing_required_stages, [:generation]}} =
        PipelineConfig.new(%{stages: [:difficulty_estimation, :calibration]})
    end

    test "returns error for invalid stage name" do
      assert {:error, :invalid_stage} =
        PipelineConfig.new(%{stages: [:generation, :invalid_stage]})
    end

    test "normalizes generation config" do
      assert {:ok, config} = PipelineConfig.new(%{
        stages: [:generation],
        generation_config: %{
          min_candidates: 5,
          max_candidates: 15
        }
      })

      assert config.generation_config.min_candidates == 5
      assert config.generation_config.max_candidates == 15
      assert config.generation_config.batch_size == 3  # default
    end

    test "normalizes verification config" do
      assert {:ok, config} = PipelineConfig.new(%{
        stages: [:generation],
        verifier_config: %{
          use_outcome: false,
          parallel: true
        }
      })

      assert config.verifier_config.use_outcome == false
      assert config.verifier_config.use_process == true  # default
      assert config.verifier_config.parallel == true
    end

    test "normalizes calibration config" do
      assert {:ok, config} = PipelineConfig.new(%{
        stages: [:generation],
        calibration_config: %{
          high_threshold: 0.8,
          low_threshold: 0.5,
          low_action: :escalate
        }
      })

      assert config.calibration_config.high_threshold == 0.8
      assert config.calibration_config.low_threshold == 0.5
      assert config.calibration_config.low_action == :escalate
      assert config.calibration_config.medium_action == :with_verification  # default
    end

    test "sets telemetry_enabled" do
      assert {:ok, config} = PipelineConfig.new(%{telemetry_enabled: false})
      assert config.telemetry_enabled == false
    end
  end

  describe "new!/1" do
    test "creates config or raises" do
      config = PipelineConfig.new!(%{})
      assert config.stages == [:difficulty_estimation, :generation, :verification, :calibration]

      assert_raise ArgumentError, ~r/Invalid PipelineConfig/, fn ->
        PipelineConfig.new!(%{stages: []})
      end
    end
  end

  describe "all_stages/0" do
    test "returns all available stages" do
      stages = PipelineConfig.all_stages()

      assert :difficulty_estimation in stages
      assert :rag in stages
      assert :generation in stages
      assert :verification in stages
      assert :search in stages
      assert :reflection in stages
      assert :calibration in stages
    end
  end

  describe "default_stages/0" do
    test "returns default stages" do
      stages = PipelineConfig.default_stages()

      assert stages == [:difficulty_estimation, :generation, :verification, :calibration]
    end
  end

  describe "required_stages/0" do
    test "returns required stages" do
      stages = PipelineConfig.required_stages()
      assert stages == [:generation]
    end
  end

  describe "with_stage/2" do
    test "adds stage if not present" do
      config = PipelineConfig.new!(%{stages: [:generation, :calibration]})
      updated = PipelineConfig.with_stage(config, :verification)

      assert :verification in updated.stages
      assert :generation in updated.stages
      assert :calibration in updated.stages
    end

    test "does not duplicate existing stage" do
      config = PipelineConfig.new!(%{stages: [:generation, :calibration]})
      updated = PipelineConfig.with_stage(config, :generation)

      assert Enum.count(updated.stages, &(&1 == :generation)) == 1
    end
  end

  describe "without_stage/2" do
    test "removes stage if present" do
      config = PipelineConfig.new!(%{})
      updated = PipelineConfig.without_stage(config, :difficulty_estimation)

      refute :difficulty_estimation in updated.stages
      assert :generation in updated.stages
      assert :verification in updated.stages
      assert :calibration in updated.stages
    end

    test "does nothing if stage not present" do
      config = PipelineConfig.new!(%{stages: [:generation, :calibration]})
      updated = PipelineConfig.without_stage(config, :verification)

      assert updated.stages == [:generation, :calibration]
    end
  end

  describe "stage_enabled?/2" do
    test "returns true for enabled stage" do
      config = PipelineConfig.new!(%{})
      assert PipelineConfig.stage_enabled?(config, :generation)
    end

    test "returns false for disabled stage" do
      config = PipelineConfig.new!(%{stages: [:generation, :calibration]})
      refute PipelineConfig.stage_enabled?(config, :verification)
    end
  end

  describe "validate/1" do
    test "returns :ok for valid config" do
      config = PipelineConfig.new!(%{})
      assert :ok = PipelineConfig.validate(config)
    end

    test "returns error for invalid generation config" do
      config = PipelineConfig.new!(%{generation_config: %{min_candidates: 0}})
      assert {:error, :invalid_generation_config} = PipelineConfig.validate(config)
    end

    test "returns error for invalid calibration config" do
      config = PipelineConfig.new!(%{calibration_config: %{high_threshold: 0.3, low_threshold: 0.5}})
      assert {:error, :invalid_calibration_config} = PipelineConfig.validate(config)
    end
  end

  describe "merge/2" do
    test "merges user config with defaults" do
      config = PipelineConfig.new!(%{})
      assert {:ok, merged} = PipelineConfig.merge(config, %{stages: [:generation, :calibration]})

      assert merged.stages == [:generation, :calibration]
    end
  end

  describe "defaults/0" do
    test "returns default config map" do
      defaults = PipelineConfig.defaults()

      assert is_map(defaults)
      assert is_list(defaults.stages)
      assert is_map(defaults.generation_config)
      assert is_map(defaults.verifier_config)
    end
  end
end
