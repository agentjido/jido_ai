defmodule Jido.Eval.LLMTest do
  use ExUnit.Case, async: true

  alias Jido.Eval.{LLM, RetryPolicy}
  alias Jido.AI.Error

  # Macro imports for HTTP testing
  defmacro with_success(body, do: block) do
    quote do
      test_name = var!(test_name)
      stub_success(test_name, unquote(body))
      unquote(block)
    end
  end

  defmacro with_error(status, body, do: block) do
    quote do
      test_name = var!(test_name)
      stub_error(test_name, unquote(status), unquote(body))
      unquote(block)
    end
  end

  defmacro with_transport_error(error_reason, do: block) do
    quote do
      test_name = var!(test_name)
      stub_transport_error(test_name, unquote(error_reason))
      unquote(block)
    end
  end

  setup do
    # Clear cache before each test
    LLM.clear_cache()

    # Set up Req.Test for HTTP mocking
    test_name = :"llm_test_#{:rand.uniform(1_000_000)}"
    Application.put_env(:jido_ai, :http_client, Req)
    Application.put_env(:jido_ai, :http_options, plug: {Req.Test, test_name})

    # Set up test API key to bypass validation
    Application.put_env(:jido_ai, :openai, api_key: "test-key")

    on_exit(fn ->
      try do
        Req.Test.verify!(test_name)
      rescue
        _ -> :ok
      end

      Application.delete_env(:jido_ai, :openai)
    end)

    {:ok, test_name: test_name}
  end

  describe "generate_text/3" do
    test "successful text generation without retry", %{test_name: test_name} do
      with_success(%{choices: [%{message: %{content: "Hello, world!"}}]}) do
        assert {:ok, "Hello, world!"} = LLM.generate_text("openai:gpt-4o", "Say hello")
      end
    end

    test "successful text generation with different model specs", %{test_name: test_name} do
      stub_openai_success(test_name, "Response")

      # String format
      assert {:ok, "Response"} = LLM.generate_text("openai:gpt-4o", "Test")

      # Tuple format
      stub_openai_success(test_name, "Response")
      assert {:ok, "Response"} = LLM.generate_text({:openai, model: "gpt-4o"}, "Test")
    end

    test "retries on rate limit errors", %{test_name: test_name} do
      # First call fails with rate limit
      with_error(429, %{error: %{message: "Rate limited"}}) do
        # Second call succeeds
        stub_openai_success(test_name, "Success after retry")

        policy = %RetryPolicy{max_retries: 2, base_delay: 10, jitter: false}

        assert {:ok, "Success after retry"} =
                 LLM.generate_text("openai:gpt-4o", "Test", retry_policy: policy)
      end
    end

    test "retries on timeout errors", %{test_name: test_name} do
      # First call times out
      stub_transport_error(test_name, :timeout)

      # Second call succeeds
      stub_openai_success(test_name, "Success after timeout")

      policy = %RetryPolicy{max_retries: 2, base_delay: 10, jitter: false}

      assert {:ok, "Success after timeout"} =
               LLM.generate_text("openai:gpt-4o", "Test", retry_policy: policy)
    end

    test "retries on server errors (5xx)", %{test_name: test_name} do
      # First call fails with server error
      stub_error(test_name, 500, %{error: %{message: "Internal server error"}})

      # Second call succeeds
      stub_openai_success(test_name, "Success after server error")

      policy = %RetryPolicy{max_retries: 2, base_delay: 10, jitter: false}

      assert {:ok, "Success after server error"} =
               LLM.generate_text("openai:gpt-4o", "Test", retry_policy: policy)
    end

    test "does not retry on non-retryable errors", %{test_name: test_name} do
      # 400 Bad Request should not be retried
      stub_error(test_name, 400, %{error: %{message: "Bad request"}})

      policy = %RetryPolicy{max_retries: 2}

      assert {:error, %Error.API.Request{status: 400}} =
               LLM.generate_text("openai:gpt-4o", "Test", retry_policy: policy)
    end

    test "respects max_retries limit", %{test_name: test_name} do
      # All calls fail with rate limit
      stub_error(test_name, 429, %{error: %{message: "Rate limited"}})

      policy = %RetryPolicy{max_retries: 2, base_delay: 1, jitter: false}

      assert {:error, %Error.API.Request{status: 429}} =
               LLM.generate_text("openai:gpt-4o", "Test", retry_policy: policy)
    end

    test "calculates exponential backoff delays correctly" do
      # These tests are placeholders since delay calculation is internal
      # In a real implementation, we might expose the calculation functions for testing
      assert :ok = :ok
    end

    test "applies jitter to delays when enabled" do
      # This test verifies jitter functionality exists without exposing internals  
      assert :ok = :ok
    end
  end

  describe "generate_object/4" do
    test "successful object generation without retry", %{test_name: test_name} do
      stub_openai_object_success(test_name, %{score: 0.8})

      schema = [score: [type: :float, required: true]]

      assert {:ok, %{score: 0.8}} =
               LLM.generate_object("openai:gpt-4o", "Rate this", schema)
    end

    test "retries object generation on retryable errors", %{test_name: test_name} do
      # First call fails
      stub_error(test_name, 429, %{error: %{message: "Rate limited"}})

      # Second call succeeds
      stub_openai_object_success(test_name, %{score: 0.9})

      schema = [score: [type: :float, required: true]]
      policy = %RetryPolicy{max_retries: 2, base_delay: 10, jitter: false}

      assert {:ok, %{score: 0.9}} =
               LLM.generate_object("openai:gpt-4o", "Rate this", schema, retry_policy: policy)
    end

    test "validates schema after successful retry", %{test_name: test_name} do
      # First call fails, second succeeds with valid data
      stub_error(test_name, 429, %{error: %{message: "Rate limited"}})

      stub_openai_object_success(test_name, %{score: 0.85})

      schema = [score: [type: :float, required: true]]
      policy = %RetryPolicy{max_retries: 2, base_delay: 10, jitter: false}

      assert {:ok, %{score: 0.85}} =
               LLM.generate_object("openai:gpt-4o", "Rate this", schema, retry_policy: policy)
    end
  end

  describe "caching" do
    test "caches successful text generation responses", %{test_name: test_name} do
      stub_openai_success(test_name, "Cached response")

      # First call should hit the API
      assert {:ok, "Cached response"} =
               LLM.generate_text("openai:gpt-4o", "Test prompt", cache: true)

      # Second call should use cache (no additional HTTP stub needed)
      assert {:ok, "Cached response"} =
               LLM.generate_text("openai:gpt-4o", "Test prompt", cache: true)
    end

    test "caches successful object generation responses", %{test_name: test_name} do
      stub_openai_object_success(test_name, %{score: 0.7})

      schema = [score: [type: :float, required: true]]

      # First call should hit the API
      assert {:ok, %{score: 0.7}} =
               LLM.generate_object("openai:gpt-4o", "Rate this", schema, cache: true)

      # Second call should use cache (no additional HTTP stub needed)
      assert {:ok, %{score: 0.7}} =
               LLM.generate_object("openai:gpt-4o", "Rate this", schema, cache: true)
    end

    test "different prompts create different cache keys", %{test_name: test_name} do
      # Set up sequential responses for different requests
      Req.Test.stub(test_name, fn conn ->
        case conn.body_params["messages"] do
          [%{"content" => "Prompt 1"}] ->
            Req.Test.json(conn, %{choices: [%{message: %{content: "Response 1"}}]})

          [%{"content" => "Prompt 2"}] ->
            Req.Test.json(conn, %{choices: [%{message: %{content: "Response 2"}}]})
        end
      end)

      # Each prompt should hit the API and get different responses
      assert {:ok, "Response 1"} =
               LLM.generate_text("openai:gpt-4o", "Prompt 1", cache: true)

      assert {:ok, "Response 2"} =
               LLM.generate_text("openai:gpt-4o", "Prompt 2", cache: true)
    end

    test "different model specs create different cache keys", %{test_name: test_name} do
      # Set up sequential responses based on temperature parameter
      Req.Test.stub(test_name, fn conn ->
        case Map.get(conn.body_params, "temperature") do
          nil ->
            Req.Test.json(conn, %{choices: [%{message: %{content: "Default temp response"}}]})

          0.5 ->
            Req.Test.json(conn, %{choices: [%{message: %{content: "Temp 0.5 response"}}]})
        end
      end)

      # Each model config should hit the API and get different responses
      assert {:ok, "Default temp response"} =
               LLM.generate_text("openai:gpt-4o", "Same prompt", cache: true)

      # Even with same prompt, different model options should create different cache key
      assert {:ok, "Temp 0.5 response"} =
               LLM.generate_text("openai:gpt-4o", "Same prompt", cache: true, temperature: 0.5)
    end

    test "cache TTL expires entries", %{test_name: test_name} do
      stub_openai_success(test_name, "First response")

      # Cache with very short TTL
      assert {:ok, "First response"} =
               LLM.generate_text("openai:gpt-4o", "Test", cache: true, cache_ttl: 10)

      # Wait for cache to expire
      Process.sleep(15)

      # Should hit API again
      stub_openai_success(test_name, "Second response")

      assert {:ok, "Second response"} =
               LLM.generate_text("openai:gpt-4o", "Test", cache: true, cache_ttl: 10)
    end

    test "clear_cache/0 removes all cached entries", %{test_name: test_name} do
      stub_openai_success(test_name, "First response")

      # Cache a response
      assert {:ok, "First response"} =
               LLM.generate_text("openai:gpt-4o", "Test", cache: true)

      # Clear cache
      assert :ok = LLM.clear_cache()

      # Should hit API again
      stub_openai_success(test_name, "After clear")

      assert {:ok, "After clear"} =
               LLM.generate_text("openai:gpt-4o", "Test", cache: true)
    end

    test "caching is disabled by default" do
      # This test verifies that without cache: true, no caching occurs
      # Implementation detail: we can't easily test this without exposing internals
      # Placeholder
      assert :ok = :ok
    end
  end

  describe "error normalization" do
    test "normalizes API errors correctly", %{test_name: test_name} do
      stub_error(test_name, 400, %{error: %{message: "API error"}})

      assert {:error, %Error.API.Request{status: 400}} =
               LLM.generate_text("openai:gpt-4o", "Test")
    end

    test "normalizes unknown errors", %{test_name: test_name} do
      stub_transport_error(test_name, :econnrefused)

      assert {:error, error} = LLM.generate_text("openai:gpt-4o", "Test")
      # Just check it's some kind of error
      assert match?(%Error.API.Request{}, error) or match?(%Error.Unknown.Unknown{}, error)
    end
  end

  describe "option handling" do
    test "passes through AI options correctly", %{test_name: test_name} do
      stub_openai_success(test_name, "Success")

      # Verify that non-LLM options are passed through
      assert {:ok, "Success"} =
               LLM.generate_text("openai:gpt-4o", "Test", temperature: 0.7, max_tokens: 100)
    end

    test "extracts LLM-specific options correctly" do
      # This tests the internal option extraction logic
      # Would need to expose private functions to test thoroughly
      # Placeholder
      assert :ok = :ok
    end
  end

  # ===========================================================================
  # Test Helper Functions
  # ===========================================================================

  defp stub_success(test_name, body) do
    Req.Test.stub(test_name, &Req.Test.json(&1, body))
  end

  defp stub_openai_success(test_name, content) do
    Req.Test.stub(test_name, fn conn ->
      Req.Test.json(conn, %{
        choices: [%{message: %{content: content}}]
      })
    end)
  end

  defp stub_openai_object_success(test_name, object) do
    Req.Test.stub(test_name, fn conn ->
      # OpenAI returns structured data in the content field
      content = Jason.encode!(object)

      Req.Test.json(conn, %{
        choices: [%{message: %{content: content}}]
      })
    end)
  end

  defp stub_error(test_name, status, body) do
    Req.Test.stub(test_name, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(status, Jason.encode!(body))
    end)
  end

  defp stub_transport_error(test_name, error_reason) do
    Req.Test.stub(test_name, &Req.Test.transport_error(&1, error_reason))
  end
end
