defmodule Jido.AI.Observe.Telemetry do
  @moduledoc false
  alias Jido.AI.Observe

  @events %{
    request_started: {:request, :start},
    request_completed: {:request, :complete},
    request_failed: {:request, :failed},
    request_cancelled: {:request, :cancelled},
    llm_started: {:llm, :start},
    llm_delta: {:llm, :delta},
    llm_completed: {:llm, :complete},
    output_started: {:output, :start},
    output_repair: {:output, :repair},
    output_validated: {:output, :validated},
    output_failed: {:output, :error},
    tool_started: {:tool, :start},
    tool_completed: {:tool, :complete}
  }

  def emit(event, config, agent_id, model \\ nil) do
    case @events[event.kind] do
      nil ->
        :ok

      {family, phase} ->
        data = event.data
        usage = data[:usage] || %{}

        metadata =
          Map.take(event, [
            :request_id,
            :run_id,
            :iteration,
            :llm_call_id,
            :tool_call_id,
            :tool_name
          ])
          |> Map.merge(Map.take(data, [:reasoning_phase, :phase_call_id, :selected_method]))
          |> Map.merge(%{
            agent_id: agent_id,
            model: data[:model] || model,
            origin: Map.get(event, :origin, :worker_runtime),
            strategy: Jido.AI.Reasoning.Linear.label(Map.get(event, :method, :react)),
            operation: operation(family),
            termination_reason: termination(event.kind, data),
            error_type: error_type(event.kind, data),
            attempt: data[:attempt]
          })

        measurements = %{
          duration_ms: data[:duration_ms] || 0,
          input_tokens: usage[:input_tokens] || 0,
          output_tokens: usage[:output_tokens] || 0,
          total_tokens: usage[:total_tokens] || 0,
          retry_count: max((data[:attempts] || 1) - 1, 0),
          queue_ms: 0
        }

        options = if event.kind == :llm_delta, do: [feature_gate: :llm_deltas], else: []
        Observe.emit(config, [:jido, :ai, family, phase], measurements, metadata, options)
    end
  end

  defp error_type(:output_failed, _), do: :output_validation
  defp error_type(:request_failed, data), do: data[:error_type] || known_error_type(data[:error])
  defp error_type(_, _), do: nil
  defp known_error_type({:error, error, _}), do: known_error_type(error)

  defp known_error_type({:failed, _, %{diagnostics: %{cause: cause}}}),
    do: known_error_type(cause)

  defp known_error_type(%{type: type}) when is_atom(type), do: type
  defp known_error_type(%{code: code}) when is_atom(code), do: code
  defp known_error_type(_), do: nil

  defp operation(:output), do: :structured_output
  defp operation(:tool), do: :tool_execute
  defp operation(_), do: :generate_text
  defp termination(:output_validated, _), do: :complete
  defp termination(:output_failed, _), do: :error
  defp termination(:request_failed, _), do: :error
  defp termination(:request_cancelled, _), do: :cancelled
  defp termination(_, data), do: data[:termination_reason]
end
