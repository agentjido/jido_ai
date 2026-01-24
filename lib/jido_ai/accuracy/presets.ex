defmodule Jido.AI.Accuracy.Presets do
  @moduledoc """
  Pre-configured strategy presets for the accuracy pipeline.

  Presets provide optimized configurations for common use cases, balancing
  cost, latency, and accuracy. Each preset returns a PipelineConfig that
  can be used directly with Pipeline.run/3.

  ## Available Presets

  | Preset    | Description                                | Candidates | Features                          |
  |-----------|-------------------------------------------|------------|-----------------------------------|
  | `:fast`   | Minimal compute, basic verification        | 1-3        | Generation + Calibration only    |
  | `:balanced` | Moderate compute, full verification      | 3-5        | + Difficulty + Verification       |
  | `:accurate` | Maximum compute, all features            | 5-10       | + Search + Reflection              |
  | `:coding` | Optimized for code correctness            | 3-5        | + RAG + Code Verifiers             |
  | `:research` | Optimized for factual QA                | 3-5        | + RAG + Factuality Verifier        |

  ## Usage

      # Get a preset configuration
      {:ok, config} = Presets.get(:balanced)

      # Use with pipeline
      {:ok, pipeline} = Pipeline.new(%{config: config})
      {:ok, result} = Pipeline.run(pipeline, "What is 2+2?", generator: my_generator)

      # Customize a preset
      {:ok, custom} = Presets.customize(:fast, %{generation_config: %{max_candidates: 5}})

      # List all presets
      Presets.list()
      # => [:fast, :balanced, :accurate, :coding, :research]

  """

  alias Jido.AI.Accuracy.{PipelineConfig, Thresholds}

  @type preset :: :fast | :balanced | :accurate | :coding | :research

  @all_presets [:fast, :balanced, :accurate, :coding, :research]

  @doc """
  Returns the configuration for a given preset.

  ## Examples

      iex> {:ok, config} = Presets.get(:fast)
      iex> config.stages
      [:generation, :calibration]

  """
  @spec get(preset()) :: {:ok, PipelineConfig.t()} | {:error, :unknown_preset}
  def get(:fast), do: create_config(fast_preset())
  def get(:balanced), do: create_config(balanced_preset())
  def get(:accurate), do: create_config(accurate_preset())
  def get(:coding), do: create_config(coding_preset())
  def get(:research), do: create_config(research_preset())
  def get(_), do: {:error, :unknown_preset}

  @doc """
  Returns a list of all available preset names.

  ## Examples

      iex> Presets.list()
      [:fast, :balanced, :accurate, :coding, :research]

  """
  @spec list() :: [preset()]
  def list, do: @all_presets

  @doc """
  Returns the raw configuration map for a preset.

  ## Examples

      iex> {:ok, config} = Presets.get_config(:fast)
      iex> config[:stages]
      [:generation, :calibration]

  """
  @spec get_config(preset()) :: {:ok, map()} | {:error, :unknown_preset}
  def get_config(:fast), do: {:ok, fast_preset()}
  def get_config(:balanced), do: {:ok, balanced_preset()}
  def get_config(:accurate), do: {:ok, accurate_preset()}
  def get_config(:coding), do: {:ok, coding_preset()}
  def get_config(:research), do: {:ok, research_preset()}
  def get_config(_), do: {:error, :unknown_preset}

  @doc """
  Customizes a preset with override values.

  ## Examples

      iex> {:ok, config} = Presets.customize(:fast, %{generation_config: %{max_candidates: 5}})
      iex> config.generation_config.max_candidates
      5

  """
  @spec customize(preset(), map()) :: {:ok, PipelineConfig.t()} | {:error, term()}
  def customize(preset, overrides) when is_map(overrides) do
    with {:ok, base_config} <- get_config(preset),
         {:ok, pipeline_config} <- PipelineConfig.new(base_config),
         {:ok, merged} <- PipelineConfig.merge(pipeline_config, overrides),
         :ok <- PipelineConfig.validate(merged) do
      {:ok, merged}
    end
  end

  @doc """
  Validates that a preset produces a valid PipelineConfig.

  ## Examples

      iex> Presets.validate(:fast)
      :ok

  """
  @spec validate(preset()) :: :ok | {:error, term()}
  def validate(preset) do
    case get(preset) do
      {:ok, config} -> PipelineConfig.validate(config)
      {:error, _} = error -> error
    end
  end

  @doc """
  Checks if a preset name is valid.

  ## Examples

      iex> Presets.preset?(:fast)
      true

  """
  @spec preset?(term()) :: boolean()
  def preset?(preset) when preset in @all_presets, do: true
  def preset?(_), do: false

  # Preset Definitions

  defp fast_preset do
    %{
      stages: [:generation, :calibration],
      generation_config: %{
        min_candidates: 1,
        max_candidates: 3,
        batch_size: 3,
        early_stop_threshold: 0.9
      },
      verifier_config: %{
        use_outcome: false,
        use_process: false,
        verifiers: [],
        parallel: false
      },
      calibration_config: %{
        high_threshold: 0.75,
        low_threshold: 0.5,
        medium_action: :with_verification,
        low_action: :abstain
      },
      telemetry_enabled: true
    }
  end

  defp balanced_preset do
    %{
      stages: [:difficulty_estimation, :generation, :verification, :calibration],
      generation_config: %{
        min_candidates: 3,
        max_candidates: 5,
        batch_size: 3,
        early_stop_threshold: Thresholds.early_stop_threshold()
      },
      verifier_config: %{
        use_outcome: true,
        use_process: true,
        verifiers: [],
        parallel: false
      },
      calibration_config: %{
        high_threshold: Thresholds.calibration_high_confidence(),
        low_threshold: Thresholds.calibration_medium_confidence(),
        medium_action: :with_verification,
        low_action: :abstain
      },
      telemetry_enabled: true
    }
  end

  defp accurate_preset do
    %{
      stages: [:difficulty_estimation, :generation, :verification, :search, :reflection, :calibration],
      generation_config: %{
        min_candidates: 5,
        max_candidates: 10,
        batch_size: 3,
        early_stop_threshold: 0.7
      },
      verifier_config: %{
        use_outcome: true,
        use_process: true,
        verifiers: [],
        parallel: false
      },
      search_config: %{
        enabled: true,
        algorithm: :beam_search,
        beam_width: 5,
        iterations: 50
      },
      reflection_config: %{
        enabled: true,
        max_iterations: 3,
        convergence_threshold: 0.1
      },
      calibration_config: %{
        high_threshold: 0.8,
        low_threshold: 0.3,
        medium_action: :with_verification,
        low_action: :abstain
      },
      telemetry_enabled: true
    }
  end

  defp coding_preset do
    %{
      stages: [:difficulty_estimation, :rag, :generation, :verification, :reflection, :calibration],
      generation_config: %{
        min_candidates: 3,
        max_candidates: 5,
        batch_size: 3,
        early_stop_threshold: 0.8
      },
      rag_config: %{
        enabled: true,
        correction: false
      },
      verifier_config: %{
        use_outcome: true,
        use_process: true,
        verifiers: [],
        parallel: false
      },
      reflection_config: %{
        enabled: true,
        max_iterations: 2,
        convergence_threshold: 0.15
      },
      calibration_config: %{
        high_threshold: 0.75,
        low_threshold: 0.4,
        medium_action: :with_verification,
        low_action: :abstain
      },
      telemetry_enabled: true
    }
  end

  defp research_preset do
    %{
      stages: [:difficulty_estimation, :rag, :generation, :verification, :calibration],
      generation_config: %{
        min_candidates: 3,
        max_candidates: 5,
        batch_size: 3,
        early_stop_threshold: 0.8
      },
      rag_config: %{
        enabled: true,
        correction: true
      },
      verifier_config: %{
        use_outcome: true,
        use_process: true,
        verifiers: [],
        parallel: false
      },
      calibration_config: %{
        high_threshold: 0.85,
        low_threshold: 0.5,
        medium_action: :with_citations,
        low_action: :abstain
      },
      telemetry_enabled: true
    }
  end

  defp create_config(preset_map) do
    PipelineConfig.new(preset_map)
  end
end
