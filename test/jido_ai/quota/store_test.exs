defmodule Jido.AI.Quota.StoreTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Quota.Store

  @moduletag :unit

  defp unique_scope(prefix) do
    "#{prefix}_#{System.unique_integer([:positive, :monotonic])}"
  end

  test "concurrent add_usage preserves all increments" do
    scope = unique_scope("quota_atomic")
    :ok = Store.reset(scope)

    1..300
    |> Task.async_stream(
      fn _ -> Store.add_usage(scope, 1, 60_000) end,
      max_concurrency: 40,
      timeout: 5_000,
      ordered: false
    )
    |> Enum.each(fn
      {:ok, usage} -> assert is_map(usage)
      other -> flunk("unexpected task result: #{inspect(other)}")
    end)

    usage = Store.get(scope)
    assert usage.requests == 300
    assert usage.total_tokens == 300
  end

  test "ensure_table! is safe under concurrent calls" do
    1..200
    |> Task.async_stream(
      fn _ -> Store.ensure_table!() end,
      max_concurrency: 50,
      timeout: 5_000,
      ordered: false
    )
    |> Enum.each(fn
      {:ok, :ok} -> :ok
      other -> flunk("unexpected ensure_table result: #{inspect(other)}")
    end)
  end

  test "add_usage migrates legacy map rows without crashing" do
    scope = unique_scope("quota_legacy")
    Store.ensure_table!()
    now = System.system_time(:millisecond)

    :ets.insert(:jido_ai_quota_store, {scope, %{window_started_at_ms: now, requests: 2, total_tokens: 9}})

    usage = Store.add_usage(scope, 3, 60_000)
    assert usage.requests == 3
    assert usage.total_tokens == 12

    assert [{^scope, _started_at, 3, 12}] = :ets.lookup(:jido_ai_quota_store, scope)
  end
end
