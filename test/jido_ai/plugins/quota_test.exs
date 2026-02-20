defmodule Jido.AI.Plugins.QuotaTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Plugins.Quota
  alias Jido.AI.Quota.Store
  alias Jido.Signal

  @scope "quota_plugin_test"
  @fallback_scope "quota_plugin_test_fallback"

  setup do
    :ok = Store.reset(@scope)
    :ok = Store.reset(@fallback_scope)
    :ok
  end

  defp ctx(state) do
    %{
      agent: %Jido.Agent{state: %{quota: state}},
      plugin_instance: %{state_key: :quota}
    }
  end

  defp quota_state(overrides) do
    Map.merge(
      %{
        enabled: true,
        scope: @scope,
        window_ms: 60_000,
        max_requests: nil,
        max_total_tokens: 100,
        error_message: "quota exceeded for current window"
      },
      overrides
    )
  end

  describe "usage accounting" do
    test "accounts ai.usage total_tokens into rolling counters" do
      state = quota_state(%{max_total_tokens: 1000})

      usage_signal =
        Signal.new!("ai.usage", %{call_id: "c1", model: "test:model", total_tokens: 12}, source: "/test")

      assert {:ok, :continue} = Quota.handle_signal(usage_signal, ctx(state))

      status =
        Store.status(
          @scope,
          %{max_requests: state[:max_requests], max_total_tokens: state[:max_total_tokens]},
          state[:window_ms]
        )

      assert status.usage.requests == 1
      assert status.usage.total_tokens == 12
      refute status.over_budget?
    end

    test "accounts ai.usage tokens from input/output fallback keys" do
      state = quota_state(%{scope: @fallback_scope, max_total_tokens: 1000})

      usage_signal =
        Signal.new!(
          "ai.usage",
          %{"call_id" => "c2", "input_tokens" => 7, "output_tokens" => 5},
          source: "/test"
        )

      assert {:ok, :continue} = Quota.handle_signal(usage_signal, ctx(state))

      status =
        Store.status(
          @fallback_scope,
          %{max_requests: state[:max_requests], max_total_tokens: state[:max_total_tokens]},
          state[:window_ms]
        )

      assert status.usage.requests == 1
      assert status.usage.total_tokens == 12
      refute status.over_budget?
    end
  end

  describe "request rewrite behavior" do
    test "rewrites over-budget budgeted signals to ai.request.error" do
      state = quota_state(%{max_total_tokens: 10})

      usage_signal =
        Signal.new!("ai.usage", %{call_id: "c3", model: "test:model", total_tokens: 12}, source: "/test")

      assert {:ok, :continue} = Quota.handle_signal(usage_signal, ctx(state))

      request_signal =
        Signal.new!("chat.message", %{prompt: "hello", call_id: "req_123"}, source: "/test")

      assert {:ok, {:continue, rewritten}} = Quota.handle_signal(request_signal, ctx(state))
      assert rewritten.type == "ai.request.error"
      assert rewritten.data.request_id == "req_123"
      assert rewritten.data.reason == :quota_exceeded
      assert rewritten.data.message == "quota exceeded for current window"
    end

    test "does not rewrite non-budgeted signals even when over budget" do
      state = quota_state(%{max_total_tokens: 10})

      usage_signal = Signal.new!("ai.usage", %{call_id: "c4", total_tokens: 12}, source: "/test")
      assert {:ok, :continue} = Quota.handle_signal(usage_signal, ctx(state))

      signal = Signal.new!("quota.status", %{scope: @scope}, source: "/test")
      assert {:ok, :continue} = Quota.handle_signal(signal, ctx(state))
    end
  end

  describe "documentation contracts" do
    test "docs define quota state keys and budget rejection contract" do
      plugin_guide = File.read!("guides/developer/plugins_and_actions_composition.md")
      plugin_module_docs = File.read!("lib/jido_ai/plugins/quota.ex")

      assert plugin_guide =~ "### Quota Runtime Contract"
      assert plugin_guide =~ "Quota state keys:"
      assert plugin_guide =~ "enabled"
      assert plugin_guide =~ "scope"
      assert plugin_guide =~ "window_ms"
      assert plugin_guide =~ "max_requests"
      assert plugin_guide =~ "max_total_tokens"
      assert plugin_guide =~ "error_message"
      assert plugin_guide =~ "Budget rejection contract:"
      assert plugin_guide =~ "ai.request.error"
      assert plugin_guide =~ "reason: :quota_exceeded"

      assert plugin_module_docs =~ "## Quota State Keys"
      assert plugin_module_docs =~ "state key `:quota`"
      assert plugin_module_docs =~ "## Budget Rejection Contract"
      assert plugin_module_docs =~ "reason: :quota_exceeded"
      assert plugin_module_docs =~ "ai.request.error"
    end

    test "examples index includes quota plugin config and rejection shape" do
      examples_readme = File.read!("lib/examples/README.md")

      assert examples_readme =~ "## Plugin Capability Pattern"
      assert examples_readme =~ "| Quota plugin | Mount `Jido.AI.Plugins.Quota`"
      assert examples_readme =~ "{Jido.AI.Plugins.Quota,"
      assert examples_readme =~ "max_total_tokens: 20_000"
      assert examples_readme =~ "type: \"ai.request.error\""
      assert examples_readme =~ "reason: :quota_exceeded"
    end
  end
end
