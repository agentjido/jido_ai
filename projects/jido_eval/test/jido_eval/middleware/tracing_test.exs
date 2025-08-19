defmodule Jido.Eval.Middleware.TracingTest do
  use ExUnit.Case, async: true

  alias Jido.Eval.Middleware.Tracing

  describe "call/3 behavior interface" do
    test "wraps function execution with tracing" do
      metric_fn = fn -> {:ok, 42} end
      context = %{metric: :test, sample: %{id: "sample_1"}}
      opts = [trace_level: :info]

      result = Tracing.call(metric_fn, context, opts)

      assert result == {:ok, 42}
    end

    test "handles errors and reraises them" do
      metric_fn = fn -> raise "test error" end
      context = %{metric: :test}
      opts = []

      assert_raise RuntimeError, "test error", fn ->
        Tracing.call(metric_fn, context, opts)
      end
    end
  end

  describe "call/2 worker interface" do
    test "wraps function execution with tracing" do
      context = %{metric: :test, sample: %{id: "sample_1"}}
      metric_fn = fn -> {:ok, 42} end

      result = Tracing.call(context, metric_fn)

      assert result == {:ok, 42}
    end

    test "handles errors and reraises them" do
      context = %{metric: :test}
      metric_fn = fn -> raise "test error" end

      assert_raise RuntimeError, "test error", fn ->
        Tracing.call(context, metric_fn)
      end
    end
  end

  describe "telemetry events" do
    test "emits start and stop events" do
      # Attach a test handler
      test_pid = self()

      :telemetry.attach(
        [:test, :trace, :start],
        [:jido, :eval, :middleware, :trace, :start],
        fn _event, _measurements, metadata, _ ->
          send(test_pid, {:trace_start, metadata})
        end,
        nil
      )

      :telemetry.attach(
        [:test, :trace, :stop],
        [:jido, :eval, :middleware, :trace, :stop],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:trace_stop, measurements, metadata})
        end,
        nil
      )

      context = %{metric: :test}
      metric_fn = fn -> {:ok, 42} end

      result = Tracing.call(context, metric_fn)

      assert result == {:ok, 42}

      # Check that telemetry events were emitted
      assert_received {:trace_start, %{trace_id: _trace_id, context: ^context}}

      assert_received {:trace_stop, %{duration: _duration},
                       %{trace_id: _trace_id, status: :success, result: {:ok, 42}}}

      # Clean up handlers
      :telemetry.detach([:test, :trace, :start])
      :telemetry.detach([:test, :trace, :stop])
    end
  end
end
