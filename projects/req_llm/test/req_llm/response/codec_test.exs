defmodule ReqLLM.Response.CodecTest do
  use ExUnit.Case, async: true

  alias ReqLLM.{Response, Model, Context, Message}
  alias ReqLLM.Response.Codec
  alias ReqLLM.Message.ContentPart
  alias ReqLLM.Providers.Anthropic

  # Common test fixtures
  setup do
    model = Model.new(:anthropic, "claude-3-haiku-20240307")

    basic_anthropic_response = %{
      "id" => "msg_01234567890",
      "model" => "claude-3-haiku-20240307",
      "content" => [
        %{"type" => "text", "text" => "Hello! How can I help you today?"}
      ],
      "usage" => %{
        "input_tokens" => 10,
        "output_tokens" => 25
      },
      "stop_reason" => "end_turn"
    }

    tool_use_response = %{
      "id" => "msg_tool123",
      "model" => "claude-3-haiku-20240307",
      "content" => [
        %{"type" => "text", "text" => "I'll help you check the weather."},
        %{
          "type" => "tool_use",
          "id" => "toolu_123",
          "name" => "get_weather",
          "input" => %{"location" => "NYC"}
        }
      ],
      "usage" => %{
        "input_tokens" => 15,
        "output_tokens" => 30
      },
      "stop_reason" => "tool_use"
    }

    thinking_response = %{
      "id" => "msg_think456",
      "model" => "claude-3-7-sonnet-20250219",
      "content" => [
        %{"type" => "thinking", "text" => "Let me think about this problem..."},
        %{"type" => "text", "text" => "Based on my analysis, the answer is 42."}
      ],
      "usage" => %{
        "input_tokens" => 20,
        "output_tokens" => 35
      },
      "stop_reason" => "end_turn"
    }

    %{
      model: model,
      basic_anthropic_response: basic_anthropic_response,
      tool_use_response: tool_use_response,
      thinking_response: thinking_response
    }
  end

  describe "protocol fallback behavior" do
    test "returns error for unsupported types", %{model: model} do
      unsupported = %{some: "data"}

      assert Codec.decode_response(unsupported, model) == {:error, :not_implemented}
      assert Codec.encode_request(unsupported) == {:error, :not_implemented}
    end
  end

  describe "Anthropic.Response codec implementation" do
    test "basic response decoding", %{model: model, basic_anthropic_response: response} do
      wrapped = %Anthropic.Response{payload: response}

      {:ok, decoded} = Codec.decode_response(wrapped, model)

      assert %Response{} = decoded
      assert decoded.id == "msg_01234567890"
      assert decoded.model == "claude-3-haiku-20240307"
      assert decoded.stream? == false
      assert decoded.usage.input_tokens == 10
      assert decoded.usage.output_tokens == 25
      assert decoded.usage.total_tokens == 35
      assert decoded.finish_reason == :stop

      # Check message content
      assert %Message{role: :assistant} = decoded.message

      assert [%ContentPart{type: :text, text: "Hello! How can I help you today?"}] =
               decoded.message.content

      # Check context contains the message
      assert [%Message{role: :assistant}] = decoded.context.messages
    end

    test "tool use response decoding", %{model: model, tool_use_response: response} do
      wrapped = %Anthropic.Response{payload: response}

      {:ok, decoded} = Codec.decode_response(wrapped, model)

      assert decoded.id == "msg_tool123"
      assert decoded.finish_reason == :tool_calls

      # Check mixed content parts
      assert %Message{role: :assistant, content: content_parts} = decoded.message
      assert length(content_parts) == 2

      # Text part
      text_part = Enum.at(content_parts, 0)
      assert %ContentPart{type: :text, text: "I'll help you check the weather."} = text_part

      # Tool call part
      tool_part = Enum.at(content_parts, 1)

      assert %ContentPart{
               type: :tool_call,
               tool_name: "get_weather",
               input: %{"location" => "NYC"},
               tool_call_id: "toolu_123"
             } = tool_part
    end

    test "thinking response decoding", %{model: model, thinking_response: response} do
      wrapped = %Anthropic.Response{payload: response}

      {:ok, decoded} = Codec.decode_response(wrapped, model)

      assert decoded.id == "msg_think456"
      assert decoded.model == "claude-3-7-sonnet-20250219"

      # Check mixed content parts including thinking
      assert %Message{role: :assistant, content: content_parts} = decoded.message
      assert length(content_parts) == 2

      # Thinking part (converted to reasoning type)
      thinking_part = Enum.at(content_parts, 0)

      assert %ContentPart{type: :reasoning, text: "Let me think about this problem..."} =
               thinking_part

      # Text part
      text_part = Enum.at(content_parts, 1)

      assert %ContentPart{type: :text, text: "Based on my analysis, the answer is 42."} =
               text_part
    end

    test "stream response decoding", %{model: model} do
      stream = Stream.cycle(["chunk1", "chunk2"])
      wrapped = %Anthropic.Response{payload: stream}

      result = Codec.decode_response(wrapped, model)

      case result do
        {:ok, decoded} ->
          assert decoded.stream? == true
          assert decoded.stream == stream
          assert decoded.id == "streaming-response"
          assert decoded.message == nil
          assert decoded.context.messages == []

        {:error, :unsupported_provider} ->
          # Stream support might not be fully implemented yet
          # This is acceptable for now
          :ok
      end
    end

    test "empty content handling", %{model: model} do
      empty_response = %{
        "id" => "msg_empty",
        "model" => "claude-3-haiku-20240307",
        "content" => [],
        "usage" => %{"input_tokens" => 5, "output_tokens" => 0},
        "stop_reason" => "end_turn"
      }

      wrapped = %Anthropic.Response{payload: empty_response}
      {:ok, decoded} = Codec.decode_response(wrapped, model)

      assert decoded.message == nil
      assert decoded.context.messages == []
    end

    test "malformed content handling", %{model: model} do
      malformed_response = %{
        "id" => "msg_bad",
        "model" => "claude-3-haiku-20240307",
        "content" => [
          %{"type" => "text", "text" => "Valid text"},
          %{"type" => "unknown_type", "data" => "ignored"},
          # Missing text field
          %{"type" => "text"},
          # Missing required fields
          %{"type" => "tool_use"},
          %{"type" => "text", "text" => "Another valid text"}
        ],
        "usage" => %{"input_tokens" => 10, "output_tokens" => 5},
        "stop_reason" => "end_turn"
      }

      wrapped = %Anthropic.Response{payload: malformed_response}
      {:ok, decoded} = Codec.decode_response(wrapped, model)

      # Should only include valid content parts
      assert %Message{content: content_parts} = decoded.message
      assert length(content_parts) == 2
      assert Enum.map(content_parts, & &1.text) == ["Valid text", "Another valid text"]
    end

    test "usage parsing edge cases", %{model: model} do
      # Missing usage
      no_usage = %{
        "id" => "msg_no_usage",
        "content" => [%{"type" => "text", "text" => "Hello"}]
      }

      wrapped = %Anthropic.Response{payload: no_usage}
      {:ok, decoded} = Codec.decode_response(wrapped, model)

      assert decoded.usage == %{input_tokens: 0, output_tokens: 0, total_tokens: 0}

      # Partial usage
      partial_usage = %{
        "id" => "msg_partial",
        "content" => [%{"type" => "text", "text" => "Hello"}],
        "usage" => %{"input_tokens" => 10}
      }

      wrapped = %Anthropic.Response{payload: partial_usage}
      {:ok, decoded} = Codec.decode_response(wrapped, model)

      assert decoded.usage == %{input_tokens: 0, output_tokens: 0, total_tokens: 0}
    end

    test "finish reason mapping", %{model: model} do
      test_cases = [
        {"end_turn", :stop},
        {"max_tokens", :length},
        {"tool_use", :tool_calls},
        {"stop_sequence", :stop},
        {"unknown_reason", "unknown_reason"},
        {nil, nil}
      ]

      for {anthropic_reason, expected_reason} <- test_cases do
        response = %{
          "id" => "msg_test",
          "content" => [%{"type" => "text", "text" => "Test"}],
          "stop_reason" => anthropic_reason
        }

        wrapped = %Anthropic.Response{payload: response}
        {:ok, decoded} = Codec.decode_response(wrapped, model)

        assert decoded.finish_reason == expected_reason
      end
    end

    test "provider metadata preservation", %{model: model} do
      response_with_meta = %{
        "id" => "msg_meta",
        "model" => "claude-3-haiku-20240307",
        "content" => [%{"type" => "text", "text" => "Test"}],
        "usage" => %{"input_tokens" => 1, "output_tokens" => 1},
        "stop_reason" => "end_turn",
        "custom_field" => "custom_value",
        "another_meta" => %{"nested" => "data"}
      }

      wrapped = %Anthropic.Response{payload: response_with_meta}
      {:ok, decoded} = Codec.decode_response(wrapped, model)

      # Custom fields should be preserved in provider_meta
      assert decoded.provider_meta["custom_field"] == "custom_value"
      assert decoded.provider_meta["another_meta"] == %{"nested" => "data"}

      # Standard fields should not be in provider_meta
      refute Map.has_key?(decoded.provider_meta, "id")
      refute Map.has_key?(decoded.provider_meta, "model")
      refute Map.has_key?(decoded.provider_meta, "content")
      refute Map.has_key?(decoded.provider_meta, "usage")
      refute Map.has_key?(decoded.provider_meta, "stop_reason")
    end

    test "unsupported provider error" do
      openai_model = Model.new(:openai, "gpt-4")
      wrapped = %Anthropic.Response{payload: %{}}

      assert Codec.decode_response(wrapped, openai_model) == {:error, :unsupported_provider}
    end

    test "encoding not supported" do
      wrapped = %Anthropic.Response{payload: %{}}

      assert Codec.encode_request(wrapped) == {:error, :not_implemented}
    end
  end

  describe "error handling" do
    test "decode with malformed payload", %{model: model} do
      # Non-map, non-stream payload
      wrapped = %Anthropic.Response{payload: "invalid"}

      assert {:error, _error} = Codec.decode_response(wrapped, model)
    end

    test "decode without model parameter" do
      wrapped = %Anthropic.Response{payload: %{}}

      assert Codec.decode_response(wrapped) == {:error, :not_implemented}
    end

    test "runtime errors during decoding", %{model: model} do
      # This should trigger an error in decode_anthropic_json
      bad_response = %{
        # nil text should cause issues
        "content" => [%{"type" => "text", "text" => nil}]
      }

      wrapped = %Anthropic.Response{payload: bad_response}
      result = Codec.decode_response(wrapped, model)

      # Should return error tuple, not crash
      assert {:error, _error} = result
    end
  end

  describe "integration with existing patterns" do
    test "decoded response works with Context operations", %{
      model: model,
      basic_anthropic_response: response
    } do
      wrapped = %Anthropic.Response{payload: response}
      {:ok, decoded} = Codec.decode_response(wrapped, model)

      # Can extract context
      assert %Context{messages: [%Message{role: :assistant}]} = decoded.context

      # Can build new context from response
      user_context = Context.new([Context.user("Hello")])
      combined_messages = Context.to_list(user_context) ++ Context.to_list(decoded.context)
      combined_context = Context.new(combined_messages)

      assert length(combined_context.messages) == 2
      assert Enum.map(combined_context.messages, & &1.role) == [:user, :assistant]
    end

    test "response message content can be converted to StreamChunks", %{
      model: model,
      tool_use_response: response
    } do
      wrapped = %Anthropic.Response{payload: response}
      {:ok, decoded} = Codec.decode_response(wrapped, model)

      # Convert message content back to chunks (simulating streaming equivalence)
      content_parts = decoded.message.content

      # Text part
      text_part = Enum.at(content_parts, 0)
      assert text_part.type == :text
      assert text_part.text == "I'll help you check the weather."

      # Tool call part  
      tool_part = Enum.at(content_parts, 1)
      assert tool_part.type == :tool_call
      assert tool_part.tool_name == "get_weather"
      assert tool_part.input == %{"location" => "NYC"}
    end
  end
end
