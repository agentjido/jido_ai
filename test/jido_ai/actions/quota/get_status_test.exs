defmodule Jido.AI.Actions.Quota.GetStatusTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Actions.Quota.GetStatus
  alias Jido.AI.Quota.Store

  @moduletag :unit
  @moduletag :capture_log

  describe "schema" do
    test "accepts optional scope" do
      refute GetStatus.schema().fields[:scope].meta.required
    end
  end

  describe "run/2 happy path" do
    test "returns quota snapshot for explicit scope and context limits" do
      scope = unique_scope("quota_status")
      :ok = Store.reset(scope)
      _usage = Store.add_usage(scope, 11, 60_000)
      _usage = Store.add_usage(scope, 9, 60_000)

      context = %{
        plugin_state: %{
          quota: %{
            scope: "ignored_scope",
            window_ms: 60_000,
            max_requests: 5,
            max_total_tokens: 40
          }
        }
      }

      assert {:ok, %{quota: quota}} = GetStatus.run(%{scope: scope}, context)
      assert quota.scope == scope
      assert quota.window_ms == 60_000
      assert quota.usage.requests == 2
      assert quota.usage.total_tokens == 20
      assert quota.limits == %{max_requests: 5, max_total_tokens: 40}
      assert quota.remaining == %{requests: 3, total_tokens: 20}
      refute quota.over_budget?
    end

    test "resolves scope and limits from plugin_state before state and agent fallbacks" do
      plugin_scope = unique_scope("plugin_scope")
      state_scope = unique_scope("state_scope")

      :ok = Store.reset(plugin_scope)
      :ok = Store.reset(state_scope)
      _usage = Store.add_usage(plugin_scope, 7, 60_000)
      _usage = Store.add_usage(state_scope, 99, 60_000)

      context = %{
        plugin_state: %{
          quota: %{scope: plugin_scope, window_ms: 30_000, max_requests: 1, max_total_tokens: 10}
        },
        state: %{quota: %{scope: state_scope, window_ms: 99_000, max_requests: 99, max_total_tokens: 999}},
        agent: %{id: "agent_scope"}
      }

      assert {:ok, %{quota: quota}} = GetStatus.run(%{}, context)
      assert quota.scope == plugin_scope
      assert quota.window_ms == 30_000
      assert quota.usage.requests == 1
      assert quota.usage.total_tokens == 7
      assert quota.limits == %{max_requests: 1, max_total_tokens: 10}
      assert quota.remaining == %{requests: 0, total_tokens: 3}
      assert quota.over_budget? == true
    end
  end

  describe "schema-enforced errors via Jido.Exec" do
    test "rejects invalid scope type" do
      assert {:error, _reason} = Jido.Exec.run(GetStatus, %{scope: 123}, %{})
    end
  end

  defp unique_scope(prefix) do
    "#{prefix}_#{System.unique_integer([:positive, :monotonic])}"
  end
end
