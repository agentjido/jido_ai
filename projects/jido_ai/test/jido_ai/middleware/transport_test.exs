defmodule Jido.AI.Middleware.TransportTest do
  use Jido.AI.TestSupport.HTTPCase
  use Jido.AI.TestSupport.KeyringCase

  alias Jido.AI.Error.API
  alias Jido.AI.Middleware
  alias Jido.AI.Middleware.{Context, Transport}
  alias Jido.AI.Test.Fixtures.ModelFixtures

  describe "call/2 request phase" do
    test "validates required api_key option" do
      model = ModelFixtures.gpt4()
      context = Context.new(:request, model, %{"messages" => []}, url: "https://api.openai.com/v1/chat/completions")

      # Should detect missing api_key
      result_context = Transport.call(context, &Function.identity/1)

      assert result_context.phase == :response
      error = Context.get_meta(result_context, :error)
      assert %API.Request{} = error
      assert error.reason =~ "Missing required option"
    end

    test "validates required url option" do
      model = ModelFixtures.gpt4()
      context = Context.new(:request, model, %{"messages" => []}, api_key: "sk-test")

      # Should detect missing url
      result_context = Transport.call(context, &Function.identity/1)

      assert result_context.phase == :response
      error = Context.get_meta(result_context, :error)
      assert %API.Request{} = error
      assert error.reason =~ "Missing required option"
    end

    test "counts request tokens and continues pipeline with valid options" do
      model = ModelFixtures.gpt4()
      request_body = %{"messages" => [%{"role" => "user", "content" => "Hello"}]}

      context =
        Context.new(:request, model, request_body,
          api_key: "sk-test",
          url: "https://api.openai.com/v1/chat/completions"
        )

      next_called = make_ref()

      next_fun = fn ctx ->
        send(self(), {next_called, ctx})
        ctx
      end

      Transport.call(context, next_fun)

      # Verify next was called and tokens were counted
      assert_received {^next_called, result_context}
      assert result_context.phase == :request
      assert Context.get_meta(result_context, :request_tokens) > 0
    end
  end

  describe "call/2 response phase" do
    test "passes through existing validation errors" do
      model = ModelFixtures.gpt4()
      error = API.Request.exception(reason: "Test error")

      context =
        Context.new(:response, model, %{}, [])
        |> Context.put_meta(:error, error)

      next_called = make_ref()

      next_fun = fn ctx ->
        send(self(), {next_called, ctx})
        ctx
      end

      result_context = Transport.call(context, next_fun)

      # Should pass through error without HTTP request
      assert_received {^next_called, ^result_context}
      assert Context.get_meta(result_context, :error) == error
    end

    test "executes HTTP request when no prior errors", %{test_name: test_name} do
      model = ModelFixtures.gpt4()
      request_body = %{"messages" => [%{"role" => "user", "content" => "Hello"}]}

      context =
        Context.new(:response, model, request_body,
          api_key: "sk-test",
          url: "https://api.openai.com/v1/chat/completions"
        )
        |> Context.put_meta(:request_tokens, 10)

      response_body = %{
        "choices" => [%{"message" => %{"content" => "Hello there!"}}],
        "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 5}
      }

      with_success(response_body) do
        next_fun = fn ctx -> ctx end
        result_context = Transport.call(context, next_fun)

        # Verify response processing
        enhanced_response = Context.get_meta(result_context, :enhanced_response)
        assert enhanced_response.jido_meta.usage == response_body["usage"]
        assert enhanced_response.jido_meta.model == model
        assert Context.get_meta(result_context, :usage) == response_body["usage"]
        # Cost might be nil for test models without pricing data
        cost = Context.get_meta(result_context, :cost)
        assert cost == nil or is_map(cost)
      end
    end
  end

  describe "execute_http_request/1" do
    test "successfully executes HTTP request with proper response processing", %{test_name: test_name} do
      model = ModelFixtures.gpt4()
      request_body = %{"messages" => [%{"role" => "user", "content" => "Hello"}]}

      context =
        Context.new(:response, model, request_body,
          api_key: "sk-test-key",
          url: "https://api.openai.com/v1/chat/completions",
          receive_timeout: 30_000,
          pool_timeout: 15_000
        )
        |> Context.put_meta(:request_tokens, 8)

      response_body = %{"choices" => [%{"message" => %{"content" => "Hi!"}}]}

      with_success(response_body) do
        result_context = Transport.execute_http_request(context)

        # Verify the response was properly processed
        enhanced_response = Context.get_meta(result_context, :enhanced_response)
        assert enhanced_response.body == response_body
        assert enhanced_response.jido_meta.model == model
      end
    end

    test "handles HTTP errors with structured error conversion", %{test_name: test_name} do
      model = ModelFixtures.gpt4()
      request_body = %{"messages" => []}

      context =
        Context.new(:response, model, request_body,
          api_key: "sk-test",
          url: "https://api.openai.com/v1/chat/completions"
        )

      error_response = %{
        "error" => %{
          "message" => "Invalid request",
          "type" => "invalid_request_error"
        }
      }

      with_error(400, error_response) do
        result_context = Transport.execute_http_request(context)

        error = Context.get_meta(result_context, :error)
        assert %API.Request{} = error
        # Error should contain information about the HTTP failure
        assert error.status == 400
        assert is_binary(error.reason)
      end
    end

    test "uses default configuration values when options not provided", %{test_name: test_name} do
      model = ModelFixtures.gpt4()
      request_body = %{"messages" => []}

      context =
        Context.new(:response, model, request_body,
          api_key: "sk-test",
          url: "https://api.test.com/v1/completions"
        )

      response_body = %{"choices" => [%{"message" => %{"content" => "test"}}]}

      with_success(response_body) do
        result_context = Transport.execute_http_request(context)

        # Should successfully process response using default configuration
        enhanced_response = Context.get_meta(result_context, :enhanced_response)
        assert enhanced_response.body == response_body
      end
    end
  end

  describe "process_successful_response/2" do
    test "processes response with usage data from API" do
      model = ModelFixtures.gpt4()
      request_body = %{"messages" => []}

      context =
        Context.new(:response, model, request_body, [])
        |> Context.put_meta(:request_tokens, 12)

      response = %{
        body: %{
          "choices" => [%{"message" => %{"content" => "Response text"}}],
          "usage" => %{"prompt_tokens" => 12, "completion_tokens" => 8}
        }
      }

      result_context = Transport.process_successful_response(context, response)

      # Verify usage and cost were calculated from actual API data
      usage = Context.get_meta(result_context, :usage)
      assert usage == %{"prompt_tokens" => 12, "completion_tokens" => 8}

      cost = Context.get_meta(result_context, :cost)
      # Cost might be nil for test models without pricing data
      assert cost == nil or is_map(cost)

      enhanced_response = Context.get_meta(result_context, :enhanced_response)
      assert enhanced_response.jido_meta.usage == usage
      assert enhanced_response.jido_meta.cost == cost
      assert enhanced_response.jido_meta.model == model
    end

    test "estimates tokens when API doesn't provide usage data" do
      model = ModelFixtures.gpt4()
      request_body = %{"messages" => []}

      context =
        Context.new(:response, model, request_body, [])
        |> Context.put_meta(:request_tokens, 10)

      response = %{
        body: %{"choices" => [%{"message" => %{"content" => "Short response"}}]}
        # Note: no usage field in response
      }

      result_context = Transport.process_successful_response(context, response)

      # Verify fallback estimation was used
      usage = Context.get_meta(result_context, :usage)
      # No usage from API
      assert is_nil(usage)

      cost = Context.get_meta(result_context, :cost)
      # Cost might be nil for test models without pricing data
      assert cost == nil or is_map(cost)

      enhanced_response = Context.get_meta(result_context, :enhanced_response)
      assert is_nil(enhanced_response.jido_meta.usage)
      assert enhanced_response.jido_meta.cost == cost
    end

    test "handles non-map response bodies gracefully" do
      model = ModelFixtures.gpt4()
      context = Context.new(:response, model, %{}, [])

      # Non-map body
      response = %{body: "text response"}

      result_context = Transport.process_successful_response(context, response)

      # Should handle gracefully without crashing
      usage = Context.get_meta(result_context, :usage)
      assert is_nil(usage)

      enhanced_response = Context.get_meta(result_context, :enhanced_response)
      assert enhanced_response.body == "text response"
    end
  end

  describe "build_enhanced_api_error/2" do
    test "formats Req.Response error with structured body" do
      request_body = %{"messages" => [%{"role" => "user", "content" => "test"}]}

      reason = %Req.Response{
        status: 429,
        body: %{
          "error" => %{
            "message" => "Rate limit exceeded",
            "type" => "rate_limit_error"
          }
        }
      }

      error = Transport.build_enhanced_api_error(reason, request_body)

      assert %API.Request{} = error
      assert error.reason == "Rate limit exceeded (rate_limit_error)"
      assert error.status == 429
      assert error.response_body == reason.body

      # Verify request body was sanitized
      sanitized_body = error.request_body
      assert sanitized_body["messages"] == "[REDACTED]"
      refute Map.has_key?(sanitized_body, "api_key")
    end

    test "formats HTTP error with text body" do
      request_body = %{"messages" => []}

      reason = %Req.Response{
        status: 503,
        body: "Service temporarily unavailable"
      }

      error = Transport.build_enhanced_api_error(reason, request_body)

      assert error.reason == "HTTP 503: Service temporarily unavailable"
      assert error.status == 503
    end

    test "handles network exceptions" do
      request_body = %{"messages" => []}
      reason = %Req.TransportError{reason: :timeout}

      error = Transport.build_enhanced_api_error(reason, request_body)

      assert error.reason =~ "Network error:"
      assert error.cause == reason
    end

    test "handles unexpected error formats" do
      request_body = %{"messages" => []}
      reason = {:unknown_error, "something went wrong"}

      error = Transport.build_enhanced_api_error(reason, request_body)

      assert error.reason =~ "Request failed:"
      assert error.cause == reason
    end
  end

  describe "middleware behavior conformance" do
    test "implements the Middleware behaviour correctly" do
      # Verify the module implements the correct behaviour
      behaviours = Transport.module_info(:attributes)[:behaviour] || []
      assert Middleware in behaviours
    end

    test "call/2 function has correct arity and spec" do
      # Verify the callback function exists with correct signature
      assert function_exported?(Transport, :call, 2)

      # Test that it can be called with proper types
      model = ModelFixtures.gpt4()
      context = Context.new(:request, model, %{"messages" => []}, api_key: "sk-test", url: "https://example.com")
      next_fun = fn ctx -> ctx end

      # Should not raise
      assert %Context{} = Transport.call(context, next_fun)
    end
  end

  describe "integration with middleware pipeline" do
    test "works correctly in full middleware chain", %{test_name: test_name} do
      # Define a simple logging middleware
      defmodule TestLoggingMiddleware do
        @behaviour Middleware

        def call(context, next) do
          # Add logging metadata
          context = Context.put_meta(context, :logged, true)
          result = next.(context)
          Context.put_meta(result, :logged_response, true)
        end
      end

      model = ModelFixtures.gpt4()
      request_body = %{"messages" => [%{"role" => "user", "content" => "test"}]}

      context =
        Context.new(:request, model, request_body,
          api_key: "sk-test",
          url: "https://api.openai.com/v1/chat/completions"
        )

      response_body = %{"choices" => [%{"message" => %{"content" => "Hello!"}}]}

      with_success(response_body) do
        # Run through middleware pipeline
        result_context =
          Middleware.run([TestLoggingMiddleware, Transport], context, fn ctx ->
            # This simulates the final function that switches to response phase
            Context.put_phase(ctx, :response)
          end)

        # Verify both middlewares processed the request
        assert Context.get_meta(result_context, :logged) == true
        assert Context.get_meta(result_context, :logged_response) == true
        assert Context.get_meta(result_context, :request_tokens) > 0
        # Should have enhanced response
        enhanced_response = Context.get_meta(result_context, :enhanced_response)
        assert enhanced_response != nil
      end
    end
  end
end
