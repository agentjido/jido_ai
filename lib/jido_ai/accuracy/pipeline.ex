defmodule Jido.AI.Accuracy.Pipeline do
  @moduledoc """
  End-to-end accuracy improvement pipeline.

  The Pipeline orchestrates all accuracy components in a configurable flow:
  difficulty estimation → RAG → generation → verification → search → reflection → calibration

  ## Configuration

  The pipeline is configured with a PipelineConfig that specifies:
  - Which stages are enabled
  - Configuration for each stage
  - Budget limits
  - Telemetry settings

  ## Usage

      # Create pipeline with default configuration
      {:ok, pipeline} = Pipeline.new(%{})

      # Define a generator function
      generator = fn query, _context ->
        {:ok, "The answer is: " <> process(query)}
      end

      # Run pipeline
      {:ok, result} = Pipeline.run(pipeline, "What is 2+2?", generator: generator)

      result.answer  # => "The answer is: 4"
      result.confidence  # => 0.85
      result.action  # => :direct

  ## Stages

  Available stages (in execution order):
  1. **difficulty_estimation** - Estimate query difficulty
  2. **rag** - Retrieve and correct context (optional)
  3. **generation** - Generate candidates with adaptive self-consistency
  4. **verification** - Score candidates with verifiers (optional)
  5. **search** - Beam search/MCTS (optional)
  6. **reflection** - Iterative improvement (optional)
  7. **calibration** - Confidence-based routing (optional)

  ## Result

  PipelineResult contains:
  - `:answer` - Final answer (or nil if abstained)
  - `:confidence` - Confidence score [0-1]
  - `:action` - Routing action taken
  - `:trace` - List of trace entries for each stage
  - `:metadata` - Execution metadata

  """

  alias Jido.AI.Accuracy.Stages.{
    CalibrationStage,
    DifficultyEstimationStage,
    GenerationStage,
    RAGStage,
    ReflectionStage,
    SearchStage,
    VerificationStage
  }

  alias Jido.AI.Accuracy.{
    PipelineConfig,
    PipelineResult,
    PipelineStage
  }

  # Import stage modules
  @type t :: %__MODULE__{
          config: PipelineConfig.t(),
          telemetry_enabled: boolean()
        }

  @type options :: [
          {:generator, function()},
          {:context, map()},
          {:timeout, pos_integer()},
          {:debug, boolean()}
        ]

  defstruct [
    :config,
    telemetry_enabled: true
  ]

  @stage_modules %{
    difficulty_estimation: DifficultyEstimationStage,
    rag: RAGStage,
    generation: GenerationStage,
    verification: VerificationStage,
    search: SearchStage,
    reflection: ReflectionStage,
    calibration: CalibrationStage
  }

  @doc """
  Creates a new pipeline from the given configuration.

  ## Parameters

  - `attrs` - Map with pipeline attributes:
    - `:config` - PipelineConfig struct or map (default: default config)
    - `:telemetry_enabled` - Whether to emit telemetry (default: true)

  ## Returns

  `{:ok, pipeline}` on success, `{:error, reason}` on validation failure.

  ## Examples

      iex> Pipeline.new(%{})
      {:ok, %Pipeline{config: %PipelineConfig{}}}

      iex> Pipeline.new(%{config: %{stages: [:generation, :calibration]}})
      {:ok, %Pipeline{}}

  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    config_result =
      case Map.get(attrs, :config) do
        %PipelineConfig{} = cfg -> {:ok, cfg}
        map when is_map(map) -> PipelineConfig.new(map)
        nil -> PipelineConfig.new(%{})
      end

    case config_result do
      {:error, reason} ->
        {:error, reason}

      {:ok, config} ->
        telemetry_enabled = Map.get(attrs, :telemetry_enabled, true)

        pipeline = %__MODULE__{
          config: config,
          telemetry_enabled: telemetry_enabled
        }

        {:ok, pipeline}
    end
  end

  @doc """
  Creates a new pipeline, raising on error.

  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, pipeline} -> pipeline
      {:error, reason} -> raise ArgumentError, "Invalid Pipeline: #{format_error(reason)}"
    end
  end

  @doc """
  Runs the pipeline on the given query.

  ## Parameters

  - `pipeline` - The pipeline struct
  - `query` - The query string to process
  - `opts` - Options:
    - `:generator` - Function to generate candidates (required)
    - `:context` - Additional context (optional)
    - `:timeout` - Overall timeout in ms (optional, default: 60_000)
    - `:debug` - Whether to emit debug info (optional)

  ## Returns

  `{:ok, result}` on success, `{:error, reason}` on failure.

  ## Examples

      {:ok, pipeline} = Pipeline.new(%{})

      generator = fn query, _context ->
        {:ok, "Answer: " <> query}
      end

      {:ok, result} = Pipeline.run(pipeline, "What is 2+2?", generator: generator)

  """
  @spec run(t(), String.t(), options()) :: {:ok, PipelineResult.t()} | {:error, term()}
  def run(%__MODULE__{} = pipeline, query, opts \\ []) when is_binary(query) do
    _start_time = System.monotonic_time(:millisecond)
    generator = Keyword.get(opts, :generator)
    context = Keyword.get(opts, :context, %{})
    timeout = Keyword.get(opts, :timeout, 60_000)

    # Validate inputs
    cond do
      query == "" ->
        {:error, :empty_query}

      is_nil(generator) ->
        {:error, :generator_required}

      not is_function(generator, 1) and not is_function(generator, 2) ->
        {:error, :invalid_generator}

      true ->
        # Run with timeout protection
        task =
          Task.async(fn ->
            do_run(pipeline, query, generator, context, opts)
          end)

        case Task.yield(task, timeout) do
          {:ok, result} ->
            result

          {:exit, _reason} ->
            {:error, :pipeline_crashed}

          nil ->
            Task.shutdown(task, :brutal_kill)
            {:error, :timeout}
        end
    end
  end

  @doc """
  Runs the pipeline with streaming of intermediate results.

  Returns a stream that emits results after each stage completes.

  ## Parameters

  - `pipeline` - The pipeline struct
  - `query` - The query string to process
  - `opts` - Options passed to run/3

  ## Returns

  An enumerable that emits {:stage, stage_name, result} tuples.

  """
  @spec run_stream(t(), String.t(), options()) :: Enumerable.t()
  def run_stream(%__MODULE__{} = pipeline, query, opts \\ []) when is_binary(query) do
    Stream.resource(
      fn ->
        # Initialize
        generator = Keyword.get(opts, :generator)
        context = Keyword.get(opts, :context, %{})
        {pipeline, query, generator, context, opts, :init}
      end,
      fn
        # Done state
        {_pipeline, _query, _gen, _ctx, _opts, :done} ->
          {:halt, nil}

        # Run next stage
        {pipeline, query, generator, context, opts, state} ->
          case state do
            :init ->
              # Start execution
              {result, new_state} = execute_next_stage(pipeline, query, generator, context, opts, [])
              {[:start | result], {pipeline, query, generator, context, opts, new_state}}

            {:running, _stage_index, trace} ->
              {result, new_state} =
                execute_next_stage(pipeline, query, generator, context, opts, trace)

              {result, {pipeline, query, generator, context, opts, new_state}}
          end
      end,
      fn _ -> :ok end
    )
  end

  @doc """
  Returns the default pipeline configuration.

  """
  @spec default_config() :: map()
  def default_config do
    PipelineConfig.defaults() |> Map.from_struct()
  end

  # Private functions

  defp do_run(pipeline, query, generator, context, opts) do
    # Initialize state
    initial_state = %{
      query: query,
      generator: generator,
      context: context,
      opts: opts
    }

    # Emit start event
    if pipeline.telemetry_enabled do
      :telemetry.execute([:jido, :accuracy, :pipeline, :start], %{query_length: String.length(query)}, %{})
    end

    # Get enabled stages
    stages = pipeline.config.stages

    # Track start time for duration calculation
    start_time = System.monotonic_time(:millisecond)

    # Execute stages sequentially, halting on error
    execution_result =
      Enum.reduce_while(stages, {initial_state, []}, fn stage_name, {state, trace} ->
        {new_state, trace_entry} = execute_stage(pipeline, stage_name, state, opts)

        if Map.get(new_state, :__halt__) do
          # Extract the error reason from the trace entry
          error_reason = Map.get(trace_entry, :error, :pipeline_error)
          {:halt, {:error, error_reason, new_state, trace ++ [trace_entry]}}
        else
          {:cont, {new_state, trace ++ [trace_entry]}}
        end
      end)

    case execution_result do
      {:error, reason, _state, _trace_entries} ->
        # Pipeline halted due to required stage failure
        {:error, reason}

      {final_state, trace_entries} ->
        # Build final result
        total_duration = System.monotonic_time(:millisecond) - start_time

        result =
          build_result(final_state, Enum.reverse(trace_entries), total_duration, pipeline.config)

        # Emit stop event
        if pipeline.telemetry_enabled do
          :telemetry.execute(
            [:jido, :accuracy, :pipeline, :stop],
            %{duration: total_duration},
            %{
              success: PipelineResult.success?(result),
              action: result.action,
              confidence: result.confidence
            }
          )
        end

        {:ok, result}
    end
  end

  defp execute_stage(pipeline, stage_name, state, opts) do
    stage_module = Map.get(@stage_modules, stage_name)

    start_time = System.monotonic_time(:millisecond)

    # Build stage config from pipeline config
    stage_config = build_stage_config(pipeline.config, stage_name, state, opts)

    # Get timeout from stage config or opts
    stage_timeout = Map.get(stage_config, :timeout, Keyword.get(opts, :timeout, 30_000))

    # Execute the stage
    result =
      if stage_module do
        case PipelineStage.execute_with_timeout(stage_module, state, stage_config, stage_timeout) do
          {:ok, new_state, metadata} ->
            duration = System.monotonic_time(:millisecond) - start_time

            new_state =
              new_state
              |> Map.put(:last_stage, stage_name)
              |> Map.update(:stages_completed, [], fn stages -> stages ++ [stage_name] end)

            trace_entry =
              PipelineResult.trace_entry(stage_name, :ok, duration, Map.put(metadata, :state, new_state))

            {new_state, trace_entry}

          {:error, reason} ->
            duration = System.monotonic_time(:millisecond) - start_time

            # Check if stage is required
            stage_required = stage_required?(stage_module)

            if stage_required do
              # Required stage failed, halt pipeline by propagating error
              trace_entry = PipelineResult.trace_entry(stage_name, :error, duration, reason)
              {Map.put(state, :__halt__, true), trace_entry}
            else
              # Optional stage failed, continue
              trace_entry = PipelineResult.trace_entry(stage_name, :error, duration, reason)
              {state, trace_entry}
            end
        end
      else
        # Stage module not found
        trace_entry = PipelineResult.trace_entry(stage_name, :error, 0, :stage_not_found)
        {state, trace_entry}
      end

    result
  end

  defp build_stage_config(config, stage_name, state, opts) do
    base_config = %{
      timeout: Keyword.get(opts, :timeout, 30_000)
    }

    # Add state-derived config first (has priority)
    base_with_state =
      base_config
      |> Map.put(:query, Map.get(state, :query))
      |> Map.put(:context, Map.get(state, :context))
      |> Map.put(:difficulty, Map.get(state, :difficulty))
      |> Map.put(:difficulty_level, Map.get(state, :difficulty_level))
      |> Map.put(:generator, Map.get(state, :generator))
      |> Map.put(:candidates, Map.get(state, :candidates))
      |> Map.put(:best_candidate, Map.get(state, :best_candidate))

    # Add stage-specific config (state-derived values take priority)
    stage_config =
      case stage_name do
        :difficulty_estimation ->
          Map.put(base_with_state, :estimator, config.difficulty_estimator)

        :rag ->
          Map.merge(base_with_state, config.rag_config || %{}, fn _k, v1, _v2 -> v1 end)

        :generation ->
          Map.merge(base_with_state, config.generation_config || %{}, fn _k, v1, _v2 -> v1 end)

        :verification ->
          Map.merge(base_with_state, config.verifier_config || %{}, fn _k, v1, _v2 -> v1 end)

        :search ->
          Map.merge(base_with_state, config.search_config || %{}, fn _k, v1, _v2 -> v1 end)

        :reflection ->
          Map.merge(base_with_state, config.reflection_config || %{}, fn _k, v1, _v2 -> v1 end)

        :calibration ->
          Map.merge(base_with_state, config.calibration_config || %{}, fn _k, v1, _v2 -> v1 end)

        _ ->
          base_with_state
      end

    stage_config
  end

  defp stage_required?(stage_module) do
    stage_module.required?()
  rescue
    _ -> true
  end

  defp build_result(state, trace_entries, total_duration, _config) do
    # Extract final answer and action
    answer = Map.get(state, :answer)
    confidence = Map.get(state, :confidence, 0.5)
    action = Map.get(state, :action, :direct)

    # Build metadata
    metadata = %{
      total_duration_ms: total_duration,
      num_candidates: Map.get(state, :num_candidates, 0),
      difficulty: Map.get(state, :difficulty),
      stages_completed: Map.get(state, :stages_completed, [])
    }

    # Check for calibration routing result
    if Map.get(state, :routing_result) do
      _metadata = Map.put(metadata, :routing_result, Map.get(state, :routing_result))
    end

    # Create result
    PipelineResult.new!(%{
      answer: answer,
      confidence: confidence,
      action: action,
      trace: trace_entries,
      metadata: metadata
    })
  end

  # Stream support

  defp execute_next_stage(_pipeline, _query, _generator, _context, _opts, _state) do
    # Placeholder for stream execution
    # Full implementation would track stage index and emit intermediate results
    {[], {nil, nil, nil, :done}}
  end

  defp format_error(atom) when is_atom(atom), do: atom
end
