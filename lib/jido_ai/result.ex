defmodule Jido.AI.Result do
  @moduledoc """
  The explicit outcome of one AI request.

  Direct reasoning does not change Agent state. A routed Agent turn can use
  the completed output to build candidate state. Core Jido commits that state
  only after the complete route Action succeeds.

  `trace` is a compatibility alias for `events`. New code should use `events`.
  """

  alias Jido.AI.Event

  @type status :: :completed | :failed | :cancelled | :limit_reached
  @type commit :: :not_requested

  @enforce_keys [:status, :request_id, :run_id, :usage, :events, :trace, :commit]
  defstruct [
    :status,
    :request_id,
    :run_id,
    :output,
    :error,
    usage: %{},
    events: [],
    trace: [],
    commit: :not_requested
  ]

  @type t :: %__MODULE__{
          status: status(),
          request_id: String.t(),
          run_id: String.t(),
          output: term(),
          error: term(),
          usage: map(),
          events: [Event.t()],
          trace: [Event.t()],
          commit: commit()
        }

  @doc false
  @spec completed(map(), term(), map(), [Event.t()]) :: t()
  def completed(request, output, usage, events)
      when is_map(request) and is_map(usage) and is_list(events) do
    %__MODULE__{
      status: :completed,
      request_id: Map.fetch!(request, :request_id),
      run_id: Map.fetch!(request, :run_id),
      output: output,
      usage: usage,
      events: events,
      trace: events,
      commit: :not_requested
    }
  end

  @doc false
  @spec failed(map(), term(), [Event.t()]) :: t()
  def failed(request, reason, events) when is_map(request) and is_list(events) do
    status = if match?({:limit_exceeded, _limit}, reason), do: :limit_reached, else: :failed

    %__MODULE__{
      status: status,
      request_id: Map.fetch!(request, :request_id),
      run_id: Map.fetch!(request, :run_id),
      error: reason,
      usage: %{},
      events: events,
      trace: events,
      commit: :not_requested
    }
  end

  @doc "Validates result identity, event order, and terminal status."
  @spec validate(term()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = result) do
    with :ok <- validate_status(result),
         :ok <- validate_identity(result),
         :ok <- validate_events(result) do
      validate_commit(result.commit)
    end
  end

  def validate(_result), do: {:error, :invalid_ai_result}

  defp validate_status(%__MODULE__{status: :completed, output: output, error: nil})
       when not is_nil(output),
       do: :ok

  defp validate_status(%__MODULE__{status: status, output: nil, error: error})
       when status in [:failed, :cancelled, :limit_reached] and not is_nil(error),
       do: :ok

  defp validate_status(_result), do: {:error, :invalid_result_status}

  defp validate_identity(%__MODULE__{request_id: request_id, run_id: run_id})
       when is_binary(request_id) and byte_size(request_id) > 0 and is_binary(run_id) and
              byte_size(run_id) > 0,
       do: :ok

  defp validate_identity(_result), do: {:error, :invalid_result_identity}

  defp validate_events(%__MODULE__{events: events, trace: events} = result)
       when is_list(events) and events != [] do
    with true <- Enum.all?(events, &(Event.validate(&1) == :ok)),
         true <- Enum.map(events, & &1.sequence) == Enum.to_list(1..length(events)),
         true <- Enum.all?(events, &same_identity?(&1, result)),
         [terminal] <- Enum.filter(events, &Event.terminal?/1),
         true <- terminal == List.last(events),
         true <- terminal_matches?(terminal.type, result.status) do
      :ok
    else
      _invalid -> {:error, :invalid_result_events}
    end
  end

  defp validate_events(_result), do: {:error, :invalid_result_events}

  defp same_identity?(event, result),
    do: event.request_id == result.request_id and event.run_id == result.run_id

  defp terminal_matches?(:request_completed, :completed), do: true
  defp terminal_matches?(:request_failed, status) when status in [:failed, :limit_reached], do: true
  defp terminal_matches?(:request_cancelled, :cancelled), do: true
  defp terminal_matches?(_type, _status), do: false

  defp validate_commit(:not_requested), do: :ok
  defp validate_commit(_commit), do: {:error, :invalid_result_commit}
end
