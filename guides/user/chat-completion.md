# Chat Completion

The `Jido.AI.Actions.ReqLlm.ChatCompletion` action provides chat completion functionality across 57+ providers through ReqLLM integration.

## Basic Usage

```elixir
alias Jido.AI.Actions.ReqLlm.ChatCompletion
alias Jido.AI.{Model, Prompt}

# Create model and prompt
{:ok, model} = Model.from({:openai, [model: "gpt-4o"]})
prompt = Prompt.new(:user, "What is the capital of France?")

# Run the completion
{:ok, result, _directives} = ChatCompletion.run(%{
  model: model,
  prompt: prompt
})

IO.puts(result.content)
# => "The capital of France is Paris."
```

## Parameters

### Required Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `model` | `Model.t()` or tuple | The AI model to use |
| `prompt` | `Prompt.t()` or string | The prompt/messages to send |

### Optional Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `temperature` | float | 0.7 | Randomness (0.0-2.0) |
| `max_tokens` | integer | 1000 | Maximum tokens in response |
| `top_p` | float | nil | Nucleus sampling parameter |
| `stop` | list(string) | nil | Stop sequences |
| `timeout` | integer | 60000 | Request timeout in ms |
| `stream` | boolean | false | Enable streaming |
| `max_retries` | integer | 0 | Retries for failures |
| `frequency_penalty` | float | nil | Frequency penalty |
| `presence_penalty` | float | nil | Presence penalty |
| `json_mode` | boolean | false | Force JSON output |
| `verbose` | boolean | false | Enable verbose logging |
| `tools` | list(atom) | nil | Tool/function modules |

## Model Specification

Models can be specified in several ways:

```elixir
# As a tuple
{:ok, result, _} = ChatCompletion.run(%{
  model: {:openai, [model: "gpt-4o"]},
  prompt: prompt
})

# As a pre-created Model struct
{:ok, model} = Model.from({:anthropic, [model: "claude-3-5-sonnet-20241022"]})
{:ok, result, _} = ChatCompletion.run(%{
  model: model,
  prompt: prompt
})
```

## Working with Prompts

### Simple Prompts

```elixir
# String is converted to system message
{:ok, result, _} = ChatCompletion.run(%{
  model: {:openai, [model: "gpt-4o"]},
  prompt: "You are a helpful assistant."
})

# Using Prompt.new for user messages
prompt = Prompt.new(:user, "Hello!")
```

### Multi-turn Conversations

```elixir
prompt = Prompt.new(%{
  messages: [
    %{role: :system, content: "You are a helpful coding assistant."},
    %{role: :user, content: "How do I create a GenServer in Elixir?"},
    %{role: :assistant, content: "Here's a basic GenServer example..."},
    %{role: :user, content: "Can you add a handle_cast callback?"}
  ]
})

{:ok, result, _} = ChatCompletion.run(%{
  model: {:openai, [model: "gpt-4o"]},
  prompt: prompt
})
```

### Templated Prompts

```elixir
prompt = Prompt.new(%{
  messages: [
    %{role: :system, content: "You are an expert in <%= @language %>.", engine: :eex},
    %{role: :user, content: "Explain <%= @concept %> to me.", engine: :eex}
  ],
  params: %{
    language: "Elixir",
    concept: "pattern matching"
  }
})

{:ok, result, _} = ChatCompletion.run(%{
  model: {:openai, [model: "gpt-4o"]},
  prompt: prompt
})
```

## Streaming Responses

Enable streaming for real-time output:

```elixir
{:ok, stream} = ChatCompletion.run(%{
  model: {:openai, [model: "gpt-4o"]},
  prompt: Prompt.new(:user, "Write a short story."),
  stream: true
})

# Process chunks as they arrive
Enum.each(stream, fn chunk ->
  IO.write(chunk.content)
end)
```

## Tool/Function Calling

Pass Jido.Action modules for function calling:

```elixir
defmodule MyApp.Actions.GetWeather do
  use Jido.Action,
    name: "get_weather",
    description: "Get the current weather for a location",
    schema: [
      location: [type: :string, required: true, doc: "City name"]
    ]

  def run(params, _context) do
    # Implementation
    {:ok, %{temperature: 72, conditions: "sunny"}}
  end
end

{:ok, result, _} = ChatCompletion.run(%{
  model: {:openai, [model: "gpt-4o"]},
  prompt: Prompt.new(:user, "What's the weather in Tokyo?"),
  tools: [MyApp.Actions.GetWeather]
})

# Result includes tool_results if function was called
IO.inspect(result.tool_results)
# => [%{name: "get_weather", arguments: %{"location" => "Tokyo"}, result: nil}]
```

## Response Format

The result map contains:

```elixir
%{
  content: "The response text from the LLM",
  tool_results: [],  # List of tool calls if any
  usage: %{...}      # Optional - token usage and cost data
}
```

With tool calls:

```elixir
%{
  content: "I'll check the weather for you.",
  tool_results: [
    %{
      name: "get_weather",
      arguments: %{"location" => "Tokyo"},
      result: nil  # Populated after you execute the tool
    }
  ],
  usage: %{input_tokens: 25, output_tokens: 15, total_tokens: 40, ...}
}
```

### Usage Data

When the provider returns token usage, it is normalized into a consistent structure:

```elixir
%{
  input_tokens: 15,
  output_tokens: 25,
  total_tokens: 40,
  reasoning_tokens: 0,       # For reasoning models (o1, o3, Gemini thinking)
  cached_tokens: 0,          # Tokens read from cache
  cache_creation_tokens: 0,  # Tokens written to cache
  input_cost: 0.00015,       # Cost in USD (when model has pricing data)
  output_cost: 0.00075,
  total_cost: 0.0009
}
```

Cost fields are included when the model has pricing metadata available.

## Controlling Response Quality

### Temperature

Lower values produce more focused/deterministic responses:

```elixir
# Deterministic (good for code, facts)
{:ok, result, _} = ChatCompletion.run(%{
  model: {:openai, [model: "gpt-4o"]},
  prompt: prompt,
  temperature: 0.1
})

# Creative (good for stories, brainstorming)
{:ok, result, _} = ChatCompletion.run(%{
  model: {:openai, [model: "gpt-4o"]},
  prompt: prompt,
  temperature: 0.9
})
```

### Max Tokens

Limit response length:

```elixir
{:ok, result, _} = ChatCompletion.run(%{
  model: {:openai, [model: "gpt-4o"]},
  prompt: prompt,
  max_tokens: 500
})
```

### JSON Mode

Force JSON output (provider-dependent):

```elixir
{:ok, result, _} = ChatCompletion.run(%{
  model: {:openai, [model: "gpt-4o"]},
  prompt: Prompt.new(:user, "List 3 programming languages as JSON"),
  json_mode: true
})
```

## Error Handling

```elixir
case ChatCompletion.run(%{model: model, prompt: prompt}) do
  {:ok, result, directives} ->
    IO.puts("Response: #{result.content}")

  {:error, reason} ->
    Logger.error("Chat completion failed: #{inspect(reason)}")
end
```

## Verbose Logging

Enable detailed logging for debugging:

```elixir
{:ok, result, _} = ChatCompletion.run(%{
  model: {:openai, [model: "gpt-4o"]},
  prompt: prompt,
  verbose: true
})
```

## Provider Support

The action supports all ReqLLM providers (57+):

| Provider | Example Model |
|----------|---------------|
| OpenAI | `gpt-4o`, `gpt-4o-mini` |
| Anthropic | `claude-3-5-sonnet-20241022` |
| Google | `gemini-pro`, `gemini-1.5-pro` |
| Mistral | `mistral-large-latest` |
| Groq | `llama-3.1-70b-versatile` |
| Cohere | `command-r-plus` |
| Ollama | `llama3.2`, `mistral` |

See ReqLLM documentation for the full provider list.
