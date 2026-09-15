defmodule Jido.AI.Runtime.ToolAttempt do
  @moduledoc false
  use Jido.Action, name: "ai_tool_attempt"

  @impl Jido.Action
  def run(call, context) do
    remaining = call.deadline - System.monotonic_time(:millisecond)

    if remaining > 0 do
      context =
        context
        |> Map.merge(call.runtime_identity)
        |> Map.put(:agent_state, call.agent_state)
        |> Map.put(:state, call.agent_state)

      tool_context = forward_context(context, call.tool.forward_context)

      tool_context = Map.merge(tool_context, Map.take(context, [:jido_ai_quota]))

      result =
        Jido.AI.Tools.Executor.execute_target(
          call.tool.target,
          call.arguments,
          tool_context,
          [timeout: min(remaining, call.tool.timeout)],
          call
        )

      with :ok <-
             Jido.AI.Control.check(
               call.profile,
               :operation,
               Map.put(call, :result, result),
               context,
               call.deadline
             ) do
        delay = Map.get(call.tool, :retry_backoff, 0)

        if Jido.AI.Error.retryable?(result) and elem(result, 2) == [] and
             call.attempt <= Map.get(call.tool, :max_retries, 0) and
             System.monotonic_time(:millisecond) + delay < call.deadline do
          Process.sleep(delay)
          {:continue, %{call | attempt: call.attempt + 1}, __MODULE__}
        else
          duration = System.monotonic_time(:millisecond) - call.started_at

          if call.interceptor,
            do: {:ok, %{call: call, raw: result, attempts: call.attempt, duration: duration}},
            else: Jido.AI.Runtime.ToolInterception.finish(call, result, call.attempt, duration, context)
        end
      end
    else
      Jido.AI.Profile.error("controls", "AI request deadline reached")
    end
  end

  defp forward_context(context, :all), do: context
  defp forward_context(_context, :none), do: %{}
  defp forward_context(context, :public), do: Jido.AI.ToolContext.runtime(context)

  defp forward_context(context, {:only, fields}),
    do: context |> Jido.AI.ToolContext.runtime() |> Map.take(fields)

  defp forward_context(context, {:except, fields}),
    do: context |> Jido.AI.ToolContext.runtime() |> Map.drop(fields)

  defp forward_context(context, fields) when is_list(fields), do: Map.take(context, fields)
end
