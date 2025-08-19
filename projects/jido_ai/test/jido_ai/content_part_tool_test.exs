defmodule Jido.AI.ContentPartToolTest do
  use ExUnit.Case

  alias Jido.AI.ContentPart

  doctest ContentPart

  describe "tool_call/3" do
    test "creates a valid tool call content part" do
      content_part = ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"})

      assert %ContentPart{
               type: :tool_call,
               tool_call_id: "call_123",
               tool_name: "get_weather",
               input: %{location: "NYC"},
               metadata: nil
             } = content_part
    end

    test "creates tool call with metadata" do
      metadata = %{provider_options: %{openai: %{temperature: 0.7}}}

      content_part =
        ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"}, metadata: metadata)

      assert content_part.metadata == metadata
    end

    test "validates inputs" do
      # Valid inputs should not raise
      assert %ContentPart{} = ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"})

      # Invalid inputs should raise FunctionClauseError
      assert_raise FunctionClauseError, fn ->
        ContentPart.tool_call(123, "get_weather", %{location: "NYC"})
      end

      assert_raise FunctionClauseError, fn ->
        ContentPart.tool_call("call_123", 123, %{location: "NYC"})
      end

      assert_raise FunctionClauseError, fn ->
        ContentPart.tool_call("call_123", "get_weather", "not a map")
      end
    end
  end

  describe "tool_result/3" do
    test "creates a valid tool result content part" do
      content_part = ContentPart.tool_result("call_123", "get_weather", %{temperature: 72})

      assert %ContentPart{
               type: :tool_result,
               tool_call_id: "call_123",
               tool_name: "get_weather",
               output: %{temperature: 72},
               metadata: nil
             } = content_part
    end

    test "creates tool result with metadata" do
      metadata = %{provider_options: %{openai: %{detail: "high"}}}

      content_part =
        ContentPart.tool_result("call_123", "get_weather", %{temperature: 72}, metadata: metadata)

      assert content_part.metadata == metadata
    end

    test "accepts various output types" do
      # Map output
      assert %ContentPart{output: %{temperature: 72}} =
               ContentPart.tool_result("call_123", "get_weather", %{temperature: 72})

      # String output
      assert %ContentPart{output: "It's sunny"} =
               ContentPart.tool_result("call_123", "get_weather", "It's sunny")

      # List output
      assert %ContentPart{output: [1, 2, 3]} =
               ContentPart.tool_result("call_123", "get_data", [1, 2, 3])

      # Number output
      assert %ContentPart{output: 42} = ContentPart.tool_result("call_123", "calculate", 42)
    end

    test "validates inputs" do
      # Valid inputs should not raise
      assert %ContentPart{} =
               ContentPart.tool_result("call_123", "get_weather", %{temperature: 72})

      # Invalid inputs should raise FunctionClauseError
      assert_raise FunctionClauseError, fn ->
        ContentPart.tool_result(123, "get_weather", %{temperature: 72})
      end

      assert_raise FunctionClauseError, fn ->
        ContentPart.tool_result("call_123", 123, %{temperature: 72})
      end
    end
  end

  describe "valid?/1 with tool content" do
    test "validates tool_call content" do
      valid_tool_call = ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"})
      assert ContentPart.valid?(valid_tool_call)

      # Invalid - empty tool_call_id
      invalid_tool_call = %ContentPart{
        type: :tool_call,
        tool_call_id: "",
        tool_name: "get_weather",
        input: %{}
      }

      refute ContentPart.valid?(invalid_tool_call)

      # Invalid - empty tool_name
      invalid_tool_call = %ContentPart{
        type: :tool_call,
        tool_call_id: "call_123",
        tool_name: "",
        input: %{}
      }

      refute ContentPart.valid?(invalid_tool_call)

      # Invalid - non-map input
      invalid_tool_call = %ContentPart{
        type: :tool_call,
        tool_call_id: "call_123",
        tool_name: "get_weather",
        input: "not a map"
      }

      refute ContentPart.valid?(invalid_tool_call)
    end

    test "validates tool_result content" do
      valid_tool_result = ContentPart.tool_result("call_123", "get_weather", %{temperature: 72})
      assert ContentPart.valid?(valid_tool_result)

      # Invalid - empty tool_call_id
      invalid_tool_result = %ContentPart{
        type: :tool_result,
        tool_call_id: "",
        tool_name: "get_weather",
        output: %{temperature: 72}
      }

      refute ContentPart.valid?(invalid_tool_result)

      # Invalid - empty tool_name
      invalid_tool_result = %ContentPart{
        type: :tool_result,
        tool_call_id: "call_123",
        tool_name: "",
        output: %{temperature: 72}
      }

      refute ContentPart.valid?(invalid_tool_result)

      # Invalid - nil output
      invalid_tool_result = %ContentPart{
        type: :tool_result,
        tool_call_id: "call_123",
        tool_name: "get_weather",
        output: nil
      }

      refute ContentPart.valid?(invalid_tool_result)
    end
  end

  describe "to_map/1 with tool content" do
    test "converts tool_call to OpenAI format" do
      tool_call = ContentPart.tool_call("call_123", "get_weather", %{location: "NYC", unit: "celsius"})

      expected = %{
        type: "tool_call",
        id: "call_123",
        function: %{
          name: "get_weather",
          arguments: Jason.encode!(%{location: "NYC", unit: "celsius"})
        }
      }

      assert ContentPart.to_map(tool_call) == expected
    end

    test "converts tool_result to OpenAI format" do
      tool_result = ContentPart.tool_result("call_123", "get_weather", %{temperature: 72, unit: "fahrenheit"})

      expected = %{
        type: "tool_result",
        tool_call_id: "call_123",
        name: "get_weather",
        content: Jason.encode!(%{temperature: 72, unit: "fahrenheit"})
      }

      assert ContentPart.to_map(tool_result) == expected
    end

    test "handles complex nested output in tool_result" do
      complex_output = %{
        "weather" => %{"temperature" => 72, "humidity" => 65},
        "forecast" => [
          %{"day" => "Monday", "high" => 75, "low" => 60},
          %{"day" => "Tuesday", "high" => 78, "low" => 63}
        ]
      }

      tool_result = ContentPart.tool_result("call_456", "get_forecast", complex_output)
      result_map = ContentPart.to_map(tool_result)

      assert result_map.type == "tool_result"
      assert result_map.tool_call_id == "call_456"
      assert result_map.name == "get_forecast"

      # Ensure the complex output is properly JSON encoded and decoded
      decoded_content = Jason.decode!(result_map.content)
      assert decoded_content == complex_output
    end
  end
end
