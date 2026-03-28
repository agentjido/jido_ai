defmodule Jido.AI.Reasoning.ReAct.PendingInput do
  @moduledoc """
  Pending-input helpers for delegated ReAct runs.

  This module keeps the acceptance rules and queue lifecycle for `steer` and
  `inject` control input out of the main ReAct strategy so the public
  orchestration path stays easier to follow.
  """

  alias Jido.AI.PendingInputServer

  @type control_kind :: :steer | :inject
  @type strategy_state :: map()

  @open_statuses [:awaiting_llm, :awaiting_tool, :completed]

  @doc """
  Starts a queue owned by the calling strategy process for the given request.
  """
  @spec start(String.t(), pid()) :: {:ok, pid()} | {:error, :pending_input_unavailable}
  def start(request_id, owner \\ self()) when is_binary(request_id) and is_pid(owner) do
    case PendingInputServer.start(owner: owner, request_id: request_id) do
      {:ok, pid} -> {:ok, pid}
      {:error, _reason} -> {:error, :pending_input_unavailable}
    end
  end

  @doc """
  Stops the tracked queue server, if any, and clears it from strategy state.
  """
  @spec stop(strategy_state()) :: strategy_state()
  def stop(state) when is_map(state) do
    case Map.get(state, :pending_input_server) do
      pid when is_pid(pid) ->
        PendingInputServer.stop(pid)
        Map.put(state, :pending_input_server, nil)

      _ ->
        Map.put(state, :pending_input_server, nil)
    end
  end

  @doc """
  Returns whether the current strategy state still accepts queued user input.
  """
  @spec open?(strategy_state()) :: boolean()
  def open?(state) when is_map(state) do
    is_binary(state[:active_request_id]) and state[:status] in @open_statuses
  end

  @doc """
  Attempts to queue a `steer` or `inject` control input and records the outcome.
  """
  @spec accept_control(strategy_state(), map(), control_kind()) ::
          {:ok, strategy_state()} | {:error, strategy_state()}
  def accept_control(state, %{content: content} = params, kind)
      when is_map(state) and is_binary(content) and kind in [:steer, :inject] do
    with {:ok, request_id} <- resolve_request_id(state, params),
         {:ok, server} <- fetch_server(state),
         :ok <- PendingInputServer.enqueue(server, queued_item(content, params)) do
      {:ok, record_control(state, kind, status: :queued, request_id: request_id)}
    else
      {:error, reason} ->
        {:error,
         record_control(state, kind,
           status: :rejected,
           reason: reason,
           request_id: Map.get(state, :active_request_id)
         )}
    end
  end

  defp resolve_request_id(state, params) do
    expected_request_id = Map.get(params, :expected_request_id)
    active_request_id = Map.get(state, :active_request_id)

    cond do
      not open?(state) ->
        {:error, :idle}

      is_binary(expected_request_id) and expected_request_id != active_request_id ->
        {:error, :request_mismatch}

      is_binary(active_request_id) ->
        {:ok, active_request_id}

      true ->
        {:error, :idle}
    end
  end

  defp fetch_server(state) do
    case Map.get(state, :pending_input_server) do
      pid when is_pid(pid) ->
        if Process.alive?(pid), do: {:ok, pid}, else: {:error, :pending_input_unavailable}

      _ ->
        {:error, :pending_input_unavailable}
    end
  end

  defp queued_item(content, params) do
    %{
      content: content,
      source: Map.get(params, :source),
      refs: normalize_optional_refs(Map.get(params, :extra_refs))
    }
  end

  defp record_control(state, kind, attrs) do
    result =
      attrs
      |> Keyword.put(:kind, kind)
      |> Keyword.put(:at_ms, System.system_time(:millisecond))
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Map.put(state, :last_pending_input_control, result)
  end

  defp normalize_optional_refs(%{} = refs), do: refs
  defp normalize_optional_refs(_), do: nil
end
