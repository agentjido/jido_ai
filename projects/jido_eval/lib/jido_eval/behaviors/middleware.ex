defmodule Jido.Eval.Middleware do
  @moduledoc """
  Behavior for middleware wrapping metric execution.

  Middleware components wrap around metric evaluation to provide cross-cutting
  concerns like tracing, timing, error handling, or context management.

  ## Callbacks

  - `c:call/3` - Wrap metric execution (required)

  ## Examples

      defmodule TracingMiddleware do
        @behaviour Jido.Eval.Middleware
        
        def call(metric_fn, context, opts) do
          trace_id = generate_trace_id()
          start_time = System.monotonic_time()
          
          try do
            result = metric_fn.()
            duration = System.monotonic_time() - start_time
            log_trace(trace_id, :success, duration)
            result
          rescue
            error ->
              duration = System.monotonic_time() - start_time
              log_trace(trace_id, :error, duration)
              reraise error, __STACKTRACE__
          end
        end
        
        defp generate_trace_id, do: System.unique_integer([:positive])
        defp log_trace(id, status, duration), do: :ok
      end
  """

  @doc """
  Wrap metric execution with middleware logic.

  Called to wrap around metric evaluation with additional behavior.

  ## Parameters

  - `metric_fn` - Function to execute the metric
  - `context` - Execution context data
  - `opts` - Middleware configuration options

  ## Returns

  - The result of calling `metric_fn.()`
  - May raise exceptions or return errors based on implementation
  """
  @callback call(metric_fn :: (-> any()), context :: any(), opts :: keyword()) ::
              any()
end
