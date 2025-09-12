defmodule ReqLLM.Providers.Anthropic.ContextTest do
  use ExUnit.Case, async: true

  alias ReqLLM.{Context, Message}
  alias ReqLLM.Context.Codec
  alias ReqLLM.Providers.Anthropic
  alias ReqLLM.Message.ContentPart

  describe "Anthropic.Context struct" do
    test "creates struct with context field" do
      context = Context.new([Context.user("Hello")])
      wrapped = %Anthropic.Context{context: context}

      assert %Anthropic.Context{context: ^context} = wrapped
      assert wrapped.context == context
    end

    test "implements Context.Codec protocol" do
      context = Context.new([Context.user("Hello world")])
      wrapped = %Anthropic.Context{context: context}

      # Should be able to encode
      encoded = Codec.encode_request(wrapped)

      assert is_map(encoded)
      assert encoded.messages
      assert length(encoded.messages) == 1
      assert hd(encoded.messages).role == "user"
      # Anthropic uses content array format
      assert hd(encoded.messages).content == [%{"type" => "text", "text" => "Hello world"}]
    end

    test "handles system message extraction" do
      context =
        Context.new([
          Context.system("You are helpful"),
          Context.user("Hi there")
        ])

      wrapped = %Anthropic.Context{context: context}

      encoded = Codec.encode_request(wrapped)

      assert encoded.system == "You are helpful"
      assert length(encoded.messages) == 1
      assert hd(encoded.messages).role == "user"
    end

    test "converts complex content parts correctly" do
      parts = [
        ContentPart.text("Check this: "),
        ContentPart.image("base64data", "image/jpeg"),
        ContentPart.tool_call("call_123", "get_info", %{query: "test"})
      ]

      message = %Message{role: :user, content: parts}
      context = Context.new([message])
      wrapped = %Anthropic.Context{context: context}

      encoded = Codec.encode_request(wrapped)
      content = hd(encoded.messages).content

      # Should have 3 content parts
      assert length(content) == 3

      # Text part
      assert Enum.at(content, 0) == %{"type" => "text", "text" => "Check this: "}

      # Image part
      image_part = Enum.at(content, 1)
      assert image_part["type"] == "image"
      assert image_part["source"]["data"] == "base64data"
      assert image_part["source"]["media_type"] == "image/jpeg"

      # Tool call part
      tool_part = Enum.at(content, 2)
      assert tool_part["type"] == "tool_use"
      assert tool_part["id"] == "call_123"
      assert tool_part["name"] == "get_info"
      assert tool_part["input"] == %{query: "test"}
    end

    test "can decode anthropic response format" do
      response_data = %{
        "content" => [
          %{"type" => "text", "text" => "Here's the result"},
          %{
            "type" => "tool_use",
            "id" => "tool_abc",
            "name" => "calculator",
            "input" => %{"expression" => "2+2"}
          }
        ]
      }

      wrapped = %Anthropic.Context{context: response_data}
      chunks = Codec.decode_response(wrapped)

      assert length(chunks) == 2

      # Text chunk
      text_chunk = Enum.at(chunks, 0)
      assert text_chunk.type == :content
      assert text_chunk.text == "Here's the result"

      # Tool call chunk
      tool_chunk = Enum.at(chunks, 1)
      assert tool_chunk.type == :tool_call
      assert tool_chunk.name == "calculator"
      assert tool_chunk.arguments == %{"expression" => "2+2"}
      assert tool_chunk.metadata.id == "tool_abc"
    end

    test "handles edge cases gracefully" do
      # Empty context
      empty_context = Context.new([])
      wrapped = %Anthropic.Context{context: empty_context}
      encoded = Codec.encode_request(wrapped)

      assert encoded.messages == []
      refute Map.has_key?(encoded, :system)

      # Malformed response data
      bad_response = %{"content" => [%{"type" => "unknown"}]}
      wrapped = %Anthropic.Context{context: bad_response}
      chunks = Codec.decode_response(wrapped)

      assert chunks == []
    end

    test "preserves thinking content blocks" do
      response_with_thinking = %{
        "content" => [
          %{"type" => "thinking", "text" => "Let me analyze this..."},
          %{"type" => "text", "text" => "The answer is 42."}
        ]
      }

      wrapped = %Anthropic.Context{context: response_with_thinking}
      chunks = Codec.decode_response(wrapped)

      assert length(chunks) == 2

      thinking_chunk = Enum.at(chunks, 0)
      assert thinking_chunk.type == :thinking
      assert thinking_chunk.text == "Let me analyze this..."

      text_chunk = Enum.at(chunks, 1)
      assert text_chunk.type == :content
      assert text_chunk.text == "The answer is 42."
    end
  end

  describe "provider-specific behavior" do
    test "rejects multiple system messages" do
      context =
        Context.new([
          Context.system("First system"),
          Context.system("Second system"),
          Context.user("Hello")
        ])

      wrapped = %Anthropic.Context{context: context}

      assert_raise RuntimeError, "Multiple system messages not supported", fn ->
        Codec.encode_request(wrapped)
      end
    end

    test "handles image_url to image conversion" do
      image_url_part = ContentPart.image_url("data:image/jpeg;base64,iVBORw0KGgo=")
      message = %Message{role: :user, content: [image_url_part]}
      context = Context.new([message])
      wrapped = %Anthropic.Context{context: context}

      encoded = Codec.encode_request(wrapped)
      content_part = hd(hd(encoded.messages).content)

      assert content_part["type"] == "image"
      assert content_part["source"]["type"] == "base64"
      assert content_part["source"]["data"] == "iVBORw0KGgo="
      assert content_part["source"]["media_type"] == "image/jpeg"
    end

    test "orders content parts consistently" do
      # Mixed content that should maintain order
      parts = [
        ContentPart.text("Step 1"),
        ContentPart.tool_call("call_a", "action_a", %{}),
        ContentPart.text("Step 2"),
        ContentPart.tool_call("call_b", "action_b", %{}),
        ContentPart.text("Done")
      ]

      message = %Message{role: :assistant, content: parts}
      context = Context.new([message])
      wrapped = %Anthropic.Context{context: context}

      encoded = Codec.encode_request(wrapped)
      content = hd(encoded.messages).content
      types = Enum.map(content, & &1["type"])

      assert types == ["text", "tool_use", "text", "tool_use", "text"]
    end
  end
end
