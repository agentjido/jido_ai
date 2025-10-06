defmodule Jido.AI.ReqLlmBridgeTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.ReqLlmBridge
  alias Jido.AI.ReqLlmBridge.Authentication

  setup :set_mimic_global

  setup do
    # Copy modules for mocking
    Mimic.copy(Authentication)
    :ok
  end

  describe "convert_messages/1" do
    test "converts single user message to string format" do
      messages = [%{role: :user, content: "Hello"}]
      result = ReqLlmBridge.convert_messages(messages)
      assert result == "Hello"
    end

    test "converts multiple messages to message format" do
      messages = [
        %{role: :system, content: "You are a helpful assistant"},
        %{role: :user, content: "Hello"},
        %{role: :assistant, content: "Hi there!"}
      ]

      result = ReqLlmBridge.convert_messages(messages)

      assert result == [
               %{role: :system, content: "You are a helpful assistant"},
               %{role: :user, content: "Hello"},
               %{role: :assistant, content: "Hi there!"}
             ]
    end
  end

  describe "convert_message/1" do
    test "converts message with role and content" do
      message = %{role: :user, content: "Test message"}
      result = ReqLlmBridge.convert_message(message)
      assert result == %{role: :user, content: "Test message"}
    end
  end

  describe "convert_response/1" do
    test "converts ReqLLM response to Jido AI format" do
      response = %{
        text: "Response content",
        usage: %{
          prompt_tokens: 10,
          completion_tokens: 5,
          total_tokens: 15
        },
        finish_reason: "stop"
      }

      result = ReqLlmBridge.convert_response(response)

      assert result.content == "Response content"
      assert result.usage.prompt_tokens == 10
      assert result.usage.completion_tokens == 5
      assert result.usage.total_tokens == 15
      assert result.finish_reason == "stop"
      assert result.tool_calls == []
    end

    test "handles response without usage information" do
      response = %{text: "Simple response"}
      result = ReqLlmBridge.convert_response(response)

      assert result.content == "Simple response"
      assert result.usage == nil
      assert result.tool_calls == []
    end

    test "extracts content from various response formats" do
      # Test different content field names
      assert ReqLlmBridge.convert_response(%{text: "from text"}).content == "from text"
      assert ReqLlmBridge.convert_response(%{content: "from content"}).content == "from content"
      assert ReqLlmBridge.convert_response(%{message: "from message"}).content == "from message"
      assert ReqLlmBridge.convert_response(%{}).content == ""
    end
  end

  describe "map_error/1" do
    test "maps ReqLLM error map to Jido AI format" do
      error = {:error, %{type: "http_error", message: "Request failed"}}
      result = ReqLlmBridge.map_error(error)

      assert {:error, mapped} = result
      assert mapped.reason == "http_error"
      assert mapped.details == "Request failed"
      assert mapped.original_error == %{type: "http_error", message: "Request failed"}
    end

    test "maps HTTP error to Jido AI format" do
      error = {:error, %{status: 400, body: "Bad Request"}}
      result = ReqLlmBridge.map_error(error)

      assert {:error, mapped} = result
      assert mapped.reason == "http_error"
      assert mapped.details == "HTTP 400: \"Bad Request\""
      assert mapped.status == 400
      assert mapped.body == "Bad Request"
    end

    test "maps string error to Jido AI format" do
      error = {:error, "Something went wrong"}
      result = ReqLlmBridge.map_error(error)

      assert {:error, mapped} = result
      assert mapped.reason == "req_llm_error"
      assert mapped.details == "Something went wrong"
    end

    test "maps unknown error to Jido AI format" do
      error = {:error, :unknown}
      result = ReqLlmBridge.map_error(error)

      assert {:error, mapped} = result
      assert mapped.reason == "unknown_error"
      assert mapped.details == ":unknown"
      assert mapped.original_error == :unknown
    end

    test "maps unexpected error format" do
      error = "not an error tuple"
      result = ReqLlmBridge.map_error(error)

      assert {:error, mapped} = result
      assert mapped.reason == "unexpected_error"
      assert String.contains?(mapped.details, "Unexpected error format")
      assert mapped.original_error == "not an error tuple"
    end
  end

  describe "build_req_llm_options/1" do
    test "extracts valid ReqLLM options from params" do
      params = %{
        temperature: 0.8,
        max_tokens: 100,
        top_p: 0.9,
        stop: ["END"],
        tools: [],
        tool_choice: "auto",
        # These should be filtered out
        messages: [],
        stream: true,
        other_param: "value"
      }

      result = ReqLlmBridge.build_req_llm_options(params)

      assert result == %{
               temperature: 0.8,
               max_tokens: 100,
               top_p: 0.9,
               stop: ["END"],
               tools: [],
               tool_choice: "auto"
             }
    end

    test "filters out nil values" do
      params = %{
        temperature: 0.8,
        max_tokens: nil,
        top_p: 0.9,
        stop: nil
      }

      result = ReqLlmBridge.build_req_llm_options(params)

      assert result == %{
               temperature: 0.8,
               top_p: 0.9
             }
    end
  end

  describe "convert_tools/1" do
    test "returns ok for empty tool list" do
      result = ReqLlmBridge.convert_tools([])
      assert {:ok, []} = result
    end

    test "handles conversion errors gracefully" do
      # Pass invalid tool modules
      result = ReqLlmBridge.convert_tools([NonExistentModule])
      assert {:error, error} = result
      assert error.reason == "tool_conversion_error"
      assert is_binary(error.details)
    end
  end

  describe "log_operation/3" do
    test "returns ok when called" do
      result = ReqLlmBridge.log_operation(:info, "Test message", module: __MODULE__)
      assert result == :ok
    end
  end

  describe "get_provider_key/3 - new authentication integration" do
    test "returns key when authentication succeeds" do
      expect(Authentication, :authenticate_for_provider, fn :openai, %{} ->
        {:ok, %{"authorization" => "Bearer sk-test"}, "sk-test"}
      end)

      result = ReqLlmBridge.get_provider_key(:openai, %{})
      assert result == "sk-test"
    end

    test "returns default when authentication fails" do
      expect(Authentication, :authenticate_for_provider, fn :openai, %{} ->
        {:error, "No key found"}
      end)

      result = ReqLlmBridge.get_provider_key(:openai, %{}, "fallback")
      assert result == "fallback"
    end

    test "passes through request options" do
      req_options = %{api_key: "override-key"}

      expect(Authentication, :authenticate_for_provider, fn :openai, ^req_options ->
        {:ok, %{"authorization" => "Bearer override-key"}, "override-key"}
      end)

      result = ReqLlmBridge.get_provider_key(:openai, req_options)
      assert result == "override-key"
    end
  end

  describe "get_provider_headers/2 - authentication headers" do
    test "returns authentication headers for provider" do
      expected_headers = %{"authorization" => "Bearer sk-test"}

      expect(Authentication, :get_authentication_headers, fn :openai, %{} ->
        expected_headers
      end)

      result = ReqLlmBridge.get_provider_headers(:openai, %{})
      assert result == expected_headers
    end

    test "returns provider-specific headers" do
      expected_headers = %{
        "x-api-key" => "sk-ant-test",
        "anthropic-version" => "2023-06-01"
      }

      expect(Authentication, :get_authentication_headers, fn :anthropic, %{} ->
        expected_headers
      end)

      result = ReqLlmBridge.get_provider_headers(:anthropic, %{})
      assert result == expected_headers
    end
  end

  describe "get_provider_authentication/2 - unified authentication" do
    test "returns both key and headers when successful" do
      expected_headers = %{"authorization" => "Bearer sk-test"}

      expect(Authentication, :authenticate_for_provider, fn :openai, %{} ->
        {:ok, expected_headers, "sk-test"}
      end)

      result = ReqLlmBridge.get_provider_authentication(:openai, %{})
      assert {:ok, {"sk-test", ^expected_headers}} = result
    end

    test "returns error when authentication fails" do
      expect(Authentication, :authenticate_for_provider, fn :openai, %{} ->
        {:error, "Authentication failed"}
      end)

      result = ReqLlmBridge.get_provider_authentication(:openai, %{})
      assert {:error, "Authentication failed"} = result
    end
  end

  describe "validate_provider_key/1 - authentication validation" do
    test "returns ok when authentication is valid" do
      expect(Authentication, :validate_authentication, fn :openai, %{} ->
        :ok
      end)

      result = ReqLlmBridge.validate_provider_key(:openai)
      assert {:ok, :available} = result
    end

    test "returns error when authentication is invalid" do
      expect(Authentication, :validate_authentication, fn :openai, %{} ->
        {:error, "No key found"}
      end)

      result = ReqLlmBridge.validate_provider_key(:openai)
      assert {:error, :missing_key} = result
    end
  end
end
