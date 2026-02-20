defmodule Jido.AI.Quota.Store do
  @moduledoc """
  In-process quota counters backed by ETS.
  """

  @table :jido_ai_quota_store

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
    current = get(scope)

    base =
      if expired?(current, now, window_ms) do
        %{window_started_at_ms: now, requests: 0, total_tokens: 0}
      else
        current
      end

    updated = %{
      window_started_at_ms: base.window_started_at_ms,
      requests: base.requests + 1,
      total_tokens: base.total_tokens + tokens
    }

    :ets.insert(@table, {scope, updated})
    updated
  end

  @doc """
  Returns current usage snapshot for a scope.
  """
  @spec get(String.t()) :: usage()
  def get(scope) when is_binary(scope) do
    ensure_table!()

    case :ets.lookup(@table, scope) do
      [{^scope, usage}] -> usage
      _ -> %{window_started_at_ms: System.system_time(:millisecond), requests: 0, total_tokens: 0}
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
        :ets.new(@table, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])
        :ok

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
end
