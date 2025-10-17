defmodule ReqLLM.ToolCallTest do
  use ExUnit.Case, async: true

  alias ReqLLM.ToolCall

  describe "new/3" do
    test "creates a ToolCall with provided id" do
      tool_call = ToolCall.new("call_123", "get_weather", ~s({"location":"Paris"}))

      assert tool_call.id == "call_123"
      assert tool_call.type == "function"
      assert tool_call.function.name == "get_weather"
      assert tool_call.function.arguments == ~s({"location":"Paris"})
    end

    test "generates an id when nil is provided" do
      tool_call = ToolCall.new(nil, "get_weather", ~s({"location":"Paris"}))

      assert String.starts_with?(tool_call.id, "call_")
      assert tool_call.type == "function"
      assert tool_call.function.name == "get_weather"
    end

    test "accepts empty arguments" do
      tool_call = ToolCall.new("call_456", "no_args", "{}")

      assert tool_call.function.arguments == "{}"
    end
  end

  describe "name/1" do
    test "extracts function name from ToolCall" do
      tool_call = ToolCall.new("call_123", "get_weather", "{}")

      assert ToolCall.name(tool_call) == "get_weather"
    end
  end

  describe "args_json/1" do
    test "extracts arguments JSON string from ToolCall" do
      args = ~s({"location":"SF","unit":"celsius"})
      tool_call = ToolCall.new("call_123", "get_weather", args)

      assert ToolCall.args_json(tool_call) == args
    end

    test "returns empty object string for empty arguments" do
      tool_call = ToolCall.new("call_123", "no_args", "{}")

      assert ToolCall.args_json(tool_call) == "{}"
    end
  end

  describe "args_map/1" do
    test "decodes valid JSON arguments to map" do
      args = ~s({"location":"Paris","unit":"celsius"})
      tool_call = ToolCall.new("call_123", "get_weather", args)

      assert ToolCall.args_map(tool_call) == %{"location" => "Paris", "unit" => "celsius"}
    end

    test "returns nil for invalid JSON" do
      tool_call = ToolCall.new("call_123", "broken", "invalid json")

      assert ToolCall.args_map(tool_call) == nil
    end

    test "decodes empty object" do
      tool_call = ToolCall.new("call_123", "no_args", "{}")

      assert ToolCall.args_map(tool_call) == %{}
    end

    test "handles nested JSON structures" do
      args = ~s({"location":{"city":"Paris","country":"France"},"unit":"celsius"})
      tool_call = ToolCall.new("call_123", "get_weather", args)

      assert ToolCall.args_map(tool_call) == %{
               "location" => %{"city" => "Paris", "country" => "France"},
               "unit" => "celsius"
             }
    end
  end

  describe "matches_name?/2" do
    test "returns true when name matches" do
      tool_call = ToolCall.new("call_123", "get_weather", "{}")

      assert ToolCall.matches_name?(tool_call, "get_weather") == true
    end

    test "returns false when name does not match" do
      tool_call = ToolCall.new("call_123", "get_weather", "{}")

      assert ToolCall.matches_name?(tool_call, "get_time") == false
    end

    test "is case-sensitive" do
      tool_call = ToolCall.new("call_123", "get_weather", "{}")

      assert ToolCall.matches_name?(tool_call, "Get_Weather") == false
    end
  end

  describe "find_args/2" do
    setup do
      tool_calls = [
        ToolCall.new("call_1", "get_weather", ~s({"location":"Paris"})),
        ToolCall.new("call_2", "get_time", ~s({"timezone":"UTC"})),
        ToolCall.new("call_3", "structured_output", ~s({"name":"John","age":30}))
      ]

      {:ok, tool_calls: tool_calls}
    end

    test "finds and decodes arguments for matching tool call", %{tool_calls: tool_calls} do
      result = ToolCall.find_args(tool_calls, "get_weather")

      assert result == %{"location" => "Paris"}
    end

    test "finds first matching tool call when multiple exist", %{tool_calls: tool_calls} do
      duplicate_calls = tool_calls ++ [ToolCall.new("call_4", "get_time", ~s({"timezone":"PST"}))]

      result = ToolCall.find_args(duplicate_calls, "get_time")

      assert result == %{"timezone" => "UTC"}
    end

    test "returns nil when no matching tool call found", %{tool_calls: tool_calls} do
      result = ToolCall.find_args(tool_calls, "nonexistent_function")

      assert result == nil
    end

    test "returns nil when arguments cannot be decoded" do
      tool_calls = [ToolCall.new("call_1", "broken", "invalid json")]

      result = ToolCall.find_args(tool_calls, "broken")

      assert result == nil
    end

    test "works with empty list" do
      result = ToolCall.find_args([], "any_function")

      assert result == nil
    end

    test "finds structured_output tool call", %{tool_calls: tool_calls} do
      result = ToolCall.find_args(tool_calls, "structured_output")

      assert result == %{"name" => "John", "age" => 30}
    end
  end

  describe "Jason.Encoder implementation" do
    test "encodes ToolCall to JSON" do
      tool_call = ToolCall.new("call_123", "get_weather", ~s({"location":"Paris"}))
      json = Jason.encode!(tool_call)

      assert json =~ ~s("id":"call_123")
      assert json =~ ~s("type":"function")
      assert json =~ ~s("name":"get_weather")
      assert json =~ ~s("arguments":"{\\"location\\":\\"Paris\\"}")
    end

    test "decodes back to map with correct structure" do
      tool_call = ToolCall.new("call_456", "get_time", ~s({"timezone":"UTC"}))
      json = Jason.encode!(tool_call)
      decoded = Jason.decode!(json)

      assert decoded["id"] == "call_456"
      assert decoded["type"] == "function"
      assert decoded["function"]["name"] == "get_time"
      assert decoded["function"]["arguments"] == ~s({"timezone":"UTC"})
    end
  end

  describe "Inspect implementation" do
    test "provides readable inspection format" do
      tool_call = ToolCall.new("call_123", "get_weather", ~s({"location":"Paris"}))
      inspected = inspect(tool_call)

      assert inspected == ~s[#ToolCall<call_123: get_weather({"location":"Paris"})>]
    end

    test "shows empty arguments" do
      tool_call = ToolCall.new("call_456", "no_args", "{}")
      inspected = inspect(tool_call)

      assert inspected == "#ToolCall<call_456: no_args({})>"
    end
  end
end
