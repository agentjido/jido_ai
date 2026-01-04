defmodule Jido.AI.Algorithms.Sequential do
  @moduledoc """
  Executes multiple algorithms in sequence, passing output to the next input.

  The Sequential algorithm is a composition pattern that chains multiple
  algorithms together, where each algorithm's output becomes the next
  algorithm's input. Execution halts on the first error.

  ## Usage

  The algorithms to execute are specified in the context:

      algorithms = [FirstAlgorithm, SecondAlgorithm, ThirdAlgorithm]
      context = %{algorithms: algorithms}

      {:ok, result} = Sequential.execute(%{initial: "data"}, context)

  ## Execution Flow

  1. The initial input is passed to the first algorithm
  2. Each algorithm's result becomes the next algorithm's input
  3. The final algorithm's result is returned
  4. If any algorithm returns an error, execution halts immediately

  ## Context Options

    * `:algorithms` - (required) List of algorithm modules to execute in order
    * `:step_timeout` - (optional) Timeout for each step in milliseconds

  ## Step Tracking

  The context passed to each algorithm includes step information:

    * `:step_index` - Current step index (0-based)
    * `:step_name` - Name of the current algorithm (from metadata)
    * `:total_steps` - Total number of algorithms

  ## Telemetry

  The following telemetry events are emitted for each step:

    * `[:jido, :ai, :algorithm, :sequential, :step, :start]`
      - Measurements: `%{system_time: integer}`
      - Metadata: `%{step_index: integer, step_name: string, algorithm: module}`

    * `[:jido, :ai, :algorithm, :sequential, :step, :stop]`
      - Measurements: `%{duration: integer}` (native time units)
      - Metadata: `%{step_index: integer, step_name: string, algorithm: module}`

    * `[:jido, :ai, :algorithm, :sequential, :step, :exception]`
      - Measurements: `%{duration: integer}` (native time units)
      - Metadata: `%{step_index: integer, step_name: string, algorithm: module, error: term}`

  ## Error Handling

  When an algorithm returns an error, the sequential execution halts and
  returns an error tuple with step information:

      {:error, %{
        reason: :original_error,
        step_index: 1,
        step_name: "algorithm_name",
        algorithm: FailingAlgorithm
      }}

  ## Example

      defmodule MyPipeline do
        alias Jido.AI.Algorithms.Sequential

        def run(input) do
          algorithms = [
            MyApp.Algorithms.Validate,
            MyApp.Algorithms.Transform,
            MyApp.Algorithms.Persist
          ]

          Sequential.execute(input, %{algorithms: algorithms})
        end
      end
  """

  use Jido.AI.Algorithms.Base,
    name: "sequential",
    description: "Executes algorithms in sequence, chaining outputs to inputs"

  require Logger

  # ============================================================================
  # Algorithm Implementation
  # ============================================================================

  @impl true
  def execute(input, context) do
    algorithms = Map.get(context, :algorithms, [])
    total_steps = length(algorithms)

    case algorithms do
      [] ->
        {:ok, input}

      _ ->
        execute_steps(algorithms, input, context, total_steps)
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
  # Private Functions
  # ============================================================================

  defp execute_steps(algorithms, input, context, total_steps) do
    algorithms
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, input}, fn {algorithm, index}, {:ok, current_input} ->
      step_name = get_step_name(algorithm)

      step_context =
        context
        |> Map.put(:step_index, index)
        |> Map.put(:step_name, step_name)
        |> Map.put(:total_steps, total_steps)

      case execute_step(algorithm, current_input, step_context) do
        {:ok, result} ->
          {:cont, {:ok, result}}

        {:error, reason} ->
          error = %{
            reason: reason,
            step_index: index,
            step_name: step_name,
            algorithm: algorithm
          }

          {:halt, {:error, error}}
      end
    end)
  end

  defp execute_step(algorithm, input, context) do
    step_index = context.step_index
    step_name = context.step_name
    start_time = System.monotonic_time()

    emit_step_start(step_index, step_name, algorithm)

    try do
      case algorithm.execute(input, context) do
        {:ok, _result} = success ->
          duration = System.monotonic_time() - start_time
          emit_step_stop(step_index, step_name, algorithm, duration)
          success

        {:error, reason} = error ->
          duration = System.monotonic_time() - start_time
          emit_step_exception(step_index, step_name, algorithm, duration, reason)
          error
      end
    rescue
      e ->
        duration = System.monotonic_time() - start_time
        emit_step_exception(step_index, step_name, algorithm, duration, e)
        {:error, e}
    end
  end

  defp get_step_name(algorithm) do
    if function_exported?(algorithm, :metadata, 0) do
      metadata = algorithm.metadata()
      Map.get(metadata, :name, inspect(algorithm))
    else
      inspect(algorithm)
    end
  end

  # ============================================================================
  # Telemetry
  # ============================================================================

  defp emit_step_start(step_index, step_name, algorithm) do
    :telemetry.execute(
      [:jido, :ai, :algorithm, :sequential, :step, :start],
      %{system_time: System.system_time()},
      %{step_index: step_index, step_name: step_name, algorithm: algorithm}
    )
  end

  defp emit_step_stop(step_index, step_name, algorithm, duration) do
    :telemetry.execute(
      [:jido, :ai, :algorithm, :sequential, :step, :stop],
      %{duration: duration},
      %{step_index: step_index, step_name: step_name, algorithm: algorithm}
    )
  end

  defp emit_step_exception(step_index, step_name, algorithm, duration, error) do
    :telemetry.execute(
      [:jido, :ai, :algorithm, :sequential, :step, :exception],
      %{duration: duration},
      %{step_index: step_index, step_name: step_name, algorithm: algorithm, error: error}
    )
  end
end
