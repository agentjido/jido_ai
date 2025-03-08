# Integrating Jido AI Skills in Your Agents

## Introduction

This guide explains how to leverage the Jido AI skill to add AI capabilities to your Jido agents. The Jido AI skill provides a modular approach to integrating large language models (LLMs) into your applications, enabling agents to perform natural language processing, chat completions, and tool invocation with minimal configuration.

## Understanding Jido Skills

In the Jido framework, skills are modular components that encapsulate specific functionality, similar to plugins. They provide:

- Signal routing and handling patterns
- Isolated state management
- Process supervision
- Configuration validation

Skills enable you to extend your agent's capabilities without modifying its core functionality, following the principle of composition over inheritance.

## The Jido AI Skill

The Jido AI skill is a specialized skill that provides AI capabilities to your agents. It acts as a bridge between your application and various AI providers (OpenAI, Anthropic, etc.) through the Jido AI library.

### Core Features

- **Chat completions**: Generate conversational responses
- **Tool usage**: Invoke agent tools using LLM-driven reasoning
- **Multiple providers**: Support for various AI providers
- **Prompt management**: Structured prompt handling with history

## Getting Started

### Basic Setup

First, ensure you have the `jido_ai` package in your dependencies:

```elixir
def deps do
  [
    {:jido, "~> 0.1.0"},
    {:jido_ai, "~> 0.1.0"}
  ]
end
```

Next, set up your API keys in your configuration:

```elixir
# In config/config.exs
config :jido_ai, :keyring,
  openai: [api_key: System.get_env("OPENAI_API_KEY")],
  anthropic: [api_key: System.get_env("ANTHROPIC_API_KEY")]
```

### Creating an Agent with the AI Skill

Here's a minimal example of an agent that uses the Jido AI skill:

```elixir
defmodule MyApp.AssistantAgent do
  use Jido.Agent,
    name: "assistant_agent",
    description: "An agent with AI capabilities"

  @default_opts [
    skills: [Jido.AI.Skill],
    ai: [
      model: "gpt-4-turbo",
      prompt: "You are a helpful AI assistant."
    ]
  ]

  def start_link(opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)
    Jido.Agent.Server.start_link(opts)
  end

  def chat(pid, message) when is_binary(message) do
    Jido.AI.Skill.chat_response(pid, message)
  end
end
```

This creates a simple agent with AI capabilities, using GPT-4 as the default model.

## Configuration Options

The Jido AI skill provides several configuration options:

| Option | Type | Description |
|--------|------|-------------|
| `model` | String or Model struct | The AI model to use (required) |
| `prompt` | String or Prompt struct | The default instructions (default: "You are a helpful assistant") |
| `response_schema` | Keyword list | A NimbleOptions schema to validate the AI response |
| `chat_action` | Module | The chat action to use (default: `Jido.AI.Actions.Instructor.ChatResponse`) |
| `tool_action` | Module | The default tool action to use (default: `Jido.AI.Actions.Langchain.GenerateToolResponse`) |
| `tools` | List of modules | The tools to make available to the AI |

### Model Configuration

You can specify the model in different ways:

```elixir
# By string identifier
ai: [model: "gpt-4-turbo"]

# By provider and model name
ai: [model: [provider: :openai, name: "gpt-4-turbo"]]

# As a Model struct
ai: [model: %Jido.AI.Model{provider: :openai, name: "gpt-4-turbo"}]
```

### Prompt Configuration

Prompts can be specified as strings or using the Prompt struct for more control:

```elixir
# Simple string prompt
ai: [prompt: "You are a helpful assistant skilled in Elixir programming."]

# Using the Prompt struct for more control
ai: [
  prompt: Jido.AI.Prompt.new()
  |> Jido.AI.Prompt.add_message(:system, "You are a helpful assistant.")
  |> Jido.AI.Prompt.add_message(:user, "Initial context: We're building an Elixir app.")
]
```

## Advanced Usage

### Adding Tools to Your Agent

Tools allow your AI to perform specific actions. Here's an example of configuring tools:

```elixir
defmodule MyApp.Calculator do
  use Jido.Action,
    name: "calculator",
    description: "Perform arithmetic calculations",
    schema: [
      expression: [type: :string, required: true]
    ]

  def run(%{expression: expr}, _context) do
    case Code.eval_string(expr) do
      {result, _} -> {:ok, %{result: result}}
      error -> {:error, "Failed to evaluate: #{inspect(error)}"}
    end
  end
end

defmodule MyApp.EnhancedAssistant do
  use Jido.Agent,
    name: "enhanced_assistant",
    description: "Assistant with calculation capabilities"

  @default_opts [
    skills: [Jido.AI.Skill],
    ai: [
      model: "gpt-4-turbo",
      prompt: "You are a helpful assistant with calculation abilities.",
      tools: [MyApp.Calculator]
    ]
  ]

  def start_link(opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)
    Jido.Agent.Server.start_link(opts)
  end

  def chat(pid, message) do
    Jido.AI.Skill.chat_response(pid, message)
  end

  def calculate(pid, message) do
    Jido.AI.Skill.tool_response(pid, message)
  end
end
```

### Custom Actions

You can customize how the AI processes requests by providing custom actions:

```elixir
defmodule MyApp.CustomChatResponse do
  use Jido.AI.Actions.Instructor.ChatResponse,
    name: "custom_chat_response"

  # Override preprocessing to add additional context
  def preprocess(params, context) do
    params = Map.put(params, :temperature, 0.7)
    
    prompt = params.prompt
    prompt = Jido.AI.Prompt.add_message(prompt, :system, "Remember to be concise.")
    
    params = Map.put(params, :prompt, prompt)
    
    super(params, context)
  end

  # Override postprocessing to format the response
  def postprocess(result, _params, _context) do
    case result do
      {:ok, response} ->
        formatted = "Response: #{response}"
        {:ok, formatted}
      other -> other
    end
  end
end

defmodule MyApp.CustomAssistant do
  use Jido.Agent,
    name: "custom_assistant"

  @default_opts [
    skills: [Jido.AI.Skill],
    ai: [
      model: "gpt-4-turbo",
      prompt: "You are a helpful assistant.",
      chat_action: MyApp.CustomChatResponse
    ]
  ]

  def start_link(opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)
    Jido.Agent.Server.start_link(opts)
  end
end
```

## A Complete Example

Here's a full-featured example that demonstrates various capabilities:

```elixir
defmodule MyApp.WeatherTool do
  use Jido.Action,
    name: "get_weather",
    description: "Get the current weather for a location",
    schema: [
      location: [type: :string, required: true]
    ]

  def run(%{location: location}, _context) do
    # In a real app, this would call a weather API
    {:ok, %{
      temperature: 72,
      conditions: "Sunny",
      location: location,
      humidity: 45,
      wind_speed: 8
    }}
  end
end

defmodule MyApp.AssistantWithHistory do
  use Jido.Agent,
    name: "assistant_with_history",
    description: "An agent that maintains conversation history"

  @system_prompt """
  You are a helpful AI assistant with access to weather information.
  
  When providing weather information, always mention:
  1. Temperature
  2. Conditions
  3. Humidity
  4. Wind speed
  
  Keep your responses concise and informative.
  """

  @default_opts [
    skills: [Jido.AI.Skill],
    ai: [
      model: "claude-3-haiku-20240307",
      prompt: @system_prompt,
      tools: [MyApp.WeatherTool]
    ]
  ]

  def start_link(opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)
    Jido.Agent.Server.start_link(opts)
  end

  def chat(pid, message, history \\ []) do
    # Build a prompt with history
    prompt = Jido.AI.Prompt.new(:system, @system_prompt)
    
    # Add history messages
    prompt = Enum.reduce(history, prompt, fn {role, content}, acc ->
      Jido.AI.Prompt.add_message(acc, role, content)
    end)
    
    # Add the current message
    prompt = Jido.AI.Prompt.add_message(prompt, :user, message)
    
    # Create signal with the prompt
    {:ok, signal} =
      Jido.Signal.new(%{
        type: "jido.ai.chat.response",
        data: %{
          prompt: prompt,
          history: history,
          message: message
        }
      })
    
    # Process the signal
    result = Jido.Agent.Server.call(pid, signal)
    
    # Update history
    updated_history = history ++ [{:user, message}, {:assistant, result}]
    
    {result, updated_history}
  end
end
```

### Using the Complete Example

```elixir
# Start the agent
{:ok, agent} = MyApp.AssistantWithHistory.start_link()

# First interaction
{response1, history1} = MyApp.AssistantWithHistory.chat(agent, "What's the weather like in New York?")
# => {"The current weather in New York is 72°F and sunny, with 45% humidity and wind speed of 8 mph.", 
#     [{:user, "What's the weather like in New York?"}, 
#      {:assistant, "The current weather in New York is 72°F and sunny, with 45% humidity and wind speed of 8 mph."}]}

# Second interaction, using the updated history
{response2, history2} = MyApp.AssistantWithHistory.chat(agent, "How about tomorrow?", history1)
# The AI will now respond with context from the previous interaction
```

## Best Practices

1. **Model Selection**: Choose the right model for your use case, balancing capability and cost
2. **Prompt Engineering**: Craft clear, specific prompts to guide the AI's responses
3. **Error Handling**: Always handle potential errors from AI providers gracefully
4. **Response Validation**: Consider using response schemas to validate and structure AI outputs
5. **Testing**: Create tests with mock responses to ensure your agent behaves as expected

## Troubleshooting

### Common Issues

1. **API Key Errors**: Ensure your API keys are correctly configured in the keyring
2. **Model Availability**: Verify that the selected model is available with your current API plan
3. **Timeout Errors**: For complex requests, consider increasing timeouts in your configuration
4. **Rate Limiting**: Implement backoff strategies for high-volume applications

## Conclusion

The Jido AI skill provides a powerful, flexible way to integrate AI capabilities into your Jido agents. By following this guide, you can create agents that leverage state-of-the-art language models while maintaining the robust, scalable architecture that the Jido framework provides.

For more information, see the following resources:

- [Jido AI Documentation](https://hexdocs.pm/jido_ai)
- [Jido Skills Overview](../skills/overview.md)
- [Testing Skills](../skills/testing.md)