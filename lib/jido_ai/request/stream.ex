defmodule Jido.AI.Request.Stream do
  @moduledoc """
  Request-scoped runtime event streaming helpers.

  The stream transport is intentionally narrow: callers can provide a pid sink
  and receive canonical ReAct runtime events for one request.
  """

  alias Jido.AI.Reasoning.ReAct.Event
  alias Jido.AI.Request.Handle

  @message_tag :jido_ai_request_event
  @terminal_kinds [:request_completed, :request_failed, :request_cancelled]

  @type sink :: {:pid, pid()}

  @doc """
  Returns the mailbox tag used for request stream messages.
  """
  @spec message_tag() :: atom()
  def message_tag, do: @message_tag

  @doc """
  Normalizes public stream sink options.
  """
  @spec normalize_sink(term()) :: {:ok, sink() | nil} | {:error, term()}
  def normalize_sink(nil), do: {:ok, nil}
  def normalize_sink({:pid, pid}) when is_pid(pid), do: {:ok, {:pid, pid}}
  def normalize_sink(pid) when is_pid(pid), do: {:ok, {:pid, pid}}
  def normalize_sink(other), do: {:error, {:invalid_stream_to, other}}

  @doc """
  Builds an enumerable over runtime events for a request handle.

  The enumerable halts after receiving `:request_completed`,
  `:request_failed`, or `:request_cancelled`.
  """
  @spec events(Handle.t(), keyword()) :: Enumerable.t()
  def events(%Handle{id: request_id}, opts \\ []) do
    timeout = Keyword.get(opts, :stream_event_timeout_ms, :infinity)

    Stream.resource(
      fn -> %{request_id: request_id, done?: false, timeout: timeout} end,
      &next_event/1,
      fn _state -> :ok end
    )
  end

  @doc """
  Sends one runtime event to a normalized stream sink.
  """
  @spec send_event(sink() | nil, Event.t() | map()) :: :ok
  def send_event(nil, _event), do: :ok

  def send_event({:pid, pid}, event) when is_pid(pid) do
    case to_event(event) do
      {:ok, event} ->
        if Process.alive?(pid), do: send(pid, {@message_tag, event})
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  def send_event(_sink, _event), do: :ok

  @doc """
  Creates a synthetic terminal failure event for non-worker rejection paths.
  """
  @spec failed_event(String.t(), term(), keyword()) :: Event.t()
  def failed_event(request_id, error, opts \\ []) when is_binary(request_id) do
    data =
      %{error: error, reason: Keyword.get(opts, :reason)}
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    new_event(request_id, :request_failed, data, opts)
  end

  @doc """
  Returns true when the event kind terminates a request stream.
  """
  @spec terminal_kind?(atom()) :: boolean()
  def terminal_kind?(kind), do: kind in @terminal_kinds

  defp next_event(%{done?: true} = state), do: {:halt, state}

  defp next_event(%{request_id: request_id, timeout: timeout} = state) do
    case receive_event(request_id, timeout) do
      {:ok, event} ->
        {[event], %{state | done?: terminal_kind?(event.kind)}}

      :timeout ->
        {:halt, %{state | done?: true}}
    end
  end

  defp receive_event(request_id, :infinity) do
    receive do
      {@message_tag, %Event{request_id: ^request_id} = event} -> {:ok, event}
    end
  end

  defp receive_event(request_id, timeout) when is_integer(timeout) and timeout >= 0 do
    receive do
      {@message_tag, %Event{request_id: ^request_id} = event} -> {:ok, event}
    after
      timeout -> :timeout
    end
  end

  defp receive_event(request_id, _timeout), do: receive_event(request_id, :infinity)

  defp to_event(%Event{} = event), do: {:ok, event}

  defp to_event(event) when is_map(event) do
    {:ok, Event.new(event)}
  rescue
    error -> {:error, error}
  end

  defp to_event(other), do: {:error, {:invalid_event, other}}

  defp new_event(request_id, kind, data, opts) do
    Event.new(%{
      seq: Keyword.get(opts, :seq, 0),
      run_id: Keyword.get(opts, :run_id, request_id),
      request_id: request_id,
      iteration: Keyword.get(opts, :iteration, 0),
      kind: kind,
      data: data
    })
  end
end
