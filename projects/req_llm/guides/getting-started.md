# Getting Started with ReqLLM

ReqLLM is a composable Elixir library for AI interactions built on Req, providing a unified interface to AI providers through a plugin-based architecture.

## Installation

Add to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:req_llm, "~> 0.1.0"}
  ]
end
```

Run `mix deps.get` to install.

## First API Call

### Basic Text Generation

```elixir
# Store your API key (one-time setup)
ReqLLM.put_key(:anthropic_api_key, "sk-ant-...")

# Generate text
{:ok, text} = ReqLLM.generate_text!("anthropic:claude-3-5-sonnet", "Hello world")
# => "Hello! How can I assist you today?"
```

### Streaming Text Generation

```elixir
{:ok, stream} = ReqLLM.stream_text!("anthropic:claude-3-5-sonnet", "Tell me a story")
stream |> Enum.each(&IO.write/1)
```

### Full Response with Metadata

```elixir
{:ok, response} = ReqLLM.generate_text("anthropic:claude-3-5-sonnet", "Hello")

# Access response body
response.body

# Extract usage information
{:ok, text, usage} = 
  ReqLLM.generate_text("anthropic:claude-3-5-sonnet", "Hello") 
  |> ReqLLM.with_usage()

# usage => %{tokens: %{input: 5, output: 12}, cost: 0.00042}
```

## Model Specifications

ReqLLM accepts three model formats:

### String Format

```elixir
# Simple provider:model format
ReqLLM.generate_text!("anthropic:claude-3-5-sonnet", prompt)
ReqLLM.generate_text!("anthropic:claude-3-haiku", prompt)
```

### Tuple Format

```elixir
# With options
ReqLLM.generate_text!(
  {:anthropic, "claude-3-5-sonnet", temperature: 0.7}, 
  prompt
)
```

### Model Struct Format

```elixir
model = %ReqLLM.Model{
  provider: :anthropic, 
  model: "claude-3-5-sonnet", 
  temperature: 0.5
}
ReqLLM.generate_text!(model, prompt)
```

## Key Management

ReqLLM integrates with [Kagi](https://github.com/jidoworkspace/kagi) for secure key storage:

### Storing Keys

```elixir
# Store API keys in session keyring
ReqLLM.put_key(:anthropic_api_key, "sk-ant-...")
ReqLLM.put_key(:openai_api_key, "sk-...")

# Case-insensitive keys work too
ReqLLM.put_key("ANTHROPIC_API_KEY", "sk-ant-...")
```

### Retrieving Keys

```elixir
api_key = ReqLLM.get_key(:anthropic_api_key)
api_key = ReqLLM.get_key("ANTHROPIC_API_KEY")  # Same result
```

Keys are automatically used by providers when making API calls. No manual header management required.

## Error Handling

ReqLLM uses [Splode](https://github.com/zachdaniel/splode) for structured error handling:

```elixir
case ReqLLM.generate_text!("anthropic:claude-3-5-sonnet", prompt) do
  {:ok, text} -> 
    IO.puts("Success: #{text}")
    
  {:error, %ReqLLM.Error.API.Request{reason: reason, status: status}} ->
    IO.puts("API error (#{status}): #{reason}")
    
  {:error, %ReqLLM.Error.Invalid.Parameter{parameter: param}} ->
    IO.puts("Invalid parameter: #{param}")
    
  {:error, error} ->
    IO.puts("Unexpected error: #{inspect(error)}")
end
```

## Common Options

All generation functions accept these options:

```elixir
ReqLLM.generate_text!(
  "anthropic:claude-3-5-sonnet",
  "Write code",
  temperature: 0.1,      # Control randomness (0.0-2.0)
  max_tokens: 1000,      # Limit response length
  system_prompt: "You are a helpful coding assistant"
)
```

## Next Steps

- **[Adding a Provider](file:///Users/mhostetler/Source/Jido/jido_workspace/projects/req_llm/guides/adding_a_provider.md)** - Extend ReqLLM with custom providers
- **[Core API Reference](file:///Users/mhostetler/Source/Jido/jido_workspace/projects/req_llm/lib/req_llm.ex)** - Complete API documentation
- **[Generation Module](file:///Users/mhostetler/Source/Jido/jido_workspace/projects/req_llm/lib/req_llm/generation.ex)** - Text generation internals
- **[Error System](file:///Users/mhostetler/Source/Jido/jido_workspace/projects/req_llm/lib/req_llm/error.ex)** - Error handling details

## Available Providers

Currently supported:

- **Anthropic**: Claude 3.5 Sonnet, Claude 3 Haiku, Claude 3 Opus

More providers coming soon.
