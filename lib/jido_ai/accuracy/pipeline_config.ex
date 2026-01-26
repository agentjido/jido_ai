defmodule Jido.AI.Accuracy.PipelineConfig do
  @moduledoc """
  Configuration for the accuracy pipeline.

  PipelineConfig defines which stages are enabled and their configuration.
  Provides validation and default values for all pipeline components.

  ## Configuration Structure

      %{
        stages: [:difficulty_estimation, :generation, :verification, :calibration],
        difficulty_estimator: HeuristicDifficulty,
        generation_config: %{
          min_candidates: 3,
          max_candidates: 10
        },
        verifier_config: %{
          use_outcome: true,
          use_process: true
        },
        calibration_config: %{
          high_threshold: 0.7,
          low_threshold: 0.4
        },
        telemetry_enabled: true
      }

  ## Stage Options

  Available stages:
  - `:difficulty_estimation` - Estimate query difficulty
  - `:rag` - Retrieve and correct context (optional)
  - `:generation` - Generate candidates
  - `:verification` - Score candidates with verifiers
  - `:search` - Beam search/MCTS (optional)
  - `:reflection` - Iterative improvement (optional)
  - `:calibration` - Confidence-based routing

  ## Usage

      # Create config with defaults
      {:ok, config} = PipelineConfig.new(%{})

      # Enable all stages
      {:ok, config} = PipelineConfig.new(%{
        stages: PipelineConfig.all_stages()
      })

      # Customize specific stage
      config = PipelineConfig.with_stage(config, :search)

      # Disable a stage
      config = PipelineConfig.without_stage(config, :rag)

  """

  alias Jido.AI.Accuracy.{Estimators, Thresholds}

  @type t :: %__MODULE__{
          stages: [atom()],
          difficulty_estimator: module() | nil,
          rag_config: rag_config() | nil,
          generation_config: generation_config(),
          verifier_config: verifier_config(),
          search_config: search_config() | nil,
          reflection_config: reflection_config() | nil,
          calibration_config: calibration_config(),
          budget_limit: float() | nil,
          telemetry_enabled: boolean()
        }

  @type rag_config :: %{
          optional(:enabled) => boolean(),
          optional(:retriever) => module(),
          optional(:correction) => boolean()
        }

  @type generation_config :: %{
          optional(:min_candidates) => pos_integer(),
          optional(:max_candidates) => pos_integer(),
          optional(:batch_size) => pos_integer(),
          optional(:early_stop_threshold) => float()
        }

  @type verifier_config :: %{
          optional(:use_outcome) => boolean(),
          optional(:use_process) => boolean(),
          optional(:verifiers) => [term()],
          optional(:parallel) => boolean()
        }

  @type search_config :: %{
          optional(:enabled) => boolean(),
          optional(:algorithm) => :beam_search | :mcts,
          optional(:beam_width) => pos_integer(),
          optional(:iterations) => pos_integer()
        }

  @type reflection_config :: %{
          optional(:enabled) => boolean(),
          optional(:max_iterations) => pos_integer(),
          optional(:convergence_threshold) => float()
        }

  @type calibration_config :: %{
          optional(:high_threshold) => float(),
          optional(:low_threshold) => float(),
          optional(:medium_action) => atom(),
          optional(:low_action) => atom()
        }

  @all_stages [
    :difficulty_estimation,
    :rag,
    :generation,
    :verification,
    :search,
    :reflection,
    :calibration
  ]

  @required_stages [:generation]

  defstruct [
    :stages,
    :difficulty_estimator,
    :rag_config,
    :generation_config,
    :verifier_config,
    :search_config,
    :reflection_config,
    :calibration_config,
    :budget_limit,
    :telemetry_enabled
  ]

  @default_stages [
    :difficulty_estimation,
    :generation,
    :verification,
    :calibration
  ]

  @doc """
  Returns all available stage names.

  """
  @spec all_stages() :: [atom()]
  def all_stages, do: @all_stages

  @doc """
  Returns the default stages configuration.

  """
  @spec default_stages() :: [atom()]
  def default_stages, do: @default_stages

  @doc """
  Returns required stages that must be present.

  """
  @spec required_stages() :: [atom()]
  def required_stages, do: @required_stages

  @doc """
  Creates a new PipelineConfig from the given attributes.

  ## Parameters

  - `attrs` - Map with configuration attributes:
    - `:stages` - List of enabled stages (default: [:difficulty_estimation, :generation, :verification, :calibration])
    - `:difficulty_estimator` - Module for difficulty estimation (default: Estimators.HeuristicDifficulty)
    - `:rag_config` - RAG stage configuration (optional)
    - `:generation_config` - Generation stage configuration (optional)
    - `:verifier_config` - Verification stage configuration (optional)
    - `:search_config` - Search stage configuration (optional)
    - `:reflection_config` - Reflection stage configuration (optional)
    - `:calibration_config` - Calibration stage configuration (optional)
    - `:budget_limit` - Overall budget limit (optional)
    - `:telemetry_enabled` - Whether to emit telemetry (default: true)

  ## Returns

  `{:ok, config}` on success, `{:error, reason}` on validation failure.

  ## Examples

      iex> PipelineConfig.new(%{})
      {:ok, %PipelineConfig{stages: [:difficulty_estimation, :generation, :verification, :calibration]}}

      iex> PipelineConfig.new(%{stages: [:generation, :calibration]})
      {:ok, %PipelineConfig{stages: [:generation, :calibration]}}

      iex> PipelineConfig.new(%{stages: []})
      {:error, :no_stages}

      iex> PipelineConfig.new(%{stages: [:generation], verifier_config: %{use_outcome: "invalid"}})
      {:error, :invalid_verifier_config}

  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    stages = Map.get(attrs, :stages, @default_stages)

    with :ok <- validate_stages(stages),
         :ok <- validate_required_stages(stages) do
      config = %__MODULE__{
        stages: stages,
        difficulty_estimator: Map.get(attrs, :difficulty_estimator, Estimators.HeuristicDifficulty),
        rag_config: normalize_rag_config(Map.get(attrs, :rag_config)),
        generation_config: normalize_generation_config(Map.get(attrs, :generation_config, %{})),
        verifier_config: normalize_verifier_config(Map.get(attrs, :verifier_config, %{})),
        search_config: normalize_search_config(Map.get(attrs, :search_config)),
        reflection_config: normalize_reflection_config(Map.get(attrs, :reflection_config)),
        calibration_config: normalize_calibration_config(Map.get(attrs, :calibration_config, %{})),
        budget_limit: Map.get(attrs, :budget_limit),
        telemetry_enabled: Map.get(attrs, :telemetry_enabled, true)
      }

      {:ok, config}
    end
  end

  @doc """
  Creates a new PipelineConfig, raising on error.

  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, config} -> config
      {:error, reason} -> raise ArgumentError, "Invalid PipelineConfig: #{format_error(reason)}"
    end
  end

  @doc """
  Returns the default configuration map.

  """
  @spec defaults() :: map()
  def defaults do
    {:ok, config} = new(%{})
    config
  end

  @doc """
  Adds a stage to the configuration if not already present.

  ## Examples

      config = PipelineConfig.new!(%{stages: [:generation, :calibration]})
      updated = PipelineConfig.with_stage(config, :verification)
      updated.stages  # => [:generation, :calibration, :verification]

  """
  @spec with_stage(t(), atom()) :: t()
  def with_stage(%__MODULE__{stages: stages} = config, stage) when is_atom(stage) do
    if stage in stages do
      config
    else
      %{config | stages: stages ++ [stage]}
    end
  end

  @doc """
  Removes a stage from the configuration if present.

  ## Examples

      config = PipelineConfig.new!(%{})
      updated = PipelineConfig.without_stage(config, :difficulty_estimation)
      updated.stages  # => [:generation, :verification, :calibration]

  """
  @spec without_stage(t(), atom()) :: t()
  def without_stage(%__MODULE__{stages: stages} = config, stage) when is_atom(stage) do
    updated_stages = Enum.reject(stages, &(&1 == stage))
    %{config | stages: updated_stages}
  end

  @doc """
  Checks if a stage is enabled in the configuration.

  """
  @spec stage_enabled?(t(), atom()) :: boolean()
  def stage_enabled?(%__MODULE__{stages: stages}, stage) when is_atom(stage) do
    stage in stages
  end

  @doc """
  Validates the configuration.

  Returns :ok if valid, {:error, reason} if invalid.

  """
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = config) do
    with :ok <- validate_stages(config.stages),
         :ok <- validate_required_stages(config.stages),
         :ok <- validate_generation_config(config.generation_config),
         :ok <- validate_verifier_config(config.verifier_config) do
      validate_calibration_config(config.calibration_config)
    end
  end

  @doc """
  Merges user configuration with defaults.

  User values override defaults for matching keys.

  """
  @spec merge(t(), map()) :: {:ok, t()} | {:error, term()}
  def merge(%__MODULE__{} = config, overrides) when is_map(overrides) do
    config
    |> Map.from_struct()
    |> Map.merge(overrides)
    |> new()
  end

  # Normalization functions

  defp normalize_rag_config(nil), do: nil
  defp normalize_rag_config(config) when is_map(config), do: config

  defp normalize_generation_config(config) when is_map(config) do
    %{
      min_candidates: Map.get(config, :min_candidates, 3),
      max_candidates: Map.get(config, :max_candidates, 10),
      batch_size: Map.get(config, :batch_size, 3),
      early_stop_threshold: Map.get(config, :early_stop_threshold, Thresholds.early_stop_threshold())
    }
  end

  defp normalize_verifier_config(config) when is_map(config) do
    %{
      use_outcome: Map.get(config, :use_outcome, true),
      use_process: Map.get(config, :use_process, true),
      verifiers: Map.get(config, :verifiers, []),
      parallel: Map.get(config, :parallel, false)
    }
  end

  defp normalize_search_config(nil), do: nil

  defp normalize_search_config(config) when is_map(config) do
    %{
      enabled: Map.get(config, :enabled, true),
      algorithm: Map.get(config, :algorithm, :beam_search),
      beam_width: Map.get(config, :beam_width, 5),
      iterations: Map.get(config, :iterations, 50)
    }
  end

  defp normalize_reflection_config(nil), do: nil

  defp normalize_reflection_config(config) when is_map(config) do
    %{
      enabled: Map.get(config, :enabled, true),
      max_iterations: Map.get(config, :max_iterations, 3),
      convergence_threshold: Map.get(config, :convergence_threshold, 0.1)
    }
  end

  defp normalize_calibration_config(config) when is_map(config) do
    %{
      high_threshold: Map.get(config, :high_threshold, Thresholds.calibration_high_confidence()),
      low_threshold: Map.get(config, :low_threshold, Thresholds.calibration_medium_confidence()),
      medium_action: Map.get(config, :medium_action, :with_verification),
      low_action: Map.get(config, :low_action, :abstain)
    }
  end

  # Validation functions

  defp validate_stages([]), do: {:error, :no_stages}

  defp validate_stages(stages) when is_list(stages) do
    if Enum.all?(stages, &(&1 in @all_stages)) do
      :ok
    else
      {:error, :invalid_stage}
    end
  end

  defp validate_stages(_), do: {:error, :stages_must_be_list}

  defp validate_required_stages(stages) when is_list(stages) do
    if Enum.all?(@required_stages, &(&1 in stages)) do
      :ok
    else
      {:error, {:missing_required_stages, @required_stages -- stages}}
    end
  end

  defp validate_generation_config(config) when is_map(config) do
    min = Map.get(config, :min_candidates, 1)
    max = Map.get(config, :max_candidates, 1)

    if is_integer(min) and min > 0 and is_integer(max) and max >= min do
      :ok
    else
      {:error, :invalid_generation_config}
    end
  end

  defp validate_verifier_config(config) when is_map(config) do
    use_outcome = Map.get(config, :use_outcome, true)
    use_process = Map.get(config, :use_process, true)

    if is_boolean(use_outcome) and is_boolean(use_process) do
      :ok
    else
      {:error, :invalid_verifier_config}
    end
  end

  defp validate_calibration_config(config) when is_map(config) do
    high = Map.get(config, :high_threshold, 0.7)
    low = Map.get(config, :low_threshold, 0.4)

    if is_number(high) and is_number(low) and high > low do
      :ok
    else
      {:error, :invalid_calibration_config}
    end
  end

  defp format_error(atom) when is_atom(atom), do: atom

  defp format_error({:missing_required_stages, stages}) do
    "missing_required_stages: #{inspect(stages)}"
  end
end
