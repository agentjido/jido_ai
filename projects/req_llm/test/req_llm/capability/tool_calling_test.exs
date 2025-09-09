defmodule ReqLLM.Capability.ToolCallingTest do
  @moduledoc """
  Unit tests for ReqLLM.Capability.ToolCalling capability verification.

  Tests the ToolCalling capability module's interface compliance, 
  tool call detection, validation, and error handling.
  """

  use ReqLLM.Test.CapabilityCase

  alias ReqLLM.Capability.ToolCalling



  describe "advertised?/1" do
    test "returns true when tool_call capability is enabled" do
      test_scenarios = [
        {true, %{tool_call?: true}},
        {true, %{tool_call?: true, reasoning?: false, supports_temperature?: true}},
        {false, %{tool_call?: false}},
        {false, %{reasoning?: true, supports_temperature?: true}},
        {false, %{}},
        {false, nil}
      ]

      for {expected_result, capabilities} <- test_scenarios do
        model = test_model("openai", "gpt-4", capabilities: capabilities)
        assert ToolCalling.advertised?(model) == expected_result,
               "Expected advertised?(model with #{inspect(capabilities)}) to be #{expected_result}"
      end
    end

    test "works with different provider models" do
      providers_with_tool_support = [
        {"openai", "gpt-4"},
        {"anthropic", "claude-3-sonnet"},
        {"fake_provider", "tool-enabled-model"}
      ]

      for {provider, model_name} <- providers_with_tool_support do
        model = test_model(provider, model_name, capabilities: %{tool_call?: true})
        assert ToolCalling.advertised?(model) == true,
               "Expected #{provider}:#{model_name} with tool_call?: true to be advertised"
      end
    end
  end

  describe "verify/2" do
    test "successful verification with valid tool calls" do
      test_scenarios = [
        {
          "single tool call",
          [%{name: "get_current_weather", arguments: %{location: "San Francisco, CA"}}],
          %{tool_calls_count: 1, first_tool_name: "get_current_weather"}
        },
        {
          "multiple tool calls",
          [
            %{name: "get_current_weather", arguments: %{location: "San Francisco, CA"}},
            %{name: "get_current_weather", arguments: %{location: "New York, NY"}}
          ],
          %{tool_calls_count: 2, first_tool_name: "get_current_weather"}
        },
        {
          "tool call with complex arguments",
          [
            %{
              name: "get_current_weather", 
              arguments: %{
                location: "Tokyo, Japan", 
                units: "celsius",
                include_forecast: true
              }
            }
          ],
          %{tool_calls_count: 1, first_tool_name: "get_current_weather"}
        }
      ]

      for {description, tool_calls, expected_data} <- test_scenarios do
        model = test_model("openai", "gpt-4")

        response = mock_http_response(%{tool_calls: tool_calls})

        Mimic.stub(ReqLLM, :generate_text, fn _model, _message, opts ->
          # Verify tool configuration was passed correctly
          assert opts[:tools] != nil
          assert opts[:tool_choice] == "auto"
          {:ok, response}
        end)

        result = ToolCalling.verify(model, [])

        assert {:ok, response_data} = result, "Test '#{description}' should pass"
        assert response_data.model_id == "openai:gpt-4"
        assert response_data.tool_calls_count == expected_data.tool_calls_count
        assert response_data.first_tool_name == expected_data.first_tool_name
        assert is_map(response_data.first_tool_args)
      end
    end



    test "validates tool call structure" do
      model = test_model("openai", "gpt-4")

      valid_scenarios = [
        {
          "basic structure",
          [%{name: "test_function", arguments: %{key: "value"}}]
        },
        {
          "with string arguments (JSON parsed)",
          [%{name: "weather_check", arguments: "{\"location\": \"Paris\"}"}]
        }
      ]

      for {description, tool_calls} <- valid_scenarios do
        response = mock_http_response(%{tool_calls: tool_calls})

        Mimic.stub(ReqLLM, :generate_text, fn _model, _message, _opts ->
          {:ok, response}
        end)

        result = ToolCalling.verify(model, [])

        assert {:ok, response_data} = result, "Valid tool call structure '#{description}' should pass"
        assert response_data.first_tool_name != nil
        assert response_data.first_tool_args != nil
      end
    end

    test "handles error cases appropriately" do
      error_scenarios = [
        {
          "no tool calls in response", 
          {:ok, mock_http_response(%{content: "I don't need to call any tools."})},
          ~r/No tool calls received/
        },
        {
          "empty tool calls array",
          {:ok, mock_http_response(%{tool_calls: []})},
          ~r/No tool calls received/
        },
        {
          "malformed tool call - missing name",
          {:ok, mock_http_response(%{tool_calls: [%{arguments: %{location: "test"}}]})},
          ~r/Tool call format invalid/
        },
        {
          "malformed tool call - missing arguments",
          {:ok, mock_http_response(%{tool_calls: [%{name: "test_tool"}]})},
          ~r/Tool call format invalid/
        },
        {
          "API error response",
          {:error, "API rate limit exceeded"},
          ~r/API rate limit exceeded/
        },
        {
          "network timeout",
          {:error, "Network timeout after 10s"},
          ~r/Network timeout after 10s/
        }
      ]

      for {description, mock_response, expected_error_pattern} <- error_scenarios do
        model = test_model("openai", "gpt-4")

        Mimic.stub(ReqLLM, :generate_text, fn _model, _message, _opts ->
          mock_response
        end)

        result = ToolCalling.verify(model, [])
        
        assert {:error, error_message} = result, "Error case '#{description}' should return error"
        assert error_message =~ expected_error_pattern,
               "Error message '#{error_message}' should match pattern #{inspect(expected_error_pattern)}"
      end
    end

    test "validates weather tool schema matches definition" do
      model = test_model("openai", "gpt-4")

      # Test that the tool definition includes expected schema structure
      Mimic.stub(ReqLLM, :generate_text, fn _model, _message, opts ->
        tools = Keyword.get(opts, :tools, [])
        weather_tool = List.first(tools)
        
        # Verify tool definition structure
        assert weather_tool.name == "get_current_weather"
        assert weather_tool.description =~ ~r/current weather/i
        assert weather_tool.parameters_schema.type == "object"
        assert weather_tool.parameters_schema.required == ["location"]
        assert Map.has_key?(weather_tool.parameters_schema.properties, :location)

        # Return successful tool call response
        tool_calls = [%{name: "get_current_weather", arguments: %{location: "San Francisco, CA"}}]
        {:ok, mock_http_response(%{tool_calls: tool_calls})}
      end)

      result = ToolCalling.verify(model, [])
      assert {:ok, _response_data} = result
    end

    test "uses default timeout when not specified" do
      model = test_model("openai", "gpt-4")

      Mimic.stub(ReqLLM, :generate_text, fn _model, _message, opts ->
        provider_opts = Keyword.get(opts, :provider_options, %{})
        # Default timeout should be 10_000
        assert provider_opts.timeout == 10_000
        assert provider_opts.receive_timeout == 10_000

        tool_calls = [%{name: "get_current_weather", arguments: %{location: "Test"}}]
        {:ok, mock_http_response(%{tool_calls: tool_calls})}
      end)

      result = ToolCalling.verify(model, [])
      assert {:ok, _response_data} = result
    end
  end

  timeout_tests(ToolCalling, :generate_text)
  model_id_tests(ToolCalling, :generate_text)
  behaviour_tests(ToolCalling)

  describe "verify/2 result format" do
    test "returns proper tool calling result structure" do
      model = test_model("openai", "gpt-4")

      # Test success format
      tool_calls = [%{name: "test_tool", arguments: %{param: "value"}}]
      response = mock_http_response(%{tool_calls: tool_calls})

      Mimic.stub(ReqLLM, :generate_text, fn _model, _message, _opts ->
        {:ok, response}
      end)

      result = ToolCalling.verify(model, [])
      assert {:ok, data} = result
      assert_tool_calling_result(data)

      # Test error format
      Mimic.stub(ReqLLM, :generate_text, fn _model, _message, _opts ->
        {:error, "Network error"}
      end)

      result = ToolCalling.verify(model, [])
      assert_capability_result(result, :failed, :tool_calling)
    end
  end

  describe "integration scenarios" do
    test "handles mixed tool call and content response" do
      # Some providers might return both tool calls and content
      model = test_model("anthropic", "claude-3-sonnet")

      response_body = %{
        content: "I'll check the weather for you.",
        tool_calls: [%{name: "get_current_weather", arguments: %{location: "Boston, MA"}}]
      }

      Mimic.stub(ReqLLM, :generate_text, fn _model, _message, _opts ->
        {:ok, mock_http_response(response_body)}
      end)

      result = ToolCalling.verify(model, [])

      assert {:ok, response_data} = result
      assert response_data.tool_calls_count == 1
      assert response_data.first_tool_name == "get_current_weather"
    end

    test "handles tool calls with different argument formats" do
      model = test_model("openai", "gpt-4")

      scenarios = [
        {
          "map arguments",
          %{location: "Seattle, WA", units: "fahrenheit"}
        },
        {
          "nested map arguments", 
          %{
            location: "Denver, CO",
            options: %{
              units: "celsius",
              include_hourly: true
            }
          }
        },
        {
          "empty arguments",
          %{}
        }
      ]

      for {description, arguments} <- scenarios do
        tool_calls = [%{name: "get_current_weather", arguments: arguments}]
        response = mock_http_response(%{tool_calls: tool_calls})

        Mimic.stub(ReqLLM, :generate_text, fn _model, _message, _opts ->
          {:ok, response}
        end)

        result = ToolCalling.verify(model, [])

        assert {:ok, response_data} = result, "Should handle #{description}"
        assert response_data.first_tool_args == arguments
      end
    end
  end
end
