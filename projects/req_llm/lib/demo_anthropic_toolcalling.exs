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
    test_simple_tool_calling(tools)

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
        user("What's the current time? Also, can you calculate 15 * 8 for me?")
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

        # Parse the response body using codec
        case ReqLLM.Context.Codec.decode(response.body) do
          {:ok, decoded_context} ->
            IO.puts("✅ Response body decoded!")
            IO.puts("📝 Messages in response: #{length(decoded_context.messages)}")

            # Find assistant messages and check for tool calls
            assistant_messages = Enum.filter(decoded_context.messages, &(&1.role == :assistant))

            Enum.each(assistant_messages, fn msg ->
              IO.puts("🤖 Assistant message: #{inspect(msg.content)}")

              # Check for tool calls in message content
              case msg.content do
                [%{type: "tool_use"} | _] = content_blocks ->
                  tool_calls = Enum.filter(content_blocks, &(&1.type == "tool_use"))
                  IO.puts("🛠️  Found #{length(tool_calls)} tool calls")

                  Enum.each(tool_calls, fn tool_call ->
                    IO.puts("   - Tool: #{tool_call.name}")
                    IO.puts("   - Input: #{inspect(tool_call.input)}")
                    execute_tool_call_raw(tool_call, tools)
                  end)

                _ ->
                  IO.puts("💬 Text response (no tool calls)")
              end
            end)

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
          "You are a helpful assistant with access to weather, time, and calculation tools."
        ),
        user(
          "I need to plan a meeting. Can you tell me the weather in New York and calculate how much 2.5 hours at $75 per hour would cost?"
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

        # Parse the response body
        case ReqLLM.Context.Codec.decode(response.body) do
          {:ok, decoded_context} ->
            IO.puts("✅ Response decoded!")
            IO.puts("📝 Total messages: #{length(decoded_context.messages)}")

            # Show all messages and process tool calls
            decoded_context.messages
            |> Enum.with_index(1)
            |> Enum.each(fn {msg, idx} ->
              IO.puts("   #{idx}. #{msg.role}: #{inspect(msg.content)}")

              # Process tool calls if this is an assistant message
              if msg.role == :assistant do
                case msg.content do
                  [%{type: "tool_use"} | _] = content_blocks ->
                    tool_calls = Enum.filter(content_blocks, &(&1.type == "tool_use"))

                    Enum.each(tool_calls, fn tool_call ->
                      execute_tool_call_raw(tool_call, tools)
                    end)

                  _ ->
                    :ok
                end
              end
            end)

          {:error, error} ->
            IO.puts("❌ Context decode failed:")
            IO.inspect(error, pretty: true)
        end

      {:error, error} ->
        IO.puts("❌ Context-based tool calling request failed:")
        IO.inspect(error, pretty: true)
    end
  end

  defp execute_tool_call_raw(tool_call, available_tools) do
    name = tool_call.name
    args = tool_call.input || %{}
    id = tool_call.id

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
