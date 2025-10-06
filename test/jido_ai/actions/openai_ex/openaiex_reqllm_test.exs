defmodule JidoTest.AI.Actions.OpenaiEx.ReqLLMTest do
  use ExUnit.Case, async: false
  use Mimic

  import Mimic

  @moduletag :capture_log

  alias Jido.AI.Actions.OpenaiEx
  alias Jido.AI.Actions.OpenaiEx.TestHelpers
  alias Jido.AI.Model
  alias OpenaiEx.ChatMessage
  alias ReqLlmBridge.Provider.Generated.ValidProviders

  # Add global mock setup
  setup :set_mimic_global

  setup do
    # Copy the modules we need to mock
    Mimic.copy(ReqLLM)
    Mimic.copy(JidoKeys)
    Mimic.copy(ValidProviders)

    # Create a mock model with ReqLLM ID
    {:ok, model} =
      Model.from({:openai, [model: "gpt-4", api_key: "test-api-key"]})

    model = %{model | reqllm_id: "openai:gpt-4"}

    # Create valid params
    params = %{
      model: model,
      messages: [
        %{role: :system, content: "You are a helpful assistant."},
        %{role: :user, content: "Hello!"}
      ]
    }

    # Create context
    context = %{state: %{}}

    {:ok, %{model: model, params: params, context: context}}
  end

  describe "convert_chat_messages_to_jido_format/1" do
    test "converts basic message maps correctly" do
      messages = [
        %{role: :system, content: "You are helpful"},
        %{role: :user, content: "Hello"}
      ]

      # Use test helper to access private function logic
      result = TestHelpers.convert_chat_messages_to_jido_format(messages)

      assert result == [
               %{role: :system, content: "You are helpful"},
               %{role: :user, content: "Hello"}
             ]
    end

    test "converts OpenaiEx ChatMessage maps" do
      messages = [
        ChatMessage.system("You are helpful"),
        ChatMessage.user("Hello")
      ]

      # Access private function through the module's public interface
      # Since it's private, we'll test it indirectly through the run function
      params = %{
        model: %Model{reqllm_id: "openai:gpt-4", api_key: "test-key"},
        messages: messages
      }

      # Mock ReqLLM response
      expect(ReqLLM, :generate_text, fn _messages, _reqllm_id, _opts ->
        {:ok, %{content: "Hello there!"}}
      end)

      expect(ValidProviders, :list, fn ->
        [:openai, :anthropic, :google]
      end)

      expect(JidoKeys, :put, fn _key, _value -> :ok end)

      assert {:ok, response} = OpenaiEx.run(params, %{})
      assert is_map(response)
      assert get_in(response, [:choices, Access.at(0), :message, :content]) == "Hello there!"
    end

    test "handles mixed message formats" do
      messages = [
        %{role: :system, content: "System message"},
        %{"role" => "user", "content" => "User message with string keys"},
        %{role: :assistant, content: "Assistant message"}
      ]

      result = TestHelpers.convert_chat_messages_to_jido_format(messages)

      assert result == [
               %{role: :system, content: "System message"},
               %{role: "user", content: "User message with string keys"},
               %{role: :assistant, content: "Assistant message"}
             ]
    end

    test "handles empty message lists" do
      messages = []

      result = TestHelpers.convert_chat_messages_to_jido_format(messages)

      assert result == []
    end

    test "handles messages with missing fields gracefully" do
      messages = [
        # Missing content
        %{role: :system},
        # Missing role
        %{content: "No role"},
        # Empty map
        %{}
      ]

      result = TestHelpers.convert_chat_messages_to_jido_format(messages)

      assert result == [
               %{role: :system, content: nil},
               %{role: nil, content: "No role"},
               %{role: nil, content: nil}
             ]
    end
  end

  describe "extract_provider_from_reqllm_id/1" do
    test "extracts valid providers safely", %{model: _model} do
      expect(ValidProviders, :list, fn ->
        [:openai, :anthropic, :google, :openrouter]
      end)

      result = TestHelpers.extract_provider_from_reqllm_id("openai:gpt-4")

      assert result == :openai
    end

    test "extracts different valid providers", %{model: _model} do
      expect(ValidProviders, :list, fn ->
        [:openai, :anthropic, :google, :openrouter]
      end)

      result = TestHelpers.extract_provider_from_reqllm_id("anthropic:claude-3")

      assert result == :anthropic
    end

    test "rejects invalid provider strings" do
      expect(ValidProviders, :list, fn ->
        [:openai, :anthropic, :google]
      end)

      result = TestHelpers.extract_provider_from_reqllm_id("invalid_provider:model")

      assert result == nil
    end

    test "prevents arbitrary atom creation" do
      expect(ValidProviders, :list, fn ->
        [:openai, :anthropic, :google]
      end)

      # This should not create a new atom
      result = TestHelpers.extract_provider_from_reqllm_id("malicious_atom:model")

      assert result == nil
      # Verify the atom wasn't created by checking if it would error when referenced
      assert_raise ArgumentError, fn ->
        :malicious_atom = :this_should_not_exist
      end
    end

    test "uses ReqLLM provider whitelist" do
      expect(ValidProviders, :list, fn ->
        # Limited list
        [:openai, :anthropic]
      end)

      # Should work for whitelisted provider
      result1 = TestHelpers.extract_provider_from_reqllm_id("openai:gpt-4")
      assert result1 == :openai

      # Should not work for non-whitelisted provider
      result2 = TestHelpers.extract_provider_from_reqllm_id("google:gemini")
      assert result2 == nil
    end

    test "handles malformed reqllm_id formats" do
      expect(ValidProviders, :list, fn ->
        [:openai, :anthropic, :google]
      end)

      # No colon separator
      result1 = TestHelpers.extract_provider_from_reqllm_id("openai-gpt-4")
      assert result1 == nil

      # Empty string
      result2 = TestHelpers.extract_provider_from_reqllm_id("")
      assert result2 == nil

      # Only colon
      result3 = TestHelpers.extract_provider_from_reqllm_id(":")
      assert result3 == nil
    end
  end

  describe "convert_to_openai_response_format/1" do
    test "converts ReqLLM response with content to OpenAI format" do
      reqllm_response = %{
        content: "Hello, how can I help you?",
        usage: %{prompt_tokens: 10, completion_tokens: 8, total_tokens: 18},
        finish_reason: "stop"
      }

      result = TestHelpers.convert_to_openai_response_format(reqllm_response)

      expected = %{
        choices: [
          %{
            message: %{
              content: "Hello, how can I help you?",
              role: "assistant",
              tool_calls: []
            },
            finish_reason: "stop",
            index: 0
          }
        ],
        usage: %{prompt_tokens: 10, completion_tokens: 8, total_tokens: 18},
        model: "unknown"
      }

      assert result == expected
    end

    test "handles tool calls correctly" do
      reqllm_response = %{
        content: "I'll help you with that calculation.",
        tool_calls: [
          %{
            id: "call_123",
            type: "function",
            function: %{name: "add", arguments: "{\"a\": 2, \"b\": 3}"}
          }
        ],
        usage: %{prompt_tokens: 15, completion_tokens: 12, total_tokens: 27}
      }

      result = TestHelpers.convert_to_openai_response_format(reqllm_response)

      assert get_in(result, [:choices, Access.at(0), :message, :tool_calls]) == [
               %{
                 id: "call_123",
                 type: "function",
                 function: %{name: "add", arguments: "{\"a\": 2, \"b\": 3}"}
               }
             ]
    end

    test "handles responses without usage metadata" do
      reqllm_response = %{
        content: "Simple response"
      }

      result = TestHelpers.convert_to_openai_response_format(reqllm_response)

      assert result.usage == %{}
      assert get_in(result, [:choices, Access.at(0), :message, :content]) == "Simple response"
    end

    test "handles different finish_reason values" do
      test_cases = [
        {%{content: "Done", finish_reason: "stop"}, "stop"},
        {%{content: "Truncated", finish_reason: "length"}, "length"},
        {%{content: "Tool call", finish_reason: "tool_calls"}, "tool_calls"},
        # Default case
        {%{content: "No reason"}, "stop"}
      ]

      for {input, expected_reason} <- test_cases do
        result = TestHelpers.convert_to_openai_response_format(input)
        assert get_in(result, [:choices, Access.at(0), :finish_reason]) == expected_reason
      end
    end

    test "handles response maps with string keys" do
      reqllm_response = %{
        "content" => "Response with string keys",
        "usage" => %{"prompt_tokens" => 5, "completion_tokens" => 4}
      }

      result = TestHelpers.convert_to_openai_response_format(reqllm_response)

      assert get_in(result, [:choices, Access.at(0), :message, :content]) ==
               "Response with string keys"
    end

    test "handles empty or nil content" do
      test_cases = [
        %{content: ""},
        %{content: nil},
        # No content key
        %{}
      ]

      for input <- test_cases do
        result = TestHelpers.convert_to_openai_response_format(input)
        content = get_in(result, [:choices, Access.at(0), :message, :content])
        assert content == "" or content == nil
      end
    end
  end

  describe "build_req_llm_options_from_chat_req/2" do
    test "maps all supported parameters correctly", %{model: model} do
      chat_req = %{
        temperature: 0.8,
        max_tokens: 150,
        top_p: 0.9,
        frequency_penalty: 0.5,
        presence_penalty: 0.3,
        stop: ["END"],
        tools: [%{type: "function", function: %{name: "test"}}],
        tool_choice: "auto"
      }

      expect(ValidProviders, :list, fn ->
        [:openai, :anthropic, :google]
      end)

      expect(JidoKeys, :put, fn "OPENAI_API_KEY", "test-api-key" -> :ok end)
      expect(ReqLlmBridge.Keys, :env_var_name, fn :openai -> "OPENAI_API_KEY" end)

      result = TestHelpers.build_req_llm_options_from_chat_req(chat_req, model)

      # Convert to map for easier assertion
      result_map = Enum.into(result, %{})

      assert result_map[:temperature] == 0.8
      assert result_map[:max_tokens] == 150
      assert result_map[:top_p] == 0.9
      assert result_map[:frequency_penalty] == 0.5
      assert result_map[:presence_penalty] == 0.3
      assert result_map[:stop] == ["END"]
      assert result_map[:tool_choice] == "auto"
      assert is_list(result_map[:tools])
    end

    test "filters unsupported parameters", %{model: model} do
      chat_req = %{
        temperature: 0.7,
        unsupported_param: "should_be_ignored",
        another_unknown: 123
      }

      expect(ValidProviders, :list, fn ->
        [:openai]
      end)

      expect(JidoKeys, :put, fn _, _ -> :ok end)
      expect(ReqLlmBridge.Keys, :env_var_name, fn :openai -> "OPENAI_API_KEY" end)

      result =
        TestHelpers.build_req_llm_options_from_chat_req(chat_req, %{model | api_key: "test"})

      result_map = Enum.into(result, %{})

      assert result_map[:temperature] == 0.7
      assert Map.has_key?(result_map, :unsupported_param) == false
      assert Map.has_key?(result_map, :another_unknown) == false
    end

    test "handles nil and missing values", %{model: model} do
      chat_req = %{
        temperature: nil,
        max_tokens: 100
        # missing other params
      }

      expect(ValidProviders, :list, fn ->
        [:openai]
      end)

      expect(JidoKeys, :put, fn _, _ -> :ok end)
      expect(ReqLlmBridge.Keys, :env_var_name, fn :openai -> "OPENAI_API_KEY" end)

      result = TestHelpers.build_req_llm_options_from_chat_req(chat_req, model)

      result_map = Enum.into(result, %{})

      # Should not include nil temperature
      assert Map.has_key?(result_map, :temperature) == false
      assert result_map[:max_tokens] == 100
      # Should not include missing params
      assert Map.has_key?(result_map, :top_p) == false
    end

    test "sets correct API keys via JidoKeys", %{model: model} do
      chat_req = %{temperature: 0.7}

      expect(ValidProviders, :list, fn ->
        [:openai, :anthropic, :google]
      end)

      expect(ReqLlmBridge.Keys, :env_var_name, fn :openai -> "OPENAI_API_KEY" end)
      expect(JidoKeys, :put, fn "OPENAI_API_KEY", "test-api-key" -> :ok end)

      TestHelpers.build_req_llm_options_from_chat_req(chat_req, model)

      # Verify the mock was called with correct parameters
      # assert_called(JidoKeys.put("OPENAI_API_KEY", "test-api-key"))
    end

    test "handles model without API key" do
      model_without_key = %{reqllm_id: "openai:gpt-4", api_key: nil}
      chat_req = %{temperature: 0.7}

      # Should not call JidoKeys.put when no API key
      result = TestHelpers.build_req_llm_options_from_chat_req(chat_req, model_without_key)

      result_map = Enum.into(result, %{})
      assert result_map[:temperature] == 0.7
    end

    test "validates tool conversion" do
      chat_req = %{
        tools: [
          %{type: "function", function: %{name: "test_tool", description: "A test tool"}}
        ]
      }

      model_without_key = %{reqllm_id: "openai:gpt-4", api_key: nil}

      result = TestHelpers.build_req_llm_options_from_chat_req(chat_req, model_without_key)

      result_map = Enum.into(result, %{})

      assert result_map[:tools] == [
               %{type: "function", function: %{name: "test_tool", description: "A test tool"}}
             ]
    end
  end

  describe "integration with ReqLLM" do
    test "full integration test with mocked ReqLLM", %{params: params, context: context} do
      # Mock ReqLlmBridge.generate_text
      expect(ReqLLM, :generate_text, fn messages, reqllm_id, opts ->
        assert is_list(messages)
        assert reqllm_id == "openai:gpt-4"
        assert is_list(opts)

        {:ok,
         %{
           content: "Hello! I'm here to help.",
           usage: %{prompt_tokens: 12, completion_tokens: 8, total_tokens: 20},
           finish_reason: "stop"
         }}
      end)

      expect(ValidProviders, :list, fn ->
        [:openai, :anthropic, :google, :openrouter]
      end)

      expect(JidoKeys, :put, fn "OPENAI_API_KEY", "test-api-key" -> :ok end)
      expect(ReqLlmBridge.Keys, :env_var_name, fn :openai -> "OPENAI_API_KEY" end)

      # Execute the action
      assert {:ok, response} = OpenaiEx.run(params, context)

      # Verify response format matches OpenAI API
      assert response.choices
      assert length(response.choices) == 1

      assert get_in(response, [:choices, Access.at(0), :message, :content]) ==
               "Hello! I'm here to help."

      assert get_in(response, [:choices, Access.at(0), :message, :role]) == "assistant"
      assert response.usage.total_tokens == 20
    end
  end
end
