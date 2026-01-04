defmodule Jido.AI.Algorithms.Hybrid do
  @moduledoc """
  Combines sequential and parallel execution in configurable stages.

  The Hybrid algorithm processes stages in order, where each stage can
  run its algorithms either sequentially or in parallel. This enables
  complex workflows that mix both execution patterns.

  ## Usage

  Stages are defined in the context:

      stages = [
        %{algorithms: [ValidateInput], mode: :sequential},
        %{algorithms: [FetchA, FetchB, FetchC], mode: :parallel},
        %{algorithms: [ProcessResults, SaveOutput], mode: :sequential}
      ]

      {:ok, result} = Hybrid.execute(%{data: "input"}, %{stages: stages})

  ## Execution Flow

  1. Stages are processed in order
  2. Each stage runs according to its mode (:sequential or :parallel)
  3. The output of each stage becomes the input to the next
  4. If any stage fails, execution halts (unless fallbacks are configured)

  ## Stage Definition

  Each stage is a map with:

    * `:algorithms` - (required) List of algorithm modules
    * `:mode` - (required) `:sequential` or `:parallel`

  For parallel stages, additional options:

    * `:merge_strategy` - How to merge results (default: `:merge_maps`)
    * `:error_mode` - Error handling (default: `:fail_fast`)
    * `:max_concurrency` - Max parallel tasks
    * `:timeout` - Per-task timeout

  ## Shorthand

  Single algorithm stages can use shorthand:

      stages = [
        ValidateInput,  # Equivalent to %{algorithms: [ValidateInput], mode: :sequential}
        %{algorithms: [FetchA, FetchB], mode: :parallel}
      ]

  ## Fallback Support

  Configure fallbacks for resilient execution:

      context = %{
        stages: [...],
        fallbacks: %{
          UnreliableAlgorithm => %{
            fallbacks: [Fallback1, Fallback2],
            timeout: 5000
          }
        }
      }

  When the primary algorithm fails or times out, fallbacks are tried in order.

  ## Telemetry

  The following telemetry events are emitted:

    * `[:jido, :ai, :algorithm, :hybrid, :start]`
      - Measurements: `%{system_time: integer, stage_count: integer}`

    * `[:jido, :ai, :algorithm, :hybrid, :stop]`
      - Measurements: `%{duration: integer}`
      - Metadata: `%{stages_completed: integer}`

    * `[:jido, :ai, :algorithm, :hybrid, :stage, :start]`
      - Measurements: `%{system_time: integer}`
      - Metadata: `%{stage_index: integer, mode: atom}`

    * `[:jido, :ai, :algorithm, :hybrid, :stage, :stop]`
      - Measurements: `%{duration: integer}`
      - Metadata: `%{stage_index: integer, mode: atom}`

  ## Example

      defmodule MyWorkflow do
        alias Jido.AI.Algorithms.Hybrid

        def run(input) do
          context = %{
            stages: [
              # Stage 1: Validate (sequential)
              %{algorithms: [ValidateSchema, NormalizeData], mode: :sequential},

              # Stage 2: Fetch from multiple sources (parallel)
              %{
                algorithms: [FetchFromAPI, FetchFromDB, FetchFromCache],
                mode: :parallel,
                merge_strategy: :merge_maps,
                error_mode: :ignore_errors
              },

              # Stage 3: Process and save (sequential)
              %{algorithms: [TransformData, SaveResults], mode: :sequential}
            ]
          }

          Hybrid.execute(input, context)
        end
      end
  """

  use Jido.AI.Algorithms.Base,
    name: "hybrid",
    description: "Combines sequential and parallel execution in stages"

  alias Jido.AI.Algorithms.Parallel

  # ============================================================================
  # Algorithm Implementation
  # ============================================================================

  @impl true
  def execute(input, context) do
    stages = Map.get(context, :stages, [])
    fallbacks = Map.get(context, :fallbacks, %{})

    case stages do
      [] ->
        {:ok, input}

      _ ->
        normalized_stages = normalize_stages(stages)
        emit_start(normalized_stages)
        start_time = System.monotonic_time()

        result = execute_stages(normalized_stages, input, context, fallbacks)

        duration = System.monotonic_time() - start_time
        emit_stop(duration, count_completed(result, normalized_stages))

        result
    end
  end

  @impl true
  def can_execute?(input, context) do
    stages = Map.get(context, :stages, [])

    case stages do
      [] ->
        true

      _ ->
        normalized_stages = normalize_stages(stages)

        Enum.all?(normalized_stages, fn stage ->
          Enum.all?(stage.algorithms, fn algo ->
            algo.can_execute?(input, context)
          end)
        end)
    end
  end

  # ============================================================================
  # Private Functions - Stage Processing
  # ============================================================================

  defp normalize_stages(stages) do
    Enum.map(stages, &normalize_stage/1)
  end

  defp normalize_stage(module) when is_atom(module) do
    %{algorithms: [module], mode: :sequential}
  end

  defp normalize_stage(%{algorithms: _, mode: _} = stage) do
    stage
  end

  defp normalize_stage(%{algorithms: algorithms}) do
    %{algorithms: algorithms, mode: :sequential}
  end

  defp execute_stages(stages, input, context, fallbacks) do
    stages
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, input}, fn {stage, index}, {:ok, current_input} ->
      emit_stage_start(index, stage.mode)
      start_time = System.monotonic_time()

      result = execute_stage(stage, current_input, context, fallbacks)

      duration = System.monotonic_time() - start_time
      emit_stage_stop(index, stage.mode, duration)

      case result do
        {:ok, output} ->
          {:cont, {:ok, output}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp execute_stage(%{algorithms: algorithms, mode: :sequential} = _stage, input, context, fallbacks) do
    execute_algorithms_sequential(algorithms, input, context, fallbacks)
  end

  defp execute_stage(%{algorithms: algorithms, mode: :parallel} = stage, input, context, _fallbacks) do
    stage_context =
      context
      |> Map.put(:algorithms, algorithms)
      |> maybe_put(:merge_strategy, stage[:merge_strategy])
      |> maybe_put(:error_mode, stage[:error_mode])
      |> maybe_put(:max_concurrency, stage[:max_concurrency])
      |> maybe_put(:timeout, stage[:timeout])

    # For parallel, we don't apply individual fallbacks - use error_mode instead
    Parallel.execute(input, stage_context)
  end

  defp execute_algorithms_sequential(algorithms, input, context, fallbacks) do
    algorithms
    |> Enum.reduce_while({:ok, input}, fn algorithm, {:ok, current_input} ->
      case execute_with_fallback(algorithm, current_input, context, fallbacks) do
        {:ok, result} -> {:cont, {:ok, result}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp execute_with_fallback(algorithm, input, context, fallbacks) do
    fallback_config = Map.get(fallbacks, algorithm)

    case algorithm.execute(input, context) do
      {:ok, result} ->
        {:ok, result}

      {:error, _reason} = error ->
        if fallback_config do
          try_fallbacks(fallback_config[:fallbacks] || [], input, context)
        else
          error
        end
    end
  end

  defp try_fallbacks([], _input, _context) do
    {:error, :all_fallbacks_failed}
  end

  defp try_fallbacks([fallback | rest], input, context) do
    case fallback.execute(input, context) do
      {:ok, result} -> {:ok, result}
      {:error, _reason} -> try_fallbacks(rest, input, context)
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # ============================================================================
  # Private Functions - Helpers
  # ============================================================================

  defp count_completed({:ok, _}, stages), do: length(stages)
  defp count_completed({:error, %{stage_index: index}}, _stages), do: index
  defp count_completed({:error, _}, _stages), do: 0

  # ============================================================================
  # Telemetry
  # ============================================================================

  defp emit_start(stages) do
    :telemetry.execute(
      [:jido, :ai, :algorithm, :hybrid, :start],
      %{system_time: System.system_time(), stage_count: length(stages)},
      %{}
    )
  end

  defp emit_stop(duration, stages_completed) do
    :telemetry.execute(
      [:jido, :ai, :algorithm, :hybrid, :stop],
      %{duration: duration},
      %{stages_completed: stages_completed}
    )
  end

  defp emit_stage_start(index, mode) do
    :telemetry.execute(
      [:jido, :ai, :algorithm, :hybrid, :stage, :start],
      %{system_time: System.system_time()},
      %{stage_index: index, mode: mode}
    )
  end

  defp emit_stage_stop(index, mode, duration) do
    :telemetry.execute(
      [:jido, :ai, :algorithm, :hybrid, :stage, :stop],
      %{duration: duration},
      %{stage_index: index, mode: mode}
    )
  end
end
