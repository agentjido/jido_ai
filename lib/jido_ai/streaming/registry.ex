defmodule Jido.AI.Streaming.Registry do
  @moduledoc """
  In-memory stream lifecycle registry used by streaming actions.
  """

  @poll_interval_ms 25

  @type stream_id :: String.t()
  @type entry :: map()

  @spec register(stream_id(), map()) :: {:ok, entry()}
  def register(stream_id, attrs \\ %{}) when is_binary(stream_id) and is_map(attrs) do
    ensure_started()
    now = now_ms()

    entry =
      %{
        stream_id: stream_id,
        status: :pending,
        model: nil,
        auto_process: true,
        buffered: false,
        token_count: 0,
        text: "",
        usage: %{input_tokens: 0, output_tokens: 0, total_tokens: 0},
        error: nil,
        started_at: now,
        updated_at: now
      }
      |> Map.merge(attrs)

    Agent.update(__MODULE__, &Map.put(&1, stream_id, entry))
    {:ok, entry}
  end

  @spec put(entry()) :: {:ok, entry()}
  def put(%{stream_id: stream_id} = entry) when is_binary(stream_id) do
    ensure_started()
    Agent.update(__MODULE__, &Map.put(&1, stream_id, entry))
    {:ok, entry}
  end

  @spec get(stream_id()) :: {:ok, entry()} | {:error, :stream_not_found}
  def get(stream_id) when is_binary(stream_id) do
    ensure_started()

    case Agent.get(__MODULE__, &Map.get(&1, stream_id)) do
      nil -> {:error, :stream_not_found}
      entry -> {:ok, entry}
    end
  end

  @spec update(stream_id(), (entry() -> entry())) :: {:ok, entry()} | {:error, :stream_not_found}
  def update(stream_id, fun) when is_binary(stream_id) and is_function(fun, 1) do
    ensure_started()

    Agent.get_and_update(__MODULE__, fn state ->
      case Map.fetch(state, stream_id) do
        {:ok, entry} ->
          updated = entry |> fun.() |> Map.put(:updated_at, now_ms())
          {{:ok, updated}, Map.put(state, stream_id, updated)}

        :error ->
          {{:error, :stream_not_found}, state}
      end
    end)
  end

  @spec append_token(stream_id(), String.t()) :: {:ok, entry()} | {:error, :stream_not_found}
  def append_token(stream_id, token) when is_binary(stream_id) and is_binary(token) do
    update(stream_id, fn entry ->
      text =
        if Map.get(entry, :buffered, false) do
          Map.get(entry, :text, "") <> token
        else
          Map.get(entry, :text, "")
        end

      entry
      |> Map.put(:text, text)
      |> Map.put(:token_count, Map.get(entry, :token_count, 0) + 1)
    end)
  end

  @spec mark_processing(stream_id()) :: {:ok, entry()} | {:error, :stream_not_found}
  def mark_processing(stream_id) when is_binary(stream_id) do
    update(stream_id, &Map.put(&1, :status, :processing))
  end

  @spec mark_streaming(stream_id()) :: {:ok, entry()} | {:error, :stream_not_found}
  def mark_streaming(stream_id) when is_binary(stream_id) do
    update(stream_id, &Map.put(&1, :status, :streaming))
  end

  @spec mark_completed(stream_id(), map()) :: {:ok, entry()} | {:error, :stream_not_found}
  def mark_completed(stream_id, attrs \\ %{}) when is_binary(stream_id) and is_map(attrs) do
    update(stream_id, fn entry ->
      attrs
      |> Map.put(:status, :completed)
      |> then(&Map.merge(entry, &1))
      |> Map.put(:error, nil)
    end)
  end

  @spec mark_error(stream_id(), term()) :: {:ok, entry()} | {:error, :stream_not_found}
  def mark_error(stream_id, reason) when is_binary(stream_id) do
    update(stream_id, fn entry ->
      entry
      |> Map.put(:status, :error)
      |> Map.put(:error, reason)
    end)
  end

  @spec delete(stream_id()) :: :ok
  def delete(stream_id) when is_binary(stream_id) do
    ensure_started()
    Agent.update(__MODULE__, &Map.delete(&1, stream_id))
    :ok
  end

  @spec wait_for_terminal(stream_id(), non_neg_integer()) ::
          {:ok, entry()} | {:error, :stream_not_found | :timeout}
  def wait_for_terminal(stream_id, timeout_ms) when is_binary(stream_id) and is_integer(timeout_ms) do
    deadline = now_ms() + max(timeout_ms, 0)
    do_wait(stream_id, deadline)
  end

  defp do_wait(stream_id, deadline) do
    case get(stream_id) do
      {:ok, %{status: status} = entry} when status in [:completed, :error] ->
        {:ok, entry}

      {:ok, _entry} ->
        if now_ms() >= deadline do
          {:error, :timeout}
        else
          Process.sleep(@poll_interval_ms)
          do_wait(stream_id, deadline)
        end

      {:error, :stream_not_found} ->
        {:error, :stream_not_found}
    end
  end

  defp ensure_started do
    case Process.whereis(__MODULE__) do
      nil ->
        case Agent.start(fn -> %{} end, name: __MODULE__) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  defp now_ms, do: System.system_time(:millisecond)
end
