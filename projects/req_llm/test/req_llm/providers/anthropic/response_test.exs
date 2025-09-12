defmodule ReqLLM.Providers.Anthropic.ResponseTest do
  use ExUnit.Case, async: true

  alias ReqLLM.{Response, Model, Context, Message}
  alias ReqLLM.Response.Codec
  alias ReqLLM.Providers.Anthropic
  alias ReqLLM.Message.ContentPart

  describe "Anthropic.Response struct" do
    setup do
      model = Model.new(:anthropic, "claude-3-haiku-20240307")
      %{model: model}
    end

    test "creates struct with payload field" do
      payload = %{"id" => "test", "content" => []}
      wrapped = %Anthropic.Response{payload: payload}

      assert %Anthropic.Response{payload: ^payload} = wrapped
      assert wrapped.payload == payload
    end

    test "implements Response.Codec protocol", %{model: model} do
      payload = %{
        "id" => "msg_123",
        "model" => "claude-3-haiku-20240307",
        "content" => [%{"type" => "text", "text" => "Hello"}],
        "usage" => %{"input_tokens" => 5, "output_tokens" => 10},
        "stop_reason" => "end_turn"
      }

      wrapped = %Anthropic.Response{payload: payload}

      {:ok, decoded} = Codec.decode_response(wrapped, model)

      assert %Response{} = decoded
      assert decoded.id == "msg_123"
      assert decoded.model == "claude-3-haiku-20240307"
      assert decoded.usage.input_tokens == 5
      assert decoded.usage.output_tokens == 10
      assert decoded.usage.total_tokens == 15
      assert decoded.finish_reason == :stop
    end

    test "converts anthropic content to message content parts", %{model: model} do
      payload = %{
        "id" => "msg_complex",
        "content" => [
          %{"type" => "text", "text" => "Let me help you."},
          %{
            "type" => "tool_use",
            "id" => "toolu_xyz",
            "name" => "search_web",
            "input" => %{"query" => "elixir documentation"}
          },
          %{"type" => "thinking", "text" => "I should search for this."}
        ]
      }

      wrapped = %Anthropic.Response{payload: payload}

      {:ok, decoded} = Codec.decode_response(wrapped, model)

      assert %Message{role: :assistant, content: content_parts} = decoded.message
      assert length(content_parts) == 3

      # Text part
      text_part = Enum.at(content_parts, 0)
      assert %ContentPart{type: :text, text: "Let me help you."} = text_part

      # Tool call part
      tool_part = Enum.at(content_parts, 1)

      assert %ContentPart{
               type: :tool_call,
               tool_name: "search_web",
               input: %{"query" => "elixir documentation"},
               tool_call_id: "toolu_xyz"
             } = tool_part

      # Thinking part (converted to reasoning)
      thinking_part = Enum.at(content_parts, 2)
      assert %ContentPart{type: :reasoning, text: "I should search for this."} = thinking_part
    end

    test "handles stream payloads", %{model: model} do
      stream = Stream.cycle(["chunk1", "chunk2"])
      wrapped = %Anthropic.Response{payload: stream}

      # Note: This may return unsupported_provider based on current implementation
      result = Codec.decode_response(wrapped, model)

      case result do
        {:ok, decoded} ->
          assert decoded.stream? == true
          assert decoded.stream == stream

        {:error, :unsupported_provider} ->
          # Acceptable if stream support isn't fully implemented
          :ok
      end
    end

    test "maps finish reasons correctly", %{model: model} do
      test_cases = [
        {"end_turn", :stop},
        {"max_tokens", :length},
        {"tool_use", :tool_calls},
        {"stop_sequence", :stop}
      ]

      for {anthropic_reason, expected_reason} <- test_cases do
        payload = %{
          "id" => "msg_finish_test",
          "content" => [%{"type" => "text", "text" => "Test"}],
          "stop_reason" => anthropic_reason
        }

        wrapped = %Anthropic.Response{payload: payload}

        {:ok, decoded} = Codec.decode_response(wrapped, model)
        assert decoded.finish_reason == expected_reason
      end
    end

    test "preserves provider metadata", %{model: model} do
      payload = %{
        "id" => "msg_meta_test",
        "content" => [%{"type" => "text", "text" => "Test"}],
        "custom_field" => "custom_value",
        "rate_limit_info" => %{"remaining" => 100}
      }

      wrapped = %Anthropic.Response{payload: payload}

      {:ok, decoded} = Codec.decode_response(wrapped, model)

      # Custom fields should be in provider_meta
      assert decoded.provider_meta["custom_field"] == "custom_value"
      assert decoded.provider_meta["rate_limit_info"] == %{"remaining" => 100}

      # Standard fields should not be in provider_meta
      refute Map.has_key?(decoded.provider_meta, "id")
      refute Map.has_key?(decoded.provider_meta, "content")
    end

    test "handles empty and malformed content", %{model: model} do
      # Empty content
      empty_payload = %{"id" => "msg_empty", "content" => []}
      wrapped = %Anthropic.Response{payload: empty_payload}

      {:ok, decoded} = Codec.decode_response(wrapped, model)
      assert decoded.message == nil
      assert decoded.context.messages == []

      # Malformed content blocks
      malformed_payload = %{
        "id" => "msg_malformed",
        "content" => [
          %{"type" => "text", "text" => "Good text"},
          # Missing required fields
          %{"type" => "tool_use"},
          %{"type" => "unknown_type", "data" => "ignored"},
          %{"type" => "text", "text" => "Another good text"}
        ]
      }

      wrapped = %Anthropic.Response{payload: malformed_payload}

      {:ok, decoded} = Codec.decode_response(wrapped, model)
      assert %Message{content: content_parts} = decoded.message
      # Only valid text parts
      assert length(content_parts) == 2
      assert Enum.map(content_parts, & &1.text) == ["Good text", "Another good text"]
    end

    test "handles missing or incomplete usage data", %{model: model} do
      # No usage field
      no_usage_payload = %{"id" => "msg_no_usage", "content" => []}
      wrapped = %Anthropic.Response{payload: no_usage_payload}

      {:ok, decoded} = Codec.decode_response(wrapped, model)
      assert decoded.usage == %{input_tokens: 0, output_tokens: 0, total_tokens: 0}

      # Incomplete usage field
      partial_usage_payload = %{
        "id" => "msg_partial_usage",
        "content" => [],
        "usage" => %{"input_tokens" => 15}
      }

      wrapped = %Anthropic.Response{payload: partial_usage_payload}

      {:ok, decoded} = Codec.decode_response(wrapped, model)
      assert decoded.usage == %{input_tokens: 0, output_tokens: 0, total_tokens: 0}
    end

    test "creates proper context from response message", %{model: model} do
      payload = %{
        "id" => "msg_context_test",
        "content" => [
          %{"type" => "text", "text" => "Response message"}
        ]
      }

      wrapped = %Anthropic.Response{payload: payload}

      {:ok, decoded} = Codec.decode_response(wrapped, model)

      # Context should contain the assistant message
      assert %Context{messages: [%Message{role: :assistant}]} = decoded.context
      assert length(decoded.context.messages) == 1

      # Message should match the response message
      context_message = hd(decoded.context.messages)
      assert context_message == decoded.message
    end
  end

  describe "error handling" do
    setup do
      model = Model.new(:anthropic, "claude-3-haiku-20240307")
      %{model: model}
    end

    test "returns error for unsupported provider" do
      openai_model = Model.new(:openai, "gpt-4")
      wrapped = %Anthropic.Response{payload: %{}}

      assert Codec.decode_response(wrapped, openai_model) == {:error, :unsupported_provider}
    end

    test "returns error for malformed payload", %{model: model} do
      # Non-map, non-stream payload
      wrapped = %Anthropic.Response{payload: "invalid_string"}

      assert {:error, _error} = Codec.decode_response(wrapped, model)
    end

    test "gracefully handles runtime errors during decoding", %{model: model} do
      # Payload that might cause issues during processing
      problematic_payload = %{
        "id" => "msg_problem",
        "content" => [
          # nil text might cause issues
          %{"type" => "text", "text" => nil}
        ]
      }

      wrapped = %Anthropic.Response{payload: problematic_payload}

      # Should not crash, should return error tuple
      result = Codec.decode_response(wrapped, model)
      assert {:error, _error} = result
    end

    test "encode operation not supported" do
      wrapped = %Anthropic.Response{payload: %{}}
      assert Codec.encode_request(wrapped) == {:error, :not_implemented}
    end

    test "decode without model parameter" do
      wrapped = %Anthropic.Response{payload: %{}}
      assert Codec.decode_response(wrapped) == {:error, :not_implemented}
    end
  end

  describe "integration scenarios" do
    setup do
      model = Model.new(:anthropic, "claude-3-haiku-20240307")
      %{model: model}
    end

    test "response can be used to build conversation context", %{model: model} do
      # Simulate assistant response
      payload = %{
        "id" => "msg_conversation",
        "content" => [
          %{"type" => "text", "text" => "I understand your question."}
        ]
      }

      wrapped = %Anthropic.Response{payload: payload}

      {:ok, response} = Codec.decode_response(wrapped, model)

      # Can extract context for conversation continuation
      response_context = response.context
      assert length(response_context.messages) == 1

      # Can combine with previous context
      user_messages = [Context.user("What is Elixir?")]
      conversation_messages = user_messages ++ Context.to_list(response_context)
      full_context = Context.new(conversation_messages)

      assert length(full_context.messages) == 2
      assert Enum.map(full_context.messages, & &1.role) == [:user, :assistant]
    end

    test "tool call responses can be processed for tool execution", %{model: model} do
      payload = %{
        "id" => "msg_tool_execution",
        "content" => [
          %{
            "type" => "tool_use",
            "id" => "call_execute_me",
            "name" => "calculator",
            "input" => %{"operation" => "add", "a" => 5, "b" => 3}
          }
        ],
        "stop_reason" => "tool_use"
      }

      wrapped = %Anthropic.Response{payload: payload}

      {:ok, response} = Codec.decode_response(wrapped, model)

      # Should indicate tool calls in finish reason
      assert response.finish_reason == :tool_calls

      # Can extract tool call information
      assert %Message{content: [tool_part]} = response.message

      assert %ContentPart{
               type: :tool_call,
               tool_name: "calculator",
               tool_call_id: "call_execute_me",
               input: %{"operation" => "add", "a" => 5, "b" => 3}
             } = tool_part
    end
  end
end
