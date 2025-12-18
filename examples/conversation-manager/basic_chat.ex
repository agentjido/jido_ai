defmodule Examples.ConversationManager.BasicChat do
  @moduledoc """
  Basic multi-turn conversation example with tool integration.

  Demonstrates:
  - Starting a conversation with tools
  - Multiple conversation turns
  - Tool execution (weather lookups)
  - Conversation history tracking
  - Proper conversation cleanup

  ## Usage

      # Run the example
      Examples.ConversationManager.BasicChat.run()

      # Start your own conversation
      {:ok, conv_id} = Examples.ConversationManager.BasicChat.start_chat([WeatherAction])
      {:ok, response} = Examples.ConversationManager.BasicChat.chat(conv_id, "What's the weather?")
      :ok = Examples.ConversationManager.BasicChat.end_chat(conv_id)
  """

  alias Jido.AI.Conversation.Manager, as: ConversationManager
  alias Jido.AI.Tools.Manager, as: ToolsManager
  alias Jido.AI.Model

  @doc """
  Run the basic chat example demonstrating multi-turn conversation.
  """
  def run do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  Conversation Manager: Basic Multi-Turn Chat")
    IO.puts(String.duplicate("=", 70) <> "\n")

    IO.puts("This example demonstrates stateful multi-turn conversations with tool calls\n")
    IO.puts(String.duplicate("-", 70) <> "\n")

    # Start conversation with weather tool
    IO.puts("Starting conversation with WeatherAction...")

    case start_chat([MockWeatherAction]) do
      {:ok, conv_id} ->
        IO.puts("Conversation started: #{String.slice(conv_id, 0, 8)}...\n")

        # Conversation flow
        conversation_flow(conv_id)

        # Show final history
        display_conversation_history(conv_id)

        # Cleanup
        end_chat(conv_id)
        IO.puts("\nConversation ended successfully")

      {:error, reason} ->
        IO.puts("Error: Failed to start conversation: #{inspect(reason)}")
    end

    IO.puts("\n" <> String.duplicate("=", 70))
  end

  @doc """
  Starts a new conversation with the given tools.
  """
  def start_chat(tools, options \\ []) do
    # Create model - defaults to GPT-4
    model_spec = Keyword.get(options, :model, {:openai, [model: "gpt-4"]})

    case Model.from(model_spec) do
      {:ok, model} ->
        system_prompt = Keyword.get(options, :system_prompt, "You are a helpful assistant with access to tools.")

        ConversationManager.create(model,
          system_prompt: system_prompt,
          options: %{
            temperature: Keyword.get(options, :temperature, 0.7),
            max_tokens: Keyword.get(options, :max_tokens, 1000)
          }
        )

      {:error, reason} ->
        {:error, {:model_error, reason}}
    end
  end

  @doc """
  Sends a message in the conversation and gets a response.
  """
  def chat(conversation_id, message, tools \\ [MockWeatherAction]) do
    ToolsManager.process(conversation_id, message, tools, max_iterations: 5)
  end

  @doc """
  Ends the conversation and cleans up resources.
  """
  def end_chat(conversation_id) do
    ConversationManager.delete(conversation_id)
  end

  @doc """
  Gets the conversation history.
  """
  def get_history(conversation_id) do
    ConversationManager.get_messages(conversation_id)
  end

  # Private Functions

  defp conversation_flow(conv_id) do
    # Turn 1: Ask about weather in Paris
    IO.puts("User: What's the weather like in Paris?")

    case chat(conv_id, "What's the weather like in Paris?") do
      {:ok, response} ->
        display_response(response, 1)

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}\n")
    end

    # Short delay for readability
    Process.sleep(500)

    # Turn 2: Ask about weather in London
    IO.puts("User: And what about London?")

    case chat(conv_id, "And what about London?") do
      {:ok, response} ->
        display_response(response, 2)

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}\n")
    end

    # Short delay for readability
    Process.sleep(500)

    # Turn 3: Ask comparative question (uses context)
    IO.puts("User: Which city is warmer?")

    case chat(conv_id, "Which city is warmer?") do
      {:ok, response} ->
        display_response(response, 3)

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}\n")
    end
  end

  defp display_response(response, turn_number) do
    IO.puts("\nAssistant (Turn #{turn_number}):")

    content = Map.get(response, :content, "")

    if content != "" do
      IO.puts("   #{content}")
    end

    tool_calls_made = Map.get(response, :tool_calls_made, 0)

    if tool_calls_made > 0 do
      IO.puts("\n   Tool iterations: #{tool_calls_made}")
    end

    IO.puts("")
  end

  defp display_conversation_history(conv_id) do
    IO.puts(String.duplicate("-", 70))
    IO.puts("\nConversation History:\n")

    case get_history(conv_id) do
      {:ok, history} ->
        IO.puts("   Total messages: #{length(history)}\n")

        history
        |> Enum.with_index(1)
        |> Enum.each(fn {msg, idx} ->
          role = msg.role
          content = msg.content

          role_display =
            case role do
              :user -> "User"
              :assistant -> "Assistant"
              :tool -> "Tool"
              :system -> "System"
              _ -> to_string(role)
            end

          IO.puts("   #{idx}. #{role_display}")

          preview =
            if String.length(content) > 60 do
              String.slice(content, 0, 60) <> "..."
            else
              content
            end

          IO.puts("      \"#{preview}\"")
          IO.puts("")
        end)

      {:error, reason} ->
        IO.puts("   Error retrieving history: #{inspect(reason)}")
    end
  end
end

# Mock Weather Action for demonstration purposes
defmodule Examples.ConversationManager.MockWeatherAction do
  @moduledoc """
  Mock weather action for demonstration.
  Returns simulated weather data based on location.
  """

  use Jido.Action,
    name: "get_weather",
    description: "Get current weather information for a city",
    schema: [
      location: [
        type: :string,
        required: true,
        doc: "City name to get weather for"
      ],
      units: [
        type: {:in, ["celsius", "fahrenheit"]},
        default: "celsius",
        doc: "Temperature units"
      ]
    ]

  @impl true
  def run(params, _context) do
    location = params.location
    units = Map.get(params, :units, "celsius")

    # Simulate weather data
    weather_data = get_mock_weather(location, units)

    {:ok, weather_data}
  end

  defp get_mock_weather(location, units) do
    # Simulated weather based on city
    {temp, description} =
      case String.downcase(location) do
        loc when loc in ["paris", "france"] ->
          if units == "celsius", do: {18, "Partly cloudy"}, else: {64, "Partly cloudy"}

        loc when loc in ["london", "england", "uk"] ->
          if units == "celsius", do: {15, "Rainy"}, else: {59, "Rainy"}

        loc when loc in ["tokyo", "japan"] ->
          if units == "celsius", do: {22, "Clear"}, else: {72, "Clear"}

        loc when loc in ["new york", "nyc"] ->
          if units == "celsius", do: {20, "Sunny"}, else: {68, "Sunny"}

        _ ->
          if units == "celsius", do: {20, "Partly cloudy"}, else: {68, "Partly cloudy"}
      end

    unit_symbol = if units == "celsius", do: "C", else: "F"

    %{
      location: location,
      temperature: temp,
      units: units,
      description: description,
      formatted: "#{temp} #{unit_symbol}, #{description}"
    }
  end
end
