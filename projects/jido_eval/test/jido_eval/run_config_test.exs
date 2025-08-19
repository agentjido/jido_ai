defmodule Jido.Eval.RunConfigTest do
  use ExUnit.Case, async: true

  alias Jido.Eval.{RunConfig, RetryPolicy}

  describe "struct creation" do
    test "creates with default values" do
      config = %RunConfig{}

      assert config.run_id == nil
      assert config.timeout == 180_000
      assert config.max_workers == 16
      assert config.seed == 42
      assert %RetryPolicy{} = config.retry_policy
      assert config.enable_caching == false
      assert config.telemetry_prefix == [:jido, :eval]
      assert config.enable_real_time_events == true
    end

    test "creates with custom values" do
      retry_policy = %RetryPolicy{max_retries: 5}

      config = %RunConfig{
        run_id: "test-run",
        timeout: 300_000,
        max_workers: 8,
        seed: 123,
        retry_policy: retry_policy,
        enable_caching: true,
        telemetry_prefix: [:my_app, :eval],
        enable_real_time_events: false
      }

      assert config.run_id == "test-run"
      assert config.timeout == 300_000
      assert config.max_workers == 8
      assert config.seed == 123
      assert config.retry_policy == retry_policy
      assert config.enable_caching == true
      assert config.telemetry_prefix == [:my_app, :eval]
      assert config.enable_real_time_events == false
    end

    test "includes nested retry policy" do
      config = %RunConfig{}

      assert config.retry_policy.max_retries == 3
      assert config.retry_policy.base_delay == 1000
    end
  end

  describe "doctests" do
    doctest RunConfig
  end
end
