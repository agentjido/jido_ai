defmodule JidoAI.Bench.ReAct.MemorySampler do
  @moduledoc false

  @keys [:total, :processes, :binary, :ets]

  def start!(interval_ms \\ 25) do
    caller = self()
    pid = spawn_link(fn -> initialize(caller, interval_ms) end)

    receive do
      {:memory_sampler_ready, ^pid, baseline} -> %{pid: pid, baseline: baseline}
    after
      5_000 -> raise "timed out while starting the memory sampler"
    end
  end

  def stop!(%{pid: pid, baseline: baseline}) do
    ref = make_ref()
    send(pid, {:stop, self(), ref})

    receive do
      {^ref, peak, final, samples, top_at_peak} ->
        %{
          baseline: baseline,
          peak: peak,
          final: final,
          peak_increase: difference(peak, baseline),
          samples: samples,
          top_at_peak: top_at_peak
        }
    after
      5_000 -> raise "timed out while stopping the memory sampler"
    end
  end

  defp initialize(caller, interval_ms) do
    baseline = snapshot()
    send(caller, {:memory_sampler_ready, self(), baseline})
    sample(interval_ms, baseline, 1, top_processes())
  end

  defp sample(interval_ms, peak, samples, top_at_peak) do
    receive do
      {:stop, caller, ref} ->
        final = snapshot()
        {peak, top_at_peak} = update_peak(peak, final, top_at_peak)

        send(
          caller,
          {ref, peak, final, samples + 1, top_at_peak}
        )
    after
      interval_ms ->
        current = snapshot()
        {peak, top_at_peak} = update_peak(peak, current, top_at_peak)
        sample(interval_ms, peak, samples + 1, top_at_peak)
    end
  end

  defp update_peak(peak, current, top_at_peak) do
    if current.total > peak.total do
      {maximum(peak, current), top_processes()}
    else
      {maximum(peak, current), top_at_peak}
    end
  end

  defp snapshot do
    :erlang.memory()
    |> Map.new()
    |> Map.take(@keys)
  end

  defp maximum(left, right) do
    Map.new(@keys, fn key -> {key, max(Map.fetch!(left, key), Map.fetch!(right, key))} end)
  end

  defp difference(left, right) do
    Map.new(@keys, fn key -> {key, Map.fetch!(left, key) - Map.fetch!(right, key)} end)
  end

  defp top_processes do
    Process.list()
    |> Enum.flat_map(fn pid ->
      case Process.info(pid, [
             :memory,
             :total_heap_size,
             :message_queue_len,
             :current_function,
             :initial_call,
             :registered_name
           ]) do
        nil -> []
        info -> [info |> Map.new() |> Map.put(:pid, inspect(pid))]
      end
    end)
    |> Enum.sort_by(& &1.memory, :desc)
    |> Enum.take(8)
  end
end
