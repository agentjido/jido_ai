defmodule ReqAI.Providers.ToolCallingTest do
  use ExUnit.Case, async: true

  describe "OpenAI provider tool calling integration" do
    test "build_request/3 includes tools in request body" do
      tools = [
        %{
          name: "get_weather",
          description: "Get weather information",
          parameters_schema: %{
            type: "object",
            properties: %{
              city: %{type: "string", description: "City name"}
            },
            required: ["city"]
          }
        }
      ]

      opts = [
        model: "gpt-4",
        tools: tools,
        tool_choice: "auto"
      ]

      {:ok, request} = ReqAI.Providers.OpenAI.build_request("Hello", [], opts)

      # Verify the request contains the tools in the correct format
      assert request.options[:json]["tools"] == [
               %{
                 "type" => "function",
                 "function" => %{
                   "name" => "get_weather",
                   "description" => "Get weather information",
                   "parameters" => %{
                     type: "object",
                     properties: %{
                       city: %{type: "string", description: "City name"}
                     },
                     required: ["city"]
                   }
                 }
               }
             ]

      assert request.options[:json]["tool_choice"] == "auto"
    end

    test "build_request/3 handles specific tool choice" do
      tools = [
        %{
          name: "get_weather",
          description: "Get weather information",
          parameters_schema: %{type: "object", properties: %{}, required: []}
        }
      ]

      opts = [
        model: "gpt-4",
        tools: tools,
        tool_choice: "get_weather"
      ]

      {:ok, request} = ReqAI.Providers.OpenAI.build_request("Hello", [], opts)

      assert request.options[:json]["tool_choice"] == %{
               "type" => "function",
               "function" => %{"name" => "get_weather"}
             }
    end

    test "build_request/3 without tools excludes tools from body" do
      opts = [model: "gpt-4"]

      {:ok, request} = ReqAI.Providers.OpenAI.build_request("Hello", [], opts)

      refute Map.has_key?(request.options[:json], "tools")
      refute Map.has_key?(request.options[:json], "tool_choice")
    end
  end

  describe "Anthropic provider tool calling integration" do
    test "build_request/3 includes tools in request body" do
      tools = [
        %{
          name: "get_weather",
          description: "Get weather information",
          parameters_schema: %{
            type: "object",
            properties: %{
              city: %{type: "string", description: "City name"}
            },
            required: ["city"]
          }
        }
      ]

      opts = [
        model: "claude-3-haiku-20240307",
        tools: tools,
        tool_choice: "auto"
      ]

      {:ok, request} = ReqAI.Providers.Anthropic.build_request("Hello", [], opts)

      # Verify the request contains the tools in the correct format
      assert request.options[:json]["tools"] == [
               %{
                 "name" => "get_weather",
                 "description" => "Get weather information",
                 "input_schema" => %{
                   type: "object",
                   properties: %{
                     city: %{type: "string", description: "City name"}
                   },
                   required: ["city"]
                 }
               }
             ]

      assert request.options[:json]["tool_choice"] == %{"type" => "auto"}
    end

    test "build_request/3 handles specific tool choice" do
      tools = [
        %{
          name: "get_weather",
          description: "Get weather information",
          parameters_schema: %{type: "object", properties: %{}, required: []}
        }
      ]

      opts = [
        model: "claude-3-haiku-20240307",
        tools: tools,
        tool_choice: "get_weather"
      ]

      {:ok, request} = ReqAI.Providers.Anthropic.build_request("Hello", [], opts)

      assert request.options[:json]["tool_choice"] == %{"type" => "tool", "name" => "get_weather"}
    end

    test "build_request/3 without tools excludes tools from body" do
      opts = [model: "claude-3-haiku-20240307"]

      {:ok, request} = ReqAI.Providers.Anthropic.build_request("Hello", [], opts)

      refute Map.has_key?(request.options[:json], "tools")
      refute Map.has_key?(request.options[:json], "tool_choice")
    end
  end

  describe "response parsing for tool calls" do
    test "OpenAI parse_response/3 handles tool calls in response" do
      response = %{
        status: 200,
        body: %{
          "choices" => [
            %{
              "message" => %{
                "tool_calls" => [
                  %{
                    "id" => "call_123",
                    "function" => %{
                      "name" => "get_weather",
                      "arguments" => "{\"city\": \"Paris\"}"
                    }
                  }
                ]
              }
            }
          ]
        }
      }

      {:ok, result} = ReqAI.Providers.OpenAI.parse_response(response, [], [])

      assert result == %{
               tool_calls: [
                 %{
                   id: "call_123",
                   type: "function",
                   name: "get_weather",
                   arguments: %{"city" => "Paris"}
                 }
               ]
             }
    end

    test "Anthropic parse_response/3 handles tool calls in response" do
      response = %{
        status: 200,
        body: %{
          "content" => [
            %{
              "type" => "tool_use",
              "id" => "call_123",
              "name" => "get_weather",
              "input" => %{"city" => "Paris"}
            }
          ]
        }
      }

      {:ok, result} = ReqAI.Providers.Anthropic.parse_response(response, [], [])

      assert result == %{
               tool_calls: [
                 %{
                   id: "call_123",
                   type: "function",
                   name: "get_weather",
                   arguments: %{"city" => "Paris"}
                 }
               ]
             }
    end
  end
end
