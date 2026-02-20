defmodule Jido.AI.Plugins.QuotaTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Plugins.Quota
  alias Jido.AI.Quota.Store
  alias Jido.Signal

  @scope "quota_plugin_test"

  setup do
    :ok = Store.reset(@scope)
    :ok
  end

  defp ctx(state) do
    %{
      agent: %Jido.Agent{state: %{quota: state}},
      plugin_instance: %{state_key: :quota}
    }
  end

  test "accounts ai.usage and rejects over-budget request signals" do
    state = %{
      enabled: true,
      scope: @scope,
      window_ms: 60_000,
      max_requests: nil,
      max_total_tokens: 10,
      error_message: "quota exceeded for current window"
    }

    usage_signal =
      Signal.new!("ai.usage", %{call_id: "c1", model: "test:model", total_tokens: 12}, source: "/test")

    assert {:ok, :continue} = Quota.handle_signal(usage_signal, ctx(state))

    request_signal = Signal.new!("chat.message", %{prompt: "hello"}, source: "/test")

    assert {:ok, {:continue, rewritten}} = Quota.handle_signal(request_signal, ctx(state))
    assert rewritten.type == "ai.request.error"
    assert rewritten.data.reason == :quota_exceeded
  end
end
