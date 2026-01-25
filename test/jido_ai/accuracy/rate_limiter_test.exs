defmodule RateLimiterTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Accuracy.RateLimiter, as: AccuracyRateLimiter

  @moduletag :capture_log

  setup do
    # Start the RateLimiter GenServer for tests
    start_supervised!(AccuracyRateLimiter)

    # Reset any existing state
    AccuracyRateLimiter.reset(:test_key)

    :ok
  end

  describe "allow_request/2" do
    test "allows requests within the rate limit" do
      assert AccuracyRateLimiter.allow_request(:test_key) == :ok
      assert AccuracyRateLimiter.allow_request(:test_key) == :ok
      assert AccuracyRateLimiter.allow_request(:test_key) == :ok
    end

    test "returns rate_limited when exceeding the limit" do
      # Configure a low limit for testing
      AccuracyRateLimiter.configure(:strict_key, max_requests: 2, window_ms: 1000)

      assert AccuracyRateLimiter.allow_request(:strict_key) == :ok
      assert AccuracyRateLimiter.allow_request(:strict_key) == :ok
      assert AccuracyRateLimiter.allow_request(:strict_key) == {:error, :rate_limited}
    end

    test "resets the counter after the time window expires" do
      AccuracyRateLimiter.configure(:window_key, max_requests: 2, window_ms: 100)

      assert AccuracyRateLimiter.allow_request(:window_key) == :ok
      assert AccuracyRateLimiter.allow_request(:window_key) == :ok
      assert AccuracyRateLimiter.allow_request(:window_key) == {:error, :rate_limited}

      # Wait for window to expire
      Process.sleep(150)

      # Should be allowed again
      assert AccuracyRateLimiter.allow_request(:window_key) == :ok
    end

    test "uses custom max_requests from opts" do
      AccuracyRateLimiter.configure(:custom_key, max_requests: 5, window_ms: 1000)

      for _ <- 1..3 do
        assert AccuracyRateLimiter.allow_request(:custom_key) == :ok
      end
    end
  end

  describe "configure/2" do
    test "stores custom rate limit configuration" do
      assert :ok = AccuracyRateLimiter.configure(:my_key, max_requests: 100, window_ms: 5000)

      # Should allow many requests before hitting limit
      for _ <- 1..50 do
        assert AccuracyRateLimiter.allow_request(:my_key) == :ok
      end
    end

    test "updates existing configuration" do
      AccuracyRateLimiter.configure(:update_key, max_requests: 1, window_ms: 1000)
      assert AccuracyRateLimiter.allow_request(:update_key) == :ok
      assert AccuracyRateLimiter.allow_request(:update_key) == {:error, :rate_limited}

      # Update to allow more
      AccuracyRateLimiter.configure(:update_key, max_requests: 10, window_ms: 1000)
      assert AccuracyRateLimiter.allow_request(:update_key) == :ok
    end
  end

  describe "reset/1" do
    test "clears the rate limit counter" do
      AccuracyRateLimiter.configure(:reset_key, max_requests: 2, window_ms: 1000)

      assert AccuracyRateLimiter.allow_request(:reset_key) == :ok
      assert AccuracyRateLimiter.allow_request(:reset_key) == :ok
      assert AccuracyRateLimiter.allow_request(:reset_key) == {:error, :rate_limited}

      # Reset should allow requests again
      AccuracyRateLimiter.reset(:reset_key)
      assert AccuracyRateLimiter.allow_request(:reset_key) == :ok
    end
  end

  describe "status/1" do
    test "returns current rate limit status" do
      AccuracyRateLimiter.configure(:status_key, max_requests: 10, window_ms: 1000)

      status = AccuracyRateLimiter.status(:status_key)

      assert is_integer(status.remaining)
      assert status.remaining <= 10
      assert status.remaining >= 0
      assert is_integer(status.reset_at)
    end

    test "shows decreased remaining after requests" do
      AccuracyRateLimiter.configure(:deplete_key, max_requests: 5, window_ms: 1000)

      status_before = AccuracyRateLimiter.status(:deplete_key)
      initial_remaining = status_before.remaining

      AccuracyRateLimiter.allow_request(:deplete_key)

      status_after = AccuracyRateLimiter.status(:deplete_key)

      assert status_after.remaining == initial_remaining - 1
    end
  end

  describe "multiple keys" do
    test "tracks rate limits independently for different keys" do
      AccuracyRateLimiter.configure(:key_a, max_requests: 2, window_ms: 1000)
      AccuracyRateLimiter.configure(:key_b, max_requests: 5, window_ms: 1000)

      # Exhaust key_a
      assert AccuracyRateLimiter.allow_request(:key_a) == :ok
      assert AccuracyRateLimiter.allow_request(:key_a) == :ok
      assert AccuracyRateLimiter.allow_request(:key_a) == {:error, :rate_limited}

      # key_b should still work
      assert AccuracyRateLimiter.allow_request(:key_b) == :ok
      assert AccuracyRateLimiter.allow_request(:key_b) == :ok
    end
  end
end
