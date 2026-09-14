defmodule Jido.AI.Quota.Store do
  @moduledoc """
  Supervised quota counters and correlated model-call records.

  Add this Store to the application supervisor before using Quota. Calls do not
  start an implicit process. Counters report guarded provider invocations and
  known tokens. `ledger/2` and status accounting distinguish pending and unknown
  usage. A provider invocation can include several transport retries.

  Records belong to the window in which they started. A window rollover or reset
  does not charge late results to the replacement window. Completed records are
  retained until that window is replaced. Store restart starts empty.
  """
  use GenServer

  @type usage :: %{
          window_started_at_ms: integer(),
          requests: non_neg_integer(),
          total_tokens: non_neg_integer()
        }

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(is_nil(name), do: [], else: [name: name]))
  end

  def ensure_table!(store \\ __MODULE__), do: GenServer.call(store, :ready)

  def get(scope, store \\ __MODULE__) when is_binary(scope),
    do: GenServer.call(store, {:get, scope})

  def reset(scope, store \\ __MODULE__) when is_binary(scope),
    do: GenServer.call(store, {:reset, scope})

  def status(scope, limits, window_ms, store \\ __MODULE__)
      when is_binary(scope) and is_map(limits),
      do: GenServer.call(store, {:status, scope, limits, window_ms})

  def ledger(scope, store \\ __MODULE__) when is_binary(scope),
    do: GenServer.call(store, {:ledger, scope})

  def add_usage(scope, tokens, window_ms, store \\ __MODULE__)
      when is_binary(scope) and is_integer(tokens) and tokens >= 0 do
    record_usage(scope, Jido.Signal.ID.generate!(), tokens, window_ms, store)
  end

  @doc "Records an external usage report once per call ID in the active window."
  def record_usage(scope, id, tokens, window_ms, store \\ __MODULE__)
      when is_binary(scope) and is_binary(id) and is_integer(tokens) and tokens >= 0,
      do: GenServer.call(store, {:report, scope, id, tokens, window_ms})

  @doc false
  def begin_call(binding, id), do: GenServer.call(binding.store, {:begin, binding, id})
  @doc false
  def finish_call(store, ticket, tokens), do: GenServer.call(store, {:finish, ticket, tokens})
  @doc false
  def progress(store, ticket, tokens), do: GenServer.call(store, {:progress, ticket, tokens})

  @impl GenServer
  def init(opts),
    do:
      {:ok,
       %{
         rows: %{},
         monitors: %{},
         clock: Keyword.get(opts, :clock, fn -> System.system_time(:millisecond) end)
       }}

  @impl GenServer
  def handle_call(:ready, _, state), do: {:reply, :ok, state}
  def handle_call({:get, scope}, _, state), do: {:reply, row(state, scope).usage, state}

  def handle_call({:ledger, scope}, _, state) do
    records =
      row(state, scope).records |> Map.values() |> Enum.sort_by(&{&1.started_at_ms, &1.id})

    {:reply, records, state}
  end

  def handle_call({:reset, scope}, _, state),
    do: {:reply, :ok, put_in(state.rows[scope], fresh(state.clock.()))}

  def handle_call({:status, scope, limits, window}, _, state) do
    {:reply, status_map(current(state, scope, window), scope, limits, window), state}
  end

  def handle_call({:report, scope, id, tokens, window}, _, state) do
    row = current(state, scope, window)

    row =
      case row.records[id] do
        nil ->
          record = record(id, :complete, tokens, state.clock.())

          %{
            row
            | records: Map.put(row.records, id, record),
              usage: %{
                row.usage
                | requests: row.usage.requests + 1,
                  total_tokens: row.usage.total_tokens + tokens
              }
          }

        %{status: :unknown} = record ->
          previous = record.total_tokens || 0
          tokens = max(previous, tokens)

          %{
            row
            | records: Map.put(row.records, id, %{record | status: :complete, total_tokens: tokens}),
              usage: %{row.usage | total_tokens: row.usage.total_tokens + tokens - previous}
          }

        _ ->
          row
      end

    {:reply, row.usage, put_in(state.rows[scope], row)}
  end

  def handle_call({:begin, binding, id}, {pid, _}, state) do
    row = current(state, binding.scope, binding.window_ms)

    cond do
      Map.has_key?(row.records, id) ->
        {:reply, {:error, :duplicate_quota_call}, state}

      binding.enabled and status_map(row, binding.scope, binding, binding.window_ms).over_budget? ->
        {:reply, {:error, :quota_exceeded}, state}

      true ->
        ref = Process.monitor(pid)
        ticket = {binding.scope, row.generation, id, ref}
        record = record(id, :pending, nil, state.clock.())

        row = %{
          row
          | records: Map.put(row.records, id, record),
            usage: %{row.usage | requests: row.usage.requests + 1}
        }

        state = state |> put_in([:rows, binding.scope], row) |> put_in([:monitors, ref], ticket)
        {:reply, {:ok, ticket}, state}
    end
  end

  def handle_call({:finish, {_, _, _, ref} = ticket, tokens}, _, state) do
    if state.monitors[ref] == ticket do
      Process.demonitor(ref, [:flush])
      state = complete(state, ticket, tokens)
      {:reply, :ok, %{state | monitors: Map.delete(state.monitors, ref)}}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call({:progress, {scope, generation, id, ref} = ticket, tokens}, _, state) do
    if state.monitors[ref] == ticket and is_integer(tokens) and tokens >= 0 do
      case state.rows[scope] do
        %{generation: ^generation, records: records} = row ->
          record = records[id]
          previous = record.total_tokens || 0
          tokens = max(previous, tokens)

          row = %{
            row
            | records: Map.put(records, id, %{record | total_tokens: tokens}),
              usage: %{row.usage | total_tokens: row.usage.total_tokens + tokens - previous}
          }

          {:reply, :ok, put_in(state.rows[scope], row)}

        _ ->
          {:reply, :ok, state}
      end
    else
      {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _, _}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _} -> {:noreply, state}
      {ticket, monitors} -> {:noreply, complete(%{state | monitors: monitors}, ticket, nil)}
    end
  end

  defp complete(state, {scope, generation, id, _}, tokens) do
    case state.rows[scope] do
      %{generation: ^generation, records: records} = row ->
        case records[id] do
          %{status: :pending} = record ->
            known? = is_integer(tokens) and tokens >= 0
            previous = record.total_tokens || 0
            tokens = if known?, do: max(previous, tokens), else: record.total_tokens

            record = %{
              record
              | status: if(known?, do: :complete, else: :unknown),
                total_tokens: tokens
            }

            row = %{
              row
              | records: Map.put(records, id, record),
                usage: %{
                  row.usage
                  | total_tokens: row.usage.total_tokens + (tokens || 0) - previous
                }
            }

            put_in(state.rows[scope], row)

          _ ->
            state
        end

      _ ->
        state
    end
  end

  defp row(state, scope), do: Map.get_lazy(state.rows, scope, fn -> fresh(state.clock.()) end)

  defp current(state, scope, window) do
    row = row(state, scope)

    if is_integer(window) and window > 0 and
         state.clock.() - row.usage.window_started_at_ms >= window,
       do: fresh(state.clock.()),
       else: row
  end

  defp fresh(now),
    do: %{
      generation: make_ref(),
      records: %{},
      usage: %{window_started_at_ms: now, requests: 0, total_tokens: 0}
    }

  defp record(id, status, tokens, now),
    do: %{id: id, status: status, total_tokens: tokens, started_at_ms: now}

  defp status_map(row, scope, limits, window) do
    requests = Map.get(limits, :max_requests)
    tokens = Map.get(limits, :max_total_tokens)
    statuses = Enum.frequencies_by(Map.values(row.records), & &1.status)

    %{
      scope: scope,
      window_ms: window,
      usage: row.usage,
      limits: %{max_requests: requests, max_total_tokens: tokens},
      over_budget?: exhausted?(requests, row.usage.requests) or exhausted?(tokens, row.usage.total_tokens),
      remaining: %{
        requests: remaining(requests, row.usage.requests),
        total_tokens: remaining(tokens, row.usage.total_tokens)
      },
      accounting: %{
        unattributed_calls: max(row.usage.requests - map_size(row.records), 0),
        pending_calls: Map.get(statuses, :pending, 0),
        unknown_calls: Map.get(statuses, :unknown, 0)
      }
    }
  end

  defp exhausted?(limit, used), do: is_integer(limit) and limit >= 0 and used >= limit
  defp remaining(nil, _), do: nil
  defp remaining(limit, used), do: max(limit - used, 0)
end
