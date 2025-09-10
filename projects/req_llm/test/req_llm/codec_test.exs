defmodule ReqLLM.CodecTest do
  use ExUnit.Case, async: true

  alias ReqLLM.{Context, Message, StreamChunk, Codec}
  alias ReqLLM.Message.ContentPart

  describe "Anthropic codec protocol implementation" do
    test "encodes system message to top level" do
      context =
        Context.new([
          Context.system("You are a helpful assistant"),
          Context.user("Hello")
        ])

      tagged = %ReqLLM.Providers.Anthropic{context: context}
      encoded = Codec.encode(tagged)

      assert encoded.system == "You are a helpful assistant"
      assert length(encoded.messages) == 1
      assert hd(encoded.messages).role == "user"
    end

    test "extracts system message from mixed context" do
      context =
        Context.new([
          Context.user("Hi"),
          Context.system("You are helpful"),
          Context.assistant("How can I help?")
        ])

      tagged = %ReqLLM.Providers.Anthropic{context: context}
      encoded = Codec.encode(tagged)

      assert encoded.system == "You are helpful"
      assert length(encoded.messages) == 2
      assert Enum.map(encoded.messages, & &1.role) == ["user", "assistant"]
    end

    test "handles context without system message" do
      context =
        Context.new([
          Context.user("Hello"),
          Context.assistant("Hi there!")
        ])

      tagged = %ReqLLM.Providers.Anthropic{context: context}
      encoded = Codec.encode(tagged)

      refute Map.has_key?(encoded, :system)
      assert length(encoded.messages) == 2
    end

    test "rejects multiple system messages" do
      context =
        Context.new([
          Context.system("First system"),
          Context.system("Second system"),
          Context.user("Hello")
        ])

      tagged = %ReqLLM.Providers.Anthropic{context: context}

      assert_raise RuntimeError, "Multiple system messages not supported", fn ->
        Codec.encode(tagged)
      end
    end

    test "encodes text content parts" do
      context =
        Context.new([
          Context.user("Simple text message")
        ])

      tagged = %ReqLLM.Providers.Anthropic{context: context}
      encoded = Codec.encode(tagged)

      message = hd(encoded.messages)
      content = hd(message.content)

      assert content["type"] == "text"
      assert content["text"] == "Simple text message"
    end

    test "encodes image content parts" do
      image_part = ContentPart.image("base64data", "image/jpeg")
      message = %Message{role: :user, content: [image_part]}
      context = Context.new([message])

      tagged = %ReqLLM.Providers.Anthropic{context: context}
      encoded = Codec.encode(tagged)

      message = hd(encoded.messages)
      content = hd(message.content)

      assert content["type"] == "image"
      assert content["source"]["type"] == "base64"
      assert content["source"]["media_type"] == "image/jpeg"
      assert content["source"]["data"] == "base64data"
    end

    test "encodes tool_call content parts" do
      tool_part = ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"})
      message = %Message{role: :assistant, content: [tool_part]}
      context = Context.new([message])

      tagged = %ReqLLM.Providers.Anthropic{context: context}
      encoded = Codec.encode(tagged)

      message = hd(encoded.messages)
      content = hd(message.content)

      assert content["type"] == "tool_use"
      assert content["id"] == "call_123"
      assert content["name"] == "get_weather"
      assert content["input"] == %{location: "NYC"}
    end

    test "encodes mixed content parts in single message" do
      parts = [
        ContentPart.text("Check the weather: "),
        ContentPart.tool_call("call_456", "get_weather", %{city: "Boston"}),
        ContentPart.text(" Thank you!")
      ]

      message = %Message{role: :assistant, content: parts}
      context = Context.new([message])

      tagged = %ReqLLM.Providers.Anthropic{context: context}
      encoded = Codec.encode(tagged)

      message = hd(encoded.messages)
      content = message.content

      assert length(content) == 3
      assert Enum.at(content, 0)["type"] == "text"
      assert Enum.at(content, 1)["type"] == "tool_use"
      assert Enum.at(content, 2)["type"] == "text"
    end
  end

  describe "Anthropic response decoding" do
    test "decodes text content block" do
      response = %{"content" => [%{"type" => "text", "text" => "Hello world!"}]}
      tagged = %ReqLLM.Providers.Anthropic{context: response}

      chunks = Codec.decode(tagged)

      assert length(chunks) == 1
      assert hd(chunks) == StreamChunk.text("Hello world!")
    end

    test "decodes tool_use content block" do
      response = %{
        "content" => [
          %{
            "type" => "tool_use",
            "id" => "tool_123",
            "name" => "search",
            "input" => %{"query" => "Elixir"}
          }
        ]
      }

      tagged = %ReqLLM.Providers.Anthropic{context: response}

      chunks = Codec.decode(tagged)

      assert length(chunks) == 1
      chunk = hd(chunks)
      assert chunk.type == :tool_call
      assert chunk.name == "search"
      assert chunk.arguments == %{"query" => "Elixir"}
      assert chunk.metadata.id == "tool_123"
    end

    test "decodes thinking content block" do
      response = %{"content" => [%{"type" => "thinking", "text" => "Let me consider..."}]}
      tagged = %ReqLLM.Providers.Anthropic{context: response}

      chunks = Codec.decode(tagged)

      assert length(chunks) == 1
      assert hd(chunks) == StreamChunk.thinking("Let me consider...")
    end

    test "decodes mixed content blocks" do
      response = %{
        "content" => [
          %{"type" => "text", "text" => "I'll search for that: "},
          %{
            "type" => "tool_use",
            "id" => "search_001",
            "name" => "web_search",
            "input" => %{"query" => "Elixir programming"}
          },
          %{"type" => "text", "text" => " Done!"}
        ]
      }

      tagged = %ReqLLM.Providers.Anthropic{context: response}

      chunks = Codec.decode(tagged)

      assert length(chunks) == 3
      assert Enum.at(chunks, 0).type == :content
      assert Enum.at(chunks, 1).type == :tool_call
      assert Enum.at(chunks, 2).type == :content
    end

    test "ignores unknown content block types" do
      response = %{
        "content" => [
          %{"type" => "text", "text" => "Known type"},
          %{"type" => "unknown_type", "data" => "some data"},
          %{"type" => "text", "text" => "Another known"}
        ]
      }

      tagged = %ReqLLM.Providers.Anthropic{context: response}

      chunks = Codec.decode(tagged)

      assert length(chunks) == 2
      assert Enum.all?(chunks, &(&1.type == :content))
      assert Enum.map(chunks, & &1.text) == ["Known type", "Another known"]
    end
  end

  describe "round-trip compatibility" do
    test "Context -> Anthropic encoding -> StreamChunks" do
      # Create a context with multiple content types
      context =
        Context.new([
          Context.system("You are helpful"),
          Context.user("Please check the weather and tell me about it"),
          Context.assistant("I'll check that for you", %{thinking: "Need to call weather API"})
        ])

      # Encode to Anthropic format
      tagged = %ReqLLM.Providers.Anthropic{context: context}
      encoded = Codec.encode(tagged)

      # Verify encoding structure (only context-related fields)
      assert is_binary(encoded.system)
      assert is_list(encoded.messages)
      assert length(encoded.messages) == 2  # system extracted, 2 regular messages remain

      # Simulate response from Anthropic
      anthropic_response = %{
        "content" => [
          %{"type" => "text", "text" => "I'll check the weather for you."},
          %{
            "type" => "tool_use",
            "id" => "weather_call",
            "name" => "get_weather",
            "input" => %{"location" => "current"}
          }
        ]
      }

      # Decode back to StreamChunks
      response_tagged = %ReqLLM.Providers.Anthropic{context: anthropic_response}
      chunks = Codec.decode(response_tagged)

      # Verify decoded chunks
      assert length(chunks) == 2
      [text_chunk, tool_chunk] = chunks

      assert text_chunk.type == :content
      assert text_chunk.text == "I'll check the weather for you."

      assert tool_chunk.type == :tool_call
      assert tool_chunk.name == "get_weather"
      assert tool_chunk.arguments == %{"location" => "current"}
      assert tool_chunk.metadata.id == "weather_call"
    end

    test "preserves content ordering in round-trip" do
      parts = [
        ContentPart.text("First, "),
        ContentPart.tool_call("call_1", "action_a", %{param: 1}),
        ContentPart.text(" then "),
        ContentPart.tool_call("call_2", "action_b", %{param: 2}),
        ContentPart.text(" finally.")
      ]

      context = Context.new([%Message{role: :assistant, content: parts}])

      # Encode
      tagged = %ReqLLM.Providers.Anthropic{context: context}
      encoded = Codec.encode(tagged)

      message_content = hd(encoded.messages).content
      assert length(message_content) == 5

      # Verify order and types
      types = Enum.map(message_content, & &1["type"])
      assert types == ["text", "tool_use", "text", "tool_use", "text"]
    end
  end

  describe "Tagged wrapper integration" do
    test "wraps context with Tagged struct" do
      context = Context.new([Context.user("Hello")])

      # Test that the Tagged wrapper works directly
      # (Provider behavior integration would be tested in provider tests)
      wrapped = %ReqLLM.Providers.Anthropic{context: context}

      assert %ReqLLM.Providers.Anthropic{context: ^context} = wrapped
    end
  end

  describe "error cases and edge cases" do
    test "handles empty context" do
      context = Context.new([])
      tagged = %ReqLLM.Providers.Anthropic{context: context}

      encoded = Codec.encode(tagged)

      refute Map.has_key?(encoded, :system)
      assert encoded.messages == []
    end

    test "handles system-only context" do
      context = Context.new([Context.system("System prompt only")])
      tagged = %ReqLLM.Providers.Anthropic{context: context}

      encoded = Codec.encode(tagged)

      assert encoded.system == "System prompt only"
      assert encoded.messages == []
    end

    test "handles empty content parts" do
      message = %Message{role: :user, content: []}
      context = Context.new([message])
      tagged = %ReqLLM.Providers.Anthropic{context: context}

      encoded = Codec.encode(tagged)

      message = hd(encoded.messages)
      assert message.content == []
    end

    test "codec returns error for unsupported tagged types" do
      unsupported_data = %{some: "data"}

      result = Codec.encode(unsupported_data)
      assert result == {:error, :not_implemented}

      result = Codec.decode(unsupported_data)
      assert result == {:error, :not_implemented}
    end

    test "decodes empty response content" do
      response = %{"content" => []}
      tagged = %ReqLLM.Providers.Anthropic{context: response}

      chunks = Codec.decode(tagged)

      assert chunks == []
    end

    test "handles malformed content parts gracefully" do
      # Missing required fields
      response = %{
        "content" => [
          # Missing text field
          %{"type" => "text"},
          # Missing required fields
          %{"type" => "tool_use"},
          %{"type" => "text", "text" => "Valid content"}
        ]
      }

      tagged = %ReqLLM.Providers.Anthropic{context: response}

      # Should not crash and should return valid chunks only
      chunks = Codec.decode(tagged)

      assert length(chunks) == 1
      assert hd(chunks).text == "Valid content"
    end
  end
end
