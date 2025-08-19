defmodule Jido.Eval.Middleware.Tracing do
  @moduledoc """
  Tracing middleware for LLM evaluation metrics.

  Provides comprehensive tracing capabilities for metric execution including:
  - Unique trace ID generation for correlation
  - Start/stop timing measurements
  - Success/error classification
  - Context and options logging
  - Telemetry event emission

  ## Configuration Options

  - `:trace_level` - Log level for trace messages (default: `:debug`)
  - `:emit_telemetry` - Whether to emit telemetry events (default: `true`)
  - `:include_context` - Include context in trace logs (default: `false`)
  - `:include_result` - Include result data in trace logs (default: `false`)

  ## Examples

      # Basic tracing with defaults
      middleware: [Jido.Eval.Middleware.Tracing]

      # Custom tracing configuration
      middleware: [{Jido.Eval.Middleware.Tracing, [
        trace_level: :info,
        include_context: true,
        include_result: true
      ]}]
  """

  @behaviour Jido.Eval.Middleware

  require Logger

  @doc """
  Wrap metric execution with comprehensive tracing.

  Generates a unique trace ID, measures execution time, logs start/stop events,
  classifies success/error outcomes, and optionally emits telemetry events.

  This implementation matches the actual worker interface which calls middleware
  as `middleware.call(context, function)`.

  ## Parameters

  - `context` - Evaluation context containing sample, metric, and run data
  - `metric_fn` - Function to execute the metric evaluation

  ## Returns

  The result of executing `metric_fn.()`, preserving the original return value
  while adding tracing instrumentation around the execution.
  """
  # Implementation for the behavior interface (call/3)
  @spec call(metric_fn :: (-> any()), context :: any(), opts :: keyword()) :: any()
  def call(metric_fn, context, opts) when is_function(metric_fn) do
    do_call(context, metric_fn, opts)
  end

  # Implementation for the worker interface (call/2)
  @spec call(context :: any(), metric_fn :: (-> any())) :: any()
  def call(context, metric_fn) when is_function(metric_fn) do
    do_call(context, metric_fn, [])
  end

  # Shared implementation
  defp do_call(context, metric_fn, opts) do
    trace_id = generate_trace_id()
    # Use configuration from opts with sensible defaults
    trace_level = Keyword.get(opts, :trace_level, :debug)
    emit_telemetry = Keyword.get(opts, :emit_telemetry, true)
    include_context = Keyword.get(opts, :include_context, false)
    include_result = Keyword.get(opts, :include_result, false)

    start_time = System.monotonic_time()

    log_trace_start(trace_id, context, trace_level, include_context)

    if emit_telemetry do
      :telemetry.execute([:jido, :eval, :middleware, :trace, :start], %{}, %{
        trace_id: trace_id,
        context: context
      })
    end

    try do
      result = metric_fn.()
      duration = System.monotonic_time() - start_time

      log_trace_success(trace_id, result, duration, trace_level, include_result)

      if emit_telemetry do
        :telemetry.execute(
          [:jido, :eval, :middleware, :trace, :stop],
          %{
            duration: duration
          },
          %{
            trace_id: trace_id,
            status: :success,
            result: result
          }
        )
      end

      result
    rescue
      error ->
        duration = System.monotonic_time() - start_time

        log_trace_error(trace_id, error, duration, trace_level)

        if emit_telemetry do
          :telemetry.execute(
            [:jido, :eval, :middleware, :trace, :stop],
            %{
              duration: duration
            },
            %{
              trace_id: trace_id,
              status: :error,
              error: error
            }
          )
        end

        reraise error, __STACKTRACE__
    end
  end

  # Generate unique trace ID for correlation
  @spec generate_trace_id() :: String.t()
  defp generate_trace_id do
    Uniq.UUID.uuid7()
  end

  # Log trace start event
  @spec log_trace_start(String.t(), any(), atom(), boolean()) :: :ok
  defp log_trace_start(trace_id, context, level, include_context) do
    base_msg = "Metric trace started [#{trace_id}]"

    message =
      if include_context do
        context_info = format_context(context)
        "#{base_msg} - Context: #{context_info}"
      else
        base_msg
      end

    Logger.log(level, message)
  end

  # Log successful trace completion
  @spec log_trace_success(String.t(), any(), integer(), atom(), boolean()) :: :ok
  defp log_trace_success(trace_id, result, duration, level, include_result) do
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)
    base_msg = "Metric trace completed [#{trace_id}] in #{duration_ms}ms"

    message =
      if include_result do
        result_info = format_result(result)
        "#{base_msg} - Result: #{result_info}"
      else
        base_msg
      end

    Logger.log(level, message)
  end

  # Log error trace completion
  @spec log_trace_error(String.t(), Exception.t(), integer(), atom()) :: :ok
  defp log_trace_error(trace_id, error, duration, level) do
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)
    error_type = error.__struct__
    error_msg = Exception.message(error)

    message =
      "Metric trace failed [#{trace_id}] in #{duration_ms}ms - #{error_type}: #{error_msg}"

    Logger.log(level, message)
  end

  # Format context for logging
  @spec format_context(any()) :: String.t()
  defp format_context(%{metric: metric, sample: sample}) when is_map(sample) do
    sample_id = Map.get(sample, :id, "unknown")
    "metric=#{inspect(metric)}, sample_id=#{sample_id}"
  end

  defp format_context(%{metric: metric}) do
    "metric=#{inspect(metric)}"
  end

  defp format_context(context) when is_map(context) do
    keys = Map.keys(context) |> Enum.take(3) |> Enum.join(", ")
    "keys=[#{keys}]"
  end

  defp format_context(_context), do: "unknown"

  # Format result for logging
  @spec format_result(any()) :: String.t()
  defp format_result({:ok, value}) do
    "ok, #{format_value(value)}"
  end

  defp format_result({:error, reason}) do
    "error, #{inspect(reason)}"
  end

  defp format_result(value) do
    format_value(value)
  end

  # Format value for logging (truncate if too long)
  @spec format_value(any()) :: String.t()
  defp format_value(value) do
    inspected = inspect(value)

    if String.length(inspected) > 100 do
      String.slice(inspected, 0, 97) <> "..."
    else
      inspected
    end
  end
end
