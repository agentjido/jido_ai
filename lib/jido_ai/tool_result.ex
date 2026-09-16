defmodule Jido.AI.ToolResult do
  @moduledoc false
  alias Jido.AI.Error
  alias Jido.AI.Observe
  alias Jido.AI.Reasoning.ReAct.PendingToolCall
  require Logger

  def normalize({:ok, output}, call), do: normalize({:ok, output, []}, call)
  def normalize({:error, reason}, call), do: normalize({:error, reason, []}, call)

  def normalize({:ok, %Jido.Action.Output{kind: kind, value: value}, effects}, _call)
      when kind in [:raw, :batch], do: {:ok, value, List.wrap(effects)}

  def normalize({:ok, %Jido.Action.Output{kind: kind}, effects}, call),
    do:
      normalize(
        {:error, {:unsupported_tool_output, "Tool output kind #{kind} needs an explicit consumer"}, effects},
        call
      )

  def normalize({:ok, output, effects}, _call), do: {:ok, output, List.wrap(effects)}

  def normalize({:error, reason, effects}, call) do
    log_exception(reason, call)

    {:error,
     Error.normalize(tool_cause(reason), :execution_error, "Tool execution failed", %{
       tool_name: call.name,
       tool_call_id: call.id
     }), List.wrap(effects)}
  end

  def normalize(other, call),
    do:
      normalize(
        {:error, Error.error_envelope(:invalid_result, "Invalid tool result", %{result: inspect(other)})},
        call
      )

  def content(result), do: Jido.AI.Model.Content.format_tool_result_content(result)

  # Core wraps a returned non-exception Action error in these two fields.
  # Recover typed error maps at the tool boundary. Keep execution failures with
  # additional runtime evidence, and keep all exception structs unchanged.
  defp tool_cause(%Jido.Action.Error.ExecutionFailureError{details: %{reason: reason, retry: _} = details} = error)
       when map_size(details) == 2 and is_map(reason) and not is_struct(reason) do
    typed? =
      (Map.has_key?(reason, :message) and
         (Map.has_key?(reason, :type) or Map.has_key?(reason, :code))) or
        (Map.has_key?(reason, "message") and
           (Map.has_key?(reason, "type") or Map.has_key?(reason, "code")))

    if typed?, do: reason, else: Error.cause(error)
  end

  defp tool_cause(reason), do: Error.cause(reason)

  # Core Exec catches Action exceptions before they reach the AI caller. Keep
  # the server log while the public error adapter removes the stacktrace.
  defp log_exception(%Jido.Action.Error.ExecutionFailureError{details: %{exception: exception}} = error, call) do
    Logger.error("Tool execution exception (#{inspect(exception)})",
      tool_name: call.name,
      tool_call_id: call.id,
      exception_message: error.message,
      stacktrace: error.stacktrace
    )
  end

  defp log_exception(_reason, _call), do: :ok

  def completed(call, result, attempts, duration_ms) do
    {status, value, effects} = result
    inspection_effects = Enum.map(effects, &inspect_effect(&1, call.agent_state))

    call
    |> Map.put(:action_module, if(is_atom(call.tool.target), do: call.tool.target))
    |> PendingToolCall.from_tool_call()
    |> PendingToolCall.complete({status, value, inspection_effects}, attempts, duration_ms)
    |> Map.from_struct()
    |> Map.put(:position, call.position)
    |> then(fn completed ->
      if effects == inspection_effects,
        do: completed,
        else: Map.put(completed, :effects_storage, :inspection)
    end)
  end

  # A completed record is inspection data. Do not embed the previous request
  # records again inside a complete state proposal on every subsequent request.
  defp inspect_effect(%Jido.AI.Effects.State{state: proposed}, base)
       when is_map(proposed) and not is_struct(proposed) do
    changed =
      Enum.filter(
        Enum.uniq(Map.keys(base) ++ Map.keys(proposed)),
        &(Map.fetch(base, &1) != Map.fetch(proposed, &1))
      )

    %{
      type: :state,
      values: Map.take(proposed, changed),
      deleted_keys: Enum.reject(changed, &Map.has_key?(proposed, &1))
    }
  end

  defp inspect_effect(effect, _base), do: effect

  def record(meta, completed) do
    completed = portable(completed)
    tools = Enum.reject(Map.get(meta, :tool_results, []), &(&1.id == completed.id))
    Map.put(meta, :tool_results, Enum.sort_by(tools ++ [completed], & &1.position))
  end

  defp portable(completed) do
    case Jido.Action.validate_static_data(completed) do
      :ok ->
        completed

      _ ->
        {status, value, effects} = completed.result

        value =
          portable_value(value, fn value ->
            if status == :error,
              do: Error.for_storage(value),
              else: Observe.sanitize_transport_payload(value)
          end)

        effects = portable_value(effects, &Observe.sanitize_transport_payload/1)

        %{completed | result: {status, value, effects}}
        |> Map.put(:result_storage, :transport)
    end
  end

  defp portable_value(value, convert) do
    case Jido.Action.validate_static_data(value) do
      :ok -> value
      _ -> convert.(value)
    end
  end
end
