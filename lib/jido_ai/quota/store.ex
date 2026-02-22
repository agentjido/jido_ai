defmodule Jido.AI.Quota.Store do
  @moduledoc """
  In-process quota counters backed by ETS.
  """

  @table :jido_ai_quota_store
  @heir_name :jido_ai_quota_store_heir

  @type usage :: %{
          required(:window_started_at_ms) => non_neg_integer(),
          required(:requests) => non_neg_integer(),
          required(:total_tokens) => non_neg_integer()
        }

  @doc """
  Adds usage to the rolling quota counter for a scope.
  """
  @spec add_usage(String.t(), non_neg_integer(), non_neg_integer()) :: usage()
  def add_usage(scope, tokens, window_ms) when is_binary(scope) and is_integer(tokens) and tokens >= 0 do
    ensure_table!()

    now = System.system_time(:millisecond)
    normalize_legacy_row!(scope)
    maybe_roll_window!(scope, now, window_ms)

    [requests, total_tokens] =
      :ets.update_counter(
        @table,
        scope,
        [{3, 1}, {4, tokens}],
        {scope, now, 0, 0}
      )

    window_started_at_ms =
      case :ets.lookup(@table, scope) do
        [{^scope, started_at, _req, _tok}] when is_integer(started_at) -> started_at
        _ -> now
      end

    %{window_started_at_ms: window_started_at_ms, requests: requests, total_tokens: total_tokens}
  end

  @doc """
  Returns current usage snapshot for a scope.
  """
  @spec get(String.t()) :: usage()
  def get(scope) when is_binary(scope) do
    ensure_table!()

    case :ets.lookup(@table, scope) do
      [{^scope, started_at, requests, total_tokens}]
      when is_integer(started_at) and is_integer(requests) and is_integer(total_tokens) ->
        %{window_started_at_ms: started_at, requests: requests, total_tokens: total_tokens}

      [{^scope, %{} = usage}] ->
        usage

      _ ->
        %{window_started_at_ms: System.system_time(:millisecond), requests: 0, total_tokens: 0}
    end
  end

  @doc """
  Resets quota counters for a scope.
  """
  @spec reset(String.t()) :: :ok
  def reset(scope) when is_binary(scope) do
    ensure_table!()
    :ets.delete(@table, scope)
    :ok
  end

  @doc """
  Returns quota status including limits, usage, and remaining budget.
  """
  @spec status(String.t(), map(), non_neg_integer()) :: map()
  def status(scope, limits, window_ms) when is_binary(scope) and is_map(limits) do
    now = System.system_time(:millisecond)
    usage = get(scope)

    usage =
      if expired?(usage, now, window_ms) do
        %{window_started_at_ms: now, requests: 0, total_tokens: 0}
      else
        usage
      end

    max_requests = Map.get(limits, :max_requests)
    max_total_tokens = Map.get(limits, :max_total_tokens)

    over_requests? = is_integer(max_requests) and max_requests >= 0 and usage.requests >= max_requests
    over_tokens? = is_integer(max_total_tokens) and max_total_tokens >= 0 and usage.total_tokens >= max_total_tokens

    %{
      scope: scope,
      window_ms: window_ms,
      usage: usage,
      limits: %{
        max_requests: max_requests,
        max_total_tokens: max_total_tokens
      },
      over_budget?: over_requests? or over_tokens?,
      remaining: %{
        requests: remaining(max_requests, usage.requests),
        total_tokens: remaining(max_total_tokens, usage.total_tokens)
      }
    }
  end

  @doc """
  Ensures the quota ETS table exists.
  """
  @spec ensure_table!() :: :ok
  def ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        create_table!()

      _tid ->
        :ok
    end
  end

  defp remaining(nil, _used), do: nil
  defp remaining(limit, used), do: max(limit - used, 0)

  defp expired?(usage, now, window_ms) when is_integer(window_ms) and window_ms > 0 do
    now - usage.window_started_at_ms >= window_ms
  end

  defp expired?(_usage, _now, _window_ms), do: false

  defp create_table! do
    heir = ensure_heir!()

    :ets.new(@table, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true},
      {:heir, heir, :ok}
    ])

    :ok
  rescue
    ArgumentError ->
      # Another process may have created the table concurrently.
      :ok
  end

  defp normalize_legacy_row!(scope) do
    case :ets.lookup(@table, scope) do
      [{^scope, %{window_started_at_ms: started_at, requests: requests, total_tokens: total_tokens}}] ->
        :ets.insert(@table, {scope, started_at, requests, total_tokens})
        :ok

      _ ->
        :ok
    end
  end

  defp maybe_roll_window!(scope, now, window_ms) when is_integer(window_ms) and window_ms > 0 do
    case :ets.lookup(@table, scope) do
      [{^scope, started_at, _requests, _total_tokens}] when is_integer(started_at) and now - started_at >= window_ms ->
        # Only replace if the row still matches the expired window we observed.
        :ets.select_replace(
          @table,
          [{{scope, started_at, :"$1", :"$2"}, [], [{{scope, now, 0, 0}}]}]
        )

        :ok

      _ ->
        :ok
    end
  end

  defp maybe_roll_window!(_scope, _now, _window_ms), do: :ok

  defp ensure_heir! do
    case Process.whereis(@heir_name) do
      nil ->
        pid = spawn(fn -> heir_loop() end)

        try do
          Process.register(pid, @heir_name)
          pid
        rescue
          ArgumentError ->
            Process.exit(pid, :normal)
            Process.whereis(@heir_name) || pid
        end

      pid ->
        pid
    end
  end

  defp heir_loop do
    receive do
      {:"ETS-TRANSFER", _table, _from, _heir_data} ->
        heir_loop()

      _ ->
        heir_loop()
    end
  end
end
