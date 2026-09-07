defmodule Jido.AI.Plugins.QuotaTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Plugins.Quota
  alias Jido.AI.Quota.Store
  alias Jido.Signal

  @scope "quota_plugin_test"
  @fallback_scope "quota_plugin_test_fallback"

  setup do
    start_supervised!({Store, []})
    :ok = Store.reset(@scope)
    :ok = Store.reset(@fallback_scope)
    :ok
  end

  defp command(signal, state) do
    definition =
      Jido.Agent.new!(%{
        name: "quota_test",
        schema: Zoi.object(%{}),
        plugins: [{Quota, Map.to_list(state)}]
      })

    %Jido.Agent.Command{agent: Jido.Agent.instantiate!(definition), signal: signal, context: %{}}
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

      assert {:ok, _command} = Quota.admit(nil, command(usage_signal, state), [])

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

      assert {:ok, _command} = Quota.admit(nil, command(usage_signal, state), [])

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

  describe "structured budget rejection" do
    test "rejects over-budget signals with a correlated quota error" do
      state = quota_state(%{max_total_tokens: 10})

      usage_signal =
        Signal.new!("ai.usage", %{call_id: "c3", model: "test:model", total_tokens: 12}, source: "/test")

      assert {:ok, _command} = Quota.admit(nil, command(usage_signal, state), [])

      request_signal =
        Signal.new!("chat.message", %{prompt: "hello", call_id: "req_123"}, source: "/test")

      assert {:error, error} = Quota.admit(nil, command(request_signal, state), [])
      assert error.details.request_id == "req_123"
      assert error.type == :quota_exceeded
      assert error.message == "quota exceeded for current window"
    end

    test "permits non-budgeted signals even when over budget" do
      state = quota_state(%{max_total_tokens: 10})

      usage_signal = Signal.new!("ai.usage", %{call_id: "c4", total_tokens: 12}, source: "/test")
      assert {:ok, _command} = Quota.admit(nil, command(usage_signal, state), [])

      signal = Signal.new!("quota.status", %{scope: @scope}, source: "/test")
      assert {:ok, _command} = Quota.admit(nil, command(signal, state), [])
    end
  end
end
