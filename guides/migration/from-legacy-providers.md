# Migration Guide: From Legacy Providers to ReqLLM

This guide helps you migrate from the legacy provider-specific implementations to the unified ReqLLM-based system.

## Why Migrate?

The ReqLLM integration provides:

- **57+ providers** instead of 4-5
- **2000+ models** with automatic discovery
- **Unified API** across all providers
- **Better performance** with optimized adapters
- **Advanced features** (RAG, plugins, fine-tuning)
- **Simpler maintenance** - one interface for all

## What Changed?

### Module Names (UNCHANGED ✅)

**Good news**: Public API module names remain the same!

```elixir
# Still works - no changes needed
Jido.AI.Actions.OpenaiEx.run(...)
Jido.AI.Actions.Instructor.run(...)
Jido.AI.Actions.Langchain.run(...)
```

### Internal Implementation (CHANGED 🔄)

The internals now use ReqLLM, but this is transparent to you.

### New Unified API (NEW ✨)

A simpler interface is now available:

```elixir
# New unified interface
Jido.AI.chat("provider:model", prompt, opts)

# Works with ANY provider
Jido.AI.chat("openai:gpt-4", prompt)
Jido.AI.chat("anthropic:claude-3-sonnet", prompt)
Jido.AI.chat("groq:llama-3.1-70b", prompt)  # NEW!
```

## Migration Scenarios

### Scenario 1: Basic Chat Completion

#### Before (Legacy)

```elixir
# Old OpenAI-specific code
alias Jido.AI.Actions.OpenaiEx

params = %{
  model: "gpt-4",
  messages: [
    %{role: "system", content: "You are helpful"},
    %{role: "user", content: "Hello"}
  ],
  temperature: 0.7
}

{:ok, result} = OpenaiEx.run(params, api_key: System.get_env("OPENAI_API_KEY"))
```

#### After (ReqLLM)

```elixir
# New unified approach
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "Hello",
  system: "You are helpful",
  temperature: 0.7
)

# Access response
response.content  # "Hello! How can I help you?"
```

**Migration Steps:**
1. Replace `OpenaiEx.run/2` with `Jido.AI.chat/3`
2. Use `provider:model` format
3. API key automatically retrieved from Keyring
4. Simpler parameter structure

### Scenario 2: Multi-Provider Setup

#### Before (Legacy)

```elixir
# Separate setup for each provider
defmodule MyApp.AI do
  def chat_openai(prompt) do
    params = %{
      model: "gpt-4",
      messages: [%{role: "user", content: prompt}]
    }
    OpenaiEx.run(params, api_key: get_openai_key())
  end

  def chat_anthropic(prompt) do
    # Different API, different parameters
    # Custom HTTP client code...
  end
end
```

#### After (ReqLLM)

```elixir
# Unified interface for all providers
defmodule MyApp.AI do
  @providers [
    "openai:gpt-4",
    "anthropic:claude-3-sonnet",
    "groq:llama-3.1-70b"
  ]

  def chat(prompt, provider \\ "openai:gpt-4") do
    Jido.AI.chat(provider, prompt)
  end

  def chat_with_fallback(prompt) do
    Enum.reduce_while(@providers, {:error, :all_failed}, fn provider, _acc ->
      case chat(prompt, provider) do
        {:ok, response} -> {:halt, {:ok, response}}
        {:error, _} -> {:cont, {:error, :all_failed}}
      end
    end)
  end
end
```

**Benefits:**
- Same code works for all providers
- Easy to add new providers
- Built-in fallback support

### Scenario 3: Streaming Responses

#### Before (Legacy)

```elixir
# OpenAI-specific streaming
params = %{
  model: "gpt-4",
  messages: messages,
  stream: true
}

{:ok, stream} = OpenaiEx.run(params, api_key: api_key)

stream
|> Stream.each(fn chunk ->
  # OpenAI-specific chunk format
  delta = get_in(chunk, ["choices", 0, "delta", "content"])
  IO.write(delta)
end)
|> Stream.run()
```

#### After (ReqLLM)

```elixir
# Unified streaming for all providers
{:ok, stream} = Jido.AI.chat(
  "openai:gpt-4",
  prompt,
  stream: true
)

stream
|> Stream.each(fn chunk ->
  # Unified chunk format
  IO.write(chunk.content)
end)
|> Stream.run()
```

**Works with ANY provider:**

```elixir
# Same code, different providers
providers = ["openai:gpt-4", "anthropic:claude-3-sonnet", "groq:llama-3.1-70b"]

Enum.each(providers, fn provider ->
  {:ok, stream} = Jido.AI.chat(provider, prompt, stream: true)
  stream |> Stream.each(&IO.write(&1.content)) |> Stream.run()
end)
```

### Scenario 4: Tool/Function Calling

#### Before (Legacy)

```elixir
# OpenAI-specific tool calling
tools = [
  %{
    "type" => "function",
    "function" => %{
      "name" => "get_weather",
      "description" => "Get weather",
      "parameters" => %{
        "type" => "object",
        "properties" => %{"location" => %{"type" => "string"}},
        "required" => ["location"]
      }
    }
  }
]

params = %{
  model: "gpt-4",
  messages: messages,
  tools: tools
}

{:ok, result} = OpenaiEx.run(params, api_key: api_key)
```

#### After (ReqLLM)

```elixir
# Unified tool calling
tools = [
  %{
    type: "function",
    function: %{
      name: "get_weather",
      description: "Get weather",
      parameters: %{
        type: "object",
        properties: %{location: %{type: "string"}},
        required: ["location"]
      }
    }
  }
]

{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "What's the weather in Paris?",
  tools: tools
)

# Handle tool calls
if response.tool_calls do
  Enum.each(response.tool_calls, fn call ->
    result = execute_tool(call.name, call.arguments)
    # Continue conversation with result...
  end)
end
```

### Scenario 5: Embeddings Generation

#### Before (Legacy)

```elixir
# OpenAI-specific embeddings
alias Jido.AI.Actions.OpenaiEx.Embeddings

params = %{
  model: "text-embedding-3-small",
  input: "Text to embed"
}

{:ok, result} = Embeddings.create(params, api_key: api_key)
embeddings = result["data"] |> hd() |> Map.get("embedding")
```

#### After (ReqLLM)

```elixir
# Unified embeddings API
{:ok, embeddings} = Jido.AI.embeddings(
  "openai:text-embedding-3-small",
  "Text to embed"
)

# Works with other providers too
{:ok, embeddings} = Jido.AI.embeddings(
  "cohere:embed-english-v3.0",
  "Text to embed"
)
```

### Scenario 6: API Key Management

#### Before (Legacy)

```elixir
# Manual API key management
api_key = System.get_env("OPENAI_API_KEY")

# Pass to every call
OpenaiEx.run(params, api_key: api_key)
```

#### After (ReqLLM)

```elixir
# Automatic key retrieval via Keyring
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-..."

# No need to pass keys
{:ok, response} = Jido.AI.chat("openai:gpt-4", prompt)

# Or set programmatically
Jido.AI.Keyring.set(:openai, "sk-...")
```

### Scenario 7: Error Handling

#### Before (Legacy)

```elixir
# Provider-specific error handling
case OpenaiEx.run(params, api_key: api_key) do
  {:ok, result} ->
    # Success
  {:error, %HTTPoison.Error{reason: :timeout}} ->
    # Handle timeout
  {:error, %{"error" => %{"message" => msg}}} ->
    # Handle API error
end
```

#### After (ReqLLM)

```elixir
# Unified error handling
case Jido.AI.chat(provider, prompt) do
  {:ok, response} ->
    # Success - same format for all providers
  {:error, %{type: :timeout}} ->
    # Timeout - any provider
  {:error, %{type: :rate_limit}} ->
    # Rate limit - any provider
  {:error, %{type: :api_error, message: msg}} ->
    # API error - any provider
end
```

### Scenario 8: Instructor Integration

#### Before (Legacy)

```elixir
# Instructor with OpenAI
alias Jido.AI.Actions.Instructor

params = %{
  model: "gpt-4",
  response_model: MySchema,
  messages: messages
}

{:ok, result} = Instructor.run(params, api_key: api_key)
```

#### After (ReqLLM)

```elixir
# Still works unchanged!
alias Jido.AI.Actions.Instructor

params = %{
  model: "gpt-4",
  response_model: MySchema,
  messages: messages
}

{:ok, result} = Instructor.run(params)  # API key auto-retrieved

# Or use unified API with JSON mode
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  prompt,
  response_format: %{type: "json_object"}
)
```

### Scenario 9: Provider Switching

#### Before (Legacy)

```elixir
# Switching providers required code changes
defmodule MyApp.Chat do
  @provider :openai  # Hardcoded

  def chat(prompt) do
    case @provider do
      :openai -> OpenaiEx.run(...)
      :anthropic -> custom_anthropic_call(...)
    end
  end
end
```

#### After (ReqLLM)

```elixir
# Provider switching via configuration
defmodule MyApp.Chat do
  @provider Application.compile_env(:my_app, :ai_provider, "openai:gpt-4")

  def chat(prompt) do
    Jido.AI.chat(@provider, prompt)
  end
end

# config/config.exs
config :my_app,
  ai_provider: "groq:llama-3.1-70b"  # Switch providers easily
```

### Scenario 10: Batch Processing

#### Before (Legacy)

```elixir
# Provider-specific batch processing
prompts
|> Enum.map(fn prompt ->
  Task.async(fn ->
    params = %{model: "gpt-4", messages: [%{role: "user", content: prompt}]}
    OpenaiEx.run(params, api_key: api_key)
  end)
end)
|> Task.await_many(30_000)
```

#### After (ReqLLM)

```elixir
# Unified batch processing
prompts
|> Task.async_stream(
  fn prompt -> Jido.AI.chat("openai:gpt-4", prompt) end,
  max_concurrency: 10,
  timeout: 30_000
)
|> Enum.to_list()

# Mix providers for fallback
prompts
|> Enum.zip(["openai:gpt-4", "anthropic:claude-3-sonnet", "groq:llama-3.1-70b"])
|> Task.async_stream(
  fn {prompt, provider} -> Jido.AI.chat(provider, prompt) end,
  max_concurrency: 10
)
|> Enum.to_list()
```

## Common Migration Pitfalls

### 1. Forgetting Provider Prefix

❌ **Wrong:**
```elixir
Jido.AI.chat("gpt-4", prompt)  # Missing provider
```

✅ **Correct:**
```elixir
Jido.AI.chat("openai:gpt-4", prompt)  # Provider:model format
```

### 2. Assuming OpenAI-Specific Behavior

❌ **Wrong:**
```elixir
# Assuming all providers support vision
{:ok, response} = Jido.AI.chat("groq:llama-3.1-70b", prompt, images: [image])
```

✅ **Correct:**
```elixir
# Check capabilities first
alias Jido.AI.Model

{:ok, model} = Model.from("groq:llama-3.1-70b")
if model.capabilities.vision do
  {:ok, response} = Jido.AI.chat(model, prompt, images: [image])
else
  # Use vision-capable provider
  {:ok, response} = Jido.AI.chat("openai:gpt-4", prompt, images: [image])
end
```

### 3. Not Using Keyring

❌ **Wrong:**
```elixir
# Passing API keys manually
{:ok, response} = Jido.AI.chat(provider, prompt, api_key: "sk-...")
```

✅ **Correct:**
```elixir
# Set once via Keyring
Jido.AI.Keyring.set(:openai, "sk-...")

# Use without passing keys
{:ok, response} = Jido.AI.chat("openai:gpt-4", prompt)
```

### 4. Hardcoding Provider Names

❌ **Wrong:**
```elixir
def chat(prompt) do
  Jido.AI.chat("openai:gpt-4", prompt)  # Hardcoded
end
```

✅ **Correct:**
```elixir
@default_provider Application.compile_env(:my_app, :ai_provider, "openai:gpt-4")

def chat(prompt, provider \\ @default_provider) do
  Jido.AI.chat(provider, prompt)
end
```

## Testing Your Migration

### Unit Tests

```elixir
defmodule MyApp.ChatTest do
  use ExUnit.Case

  # Test with multiple providers
  @providers ["openai:gpt-4", "anthropic:claude-3-sonnet"]

  for provider <- @providers do
    test "chat works with #{provider}" do
      {:ok, response} = MyApp.Chat.chat("Hello", unquote(provider))
      assert is_binary(response.content)
    end
  end
end
```

### Integration Tests

```elixir
# Test fallback chain
test "fallback chain works" do
  # Primary should fail
  Application.put_env(:jido_ai, :openai_api_key, "invalid")

  # Should fallback successfully
  {:ok, response} = MyApp.Chat.chat_with_fallback("Hello")
  assert response.provider != :openai
end
```

## Checklist

- [ ] Identify all provider-specific code
- [ ] Replace with unified `Jido.AI.chat/3` calls
- [ ] Set up Keyring for API key management
- [ ] Update tests to cover multiple providers
- [ ] Test fallback chains
- [ ] Update documentation
- [ ] Deploy to staging and test
- [ ] Monitor performance and errors
- [ ] Roll out to production

## Next Steps

- [Breaking Changes](breaking-changes.md) - Version-specific changes
- [ReqLLM Integration](reqllm-integration.md) - Deep-dive into architecture
- [Provider Matrix](../providers/provider-matrix.md) - Explore all 57+ providers
- [Advanced Features](../features/) - Use RAG, plugins, fine-tuning

## Getting Help

- [Troubleshooting Guide](../troubleshooting.md) - Common issues
- [GitHub Issues](https://github.com/agentjido/jido_ai/issues) - Report problems
- [Examples](https://github.com/agentjido/jido_ai/tree/main/examples) - More examples
