defmodule ReqLLM.Context.CodecTest do
  use ExUnit.Case, async: true

  alias ReqLLM.{Context, Message, StreamChunk}
  alias ReqLLM.Context.Codec
  alias ReqLLM.Message.ContentPart
  alias ReqLLM.Providers.{OpenAI}
  alias ReqLLM.Providers.Anthropic

  # Common test fixtures
  setup do
    simple_context = Context.new([Context.user("Hello")])

    system_context =
      Context.new([
        Context.system("You are helpful"),
        Context.user("Hi"),
        Context.assistant("How can I help?")
      ])

    mixed_content_parts = [
      ContentPart.text("Check weather: "),
      ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"}),
      ContentPart.text(" Done!")
    ]

    complex_context =
      Context.new([
        Context.system("System prompt"),
        %Message{role: :user, content: [ContentPart.text("User message")]},
        %Message{role: :assistant, content: mixed_content_parts}
      ])

    %{
      simple_context: simple_context,
      system_context: system_context,
      complex_context: complex_context,
      mixed_content_parts: mixed_content_parts
    }
  end

  describe "protocol fallback behavior" do
    test "returns error for unsupported types" do
      unsupported = %{some: "data"}

      assert Codec.encode_request(unsupported) == {:error, :not_implemented}
      assert Codec.decode_response(unsupported) == {:error, :not_implemented}
    end
  end

  describe "Anthropic codec implementation" do
    test "basic encoding", %{simple_context: context} do
      tagged = %Anthropic.Context{context: context}
      encoded = Codec.encode_request(tagged)

      assert length(encoded.messages) == 1
      assert hd(encoded.messages).role == "user"
      refute Map.has_key?(encoded, :system)
    end

    test "system message extraction", %{system_context: context} do
      tagged = %Anthropic.Context{context: context}
      encoded = Codec.encode_request(tagged)

      assert encoded.system == "You are helpful"
      assert length(encoded.messages) == 2
      assert Enum.map(encoded.messages, & &1.role) == ["user", "assistant"]
    end

    test "rejects multiple system messages" do
      context =
        Context.new([
          Context.system("First"),
          Context.system("Second"),
          Context.user("Hello")
        ])

      tagged = %Anthropic.Context{context: context}

      assert_raise RuntimeError, "Multiple system messages not supported", fn ->
        Codec.encode_request(tagged)
      end
    end

    test "content part encoding - text, image, tool_call", %{mixed_content_parts: parts} do
      image_part = ContentPart.image("base64data", "image/jpeg")
      all_parts = [ContentPart.text("Text")] ++ [image_part] ++ parts

      message = %Message{role: :user, content: all_parts}
      context = Context.new([message])
      tagged = %Anthropic.Context{context: context}
      encoded = Codec.encode_request(tagged)

      content = hd(encoded.messages).content
      assert length(content) == 5

      # Text part
      assert Enum.at(content, 0) == %{"type" => "text", "text" => "Text"}

      # Image part  
      image_encoded = Enum.at(content, 1)
      assert image_encoded["type"] == "image"
      assert image_encoded["source"]["type"] == "base64"
      assert image_encoded["source"]["media_type"] == "image/jpeg"
      assert image_encoded["source"]["data"] == "base64data"

      # Tool call part
      tool_encoded = Enum.at(content, 3)
      assert tool_encoded["type"] == "tool_use"
      assert tool_encoded["id"] == "call_123"
      assert tool_encoded["name"] == "get_weather"
      assert tool_encoded["input"] == %{location: "NYC"}
    end

    test "image_url type encoding for compatibility" do
      image_url_part = ContentPart.image_url("data:image/png;base64,iVBORw0KGgo=")
      message = %Message{role: :user, content: [image_url_part]}
      context = Context.new([message])
      tagged = %Anthropic.Context{context: context}
      encoded = Codec.encode_request(tagged)

      content = hd(hd(encoded.messages).content)
      assert content["type"] == "image"
      assert content["source"]["type"] == "base64"
      assert content["source"]["data"] == "iVBORw0KGgo="
    end

    test "response decoding - text, tool_use, thinking" do
      response = %{
        "content" => [
          %{"type" => "text", "text" => "Hello!"},
          %{
            "type" => "tool_use",
            "id" => "tool_1",
            "name" => "search",
            "input" => %{"q" => "test"}
          },
          %{"type" => "thinking", "text" => "Let me think..."}
        ]
      }

      tagged = %Anthropic.Context{context: response}
      chunks = Codec.decode_response(tagged)

      assert length(chunks) == 3
      assert Enum.at(chunks, 0) == StreamChunk.text("Hello!")

      tool_chunk = Enum.at(chunks, 1)
      assert tool_chunk.type == :tool_call
      assert tool_chunk.name == "search"
      assert tool_chunk.arguments == %{"q" => "test"}
      assert tool_chunk.metadata.id == "tool_1"

      assert Enum.at(chunks, 2) == StreamChunk.thinking("Let me think...")
    end

    test "decoding ignores unknown content blocks and malformed data" do
      response = %{
        "content" => [
          %{"type" => "text", "text" => "Valid"},
          %{"type" => "unknown_type", "data" => "ignored"},
          # Missing text field
          %{"type" => "text"},
          # Missing required fields
          %{"type" => "tool_use"},
          %{"type" => "text", "text" => "Also valid"}
        ]
      }

      tagged = %Anthropic.Context{context: response}
      chunks = Codec.decode_response(tagged)

      assert length(chunks) == 2
      assert Enum.map(chunks, & &1.text) == ["Valid", "Also valid"]
    end

    test "empty context and edge cases" do
      # Empty context
      empty_context = Context.new([])
      tagged = %Anthropic.Context{context: empty_context}
      encoded = Codec.encode_request(tagged)
      assert encoded.messages == []
      refute Map.has_key?(encoded, :system)

      # System-only context
      system_only = Context.new([Context.system("Only system")])
      tagged = %Anthropic.Context{context: system_only}
      encoded = Codec.encode_request(tagged)
      assert encoded.system == "Only system"
      assert encoded.messages == []

      # Empty content parts
      empty_message = %Message{role: :user, content: []}
      context = Context.new([empty_message])
      tagged = %Anthropic.Context{context: context}
      encoded = Codec.encode_request(tagged)
      assert hd(encoded.messages).content == []

      # Empty response
      empty_response = %{"content" => []}
      tagged = %Anthropic.Context{context: empty_response}
      chunks = Codec.decode_response(tagged)
      assert chunks == []
    end
  end

  describe "OpenAI codec implementation" do
    test "basic encoding", %{simple_context: context} do
      tagged = %OpenAI{context: context}
      encoded = Codec.encode_request(tagged)

      assert length(encoded.messages) == 1
      assert hd(encoded.messages)["role"] == "user"
      assert hd(encoded.messages)["content"] == "Hello"
    end

    test "system message handling", %{system_context: context} do
      tagged = %OpenAI{context: context}
      encoded = Codec.encode_request(tagged)

      assert length(encoded.messages) == 3
      roles = Enum.map(encoded.messages, & &1["role"])
      assert roles == ["system", "user", "assistant"]
    end

    test "content encoding - single text vs multi-part" do
      # Single text becomes string
      single_text = Context.new([Context.user("Simple")])
      tagged = %OpenAI{context: single_text}
      encoded = Codec.encode_request(tagged)
      assert hd(encoded.messages)["content"] == "Simple"

      # Multi-part becomes array
      parts = [ContentPart.text("Text"), ContentPart.image("data", "image/png")]
      multi_message = %Message{role: :user, content: parts}
      multi_context = Context.new([multi_message])
      tagged = %OpenAI{context: multi_context}
      encoded = Codec.encode_request(tagged)

      content = hd(encoded.messages)["content"]
      assert is_list(content)
      assert length(content) == 2
    end

    test "content part encoding - image, image_url, tool_call" do
      parts = [
        ContentPart.image("base64data", "image/jpeg"),
        ContentPart.image_url("https://example.com/image.jpg"),
        ContentPart.tool_call("call_1", "search", %{q: "test"})
      ]

      message = %Message{role: :assistant, content: parts}
      context = Context.new([message])
      tagged = %OpenAI{context: context}
      encoded = Codec.encode_request(tagged)

      content = hd(encoded.messages)["content"]
      assert length(content) == 3

      # Image with data
      image_part = Enum.at(content, 0)
      assert image_part["type"] == "image_url"
      assert image_part["image_url"]["url"] == "data:image/jpeg;base64,base64data"

      # Image URL
      image_url_part = Enum.at(content, 1)
      assert image_url_part["type"] == "image_url"
      assert image_url_part["image_url"]["url"] == "https://example.com/image.jpg"

      # Tool call
      tool_part = Enum.at(content, 2)
      assert tool_part["type"] == "function"
      assert tool_part["function"]["name"] == "search"
      assert tool_part["function"]["arguments"] == ~s|{"q":"test"}|
      assert tool_part["id"] == "call_1"
    end

    test "response decoding - text and tool calls" do
      # Text response
      text_response = %{"choices" => [%{"message" => %{"content" => "Hello world"}}]}
      tagged = %OpenAI{context: text_response}
      chunks = Codec.decode_response(tagged)
      assert length(chunks) == 1
      assert hd(chunks) == StreamChunk.text("Hello world")

      # Tool calls response
      tool_response = %{
        "choices" => [
          %{
            "message" => %{
              "tool_calls" => [
                %{
                  "id" => "call_1",
                  "function" => %{
                    "name" => "get_weather",
                    "arguments" => ~s|{"location":"NYC"}|
                  }
                }
              ]
            }
          }
        ]
      }

      tagged = %OpenAI{context: tool_response}
      chunks = Codec.decode_response(tagged)
      assert length(chunks) == 1

      chunk = hd(chunks)
      assert chunk.type == :tool_call
      assert chunk.name == "get_weather"
      assert chunk.arguments == %{"location" => "NYC"}
      assert chunk.metadata.id == "call_1"
    end

    test "response decoding edge cases" do
      # Empty content
      empty_response = %{"choices" => [%{"message" => %{"content" => ""}}]}
      tagged = %OpenAI{context: empty_response}
      chunks = Codec.decode_response(tagged)
      assert chunks == []

      # Invalid JSON in tool arguments
      bad_json_response = %{
        "choices" => [
          %{
            "message" => %{
              "tool_calls" => [
                %{
                  "id" => "call_1",
                  "function" => %{
                    "name" => "test",
                    "arguments" => "invalid json {"
                  }
                }
              ]
            }
          }
        ]
      }

      tagged = %OpenAI{context: bad_json_response}
      chunks = Codec.decode_response(tagged)
      assert length(chunks) == 1
      assert hd(chunks).arguments == %{}

      # Malformed responses
      malformed = %{"choices" => [%{"message" => %{}}]}
      tagged = %OpenAI{context: malformed}
      chunks = Codec.decode_response(tagged)
      assert chunks == []
    end
  end

  describe "round-trip data integrity" do
    test "Anthropic encode-decode preserves content types", %{complex_context: context} do
      # Encode to Anthropic format
      tagged = %Anthropic.Context{context: context}
      encoded = Codec.encode_request(tagged)

      # Verify encoding structure
      assert encoded.system == "System prompt"
      assert length(encoded.messages) == 2

      # Check content ordering preservation
      assistant_content = Enum.at(encoded.messages, 1).content
      assert length(assistant_content) == 3
      types = Enum.map(assistant_content, & &1["type"])
      assert types == ["text", "tool_use", "text"]

      # Simulate Anthropic response with similar content
      response_data = %{
        "content" => [
          %{"type" => "text", "text" => "I'll help you"},
          %{
            "type" => "tool_use",
            "id" => "new_call",
            "name" => "search",
            "input" => %{"q" => "help"}
          }
        ]
      }

      # Decode response
      response_tagged = %Anthropic.Context{context: response_data}
      chunks = Codec.decode_response(response_tagged)

      assert length(chunks) == 2
      assert Enum.at(chunks, 0).type == :content
      assert Enum.at(chunks, 1).type == :tool_call
      assert Enum.at(chunks, 1).name == "search"
    end

    test "OpenAI encode-decode preserves message structure", %{system_context: context} do
      # Encode to OpenAI format
      tagged = %OpenAI{context: context}
      encoded = Codec.encode_request(tagged)

      assert length(encoded.messages) == 3
      roles = Enum.map(encoded.messages, & &1["role"])
      assert roles == ["system", "user", "assistant"]

      # Simulate OpenAI response
      response_data = %{
        "choices" => [
          %{
            "message" => %{
              "content" => "I'm here to help you with anything you need."
            }
          }
        ]
      }

      # Decode response
      response_tagged = %OpenAI{context: response_data}
      chunks = Codec.decode_response(response_tagged)

      assert length(chunks) == 1
      assert hd(chunks).type == :content
      assert hd(chunks).text == "I'm here to help you with anything you need."
    end

    test "content ordering consistency across providers" do
      # Create mixed content message
      parts = [
        ContentPart.text("Step 1: "),
        ContentPart.tool_call("call_a", "action_a", %{param: "a"}),
        ContentPart.text(" Step 2: "),
        ContentPart.tool_call("call_b", "action_b", %{param: "b"}),
        ContentPart.text(" Done!")
      ]

      message = %Message{role: :assistant, content: parts}
      context = Context.new([message])

      # Test Anthropic ordering
      anthropic_tagged = %Anthropic.Context{context: context}
      anthropic_encoded = Codec.encode_request(anthropic_tagged)
      anthropic_content = hd(anthropic_encoded.messages).content
      anthropic_types = Enum.map(anthropic_content, & &1["type"])
      assert anthropic_types == ["text", "tool_use", "text", "tool_use", "text"]

      # Test OpenAI ordering  
      openai_tagged = %OpenAI{context: context}
      openai_encoded = Codec.encode_request(openai_tagged)
      openai_content = hd(openai_encoded.messages)["content"]
      openai_types = Enum.map(openai_content, & &1["type"])
      # OpenAI uses "function" instead of "tool_use"
      expected_openai = ["text", "function", "text", "function", "text"]
      assert openai_types == expected_openai
    end

    test "unicode and special characters preservation" do
      unicode_text = "Hello 世界! Emoji: 🌍 Math: ∑∞ Special: <>&\"'"
      context = Context.new([Context.user(unicode_text)])

      # Test Anthropic
      anthropic_tagged = %Anthropic.Context{context: context}
      anthropic_encoded = Codec.encode_request(anthropic_tagged)
      assert hd(hd(anthropic_encoded.messages).content)["text"] == unicode_text

      # Test OpenAI
      openai_tagged = %OpenAI{context: context}
      openai_encoded = Codec.encode_request(openai_tagged)
      assert hd(openai_encoded.messages)["content"] == unicode_text
    end

    test "large payload handling" do
      # Create large content
      # ~20KB
      large_text = String.duplicate("Large content block. ", 1000)
      large_context = Context.new([Context.user(large_text)])

      # Should encode without issues
      anthropic_tagged = %Anthropic.Context{context: large_context}
      anthropic_encoded = Codec.encode_request(anthropic_tagged)
      encoded_text = hd(hd(anthropic_encoded.messages).content)["text"]
      assert String.length(encoded_text) > 15000
      assert encoded_text == large_text

      openai_tagged = %OpenAI{context: large_context}
      openai_encoded = Codec.encode_request(openai_tagged)
      assert hd(openai_encoded.messages)["content"] == large_text
    end
  end

  describe "error handling and validation" do
    test "malformed context structures" do
      # Context with nil messages should not crash encoding
      try do
        bad_context = %Context{messages: nil}
        tagged = %Anthropic.Context{context: bad_context}
        # This might raise but shouldn't crash the VM
        Codec.encode_request(tagged)
      rescue
        # Expected to fail gracefully
        _ -> :ok
      end
    end

    test "provider-specific error scenarios" do
      # Test tool call with missing fields
      incomplete_tool = %Message.ContentPart{
        type: :tool_call,
        tool_name: "test",
        input: %{},
        # Missing ID
        tool_call_id: nil
      }

      message = %Message{role: :assistant, content: [incomplete_tool]}
      context = Context.new([message])

      # Should encode without crashing (providers handle missing fields)
      anthropic_tagged = %Anthropic.Context{context: context}
      anthropic_encoded = Codec.encode_request(anthropic_tagged)
      assert is_map(anthropic_encoded)

      openai_tagged = %OpenAI{context: context}
      openai_encoded = Codec.encode_request(openai_tagged)
      assert is_map(openai_encoded)
    end
  end
end
