#!/usr/bin/env mix run
# Demo script to test the Anthropic provider with tool calling using raw Req approach
# Run with: mix run lib/demo_anthropic_toolcalling.exs

require Logger

defmodule AnthropicToolCallingDemo do
  @moduledoc """
  Demo script to test the Anthropic provider tool calling functionality using raw Req approach.
  This tests the lower-level tool calling integration.
  """

  def run do
    IO.puts("=== ReqLLM Anthropic Provider Tool Calling Demo (Raw Req Approach) ===\n")

    # Check if we have an API key set
    api_key = JidoKeys.get("ANTHROPIC_API_KEY")

    if !api_key || api_key == "" do
      IO.puts("❌ Error: ANTHROPIC_API_KEY not found in JidoKeys")
      IO.puts("Please run: iex -S mix")
      IO.puts("Then: JidoKeys.put(\"ANTHROPIC_API_KEY\", \"your-key-here\")")
      exit(:normal)
    end

    IO.puts("✅ API key found (length: #{String.length(api_key)})")

    # Create demo tools
    tools = create_demo_tools()
    IO.puts("🔧 Created #{length(tools)} demo tools:")
    Enum.each(tools, &IO.puts("   - #{&1.name}: #{&1.description}"))

    # Test simple tool calling with raw Req
    # test_simple_tool_calling(tools)

    # Test context-based tool calling
    test_context_tool_calling(tools)
  end

  defp test_simple_tool_calling(tools) do
    IO.puts("\n🎯 Testing simple tool calling with raw Req...")

    # Create ReqLLM model
    {:ok, model} = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")
    IO.puts("📋 Model: #{model.provider}:#{model.model}")

    # Create context with user message
    import ReqLLM.Context

    context =
      ReqLLM.Context.new([
        user("I need you to use the available tools to help me. Please call the get_time tool to get the current time, and use the calculator tool to calculate 15 * 8.")
      ])

    # Manual Req setup with tools
    base_request = Req.new(url: "/messages")
    IO.puts("🔧 Base request created")

    # Attach Anthropic provider with tools
    attached_request =
      ReqLLM.Providers.Anthropic.attach(
        base_request,
        model,
        context: context,
        tools: tools,
        max_tokens: 500
      )

    IO.puts("🔌 Anthropic provider attached with #{length(tools)} tools")

    # Make the request
    case Req.request(attached_request, method: :post) do
      {:ok, response} ->
        IO.puts("✅ Tool calling request successful!")
        IO.puts("📊 HTTP Status: #{response.status}")

        # Parse the response body by wrapping it first
        raw_data = response.body
        IO.puts("📄 Raw response data keys: #{inspect(Map.keys(raw_data))}")
        IO.puts("📄 Raw content sample: #{inspect(get_in(raw_data, ["content"]))}")


        wrapped_response = ReqLLM.Providers.Anthropic.wrap_response(raw_data)

        # Debug wrapper before decode
        IO.puts("🔍 Wrapped response structure:")
        IO.puts("   Type: #{inspect(wrapped_response.__struct__)}")
        IO.puts("   Payload keys: #{inspect(wrapped_response.payload |> Map.keys())}")

        # Test decoding directly
        IO.puts("🧪 Testing direct decode...")
        direct_result = ReqLLM.Providers.Anthropic.ResponseDecoder.decode_anthropic_json(
          wrapped_response.payload, 
          model.model
        )
        IO.puts("   Direct decode result: #{inspect(direct_result |> elem(0))}")
        case direct_result do
          {:ok, direct_response} ->
            IO.puts("   Direct message: #{inspect(direct_response.message != nil)}")
            if direct_response.message do
              IO.puts("   Direct content parts: #{length(direct_response.message.content)}")
              Enum.each(direct_response.message.content, fn part ->
                IO.puts("     Part: #{part.type} - #{inspect(part)}")
              end)
            end
          {:error, err} ->
            IO.puts("   Direct decode error: #{inspect(err)}")
        end

        case ReqLLM.Response.decode_response(raw_data, model) do
          {:ok, decoded_response} ->
            IO.puts("✅ Response decoded!")
            IO.puts("📝 Response text: #{ReqLLM.Response.text(decoded_response)}")

            IO.puts(
              "🛠️  Tool calls found: #{length(ReqLLM.Response.tool_calls(decoded_response))}"
            )

            # Extract tool calls from content parts (Anthropic specific)
            tool_call_parts =
              if decoded_response.message && decoded_response.message.content do
                Enum.filter(decoded_response.message.content, &(&1.type == :tool_call))
              else
                []
              end

            if length(tool_call_parts) > 0 do
              IO.puts("\n🔧 Processing tool calls:")

              Enum.each(tool_call_parts, fn tool_call ->
                IO.puts("   - Tool: #{tool_call.tool_name} (ID: #{tool_call.tool_call_id})")
                execute_tool_call_from_response(tool_call, tools)
              end)
            else
              IO.puts("💬 Text response (no tool calls)")
            end

            # Also show the raw Anthropic content structure for reference
            if decoded_response.message && decoded_response.message.content do
              IO.puts("\n📋 Content structure:")

              Enum.with_index(decoded_response.message.content, 1)
              |> Enum.each(fn {content, idx} ->
                IO.puts("   #{idx}. #{inspect(content, limit: :infinity)}")
              end)
            else
              IO.puts("\n📋 No message content found")
              IO.puts("   Response keys: #{inspect(Map.keys(decoded_response))}")
              if Map.has_key?(decoded_response, :error) do
                IO.puts("   Error: #{inspect(decoded_response.error)}")
              end
            end

          {:error, error} ->
            IO.puts("❌ Response decode failed:")
            IO.inspect(error, pretty: true)
        end

      {:error, error} ->
        IO.puts("❌ Tool calling request failed:")
        IO.inspect(error, pretty: true)
    end
  end

  defp test_context_tool_calling(tools) do
    IO.puts("\n🎯 Testing context-based tool calling with raw Req...")

    # Create ReqLLM model
    {:ok, model} = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

    # Create context with system and user messages
    import ReqLLM.Context

    context =
      ReqLLM.Context.new([
        system(
          "You are a helpful assistant with access to weather, time, and calculation tools. Always use the available tools to provide accurate information."
        ),
        user(
          "I need to plan a meeting. Please use the get_weather tool to tell me the weather in New York and use the calculator tool to calculate how much 2.5 * 75 would cost."
        )
      ])

    IO.puts("📨 Context has #{length(context.messages)} messages")

    # Manual Req setup with tools and options
    base_request = Req.new(url: "/messages")

    attached_request =
      ReqLLM.Providers.Anthropic.attach(
        base_request,
        model,
        context: context,
        tools: tools,
        temperature: 0.3,
        max_tokens: 500
      )

    # Make the request
    case Req.request(attached_request, method: :post) do
      {:ok, response} ->
        IO.puts("✅ Context-based tool calling request successful!")
        IO.puts("📊 HTTP Status: #{response.status}")

        # Parse the response body by wrapping it first
        raw_data = response.body
        IO.puts("📄 Raw response data keys: #{inspect(Map.keys(raw_data))}")
        IO.puts("📄 Raw content sample: #{inspect(get_in(raw_data, ["content"]))}")


        wrapped_response = ReqLLM.Providers.Anthropic.wrap_response(raw_data)

        # Debug wrapper before decode
        IO.puts("🔍 Wrapped response structure:")
        IO.puts("   Type: #{inspect(wrapped_response.__struct__)}")
        IO.puts("   Payload keys: #{inspect(wrapped_response.payload |> Map.keys())}")

        # Test decoding directly
        IO.puts("🧪 Testing direct decode...")
        direct_result = ReqLLM.Providers.Anthropic.ResponseDecoder.decode_anthropic_json(
          wrapped_response.payload, 
          model.model
        )
        IO.puts("   Direct decode result: #{inspect(direct_result |> elem(0))}")
        case direct_result do
          {:ok, direct_response} ->
            IO.puts("   Direct message: #{inspect(direct_response.message != nil)}")
            if direct_response.message do
              IO.puts("   Direct content parts: #{length(direct_response.message.content)}")
              Enum.each(direct_response.message.content, fn part ->
                IO.puts("     Part: #{part.type} - #{inspect(part)}")
              end)
            end
          {:error, err} ->
            IO.puts("   Direct decode error: #{inspect(err)}")
        end

        case ReqLLM.Response.decode_response(raw_data, model) do
          {:ok, decoded_response} ->
            IO.puts("✅ Response decoded!")
            IO.puts("📝 Response text: #{ReqLLM.Response.text(decoded_response)}")

            IO.puts(
              "🛠️  Tool calls found: #{length(ReqLLM.Response.tool_calls(decoded_response))}"
            )

            # Extract tool calls from content parts (Anthropic specific)
            tool_call_parts =
              if decoded_response.message && decoded_response.message.content do
                Enum.filter(decoded_response.message.content, &(&1.type == :tool_call))
              else
                []
              end

            if length(tool_call_parts) > 0 do
              IO.puts("\n🔧 Processing tool calls:")

              Enum.with_index(tool_call_parts, 1)
              |> Enum.each(fn {tool_call, idx} ->
                IO.puts("   #{idx}. Tool: #{tool_call.tool_name} (ID: #{tool_call.tool_call_id})")
                execute_tool_call_from_response(tool_call, tools)
              end)
            else
              IO.puts("💬 Text response (no tool calls)")
            end

            # Show the full message structure for debugging
            IO.puts("\n🔍 Message structure:")
            if decoded_response.message do
              IO.puts("   Role: #{decoded_response.message.role}")
              IO.puts("   Content parts: #{length(decoded_response.message.content)}")

              Enum.with_index(decoded_response.message.content, 1)
              |> Enum.each(fn {content, idx} ->
                IO.puts("   #{idx}. #{inspect(content, limit: :infinity)}")
              end)
            else
              IO.puts("   ❌ No message found in response")
              IO.puts("   Response keys: #{inspect(Map.keys(decoded_response))}")
              if Map.has_key?(decoded_response, :error) do
                IO.puts("   Error: #{inspect(decoded_response.error)}")
              end
            end

          {:error, error} ->
            IO.puts("❌ Response decode failed:")
            IO.inspect(error, pretty: true)
        end

      {:error, error} ->
        IO.puts("❌ Context-based tool calling request failed:")
        IO.inspect(error, pretty: true)
    end
  end

  defp execute_tool_call_from_response(
         %ReqLLM.Message.ContentPart{type: :tool_call} = tool_call,
         available_tools
       ) do
    name = tool_call.tool_name
    args = tool_call.input || %{}
    id = tool_call.tool_call_id

    IO.puts("\n🔧 Executing tool: #{name} (ID: #{id})")
    IO.puts("   Arguments: #{inspect(args)}")

    # Find and execute the tool
    case Enum.find(available_tools, &(&1.name == name)) do
      nil ->
        IO.puts("   ❌ Tool not found!")
        {:error, "Tool not found"}

      tool ->
        case ReqLLM.Tool.execute(tool, args) do
          {:ok, result} ->
            IO.puts("   ✅ Success: #{inspect(result)}")
            {:ok, result}

          {:error, error} ->
            IO.puts("   ❌ Error: #{inspect(error)}")
            {:error, error}
        end
    end
  end



  defp create_demo_tools do
    [
      # Weather tool
      ReqLLM.Tool.new!(
        name: "get_weather",
        description: "Get the current weather for a given city",
        parameter_schema: [
          city: [type: :string, required: true, doc: "City name (e.g., 'San Francisco')"]
        ],
        callback: fn %{city: city} ->
          IO.puts("🌤️  Executing weather tool for city: #{city}")

          # Simulate weather API call
          weather_data = %{
            city: city,
            temperature: "#{:rand.uniform(25) + 10}°C",
            conditions: Enum.random(["Sunny", "Partly cloudy", "Cloudy", "Rainy"]),
            humidity: "#{:rand.uniform(40) + 40}%",
            wind: "#{:rand.uniform(15) + 5} km/h"
          }

          {:ok, weather_data}
        end
      ),

      # Calculator tool
      ReqLLM.Tool.new!(
        name: "calculator",
        description: "Perform basic mathematical calculations",
        parameter_schema: [
          expression: [
            type: :string,
            required: true,
            doc: "Mathematical expression (e.g., '15 * 8', '100 + 50')"
          ]
        ],
        callback: fn %{expression: expr} ->
          IO.puts("🧮 Executing calculator tool: #{expr}")

          # Simple expression evaluation (in real app, use a proper parser)
          result =
            try do
              # Very basic evaluation for demo - NOT for production!
              {result, _} = Code.eval_string(expr, [], __ENV__)
              result
            rescue
              _ -> "Error: Cannot evaluate expression '#{expr}'"
            end

          {:ok, %{expression: expr, result: result}}
        end
      ),

      # Time tool
      ReqLLM.Tool.new!(
        name: "get_time",
        description: "Get the current time and date",
        parameter_schema: [
          timezone: [
            type: :string,
            default: "UTC",
            doc: "Timezone (e.g., 'UTC', 'America/New_York')"
          ]
        ],
        callback: fn params ->
          timezone = Map.get(params, :timezone, "UTC")
          IO.puts("🕐 Executing time tool for timezone: #{timezone}")

          now = DateTime.utc_now()
          formatted_time = DateTime.to_string(now)

          {:ok,
           %{
             current_time: formatted_time,
             timezone: timezone,
             unix_timestamp: DateTime.to_unix(now)
           }}
        end
      )
    ]
  end
end

# Run the demo
AnthropicToolCallingDemo.run()
