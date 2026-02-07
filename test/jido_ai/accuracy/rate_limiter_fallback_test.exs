defmodule Jido.AI.Accuracy.RateLimiterFallbackTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Accuracy.RateLimiter

  @moduletag :capture_log

  setup do
    # Ensure process and ETS tables are absent to exercise fallback paths.
    if pid = Process.whereis(RateLimiter) do
      GenServer.stop(pid, :normal, 1000)
    end

    if :ets.whereis(:jido_ai_rate_limiter) != :undefined do
      :ets.delete(:jido_ai_rate_limiter)
    end

    if :ets.whereis(:jido_ai_rate_limiter_config) != :undefined do
      :ets.delete(:jido_ai_rate_limiter_config)
    end

    :ok
  end

  test "allow_request/2 returns :ok when limiter is not started" do
    assert :ok = RateLimiter.allow_request(:fallback_key)
  end

  test "configure/2 succeeds when limiter is not started" do
    assert :ok = RateLimiter.configure(:fallback_key, max_requests: 2, window_ms: 1000)
  end

  test "status/1 returns defaults when limiter is not started" do
    status = RateLimiter.status(:fallback_key)

    assert is_integer(status.remaining)
    assert is_integer(status.reset_at)
    assert status.remaining >= 0
  end
end
