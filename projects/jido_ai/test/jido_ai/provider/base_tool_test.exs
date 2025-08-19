defmodule Jido.AI.Provider.BaseToolTest do
  use ExUnit.Case

  alias Jido.AI.{ContentPart, Message, Provider.Base}

  describe "encode_message/1 with tool content" do
    test "encodes assistant message with tool calls" do
      tool_calls = [
        ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"}),
        ContentPart.tool_call("call_456", "get_time", %{timezone: "EST"})
      ]

      message = Message.assistant_with_tools("I'll help with that.", tool_calls)
      encoded = Base.encode_message(message)

      assert encoded["role"] == "assistant"
      assert length(encoded["content"]) == 3

      # Check text content
      text_part = Enum.at(encoded["content"], 0)
      assert text_part == %{type: "text", text: "I'll help with that."}

      # Check first tool call
      tool_call_1 = Enum.at(encoded["content"], 1)
      assert tool_call_1.type == "tool_call"
      assert tool_call_1.id == "call_123"
      assert tool_call_1.function.name == "get_weather"
      assert tool_call_1.function.arguments == Jason.encode!(%{location: "NYC"})

      # Check second tool call
      tool_call_2 = Enum.at(encoded["content"], 2)
      assert tool_call_2.type == "tool_call"
      assert tool_call_2.id == "call_456"
      assert tool_call_2.function.name == "get_time"
      assert tool_call_2.function.arguments == Jason.encode!(%{timezone: "EST"})
    end

    test "encodes tool result message" do
      message = Message.tool_result("call_123", "get_weather", %{temperature: 72, conditions: "sunny"})
      encoded = Base.encode_message(message)

      assert encoded["role"] == "tool"
      assert encoded["tool_call_id"] == "call_123"
      assert length(encoded["content"]) == 1

      tool_result = Enum.at(encoded["content"], 0)
      assert tool_result.type == "tool_result"
      assert tool_result.tool_call_id == "call_123"
      assert tool_result.name == "get_weather"
      assert tool_result.content == Jason.encode!(%{temperature: 72, conditions: "sunny"})
    end

    test "encodes mixed content with text and tool calls" do
      content = [
        ContentPart.text("I'll check the weather and time for you."),
        ContentPart.tool_call("call_1", "get_weather", %{location: "NYC"}),
        ContentPart.tool_call("call_2", "get_time", %{timezone: "EST"})
      ]

      message = %Message{role: :assistant, content: content}
      encoded = Base.encode_message(message)

      assert encoded["role"] == "assistant"
      assert length(encoded["content"]) == 3

      # Check content types
      content_types = Enum.map(encoded["content"], & &1.type)
      assert content_types == ["text", "tool_call", "tool_call"]
    end
  end

  describe "encode_messages/1 with tool content" do
    test "encodes complete tool conversation" do
      messages = [
        %Message{role: :user, content: "What's the weather in NYC?"},
        Message.assistant_with_tools("I'll check that.", [
          ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"})
        ]),
        Message.tool_result("call_123", "get_weather", %{temperature: 72, conditions: "sunny"}),
        %Message{role: :assistant, content: "It's 72°F and sunny in NYC."}
      ]

      encoded_messages = Base.encode_messages(messages)

      assert length(encoded_messages) == 4

      # Check user message
      assert Enum.at(encoded_messages, 0) == %{
               "role" => "user",
               "content" => "What's the weather in NYC?"
             }

      # Check assistant message with tool call
      assistant_msg = Enum.at(encoded_messages, 1)
      assert assistant_msg["role"] == "assistant"
      assert length(assistant_msg["content"]) == 2
      assert Enum.at(assistant_msg["content"], 0).type == "text"
      assert Enum.at(assistant_msg["content"], 1).type == "tool_call"

      # Check tool result message
      tool_msg = Enum.at(encoded_messages, 2)
      assert tool_msg["role"] == "tool"
      assert tool_msg["tool_call_id"] == "call_123"
      assert length(tool_msg["content"]) == 1
      assert Enum.at(tool_msg["content"], 0).type == "tool_result"

      # Check final assistant message
      assert Enum.at(encoded_messages, 3) == %{
               "role" => "assistant",
               "content" => "It's 72°F and sunny in NYC."
             }
    end
  end

  describe "tool call ID linking" do
    test "maintains tool call ID consistency" do
      tool_call_id = "call_abc123"
      tool_name = "get_weather"
      tool_input = %{"location" => "NYC", "unit" => "celsius"}
      tool_output = %{"temperature" => 22, "conditions" => "cloudy"}

      # Create assistant message with tool call
      assistant_msg =
        Message.assistant_with_tools("Checking weather...", [
          ContentPart.tool_call(tool_call_id, tool_name, tool_input)
        ])

      # Create tool result message
      tool_msg = Message.tool_result(tool_call_id, tool_name, tool_output)

      # Encode both messages
      encoded_assistant = Base.encode_message(assistant_msg)
      encoded_tool = Base.encode_message(tool_msg)

      # Extract tool call from assistant message
      tool_call_content = Enum.find(encoded_assistant["content"], &(&1.type == "tool_call"))
      assert tool_call_content.id == tool_call_id

      # Check tool result message
      assert encoded_tool["tool_call_id"] == tool_call_id
      tool_result_content = Enum.at(encoded_tool["content"], 0)
      assert tool_result_content.tool_call_id == tool_call_id
      assert tool_result_content.name == tool_name

      # Verify JSON serialization/deserialization of arguments and content
      assert Jason.decode!(tool_call_content.function.arguments) == tool_input
      assert Jason.decode!(tool_result_content.content) == tool_output
    end
  end

  describe "complex tool scenarios" do
    test "handles multiple tool calls with different result types" do
      messages = [
        %Message{role: :user, content: "Get weather, current time, and my calendar for today"},
        Message.assistant_with_tools("I'll get all that information.", [
          ContentPart.tool_call("weather_123", "get_weather", %{location: "NYC"}),
          ContentPart.tool_call("time_456", "get_current_time", %{}),
          ContentPart.tool_call("cal_789", "get_calendar", %{date: "2024-01-15"})
        ]),
        Message.tool_result("weather_123", "get_weather", %{temp: 72, condition: "sunny"}),
        Message.tool_result("time_456", "get_current_time", "2:30 PM EST"),
        Message.tool_result("cal_789", "get_calendar", [
          %{time: "9:00 AM", event: "Team meeting"},
          %{time: "2:00 PM", event: "Client call"}
        ]),
        %Message{
          role: :assistant,
          content:
            "Here's what I found: Weather is 72°F and sunny. It's currently 2:30 PM EST. You have a team meeting at 9 AM and client call at 2 PM today."
        }
      ]

      encoded_messages = Base.encode_messages(messages)
      assert length(encoded_messages) == 6

      # Verify tool call IDs are properly linked
      assistant_msg = Enum.at(encoded_messages, 1)
      tool_calls = Enum.filter(assistant_msg["content"], &(&1.type == "tool_call"))
      assert length(tool_calls) == 3

      tool_call_ids = Enum.map(tool_calls, & &1.id)
      assert "weather_123" in tool_call_ids
      assert "time_456" in tool_call_ids
      assert "cal_789" in tool_call_ids

      # Verify tool result messages have correct IDs
      weather_result = Enum.at(encoded_messages, 2)
      assert weather_result["tool_call_id"] == "weather_123"

      time_result = Enum.at(encoded_messages, 3)
      assert time_result["tool_call_id"] == "time_456"

      calendar_result = Enum.at(encoded_messages, 4)
      assert calendar_result["tool_call_id"] == "cal_789"
    end

    test "handles tool calls with complex nested arguments" do
      complex_input = %{
        "location" => %{"city" => "New York", "state" => "NY", "country" => "USA"},
        "options" => %{
          "units" => "metric",
          "include_forecast" => true,
          "forecast_days" => 5,
          "include_alerts" => true
        },
        "preferences" => ["temperature", "humidity", "wind_speed"]
      }

      message =
        Message.assistant_with_tools("Getting detailed weather data...", [
          ContentPart.tool_call("weather_complex", "get_detailed_weather", complex_input)
        ])

      encoded = Base.encode_message(message)
      tool_call = Enum.find(encoded["content"], &(&1.type == "tool_call"))

      # Verify complex arguments are properly JSON encoded
      decoded_args = Jason.decode!(tool_call.function.arguments)
      assert decoded_args == complex_input
    end
  end
end
