# Jido AI Agent Demo
#
# This script demonstrates how to use the new Jido.AI.Agent for various AI operations.
# To run: `elixir examples/ai_agent_demo.exs`

defmodule AIAgentDemo do
  @moduledoc """
  Interactive demo showing Jido.AI.Agent capabilities.
  """

  alias Jido.AI.Agent

  def run do
    IO.puts("=== Jido AI Agent Demo ===\n")

    # Start an AI agent with custom configuration
    IO.puts("1. Starting AI Agent...")
    {:ok, pid} = Agent.start_link(
      id: "demo_agent",
      default_model: "openai:gpt-4o",
      temperature: 0.7,
      max_tokens: 1000,
      system_prompt: "You are a helpful AI assistant."
    )

    IO.puts("   ✓ Agent started with PID: #{inspect(pid)}")
    IO.puts("   ✓ Agent alive? #{Jido.agent_alive?(pid)}")

    # Demo text generation (commented out as it requires API keys)
    IO.puts("\n2. Text Generation Examples:")
    demo_text_generation(pid)

    # Demo object generation (commented out as it requires API keys)
    IO.puts("\n3. Object Generation Examples:")
    demo_object_generation(pid)

    # Demo streaming (commented out as it requires API keys)
    IO.puts("\n4. Tool Calling Examples:")
    demo_tool_calling(pid)

    IO.puts("\n5. Streaming Examples:")
    demo_streaming(pid)

    IO.puts("\n=== Demo Complete ===")

    # Clean up
    GenServer.stop(pid, :normal)
    IO.puts("Agent stopped.")
  end

  defp demo_text_generation(pid) do
    IO.puts("   • Simple text generation:")
    IO.puts(~s|     Jido.AI.Agent.generate_text(pid, "Hello, how are you?")|)

    case Jido.AI.Agent.generate_text(pid, "Hello, how are you?") do
      {:ok, text} ->
        IO.puts("     ✓ Response: #{String.slice(text, 0, 80)}#{if String.length(text) > 80, do: "...", else: ""}")
      {:error, reason} ->
        IO.puts("     ✗ Error: #{inspect(reason)}")
    end

    IO.puts("\n   • Text generation with options:")
    IO.puts(~s|     Jido.AI.Agent.generate_text(pid, "Explain AI", model: "openai:gpt-3.5-turbo", temperature: 0.3)|)

    case Jido.AI.Agent.generate_text(pid, "Explain AI", model: "openai:gpt-3.5-turbo", temperature: 0.3) do
      {:ok, text} ->
        IO.puts("     ✓ Response: #{String.slice(text, 0, 80)}#{if String.length(text) > 80, do: "...", else: ""}")
      {:error, reason} ->
        IO.puts("     ✗ Error: #{inspect(reason)}")
    end
  end

  defp demo_object_generation(pid) do
    IO.puts("   • Structured object generation:")
    schema = [
      name: [type: :string, required: true],
      age: [type: :integer, required: true],
      hobbies: [type: {:list, :string}, required: false]
    ]

    IO.puts("     Schema: #{inspect(schema)}")
    IO.puts(~s|     Jido.AI.Agent.generate_object(pid, "Create a person profile", schema: schema)|)

    case Jido.AI.Agent.generate_object(pid, "Create a person profile", schema: schema) do
      {:ok, object} ->
        IO.puts("     ✓ Object: #{inspect(object)}")
      {:error, reason} ->
        IO.puts("     ✗ Error: #{inspect(reason)}")
    end

    IO.puts("\n   • Schema validation:")
    IO.puts("     Calling without schema parameter...")

    try do
      Jido.AI.Agent.generate_object(pid, "Create something")
    rescue
      e in ArgumentError ->
        IO.puts("     ✓ Properly caught error: #{e.message}")
    end
  end

  defp demo_tool_calling(pid) do
    # Define some simple actions that can be used as tools
    simple_actions = [
      Jido.Tools.Arithmetic.Add,
      Jido.Tools.Arithmetic.Multiply,
      Jido.Tools.Basic.Today,
      Jido.Tools.Basic.Log
    ]

    IO.puts("   • Text generation with tool calling:")
    IO.puts("     Available tools: Add, Multiply, Today, Log")
    IO.puts(~s|     Jido.AI.Agent.generate_text(pid, "Calculate 15 + 27, then multiply by 3, and tell me today's date", actions: actions)|)

    case Jido.AI.Agent.generate_text(pid, "Calculate 15 + 27, then multiply by 3, and tell me today's date. Use the available tools to help with calculations and getting today's date.", actions: simple_actions) do
      {:ok, text} ->
        IO.puts("     ✓ Response with tool usage: #{String.slice(text, 0, 150)}#{if String.length(text) > 150, do: "...", else: ""}")
      {:error, reason} ->
        IO.puts("     ✗ Error: #{inspect(reason)}")
    end

    IO.puts("\n   • Object generation with tool calling:")
    schema = [
      calculation_result: [type: :integer, required: true],
      steps: [type: {:list, :string}, required: true],
      today: [type: :string, required: true]
    ]

    IO.puts("     Schema: #{inspect(schema)}")
    IO.puts(~s|     Jido.AI.Agent.generate_object(pid, "Use tools to calculate 8 * 6 + 10 and get today's date", schema: schema, actions: actions)|)

    case Jido.AI.Agent.generate_object(pid, "Use the available tools to calculate 8 * 6 + 10 and get today's date. Return the result in the specified schema format.", schema: schema, actions: simple_actions) do
      {:ok, object} ->
        IO.puts("     ✓ Structured result with tool usage:")
        Enum.each(object, fn {key, value} ->
          display_value = case value do
            list when is_list(list) -> "[#{Enum.join(list, ", ")}]"
            other -> inspect(other)
          end
          IO.puts("       #{key}: #{display_value}")
        end)
      {:error, reason} ->
        IO.puts("     ✗ Error: #{inspect(reason)}")
    end
  end

  defp demo_streaming(pid) do
    IO.puts("   • Streaming text generation:")
    IO.puts(~s|     Jido.AI.Agent.stream_text(pid, "Tell me a short story")|)

    case Jido.AI.Agent.stream_text(pid, "Tell me a short story") do
      {:ok, stream} ->
        stream_type = cond do
          is_function(stream) -> "Stream function"
          is_list(stream) -> "List"
          is_struct(stream) -> inspect(stream.__struct__)
          true -> "Unknown"
        end
        IO.puts("     ✓ Stream received, type: #{stream_type}")
        # Would normally iterate: Enum.each(stream, &IO.write/1)
      {:error, reason} ->
        IO.puts("     ✗ Error: #{inspect(reason)}")
    end

    IO.puts("\n   • Streaming object generation:")
    schema = [
      items: [type: {:list, :string}, required: true]
    ]

    IO.puts("     Schema: #{inspect(schema)}")
    IO.puts(~s|     Jido.AI.Agent.stream_object(pid, "Generate a list of items", schema: schema)|)

    case Jido.AI.Agent.stream_object(pid, "Generate a list of items", schema: schema) do
      {:ok, stream} ->
        stream_type = cond do
          is_function(stream) -> "Stream function"
          is_list(stream) -> "List"
          is_struct(stream) -> inspect(stream.__struct__)
          true -> "Unknown"
        end
        IO.puts("     ✓ Stream received, type: #{stream_type}")
      {:error, reason} ->
        IO.puts("     ✗ Error: #{inspect(reason)}")
    end
  end
end

# Run the demo if this file is executed directly
if Path.basename(__ENV__.file) == "ai_agent_demo.exs" do
  AIAgentDemo.run()
end
