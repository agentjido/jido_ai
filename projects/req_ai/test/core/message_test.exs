defmodule ReqAI.MessageTest do
  use ExUnit.Case, async: true

  import ReqAI.Test.{Factory, Macros}

  alias ReqAI.{Message, ContentPart}

  doctest Message

  describe "constructors" do
    test "creates basic user and system messages" do
      user_msg = Message.new(:user, "Hello")
      assert_struct(user_msg, Message, role: :user, content: "Hello", metadata: nil)

      system_msg = Message.new(:system, "You are helpful")
      assert_struct(system_msg, Message, role: :system, content: "You are helpful")
    end

    test "assistant_with_tools/3 creates assistant message with tools" do
      tool_calls = [tool_use_part("call_123", "get_weather", %{location: "NYC"})]
      message = Message.assistant_with_tools("I'll check the weather.", tool_calls)

      assert %Message{role: :assistant} = message
      assert [text_part | tool_parts] = message.content
      assert %ContentPart{type: :text, text: "I'll check the weather."} = text_part
      assert tool_parts == tool_calls
    end

    test "user_multimodal/2 creates user message with content parts" do
      content_parts = [text_part("Describe this:"), image_part("https://example.com/image.png")]
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

  describe "validation" do
    test "validates different message types" do
      valid_messages = [
        user_msg("Hello"),
        assistant_msg("Hi there"),
        Message.new(:tool, "Result", tool_call_id: "call_123"),
        user_msg([text_part("Hello"), image_part("https://example.com/image.png")])
      ]

      for message <- valid_messages do
        assert Message.valid?(message)
      end
    end

    test "rejects invalid messages" do
      invalid_messages = [
        Message.new(:user, ""),
        Message.new(:user, []),
        Message.new(:tool, "Result"),
        %{role: :user, content: "Hello"},
        nil
      ]

      for message <- invalid_messages do
        refute Message.valid?(message)
      end
    end
  end

  describe "Enumerable protocol" do
    test "basic protocol conformance" do
      message = user_msg("Hello")
      assert Enumerable.impl_for(message) != nil
      assert Enum.count(message) == 1
    end
  end

  describe "provider_options" do
    test "extracts metadata correctly" do
      assert Message.provider_options(user_msg("Hello")) == %{}

      options = %{openai: %{reasoning_effort: "low"}}
      message = user_msg("Hello", metadata: %{provider_options: options})
      assert Message.provider_options(message) == options
    end

    test "handles complex multi-modal and tool scenarios" do
      content_parts = [
        text_part("Analyze this:"),
        ContentPart.file(<<1, 2, 3>>, "application/json", "data.json"),
        image_part("https://example.com/chart.png")
      ]

      assert Message.valid?(user_msg(content_parts))

      tool_calls = [tool_use_part("call_123", "get_weather", %{location: "NYC"})]
      assistant_msg = Message.assistant_with_tools("Checking weather.", tool_calls)
      tool_msg = Message.tool_result("call_123", "get_weather", %{temperature: 72})

      assert Message.valid?(assistant_msg)
      assert Message.valid?(tool_msg)
    end
  end
end
