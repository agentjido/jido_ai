defmodule Jido.AI.Middleware.TokenCounterTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Middleware
  alias Jido.AI.Middleware.Context
  alias Jido.AI.{Middleware, Middleware.Context, Middleware.TokenCounter, Model}

  setup do
    model = %Model{provider: :openai, model: "gpt-4"}
    {:ok, model: model}
  end

  describe "request phase token counting" do
    test "counts tokens in request messages", %{model: model} do
      body = %{
        "model" => "gpt-4",
        "messages" => [
          %{"role" => "system", "content" => "You are a helpful assistant"},
          %{"role" => "user", "content" => "Hello world"}
        ]
      }

      context = Context.new(:request, model, body, [])

      result_context =
        TokenCounter.call(context, fn ctx ->
          # Simulate next middleware just passing through
          ctx
        end)

      request_tokens = Context.get_meta(result_context, :request_tokens)
      assert is_integer(request_tokens)
      assert request_tokens > 0
      # Should include message content + overhead
      assert request_tokens > 15
    end

    test "handles empty request body", %{model: model} do
      body = %{}
      context = Context.new(:request, model, body, [])

      result_context = TokenCounter.call(context, fn ctx -> ctx end)

      request_tokens = Context.get_meta(result_context, :request_tokens)
      assert request_tokens == 0
    end

    test "preserves existing metadata", %{model: model} do
      body = %{"messages" => [%{"role" => "user", "content" => "Hello"}]}

      context =
        Context.new(:request, model, body, [])
        |> Context.put_meta(:existing_key, "existing_value")

      result_context = TokenCounter.call(context, fn ctx -> ctx end)

      assert Context.get_meta(result_context, :existing_key) == "existing_value"
      assert is_integer(Context.get_meta(result_context, :request_tokens))
    end
  end

  describe "response phase token counting" do
    test "counts tokens in response choices", %{model: model} do
      body = %{
        "choices" => [
          %{"message" => %{"content" => "Hello there, how can I help you today?"}}
        ]
      }

      context = Context.new(:response, model, body, [])

      result_context =
        TokenCounter.call(context, fn ctx ->
          # Simulate next middleware just passing through
          ctx
        end)

      response_tokens = Context.get_meta(result_context, :response_tokens)
      assert is_integer(response_tokens)
      assert response_tokens > 5
    end

    test "handles multiple choices", %{model: model} do
      body = %{
        "choices" => [
          %{"message" => %{"content" => "Response one"}},
          %{"message" => %{"content" => "Response two"}}
        ]
      }

      context = Context.new(:response, model, body, [])

      result_context = TokenCounter.call(context, fn ctx -> ctx end)

      response_tokens = Context.get_meta(result_context, :response_tokens)
      assert is_integer(response_tokens)
      assert response_tokens > 4
    end

    test "handles empty response body", %{model: model} do
      body = %{}
      context = Context.new(:response, model, body, [])

      result_context = TokenCounter.call(context, fn ctx -> ctx end)

      response_tokens = Context.get_meta(result_context, :response_tokens)
      assert response_tokens == 0
    end
  end

  describe "middleware integration" do
    test "integrates with middleware pipeline", %{model: model} do
      request_body = %{
        "messages" => [
          %{"role" => "user", "content" => "Hello world"}
        ]
      }

      response_body = %{
        "choices" => [
          %{"message" => %{"content" => "Hello there!"}}
        ]
      }

      context = Context.new(:request, model, request_body, [])

      # Simulate a complete middleware pipeline
      final_context =
        Middleware.run([TokenCounter], context, fn ctx ->
          # Simulate API call - switch to response phase and update body
          ctx
          |> Context.put_phase(:response)
          |> Context.put_body(response_body)
        end)

      # Both request and response tokens should be counted
      request_tokens = Context.get_meta(final_context, :request_tokens)
      response_tokens = Context.get_meta(final_context, :response_tokens)

      assert is_integer(request_tokens)
      assert is_integer(response_tokens)
      assert request_tokens > 0
      assert response_tokens > 0
    end

    test "works with other middleware", %{model: model} do
      # Simple test middleware that adds a marker
      defmodule TestMiddleware do
        @behaviour Middleware

        def call(context, next) do
          context = Context.put_meta(context, :test_marker, true)
          next.(context)
        end
      end

      request_body = %{"messages" => [%{"role" => "user", "content" => "Test"}]}
      context = Context.new(:request, model, request_body, [])

      final_context =
        Middleware.run([TestMiddleware, TokenCounter], context, fn ctx ->
          ctx |> Context.put_phase(:response) |> Context.put_body(%{"choices" => []})
        end)

      # Both middleware should have run
      assert Context.get_meta(final_context, :test_marker) == true
      assert is_integer(Context.get_meta(final_context, :request_tokens))
    end
  end

  describe "behaviour compliance" do
    test "implements Middleware behaviour" do
      assert TokenCounter.__info__(:attributes)
             |> Keyword.get_values(:behaviour)
             |> List.flatten()
             |> Enum.member?(Middleware)
    end

    test "validates as proper middleware" do
      assert Middleware.validate_middlewares([TokenCounter]) == :ok
    end
  end

  describe "edge cases" do
    test "handles nil body gracefully", %{model: model} do
      context = Context.new(:request, model, nil, [])

      # Should not crash
      result_context = TokenCounter.call(context, fn ctx -> ctx end)

      request_tokens = Context.get_meta(result_context, :request_tokens)
      assert request_tokens == 0
    end

    test "handles context with existing token counts", %{model: model} do
      body = %{"messages" => [%{"role" => "user", "content" => "Hello"}]}

      context =
        Context.new(:request, model, body, [])
        # Pre-existing value
        |> Context.put_meta(:request_tokens, 999)

      result_context = TokenCounter.call(context, fn ctx -> ctx end)

      # Should overwrite with actual count
      request_tokens = Context.get_meta(result_context, :request_tokens)
      assert request_tokens != 999
      assert is_integer(request_tokens)
    end
  end
end
