#!/usr/bin/env mix run
# Demo script to test tool calling using ONLY the generic top-level API
# Run with: mix run lib/demo_anthropic_toolcalling_clean.exs

require Logger

defmodule AnthropicToolCallingCleanDemo do
  @moduledoc """
  Demo script testing tool calling using ONLY the generic ReqLLM API.
  No provider-specific code should appear here - all provider details
  are hidden within the protocol implementations.
  """

  def run do
    IO.puts("=== ReqLLM Generic API Tool Calling Demo ===\n")

    # Check API key
    api_key = JidoKeys.get("ANTHROPIC_API_KEY")

    if !api_key || api_key == "" do
      IO.puts("❌ Error: ANTHROPIC_API_KEY not found in JidoKeys")
      exit(:normal)
    end

    IO.puts("✅ API key found (length: #{String.length(api_key)})")

    # Test with generic API only
    test_generic_api_tool_calling()
  end

  defp test_generic_api_tool_calling do
    IO.puts("\n🎯 Testing tool calling with generic ReqLLM API...")

    # 1. Create ReqLLM.Model (generic)
    {:ok, model} = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")
    IO.puts("📋 Model: #{model.provider}:#{model.model}")

    # 2. Create ReqLLM.Context (generic)
    import ReqLLM.Context

    context = ReqLLM.Context.new([
      system("You are a helpful assistant with access to tools. Use them when requested."),
      user("I need to plan a meeting. Can you get the weather for New York and then calculate what time it will be in 3 hours?")
    ])

    IO.puts("📨 Context has #{length(context.messages)} messages")

    # 3. Create tools (generic format)
    tools = create_demo_tools()
    IO.puts("🔧 Created #{length(tools)} demo tools")

    # 4. Make request using raw Req with generic ReqLLM provider attachment
    # This is the lowest level that should expose any provider details
    base_request = Req.new(url: "/messages")

    # The provider attachment is the boundary - this should be the only
    # place we see provider-specific code
    {:ok, provider_module} = ReqLLM.Provider.get(model.provider)
    
    attached_request = provider_module.attach(
      base_request,
      model,
      context: context,
      tools: tools,
      max_tokens: 500
    )

    IO.puts("🔌 Provider attached")

    # 5. Make request and decode using generic API
    case Req.request(attached_request, method: :post) do
      {:ok, http_response} ->
        IO.puts("✅ HTTP request successful! Status: #{http_response.status}")

        # 6. Decode response using ONLY generic API
        case ReqLLM.Response.decode_response(http_response.body, model) do
          {:ok, response} ->
            IO.puts("✅ Response decoded successfully!")
            
            # 7. Use generic ReqLLM.Response API
            display_response_with_generic_api(response)
            
            # 8. Handle tool calls if present
            tool_calls = ReqLLM.Response.tool_calls(response)
            if length(tool_calls) > 0 do
              handle_tool_calls_generic(response, tools)
            end

          {:error, decode_error} ->
            IO.puts("❌ Response decode failed: #{inspect(decode_error)}")
        end

      {:error, http_error} ->
        IO.puts("❌ HTTP request failed: #{inspect(http_error)}")
    end
  end

  defp display_response_with_generic_api(response) do
    IO.puts("\n📄 Generic Response Analysis:")
    IO.puts("   ID: #{response.id}")
    IO.puts("   Model: #{response.model}")
    IO.puts("   Finish reason: #{ReqLLM.Response.finish_reason(response)}")
    IO.puts("   Text: #{ReqLLM.Response.text(response)}")
    IO.puts("   Tool calls: #{length(ReqLLM.Response.tool_calls(response))}")
    IO.puts("   Usage: #{inspect(ReqLLM.Response.usage(response))}")
    IO.puts("   Context messages: #{length(response.context.messages)}")
    IO.puts("   OK?: #{ReqLLM.Response.ok?(response)}")
  end

  defp handle_tool_calls_generic(response, available_tools) do
    IO.puts("\n🔧 Handling tool calls using generic API...")
    
    # The Response.tool_calls/1 should return generic tool call structures
    # NOT provider-specific content parts
    tool_calls = ReqLLM.Response.tool_calls(response)
    
    IO.puts("Found #{length(tool_calls)} tool calls:")
    Enum.each(tool_calls, fn tool_call ->
      IO.puts("   - #{inspect(tool_call)}")
    end)
    
    # For now, let's also show what's in the message content to understand
    # the current state - but this would ideally be hidden
    if response.message && response.message.content do
      IO.puts("\n🔍 Message content parts (for debugging):")
      Enum.with_index(response.message.content, 1)
      |> Enum.each(fn {part, idx} ->
        IO.puts("   #{idx}. Type: #{part.type}, Content: #{inspect(part, limit: :infinity)}")
      end)
    end
  end

  defp create_demo_tools do
    # Create proper ReqLLM.Tool structs using the generic API
    {:ok, weather_tool} = ReqLLM.Tool.new([
      name: "get_weather",
      description: "Get the current weather for a given city",
      parameter_schema: [
        city: [type: :string, required: true, doc: "The city to get weather for"]
      ],
      callback: fn %{city: city} -> 
        {:ok, %{
          city: city,
          temperature: "22°C", 
          conditions: "Rainy",
          humidity: "74%",
          wind: "7 km/h"
        }}
      end
    ])

    {:ok, calculator_tool} = ReqLLM.Tool.new([
      name: "calculator", 
      description: "Perform basic mathematical calculations",
      parameter_schema: [
        expression: [type: :string, required: true, doc: "The mathematical expression to evaluate (e.g., '2 + 3', '10 * 5')"]
      ],
      callback: fn %{expression: expr} -> 
        # Simple eval for demo purposes
        try do
          {result, _} = Code.eval_string(expr)
          {:ok, %{expression: expr, result: result}}
        rescue
          _ -> {:error, "Invalid expression"}
        end
      end
    ])

    {:ok, time_tool} = ReqLLM.Tool.new([
      name: "get_time",
      description: "Get the current time and date", 
      parameter_schema: [],
      callback: fn _args ->
        now = DateTime.utc_now()
        {:ok, %{
          current_time: DateTime.to_iso8601(now),
          timezone: "UTC",
          formatted: Calendar.strftime(now, "%Y-%m-%d %H:%M:%S UTC")
        }}
      end
    ])

    [weather_tool, calculator_tool, time_tool]
  end
end

AnthropicToolCallingCleanDemo.run()
