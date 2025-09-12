# Getting Started

## Installation

```elixir
def deps do
  [
    {:req_llm, "~> 0.1.0"}
  ]
end
```

## Generate Text

```elixir
ReqLLM.put_key(:anthropic_api_key, "sk-ant-...")
{:ok, text} = ReqLLM.generate_text!("anthropic:claude-3-sonnet", "Hello")
{:ok, stream} = ReqLLM.stream_text!("anthropic:claude-3-sonnet", "Tell me a story")
Enum.join(stream) |> IO.puts()
```

## Usage & Cost

```elixir
{:ok, response} = ReqLLM.generate_text("anthropic:claude-3-sonnet", "Hello")
{:ok, text, usage} = ReqLLM.with_usage({:ok, response})
# usage => %{tokens: %{input: 5, output: 12}, cost: 0.00042}
```

## Model Specifications

```elixir
"anthropic:claude-3-sonnet"
{:anthropic, "claude-3-sonnet", temperature: 0.7}
%ReqLLM.Model{provider: :anthropic, model: "claude-3-sonnet", temperature: 0.7}
```

## Key Management

```elixir
ReqLLM.put_key(:anthropic_api_key, "sk-ant-...")
ReqLLM.put_key("OPENAI_API_KEY", "sk-...")
# Providers automatically retrieve keys
```

## Error Handling

```elixir
case ReqLLM.generate_text!("anthropic:claude-3-sonnet", prompt) do
  {:ok, text} -> 
    IO.puts("Success: #{text}")
  {:error, %ReqLLM.Error.API.Request{reason: reason}} ->
    IO.puts("API error: #{reason}")
  {:error, %ReqLLM.Error.Invalid.Parameter{parameter: param}} ->
    IO.puts("Invalid parameter: #{param}")
  {:error, error} ->
    IO.puts("Unexpected error: #{inspect(error)}")
end
```

## Common Options

```elixir
ReqLLM.generate_text!(
  "anthropic:claude-3-sonnet",
  "Write code",
  temperature: 0.1,      # Control randomness (0.0-2.0)
  max_tokens: 1000,      # Limit response length
  system_prompt: "You are a helpful coding assistant"
)
```

## Available Providers

- **Anthropic**: Claude 3.5 Sonnet, Claude 3 Haiku, Claude 3 Opus
- **OpenAI**: GPT-4o, GPT-4 Turbo, GPT-3.5 Turbo
