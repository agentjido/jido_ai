defmodule Jido.Eval.MiddlewareTest do
  use ExUnit.Case, async: true

  alias Jido.Eval.Middleware

  defmodule TestMiddleware do
    @behaviour Middleware

    def call(metric_fn, context, opts) do
      send(self(), {:before_call, context, opts})
      result = metric_fn.()
      send(self(), {:after_call, result})
      result
    end
  end

  defmodule TimingMiddleware do
    @behaviour Middleware

    def call(metric_fn, _context, _opts) do
      start_time = System.monotonic_time()
      result = metric_fn.()
      duration = System.monotonic_time() - start_time

      send(self(), {:timing, duration})
      result
    end
  end

  defmodule ErrorHandlingMiddleware do
    @behaviour Middleware

    def call(metric_fn, _context, opts) do
      try do
        metric_fn.()
      rescue
        error ->
          if Keyword.get(opts, :reraise, true) do
            reraise error, __STACKTRACE__
          else
            {:error, error}
          end
      end
    end
  end

  describe "behaviour implementation" do
    test "TestMiddleware wraps function execution" do
      metric_fn = fn -> {:ok, 42} end
      context = %{metric: :test}
      opts = [debug: true]

      result = TestMiddleware.call(metric_fn, context, opts)

      assert result == {:ok, 42}
      assert_received {:before_call, ^context, ^opts}
      assert_received {:after_call, {:ok, 42}}
    end

    test "TimingMiddleware measures execution time" do
      metric_fn = fn ->
        Process.sleep(10)
        :success
      end

      result = TimingMiddleware.call(metric_fn, %{}, [])

      assert result == :success
      assert_received {:timing, duration}
      assert duration > 0
    end

    test "ErrorHandlingMiddleware catches and reraises errors by default" do
      metric_fn = fn -> raise "test error" end

      assert_raise RuntimeError, "test error", fn ->
        ErrorHandlingMiddleware.call(metric_fn, %{}, [])
      end
    end

    test "ErrorHandlingMiddleware can return errors without raising" do
      metric_fn = fn -> raise "test error" end

      result = ErrorHandlingMiddleware.call(metric_fn, %{}, reraise: false)

      assert {:error, %RuntimeError{message: "test error"}} = result
    end

    test "middleware can modify return values" do
      defmodule ModifyingMiddleware do
        @behaviour Middleware

        def call(metric_fn, _context, _opts) do
          result = metric_fn.()
          {:wrapped, result}
        end
      end

      metric_fn = fn -> :original end
      result = ModifyingMiddleware.call(metric_fn, %{}, [])

      assert result == {:wrapped, :original}
    end
  end

  describe "behaviour validation" do
    test "behaviour callbacks are defined" do
      callbacks = Middleware.behaviour_info(:callbacks)

      assert {:call, 3} in callbacks
    end

    test "no optional callbacks defined" do
      optional_callbacks = Middleware.behaviour_info(:optional_callbacks)
      assert optional_callbacks == []
    end
  end
end
