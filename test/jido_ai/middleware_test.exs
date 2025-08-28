defmodule Jido.AI.MiddlewareTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Middleware
  alias Jido.AI.Middleware.Context
  alias Jido.AI.Middleware.CostCalculator
  alias Jido.AI.Middleware.UsageExtraction
  alias Jido.AI.Model

  # Test middleware modules
  defmodule TestMiddleware do
    @behaviour Jido.AI.Middleware

    @impl true
    def call(context, next) do
      # Add metadata on request
      context = Context.put_meta(context, :test_middleware, true)

      # Call next
      context = next.(context)

      # Modify on response
      Context.put_meta(context, :test_processed, true)
    end
  end

  defmodule LoggingMiddleware do
    @behaviour Jido.AI.Middleware

    @impl true
    def call(context, next) do
      # Log request
      context = Context.put_private(context, :logged_request, true)

      # Continue chain
      context = next.(context)

      # Log response
      Context.put_private(context, :logged_response, true)
    end
  end

  defmodule CountingMiddleware do
    @behaviour Jido.AI.Middleware

    @impl true
    def call(context, next) do
      # Count request
      count = Context.get_private(context, :count, 0)
      context = Context.put_private(context, :count, count + 1)

      # Continue
      next.(context)
    end
  end

  # Invalid module for testing
  defmodule InvalidMiddleware do
    def call(_context, _next), do: :invalid
  end

  defp create_test_context do
    model = %Model{provider: :openai, model: "gpt-4"}
    body = %{messages: [%{role: "user", content: "Hello"}]}
    opts = [temperature: 0.7]

    Context.new(:request, model, body, opts)
  end

  defp test_final_function(context) do
    # Simulate API call - switch to response phase and add response body
    response_body = %{
      choices: [%{message: %{content: "Hello, how can I help?"}}]
    }

    context
    |> Context.put_phase(:response)
    |> Context.put_body(response_body)
  end

  describe "run/3" do
    test "executes single middleware correctly" do
      context = create_test_context()
      middlewares = [TestMiddleware]

      result = Middleware.run(middlewares, context, &test_final_function/1)

      assert result.phase == :response
      assert Context.get_meta(result, :test_middleware) == true
      assert Context.get_meta(result, :test_processed) == true
      assert result.body.choices
    end

    test "executes multiple middleware in correct order" do
      context = create_test_context()
      middlewares = [LoggingMiddleware, TestMiddleware, CountingMiddleware]

      result = Middleware.run(middlewares, context, &test_final_function/1)

      assert result.phase == :response
      # All middleware should have executed
      assert Context.get_meta(result, :test_middleware) == true
      assert Context.get_meta(result, :test_processed) == true
      assert Context.get_private(result, :logged_request) == true
      assert Context.get_private(result, :logged_response) == true
      assert Context.get_private(result, :count) == 1
    end

    test "middleware can modify context between calls" do
      defmodule ModifyingMiddleware do
        @behaviour Jido.AI.Middleware

        @impl true
        def call(context, next) do
          # Modify body before next middleware
          new_body = Map.put(context.body, :modified, true)
          context = Context.put_body(context, new_body)

          next.(context)
        end
      end

      context = create_test_context()
      middlewares = [ModifyingMiddleware]

      result =
        Middleware.run(middlewares, context, fn ctx ->
          # Final function should see the modified body
          assert ctx.body.modified == true

          # Preserve the modification in response body
          response_body = %{
            choices: [%{message: %{content: "Hello, how can I help?"}}],
            modified: true
          }

          ctx
          |> Context.put_phase(:response)
          |> Context.put_body(response_body)
        end)

      assert result.body.modified == true
    end

    test "works with empty middleware list" do
      context = create_test_context()
      middlewares = []

      result = Middleware.run(middlewares, context, &test_final_function/1)

      assert result.phase == :response
      assert result.body.choices
    end

    test "middleware executes in correct order (first to last on request, reverse on response)" do
      defmodule OrderTestMiddleware do
        @behaviour Jido.AI.Middleware

        @impl true
        def call(context, next) do
          # Add to order list on request
          order = Context.get_private(context, :order, [])
          context = Context.put_private(context, :order, order ++ [:middleware1_request])

          # Call next
          context = next.(context)

          # Add to order list on response
          order = Context.get_private(context, :order, [])
          Context.put_private(context, :order, order ++ [:middleware1_response])
        end
      end

      defmodule OrderTestMiddleware2 do
        @behaviour Jido.AI.Middleware

        @impl true
        def call(context, next) do
          order = Context.get_private(context, :order, [])
          context = Context.put_private(context, :order, order ++ [:middleware2_request])

          context = next.(context)

          order = Context.get_private(context, :order, [])
          Context.put_private(context, :order, order ++ [:middleware2_response])
        end
      end

      context = create_test_context()
      middlewares = [OrderTestMiddleware, OrderTestMiddleware2]

      result =
        Middleware.run(middlewares, context, fn ctx ->
          order = Context.get_private(ctx, :order, [])
          ctx = Context.put_private(ctx, :order, order ++ [:final_function])
          test_final_function(ctx)
        end)

      expected_order = [
        :middleware1_request,
        :middleware2_request,
        :final_function,
        :middleware2_response,
        :middleware1_response
      ]

      assert Context.get_private(result, :order) == expected_order
    end
  end

  describe "run_one/3" do
    test "executes single middleware" do
      context = create_test_context()

      result = Middleware.run_one(TestMiddleware, context, &test_final_function/1)

      assert result.phase == :response
      assert Context.get_meta(result, :test_middleware) == true
      assert Context.get_meta(result, :test_processed) == true
    end
  end

  describe "validate_middlewares/1" do
    test "returns :ok for valid middleware list" do
      assert Middleware.validate_middlewares([TestMiddleware, LoggingMiddleware]) == :ok
    end

    test "returns :ok for empty list" do
      assert Middleware.validate_middlewares([]) == :ok
    end

    test "returns error for invalid middleware" do
      result = Middleware.validate_middlewares([InvalidMiddleware])
      assert {:error, message} = result
      assert message =~ "does not implement Jido.AI.Middleware behaviour"
    end

    test "returns error when list contains mix of valid and invalid middleware" do
      result = Middleware.validate_middlewares([TestMiddleware, InvalidMiddleware])
      assert {:error, message} = result
      assert message =~ "InvalidMiddleware"
    end
  end

  describe "default_pipeline/0" do
    test "returns default middleware pipeline" do
      pipeline = Middleware.default_pipeline()

      assert pipeline == [
               UsageExtraction,
               CostCalculator
             ]
    end
  end

  describe "provider_pipeline/2" do
    test "returns default pipeline for unknown provider" do
      pipeline = Middleware.provider_pipeline(:unknown_provider)

      assert pipeline == [
               UsageExtraction,
               CostCalculator
             ]
    end

    test "adds additional middleware to default pipeline" do
      pipeline = Middleware.provider_pipeline(:openai, additional: [TestMiddleware])

      assert pipeline == [
               TestMiddleware,
               UsageExtraction,
               CostCalculator
             ]
    end

    test "overrides entire pipeline with custom middleware" do
      pipeline = Middleware.provider_pipeline(:test, override: [TestMiddleware, LoggingMiddleware])

      assert pipeline == [TestMiddleware, LoggingMiddleware]
    end

    test "reads provider-specific config from Application environment" do
      # Mock Application.get_env to return provider-specific config
      original_env = Application.get_env(:jido_ai, :middlewares, %{})

      test_config = %{
        providers: %{
          custom_provider: [middlewares: [TestMiddleware, LoggingMiddleware]]
        }
      }

      Application.put_env(:jido_ai, :middlewares, test_config)

      try do
        pipeline = Middleware.provider_pipeline(:custom_provider)

        # Should return the configured middlewares for the custom provider
        assert pipeline == [TestMiddleware, LoggingMiddleware]
      after
        Application.put_env(:jido_ai, :middlewares, original_env)
      end
    end
  end

  describe "run_safe/4" do
    test "returns {:ok, context} on successful execution" do
      context = create_test_context()
      middlewares = [TestMiddleware]

      result = Middleware.run_safe(middlewares, context, &test_final_function/1)

      assert {:ok, final_context} = result
      assert final_context.phase == :response
      assert Context.get_meta(final_context, :test_middleware) == true
    end

    test "validates middlewares by default" do
      context = create_test_context()
      middlewares = [InvalidMiddleware]

      result = Middleware.run_safe(middlewares, context, &test_final_function/1)

      assert {:error, message} = result
      assert message =~ "does not implement Jido.AI.Middleware behaviour"
    end

    test "skips validation when validate: false" do
      context = create_test_context()

      # Create a middleware that would fail validation but works functionally
      defmodule WorkingButInvalidMiddleware do
        # Intentionally not implementing @behaviour
        def call(context, next) do
          next.(context)
        end
      end

      middlewares = [WorkingButInvalidMiddleware]

      result = Middleware.run_safe(middlewares, context, &test_final_function/1, validate: false)

      assert {:ok, final_context} = result
      assert final_context.phase == :response
    end

    test "catches and wraps exceptions" do
      defmodule ExceptionMiddleware do
        @behaviour Jido.AI.Middleware

        @impl true
        def call(_context, _next) do
          raise RuntimeError, "Test exception"
        end
      end

      context = create_test_context()
      middlewares = [ExceptionMiddleware]

      result = Middleware.run_safe(middlewares, context, &test_final_function/1)

      assert {:error, {:middleware_exception, %RuntimeError{message: "Test exception"}, _stacktrace}} = result
    end

    test "catches and wraps throws" do
      defmodule ThrowMiddleware do
        @behaviour Jido.AI.Middleware

        @impl true
        def call(_context, _next) do
          throw(:test_throw)
        end
      end

      context = create_test_context()
      middlewares = [ThrowMiddleware]

      result = Middleware.run_safe(middlewares, context, &test_final_function/1)

      assert {:error, {:middleware_throw, :test_throw}} = result
    end

    test "catches and wraps exits" do
      defmodule ExitMiddleware do
        @behaviour Jido.AI.Middleware

        @impl true
        def call(_context, _next) do
          exit(:test_exit)
        end
      end

      context = create_test_context()
      middlewares = [ExitMiddleware]

      result = Middleware.run_safe(middlewares, context, &test_final_function/1)

      assert {:error, {:middleware_exit, :test_exit}} = result
    end
  end

  describe "load_config/0" do
    test "returns empty map when no config is set" do
      original_env = Application.get_env(:jido_ai, :middlewares, %{})
      Application.delete_env(:jido_ai, :middlewares)

      try do
        config = Middleware.load_config()
        assert config == %{}
      after
        Application.put_env(:jido_ai, :middlewares, original_env)
      end
    end

    test "returns configured middleware config" do
      original_env = Application.get_env(:jido_ai, :middlewares, %{})

      test_config = %{
        default: [TestMiddleware],
        providers: %{
          openai: [TestMiddleware, LoggingMiddleware]
        }
      }

      Application.put_env(:jido_ai, :middlewares, test_config)

      try do
        config = Middleware.load_config()
        assert config == test_config
      after
        Application.put_env(:jido_ai, :middlewares, original_env)
      end
    end
  end
end
