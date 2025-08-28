defmodule Jido.AI.Provider.Request.StreamingMiddlewareBasicTest do
  @moduledoc """
  Basic tests verifying streaming middleware integration works correctly.
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Error.API.Request
  alias Jido.AI.Error.Invalid.Parameter
  alias Jido.AI.Middleware
  alias Jido.AI.Middleware.Context
  alias Jido.AI.Middleware.TokenCounter
  alias Jido.AI.Provider.Request.HTTP
  alias Jido.AI.Test.Fixtures.ModelFixtures

  describe "middleware integration" do
    test "token counting middleware processes streaming requests" do
      model = ModelFixtures.gpt4()
      request_body = %{"messages" => [%{"role" => "user", "content" => "Test"}]}

      # Test that middleware runs correctly
      context = Context.new(:request, model, request_body, [])

      # Verify TokenCounter middleware works
      context_with_tokens =
        Middleware.run([TokenCounter], context, fn ctx ->
          Context.put_phase(ctx, :response)
        end)

      request_tokens = Context.get_meta(context_with_tokens, :request_tokens)
      assert is_integer(request_tokens)
      assert request_tokens > 0
    end

    test "streaming handles validation errors" do
      model = ModelFixtures.gpt4()
      request_body = %{"messages" => [%{"role" => "user", "content" => "Hello"}]}
      # Missing api_key
      opts = [url: "https://api.openai.com/v1/chat/completions"]

      result = HTTP.do_stream_request(TestProvider, model, request_body, opts)

      assert {:error, error} = result
      # The validation error happens in the streaming function's initial validation
      assert error.__struct__ == Parameter
      assert error.parameter == "api_key"
    end

    test "streaming middleware validation follows expected pattern" do
      model = ModelFixtures.gpt4()
      request_body = %{"messages" => [%{"role" => "user", "content" => "Error test"}]}
      # Missing api_key
      opts = [url: "https://api.openai.com/v1/chat/completions"]

      # Test non-streaming error (through full middleware)
      non_stream_result = HTTP.do_http_request(TestProvider, model, request_body, opts)
      assert {:error, non_stream_error} = non_stream_result

      # Test streaming error (direct validation in create_streaming_response)
      stream_result = HTTP.do_stream_request(TestProvider, model, request_body, opts)
      assert {:error, stream_error} = stream_result

      # Non-streaming goes through Transport middleware which converts to API.Request
      assert non_stream_error.__struct__ == Request
      # Streaming does direct validation which returns Parameter error
      assert stream_error.__struct__ == Parameter
    end
  end
end
