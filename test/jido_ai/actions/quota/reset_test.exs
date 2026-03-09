defmodule Jido.AI.Actions.Quota.ResetTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Actions.Quota.Reset
  alias Jido.AI.Quota.Store

  @moduletag :unit
  @moduletag :capture_log

  describe "schema" do
    test "accepts optional scope" do
      refute Reset.schema().fields[:scope].meta.required
    end
  end

  describe "run/2 happy path" do
    test "resets counters for explicit scope and returns quota envelope" do
      scope = unique_scope("quota_reset")
      :ok = Store.reset(scope)
      _usage = Store.add_usage(scope, 12, 60_000)
      _usage = Store.add_usage(scope, 8, 60_000)

      pre_status = Store.status(scope, %{max_requests: nil, max_total_tokens: nil}, 60_000)
      assert pre_status.usage.requests == 2
      assert pre_status.usage.total_tokens == 20

      assert {:ok, %{quota: quota}} = Reset.run(%{scope: scope}, %{})
      assert quota.scope == scope
      assert quota.reset == true

      post_status = Store.status(scope, %{max_requests: nil, max_total_tokens: nil}, 60_000)
      assert post_status.usage.requests == 0
      assert post_status.usage.total_tokens == 0
    end

    test "resolves scope from plugin_state before state and agent fallbacks" do
      plugin_scope = unique_scope("plugin_scope")
      state_scope = unique_scope("state_scope")
      agent_scope = unique_scope("agent_scope")

      :ok = Store.reset(plugin_scope)
      :ok = Store.reset(state_scope)
      :ok = Store.reset(agent_scope)
      _usage = Store.add_usage(plugin_scope, 5, 60_000)
      _usage = Store.add_usage(state_scope, 5, 60_000)
      _usage = Store.add_usage(agent_scope, 5, 60_000)

      context = %{
        plugin_state: %{quota: %{scope: plugin_scope}},
        state: %{quota: %{scope: state_scope}},
        agent: %{id: agent_scope}
      }

      assert {:ok, %{quota: quota}} = Reset.run(%{}, context)
      assert quota.scope == plugin_scope
      assert quota.reset == true

      plugin_status = Store.status(plugin_scope, %{max_requests: nil, max_total_tokens: nil}, 60_000)
      state_status = Store.status(state_scope, %{max_requests: nil, max_total_tokens: nil}, 60_000)
      agent_status = Store.status(agent_scope, %{max_requests: nil, max_total_tokens: nil}, 60_000)

      assert plugin_status.usage.requests == 0
      assert state_status.usage.requests == 1
      assert agent_status.usage.requests == 1
    end
  end

  describe "schema-enforced errors via Jido.Exec" do
    test "rejects invalid scope type" do
      assert {:error, _reason} = Jido.Exec.run(Reset, %{scope: :bad_scope}, %{})
    end
  end

  defp unique_scope(prefix) do
    "#{prefix}_#{System.unique_integer([:positive, :monotonic])}"
  end
end
