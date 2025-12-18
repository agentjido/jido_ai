# High-Performance Providers

High-performance providers are optimized for speed and throughput, offering ultra-fast inference times ideal for latency-sensitive applications.

## Supported Providers

- **Groq** - Ultra-fast inference with LPU architecture
- **Together AI** - Fast inference with 100+ models
- **Cerebras** - Fast inference with long context support
- **Fireworks AI** - Fast deployment of custom models

## When to Use High-Performance Providers

**Best for:**
- Real-time applications (chatbots, voice assistants)
- High-throughput batch processing
- Cost-sensitive workloads (free tiers available)
- Development and testing (fast iteration)

**Not ideal for:**
- Tasks requiring maximum accuracy over speed
- Long-form content generation (use standard providers)
- Multi-modal tasks (vision, audio)

## Groq

### Overview

Groq uses Language Processing Units (LPUs) for ultra-fast inference, achieving <500ms response times.

**Key Features:**
- ⚡ Fastest inference available (200-500ms typical)
- 🆓 Generous free tier (30 RPM)
- 📊 Limited model selection but high quality
- 🎯 Optimized for Llama and Mixtral models

### Setup

```elixir
# Set API key
export GROQ_API_KEY="gsk_..."

# Or via Keyring
Jido.AI.Keyring.set(:groq, "gsk_...")
```

### Available Models

```elixir
# List Groq models
{:ok, models} = Jido.AI.Model.Registry.discover_models(provider: :groq)

# Popular models:
# - groq:llama-3.1-70b-versatile
# - groq:llama-3.1-8b-instant
# - groq:mixtral-8x7b-32768
# - groq:gemma-7b-it
```

### Usage Examples

```elixir
# Basic chat
{:ok, response} = Jido.AI.chat(
  "groq:llama-3.1-70b-versatile",
  "What is the capital of France?"
)

# With streaming for real-time responses
{:ok, stream} = Jido.AI.chat(
  "groq:llama-3.1-8b-instant",
  "Tell me a story",
  stream: true
)

stream
|> Stream.each(fn chunk -> IO.write(chunk.content) end)
|> Stream.run()

# With tool calling
tools = [
  %{
    type: "function",
    function: %{
      name: "get_weather",
      description: "Get weather for a location",
      parameters: %{
        type: "object",
        properties: %{location: %{type: "string"}},
        required: ["location"]
      }
    }
  }
]

{:ok, response} = Jido.AI.chat(
  "groq:llama-3.1-70b-versatile",
  "What's the weather in Paris?",
  tools: tools
)
```

### Performance Tips

```elixir
# Use instant models for maximum speed
"groq:llama-3.1-8b-instant"  # <200ms typical

# Use versatile models for better quality
"groq:llama-3.1-70b-versatile"  # <500ms typical

# Optimize token usage
max_tokens: 256  # Faster responses with shorter outputs

# Use JSON mode for structured outputs
response_format: %{type: "json_object"}
```

### Rate Limits

| Tier | RPM | TPM | Notes |
|------|-----|-----|-------|
| Free | 30 | 6,000 | Per model |
| Pro | 6,000 | 600,000 | Unlimited models |

## Together AI

### Overview

Together AI offers 100+ open-source models with fast inference and competitive pricing.

**Key Features:**
- 📚 Largest model selection (100+ models)
- ⚡ Fast inference (500-1000ms)
- 💰 Competitive pricing
- 🔧 Custom model deployment

### Setup

```elixir
# Set API key
export TOGETHER_API_KEY="..."

# Or via Keyring
Jido.AI.Keyring.set(:together, "...")
```

### Available Models

```elixir
# List all Together models
{:ok, models} = Jido.AI.Model.Registry.discover_models(provider: :together)

# Popular models:
# - together:meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo
# - together:mistralai/Mixtral-8x7B-Instruct-v0.1
# - together:Qwen/Qwen2-72B-Instruct
```

### Usage Examples

```elixir
# Basic chat with Llama 3.1
{:ok, response} = Jido.AI.chat(
  "together:meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo",
  "Explain quantum computing"
)

# Use with streaming
{:ok, stream} = Jido.AI.chat(
  "together:mistralai/Mixtral-8x7B-Instruct-v0.1",
  "Write a poem",
  stream: true
)

# Fine-tuned models
{:ok, response} = Jido.AI.chat(
  "together:username/my-fine-tuned-model",
  "Custom task"
)
```

### Performance Tips

```elixir
# Use Turbo models for speed
"together:meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo"

# Batch processing optimization
requests = Enum.map(prompts, fn prompt ->
  Task.async(fn ->
    Jido.AI.chat("together:...", prompt)
  end)
end)

results = Task.await_many(requests, 30_000)
```

### Rate Limits

| Tier | RPM | TPM | Notes |
|------|-----|-----|-------|
| Free | 60 | 60,000 | Trial credits |
| Pay-as-you-go | 3,000 | 1,000,000 | No minimums |

## Cerebras

### Overview

Cerebras offers ultra-fast inference with support for long context windows.

**Key Features:**
- ⚡ Ultra-fast inference
- 📏 Long context support (128K+)
- 🎯 Optimized Llama models
- 💰 Competitive pricing

### Setup

```elixir
# Set API key
export CEREBRAS_API_KEY="..."

# Or via Keyring
Jido.AI.Keyring.set(:cerebras, "...")
```

### Available Models

```elixir
# List Cerebras models
{:ok, models} = Jido.AI.Model.Registry.discover_models(provider: :cerebras)

# Available models:
# - cerebras:llama3.1-70b
# - cerebras:llama3.1-8b
```

### Usage Examples

```elixir
# Long context processing
{:ok, response} = Jido.AI.chat(
  "cerebras:llama3.1-70b",
  long_document <> "\n\nSummarize this document.",
  max_tokens: 1000
)

# Fast inference for real-time apps
{:ok, response} = Jido.AI.chat(
  "cerebras:llama3.1-8b",
  user_query,
  temperature: 0.7
)
```

## Fireworks AI

### Overview

Fireworks AI enables fast deployment and inference of custom models.

**Key Features:**
- 🚀 Fast custom model deployment
- 📚 50+ pre-built models
- 💡 Function calling support
- 🎯 Optimized for production

### Setup

```elixir
# Set API key
export FIREWORKS_API_KEY="..."

# Or via Keyring
Jido.AI.Keyring.set(:fireworks, "...")
```

### Available Models

```elixir
# List Fireworks models
{:ok, models} = Jido.AI.Model.Registry.discover_models(provider: :fireworks)

# Popular models:
# - fireworks:accounts/fireworks/models/llama-v3p1-70b-instruct
# - fireworks:accounts/fireworks/models/mixtral-8x7b-instruct
```

### Usage Examples

```elixir
# Basic chat
{:ok, response} = Jido.AI.chat(
  "fireworks:accounts/fireworks/models/llama-v3p1-70b-instruct",
  "Hello, world!"
)

# With function calling
tools = [
  %{
    type: "function",
    function: %{
      name: "calculate",
      description: "Perform calculation",
      parameters: %{
        type: "object",
        properties: %{
          expression: %{type: "string"}
        }
      }
    }
  }
]

{:ok, response} = Jido.AI.chat(
  "fireworks:accounts/fireworks/models/llama-v3p1-70b-instruct",
  "What is 15 * 23?",
  tools: tools
)
```

## Performance Comparison

### Latency Benchmarks

| Provider | Model | Avg Latency | Throughput |
|----------|-------|-------------|------------|
| Groq | llama-3.1-8b | 200ms | ⚡⚡⚡⚡⚡ |
| Groq | llama-3.1-70b | 400ms | ⚡⚡⚡⚡ |
| Together | Llama-3.1-70B-Turbo | 800ms | ⚡⚡⚡ |
| Cerebras | llama3.1-70b | 500ms | ⚡⚡⚡⚡ |
| Fireworks | llama-v3p1-70b | 700ms | ⚡⚡⚡ |

### Cost Comparison (per 1M tokens)

| Provider | Input | Output | Notes |
|----------|-------|--------|-------|
| Groq | Free (tier) | Free (tier) | 30 RPM limit |
| Together | $0.20 | $0.20 | Varies by model |
| Cerebras | $0.60 | $0.60 | Llama models |
| Fireworks | $0.20 | $0.20 | Varies by model |

## Best Practices

### 1. Choose the Right Model

```elixir
# Speed-critical (chatbot, voice)
"groq:llama-3.1-8b-instant"

# Balance (general purpose)
"groq:llama-3.1-70b-versatile"

# Quality-critical (complex reasoning)
"together:meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo"
```

### 2. Optimize Token Usage

```elixir
# Limit output tokens for faster responses
opts = [
  max_tokens: 256,  # Faster than 1024+
  temperature: 0.7
]

{:ok, response} = Jido.AI.chat(model, prompt, opts)
```

### 3. Use Streaming for UX

```elixir
# Stream for real-time feedback
{:ok, stream} = Jido.AI.chat(model, prompt, stream: true)

stream
|> Stream.each(fn chunk ->
  # Send to client immediately
  Phoenix.PubSub.broadcast(MyApp.PubSub, "chat:#{id}", {:chunk, chunk})
end)
|> Stream.run()
```

### 4. Implement Fallback Chains

```elixir
def fast_chat(prompt) do
  providers = [
    "groq:llama-3.1-8b-instant",        # Try fastest first
    "together:meta-llama/...-Turbo",     # Fallback
    "openai:gpt-3.5-turbo"               # Final fallback
  ]

  Enum.reduce_while(providers, {:error, :all_failed}, fn provider, _acc ->
    case Jido.AI.chat(provider, prompt, timeout: 5_000) do
      {:ok, response} -> {:halt, {:ok, response}}
      {:error, _} -> {:cont, {:error, :all_failed}}
    end
  end)
end
```

### 5. Monitor Performance

```elixir
def chat_with_metrics(provider, prompt) do
  start_time = System.monotonic_time(:millisecond)

  result = Jido.AI.chat(provider, prompt)

  latency = System.monotonic_time(:millisecond) - start_time

  # Log metrics
  :telemetry.execute([:jido_ai, :chat], %{latency: latency}, %{
    provider: provider,
    success: match?({:ok, _}, result)
  })

  result
end
```

## Troubleshooting

### Rate Limit Errors

```elixir
# Implement exponential backoff
def chat_with_retry(provider, prompt, retries \\ 3) do
  case Jido.AI.chat(provider, prompt) do
    {:ok, response} -> {:ok, response}
    {:error, %{status: 429}} when retries > 0 ->
      :timer.sleep(1000 * (4 - retries))  # Exponential backoff
      chat_with_retry(provider, prompt, retries - 1)
    {:error, reason} -> {:error, reason}
  end
end
```

### Timeout Errors

```elixir
# Increase timeout for complex queries
{:ok, response} = Jido.AI.chat(
  provider,
  prompt,
  timeout: 30_000  # 30 seconds
)
```

## Next Steps

- [Provider Matrix](provider-matrix.md) - Compare all providers
- [Specialized Providers](specialized.md) - Unique capabilities
- [Getting Started](../getting-started.md) - Basic setup
- [Advanced Features](../features/) - Use advanced capabilities
