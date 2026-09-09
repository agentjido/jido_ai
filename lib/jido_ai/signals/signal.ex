defmodule Jido.AI.Signal do
  @moduledoc """
  Projects canonical request events into typed AI Signals.

  The projection is pure. Return `emit/1` Directives from an Agent Action or
  Flow to use core outbound preparation and post-commit delivery. This does
  not start a subscription, store events, or retry delivery.
  """

  alias Jido.AI.Runtime.Event
  alias Jido.AI.Signal

  @doc "Builds zero or more typed Signals from one canonical request event."
  def from_event(event, opts \\ [])

  def from_event(%Event{} = event, opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      time = event.at_ms |> DateTime.from_unix!(:millisecond) |> DateTime.to_iso8601()
      opts = Keyword.put_new(opts, :time, time)

      Enum.reduce_while(payloads(event), {:ok, []}, fn {module, data}, {:ok, signals} ->
        case module.new(data, opts) do
          {:ok, signal} -> {:cont, {:ok, [signal | signals]}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, signals} -> {:ok, Enum.reverse(signals)}
        error -> error
      end
    else
      {:error, :invalid_signal_options}
    end
  end

  def from_event(_, _), do: {:error, :invalid_runtime_event}

  @doc "Builds core Emit Directives; core selects the Agent's configured dispatch."
  def emit(event) do
    with {:ok, signals} <- from_event(event),
         do: {:ok, Enum.map(signals, &%Jido.Agent.Directive.Emit{signal: &1})}
  end

  defp payloads(%{kind: :llm_delta} = event) do
    data =
      Map.take(event, [:seq, :run_id, :request_id, :iteration])
      |> Map.merge(%{
        call_id: event.llm_call_id || "",
        delta: Map.get(event.data, :delta, ""),
        chunk_type: Map.get(event.data, :chunk_type, :content),
        metadata: metadata(event, :generate_text)
      })

    [{Signal.LLMDelta, data}]
  end

  defp payloads(%{kind: :llm_completed, data: data} = event) do
    turn =
      data
      |> Map.put(:type, Map.get(data, :turn_type, :final_answer))
      |> Jido.AI.Turn.from_result_map()

    response =
      {Signal.LLMResponse,
       %{
         call_id: event.llm_call_id || data[:call_id] || "",
         result: {:ok, turn, []},
         metadata: metadata(event, :generate_text)
       }}

    [response | usage(event, turn)]
  end

  defp payloads(%{kind: :tool_started, data: data} = event) do
    [{Signal.ToolStarted, tool_data(event) |> Map.put(:arguments, Map.get(data, :arguments, []))}]
  end

  defp payloads(%{kind: :tool_completed, data: data} = event) do
    result = Jido.AI.Error.normalize_result(Map.get(data, :result, {:error, :unknown, []}))
    [{Signal.ToolResult, tool_data(event) |> Map.put(:result, result)}]
  end

  defp payloads(%{kind: :request_started} = event),
    do: [
      {Signal.RequestStarted, request_data(event) |> Map.put(:query, Map.get(event.data, :query, ""))}
    ]

  defp payloads(%{kind: :request_completed} = event),
    do: [{Signal.RequestCompleted, request_data(event) |> Map.put(:result, event.data[:result])}]

  defp payloads(%{kind: :request_failed} = event),
    do: [{Signal.RequestFailed, request_data(event) |> Map.put(:error, event.data[:error])}]

  defp payloads(%{kind: :request_cancelled} = event),
    do: [
      {Signal.RequestFailed,
       request_data(event)
       |> Map.put(:error, {:cancelled, Map.get(event.data, :reason, :cancelled)})}
    ]

  defp payloads(_), do: []

  defp request_data(event), do: Map.take(event, [:request_id, :run_id])

  defp tool_data(event) do
    %{
      call_id: event.tool_call_id || event.data[:tool_call_id] || "",
      tool_name: event.tool_name || event.data[:tool_name] || "",
      metadata: metadata(event, :tool_execute)
    }
  end

  defp metadata(event, operation) do
    event
    |> Map.take([:request_id, :run_id, :iteration])
    |> Map.merge(Map.take(event.data, [:reasoning_phase, :phase_call_id, :selected_method]))
    |> Map.merge(%{
      operation: operation,
      origin: :worker_runtime,
      strategy: Jido.AI.Reasoning.Linear.label(event.method)
    })
  end

  defp usage(_event, %{usage: usage}) when usage in [nil, %{}], do: []

  defp usage(event, turn) do
    input = turn.usage[:input_tokens] || 0
    output = turn.usage[:output_tokens] || 0

    [
      {Signal.Usage,
       %{
         call_id: event.llm_call_id || "",
         model: turn.model || "",
         input_tokens: input,
         output_tokens: output,
         total_tokens: input + output,
         metadata: metadata(event, :generate_text)
       }}
    ]
  end
end
