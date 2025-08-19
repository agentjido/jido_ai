defmodule Jido.AI.MessageToolTest do
  use ExUnit.Case

  alias Jido.AI.Message
  alias Jido.AI.{ContentPart, Message}

  doctest Message

  describe "assistant_with_tools/2" do
    test "creates assistant message with tool calls" do
      tool_calls = [
        ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"}),
        ContentPart.tool_call("call_456", "get_time", %{timezone: "EST"})
      ]

      message = Message.assistant_with_tools("I'll get that information for you.", tool_calls)

      assert %Message{
               role: :assistant,
               content: [
                 %ContentPart{type: :text, text: "I'll get that information for you."},
                 %ContentPart{type: :tool_call, tool_call_id: "call_123"},
                 %ContentPart{type: :tool_call, tool_call_id: "call_456"}
               ]
             } = message
    end

    test "creates assistant message with metadata" do
      tool_calls = [ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"})]
      metadata = %{provider_options: %{openai: %{temperature: 0.7}}}

      message = Message.assistant_with_tools("I'll check that.", tool_calls, metadata: metadata)

      assert message.metadata == metadata
    end

    test "validates inputs" do
      tool_calls = [ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"})]

      # Valid inputs should not raise
      assert %Message{} = Message.assistant_with_tools("I'll help.", tool_calls)

      # Invalid text input should raise FunctionClauseError
      assert_raise FunctionClauseError, fn ->
        Message.assistant_with_tools(123, tool_calls)
      end

      # Invalid tool_calls input should raise FunctionClauseError
      assert_raise FunctionClauseError, fn ->
        Message.assistant_with_tools("I'll help.", "not a list")
      end
    end
  end

  describe "tool_result/3" do
    test "creates tool result message" do
      message = Message.tool_result("call_123", "get_weather", %{temperature: 72, unit: "fahrenheit"})

      assert %Message{
               role: :tool,
               tool_call_id: "call_123",
               content: [
                 %ContentPart{
                   type: :tool_result,
                   tool_call_id: "call_123",
                   tool_name: "get_weather",
                   output: %{temperature: 72, unit: "fahrenheit"}
                 }
               ]
             } = message
    end

    test "creates tool result message with metadata" do
      metadata = %{provider_options: %{openai: %{detail: "high"}}}

      message =
        Message.tool_result("call_123", "get_weather", %{temperature: 72}, metadata: metadata)

      assert message.metadata == metadata
    end

    test "accepts various output types" do
      # Map output
      message = Message.tool_result("call_123", "get_weather", %{temperature: 72})
      [content_part] = message.content
      assert content_part.output == %{temperature: 72}

      # String output
      message = Message.tool_result("call_123", "get_weather", "It's sunny")
      [content_part] = message.content
      assert content_part.output == "It's sunny"

      # List output
      message = Message.tool_result("call_123", "get_data", [1, 2, 3])
      [content_part] = message.content
      assert content_part.output == [1, 2, 3]
    end

    test "validates inputs" do
      # Valid inputs should not raise
      assert %Message{} = Message.tool_result("call_123", "get_weather", %{temperature: 72})

      # Invalid inputs should raise FunctionClauseError
      assert_raise FunctionClauseError, fn ->
        Message.tool_result(123, "get_weather", %{temperature: 72})
      end

      assert_raise FunctionClauseError, fn ->
        Message.tool_result("call_123", 123, %{temperature: 72})
      end
    end
  end

  describe "valid?/1 with tool messages" do
    test "validates tool role messages with tool_call_id" do
      valid_tool_message = Message.tool_result("call_123", "get_weather", %{temperature: 72})
      assert Message.valid?(valid_tool_message)
    end

    test "rejects tool role messages without tool_call_id" do
      invalid_message = %Message{
        role: :tool,
        tool_call_id: nil,
        content: [ContentPart.tool_result("call_123", "get_weather", %{temperature: 72})]
      }

      refute Message.valid?(invalid_message)

      invalid_message = %Message{
        role: :tool,
        tool_call_id: "",
        content: [ContentPart.tool_result("call_123", "get_weather", %{temperature: 72})]
      }

      refute Message.valid?(invalid_message)
    end

    test "validates assistant messages with tool calls" do
      tool_calls = [ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"})]
      valid_message = Message.assistant_with_tools("I'll check that.", tool_calls)

      assert Message.valid?(valid_message)
    end

    test "validates non-tool role messages without tool_call_id requirement" do
      user_message = %Message{role: :user, content: "Hello", tool_call_id: nil}
      assert Message.valid?(user_message)

      assistant_message = %Message{role: :assistant, content: "Hi there", tool_call_id: nil}
      assert Message.valid?(assistant_message)

      system_message = %Message{role: :system, content: "You are helpful", tool_call_id: nil}
      assert Message.valid?(system_message)
    end
  end

  describe "tool call conversation flow" do
    test "creates valid conversation with tool calls and results" do
      # User message
      user_msg = %Message{role: :user, content: "What's the weather in NYC?"}

      # Assistant message with tool call
      tool_calls = [ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"})]
      assistant_msg = Message.assistant_with_tools("I'll check the weather for you.", tool_calls)

      # Tool result message
      tool_msg = Message.tool_result("call_123", "get_weather", %{temperature: 72, conditions: "sunny"})

      # Final assistant response
      final_msg = %Message{
        role: :assistant,
        content: "The weather in NYC is sunny with a temperature of 72°F."
      }

      conversation = [user_msg, assistant_msg, tool_msg, final_msg]

      # Verify all messages are valid
      assert Enum.all?(conversation, &Message.valid?/1)

      # Verify tool call ID linking
      [tool_call] = assistant_msg.content |> Enum.filter(&(&1.type == :tool_call))
      [tool_result] = tool_msg.content |> Enum.filter(&(&1.type == :tool_result))

      assert tool_call.tool_call_id == tool_result.tool_call_id
      assert tool_msg.tool_call_id == tool_call.tool_call_id
    end

    test "handles multiple tool calls in single message" do
      tool_calls = [
        ContentPart.tool_call("call_1", "get_weather", %{location: "NYC"}),
        ContentPart.tool_call("call_2", "get_time", %{timezone: "EST"}),
        ContentPart.tool_call("call_3", "get_calendar", %{date: "2024-01-15"})
      ]

      message = Message.assistant_with_tools("I'll get all that information.", tool_calls)

      assert Message.valid?(message)
      # text + 3 tool calls
      assert length(message.content) == 4

      tool_call_parts = Enum.filter(message.content, &(&1.type == :tool_call))
      assert length(tool_call_parts) == 3

      # Verify unique tool call IDs
      tool_call_ids = Enum.map(tool_call_parts, & &1.tool_call_id)
      assert tool_call_ids == ["call_1", "call_2", "call_3"]
    end
  end
end
