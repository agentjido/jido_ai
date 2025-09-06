defmodule ReqAI.MessageTest do
  use ExUnit.Case, async: true

  alias ReqAI.{Message, ContentPart}

  doctest Message

  # 4 constructor tests (user, assistant, system, tool_result helper functions)
  describe "constructors" do
    test "new/3 creates basic user and system messages" do
      user_msg = Message.new(:user, "Hello")
      assert %Message{role: :user, content: "Hello", metadata: nil} = user_msg

      system_msg = Message.new(:system, "You are helpful")
      assert %Message{role: :system, content: "You are helpful"} = system_msg
    end

    test "assistant_with_tools/3 creates assistant message with tools" do
      tool_calls = [ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"})]
      message = Message.assistant_with_tools("I'll check the weather.", tool_calls)

      assert %Message{role: :assistant} = message
      assert [text_part | tool_parts] = message.content
      assert %ContentPart{type: :text, text: "I'll check the weather."} = text_part
      assert tool_parts == tool_calls
    end

    test "user_multimodal/2 creates user message with content parts" do
      content_parts = [
        ContentPart.text("Describe this:"),
        ContentPart.image_url("https://example.com/image.png")
      ]

      message = Message.user_multimodal(content_parts)
      assert %Message{role: :user, content: ^content_parts} = message
    end

    test "tool_result/4 creates tool result message" do
      message = Message.tool_result("call_123", "get_weather", %{temperature: 72})

      assert %Message{role: :tool, tool_call_id: "call_123"} = message
      assert [result_part] = message.content
      assert %ContentPart{type: :tool_result, output: %{temperature: 72}} = result_part
    end
  end

  # 2 validation tests
  describe "validation" do
    test "valid?/1 validates message structure and content" do
      assert Message.valid?(Message.new(:user, "Hello"))
      assert Message.valid?(Message.new(:assistant, "Hi there"))
      assert Message.valid?(Message.new(:tool, "Result", tool_call_id: "call_123"))

      content_parts = [
        ContentPart.text("Hello"),
        ContentPart.image_url("https://example.com/image.png")
      ]

      assert Message.valid?(Message.new(:user, content_parts))
    end

    test "valid?/1 rejects invalid messages" do
      refute Message.valid?(Message.new(:user, ""))
      refute Message.valid?(Message.new(:user, []))
      # tool role needs tool_call_id
      refute Message.valid?(Message.new(:tool, "Result"))
      # not a Message struct
      refute Message.valid?(%{role: :user, content: "Hello"})
      refute Message.valid?(nil)

      invalid_parts = [ContentPart.text("Hello"), %ContentPart{type: :text, text: ""}]
      refute Message.valid?(Message.new(:user, invalid_parts))
    end
  end

  # 2 Enumerable protocol tests
  describe "Enumerable protocol" do
    test "implements basic enumerable functions" do
      message = Message.new(:user, "Hello")

      assert Enumerable.count(message) == {:ok, 1}
      assert Enumerable.member?(message, message) == {:error, Enumerable.ReqAI.Message}
      assert Enumerable.slice(message) == {:error, Enumerable.ReqAI.Message}
    end

    test "implements reduce/3 correctly" do
      message = Message.new(:user, "Hello")

      # Test continuation
      result = Enumerable.reduce(message, {:cont, []}, fn msg, acc -> {:cont, [msg | acc]} end)
      assert {:cont, [message]} = result

      # Test halt
      result = Enumerable.reduce(message, {:halt, []}, fn _msg, acc -> {:cont, acc} end)
      assert {:halted, []} = result
    end
  end

  # 2 provider_options & edge case tests
  describe "provider_options and edge cases" do
    test "provider_options/1 extracts metadata correctly" do
      assert Message.provider_options(Message.new(:user, "Hello")) == %{}

      options = %{openai: %{reasoning_effort: "low"}}
      message = Message.new(:user, "Hello", metadata: %{provider_options: options})
      assert Message.provider_options(message) == options
    end

    test "handles complex multi-modal and tool interaction scenarios" do
      # Multi-modal message
      content_parts = [
        ContentPart.text("Analyze this:"),
        ContentPart.file(<<1, 2, 3>>, "application/json", "data.json"),
        ContentPart.image_url("https://example.com/chart.png")
      ]

      assert Message.valid?(Message.new(:user, content_parts))

      # Tool interaction flow
      tool_calls = [ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"})]
      assistant_msg = Message.assistant_with_tools("Checking weather.", tool_calls)
      tool_msg = Message.tool_result("call_123", "get_weather", %{temperature: 72})

      assert Message.valid?(assistant_msg)
      assert Message.valid?(tool_msg)
    end
  end
end
