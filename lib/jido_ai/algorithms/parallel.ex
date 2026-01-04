defmodule Jido.AI.Algorithms.Parallel do
  @moduledoc """
  Executes multiple algorithms concurrently and merges their results.

  The Parallel algorithm runs all specified algorithms at the same time,
  collecting their results and combining them according to the configured
  merge strategy.

  ## Usage

  The algorithms to execute are specified in the context:

      algorithms = [AlgorithmA, AlgorithmB, AlgorithmC]
      context = %{algorithms: algorithms}

      {:ok, result} = Parallel.execute(%{data: "input"}, context)

  ## Execution Flow

  1. All algorithms receive the same input
  2. Algorithms execute concurrently up to max_concurrency limit
  3. Results are collected and merged according to merge_strategy
  4. Errors are handled according to error_mode

  ## Context Options

    * `:algorithms` - (required) List of algorithm modules to execute
    * `:merge_strategy` - How to merge results (default: `:merge_maps`)
      - `:merge_maps` - Deep merge all result maps
      - `:collect` - Return list of results
      - `fun/1` - Custom function receiving list of results
    * `:error_mode` - How to handle errors (default: `:fail_fast`)
      - `:fail_fast` - Return first error encountered
      - `:collect_errors` - Return all errors as a list
      - `:ignore_errors` - Return only successful results
    * `:max_concurrency` - Max parallel tasks (default: System.schedulers_online * 2)
    * `:timeout` - Timeout per task in ms (default: 5000)

  ## Merge Strategies

  ### `:merge_maps` (default)

  Deep merges all result maps into a single map. Later results override
  earlier ones for conflicting keys.

      # Results: [%{a: 1}, %{b: 2}, %{a: 3}]
      # Merged:  %{a: 3, b: 2}

  ### `:collect`

  Returns all results as a list, preserving order.

      # Results: [%{a: 1}, %{b: 2}]
      # Merged:  [%{a: 1}, %{b: 2}]

  ### Custom function

  Provide a function that receives the list of results:

      context = %{
        algorithms: algorithms,
        merge_strategy: fn results ->
          %{combined: Enum.map(results, & &1.value)}
        end
      }

  ## Error Handling Modes

  ### `:fail_fast` (default)

  Returns the first error encountered. Note that due to concurrent execution,
  which error is "first" may vary between runs.

  ### `:collect_errors`

  Collects all errors and returns them as a list:

      {:error, %{errors: [error1, error2], successful: [result1]}}

  ### `:ignore_errors`

  Ignores errors and returns only successful results:

      {:ok, merged_successful_results}

  If all algorithms fail, returns an error.

  ## Telemetry

  The following telemetry events are emitted:

    * `[:jido, :ai, :algorithm, :parallel, :start]`
      - Measurements: `%{system_time: integer, algorithm_count: integer}`
      - Metadata: `%{algorithms: list}`

    * `[:jido, :ai, :algorithm, :parallel, :stop]`
      - Measurements: `%{duration: integer}`
      - Metadata: `%{success_count: integer, error_count: integer}`

    * `[:jido, :ai, :algorithm, :parallel, :task, :stop]`
      - Measurements: `%{duration: integer}`
      - Metadata: `%{algorithm: module, status: :ok | :error}`

  ## Example

      defmodule MyPipeline do
        alias Jido.AI.Algorithms.Parallel

        def run(input) do
          context = %{
            algorithms: [
              MyApp.Algorithms.FetchUserData,
              MyApp.Algorithms.FetchSettings,
              MyApp.Algorithms.FetchPreferences
            ],
            merge_strategy: :merge_maps,
            error_mode: :ignore_errors,
            max_concurrency: 4,
            timeout: 10_000
          }

          Parallel.execute(input, context)
        end
      end

  ## Security Considerations

  The `:merge_strategy` option can accept a custom function. This function
  is executed without sandboxing.

  **WARNING**: Never pass functions from untrusted sources (e.g., deserialized
  data, user input). Custom merge functions should only come from compile-time
  definitions or trusted runtime sources.
  """

  use Jido.AI.Algorithms.Base,
    name: "parallel",
    description: "Executes algorithms concurrently and merges results"

  alias Jido.AI.Algorithms.Helpers

  # Evaluated at compile time for performance. This means the value is fixed
  # based on the build machine's scheduler count. For most deployments this
  # is acceptable as it provides a sensible default.
  @default_max_concurrency System.schedulers_online() * 2

  # Default timeout of 5 seconds per task. For LLM operations, you may need
  # to increase this via the :timeout context option.
  @default_timeout 5_000

  # ============================================================================
  # Algorithm Implementation
  # ============================================================================

  @impl true
  def execute(input, context) do
    algorithms = Map.get(context, :algorithms, [])
    merge_strategy = Map.get(context, :merge_strategy, :merge_maps)
    error_mode = Map.get(context, :error_mode, :fail_fast)
    max_concurrency = Map.get(context, :max_concurrency, @default_max_concurrency)
    timeout = Map.get(context, :timeout, @default_timeout)

    case algorithms do
      [] ->
        {:ok, input}

      _ ->
        emit_start(algorithms)
        start_time = System.monotonic_time()

        results = execute_parallel(algorithms, input, context, max_concurrency, timeout)

        duration = System.monotonic_time() - start_time
        do_handle_results(results, merge_strategy, error_mode, duration)
    end
  end

  @impl true
  def can_execute?(input, context) do
    algorithms = Map.get(context, :algorithms, [])

    case algorithms do
      [] ->
        true

      _ ->
        Enum.all?(algorithms, fn algo ->
          algo.can_execute?(input, context)
        end)
    end
  end

  # ============================================================================
  # Private Functions - Execution
  # ============================================================================

  defp execute_parallel(algorithms, input, context, max_concurrency, timeout) do
    algorithms
    |> Task.async_stream(
      fn algorithm ->
        execute_task(algorithm, input, context)
      end,
      max_concurrency: max_concurrency,
      timeout: timeout,
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, :timeout} -> {:error, :timeout}
      {:exit, reason} -> {:error, {:exit, reason}}
    end)
  end

  defp execute_task(algorithm, input, context) do
    start_time = System.monotonic_time()

    try do
      case algorithm.execute(input, context) do
        {:ok, _result} = success ->
          emit_task_stop(algorithm, start_time, :ok)
          success

        {:error, _reason} = error ->
          emit_task_stop(algorithm, start_time, :error)
          error
      end
    rescue
      e ->
        emit_task_stop(algorithm, start_time, :error)
        {:error, {:exception, e}}
    end
  end

  # ============================================================================
  # Private Functions - Result Handling
  # ============================================================================

  defp do_handle_results(results, merge_strategy, error_mode, duration) do
    {successes, errors} = Helpers.partition_results(results)

    success_count = length(successes)
    error_count = length(errors)

    emit_stop(duration, success_count, error_count)

    Helpers.handle_results(results, merge_strategy, error_mode)
  end

  # ============================================================================
  # Telemetry
  # ============================================================================

  defp emit_start(algorithms) do
    :telemetry.execute(
      [:jido, :ai, :algorithm, :parallel, :start],
      %{system_time: System.system_time(), algorithm_count: length(algorithms)},
      %{algorithms: algorithms}
    )
  end

  defp emit_stop(duration, success_count, error_count) do
    :telemetry.execute(
      [:jido, :ai, :algorithm, :parallel, :stop],
      %{duration: duration},
      %{success_count: success_count, error_count: error_count}
    )
  end

  defp emit_task_stop(algorithm, start_time, status) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:jido, :ai, :algorithm, :parallel, :task, :stop],
      %{duration: duration},
      %{algorithm: algorithm, status: status}
    )
  end
end
