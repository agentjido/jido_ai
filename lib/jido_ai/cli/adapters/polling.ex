defmodule Jido.AI.CLI.Adapters.Polling do
  @moduledoc false

  @spec await(pid(), non_neg_integer(), atom(), (map() -> map()), non_neg_integer()) ::
          {:ok, %{answer: term(), meta: map()}} | {:error, term()}
  def await(pid, timeout_ms, fallback_key, meta_fun, interval \\ 100)
      when is_pid(pid) and is_integer(timeout_ms) and timeout_ms >= 0 and is_atom(fallback_key) and
             is_function(meta_fun, 1) and is_integer(interval) and interval > 0 do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll(pid, deadline, interval, fallback_key, meta_fun)
  end

  defp poll(pid, deadline, interval, fallback_key, meta_fun) do
    if deadline_reached?(deadline) do
      {:error, :timeout}
    else
      poll_status(pid, deadline, interval, fallback_key, meta_fun)
    end
  end

  defp deadline_reached?(deadline), do: System.monotonic_time(:millisecond) >= deadline

  defp poll_status(pid, deadline, interval, fallback_key, meta_fun) do
    case Jido.AgentServer.status(pid) do
      {:ok, status} -> handle_status(status, pid, deadline, interval, fallback_key, meta_fun)
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_status(status, _pid, _deadline, _interval, fallback_key, meta_fun) when status.snapshot.done? do
    {:ok, %{answer: extract_answer(status, fallback_key), meta: meta_fun.(status)}}
  end

  defp handle_status(_status, pid, deadline, interval, fallback_key, meta_fun) do
    Process.sleep(interval)
    poll(pid, deadline, interval, fallback_key, meta_fun)
  end

  defp extract_answer(status, fallback_key) do
    case status.snapshot.result do
      nil -> Map.get(status.raw_state, fallback_key, "")
      "" -> Map.get(status.raw_state, fallback_key, "")
      result -> result
    end
  end
end
