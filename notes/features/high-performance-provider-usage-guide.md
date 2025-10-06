# High-Performance Provider Usage Guide

## Overview

This guide provides comprehensive documentation for using high-performance providers (Groq and Together AI) through Jido AI's ReqLLM integration. These providers offer exceptional speed and throughput capabilities, making them ideal for applications requiring real-time responses or high-volume processing.

## Quick Start

### Groq Provider

Groq specializes in ultra-fast inference with models optimized for speed:

```elixir
# Create a Groq model
{:ok, model} = Jido.AI.Model.from({:groq, [
  model: "llama-3.1-8b-instant"
]})

# Use with any Jido AI action
{:ok, result} = Jido.AI.Actions.OpenaiEx.run(%{
  model: model,
  messages: [%{role: :user, content: "Hello, world!"}]
}, %{})
```

### Together AI Provider

Together AI provides access to a wide range of models with high throughput:

```elixir
# Create a Together AI model (provider name may vary)
{:ok, model} = Jido.AI.Model.from({:together, [
  model: "mistralai/Mixtral-8x7B-Instruct-v0.1"
]})

# Use with standard Jido AI patterns
{:ok, result} = Jido.AI.Actions.OpenaiEx.run(%{
  model: model,
  messages: messages,
  temperature: 0.7,
  max_tokens: 1000
}, %{})
```

## Provider Configuration

### Authentication Setup

Both providers require API keys for authentication:

```elixir
# Set API keys via environment variables (recommended)
export GROQ_API_KEY="your-groq-api-key"
export TOGETHER_API_KEY="your-together-api-key"

# Or set them programmatically
Jido.AI.Keyring.set(Jido.AI.Keyring, :groq_api_key, "your-groq-api-key")
Jido.AI.Keyring.set(Jido.AI.Keyring, :together_api_key, "your-together-api-key")

# Use session-specific keys for per-process isolation
Jido.AI.ReqLlmBridge.SessionAuthentication.set_for_provider(:groq, "session-key")
```

### Provider Discovery

List all available high-performance providers:

```elixir
# Get all providers
providers = Jido.AI.Provider.providers()

# Filter for high-performance providers
hp_providers = Enum.filter(providers, fn {provider, _adapter} ->
  provider in [:groq, :together, :together_ai, :togetherai]
end)

IO.inspect(hp_providers)
# Output: [groq: :reqllm_backed, together: :reqllm_backed, ...]
```

## Model Selection and Capabilities

### Groq Models

Groq specializes in fast inference with optimized models:

```elixir
# List available Groq models
{:ok, models} = Jido.AI.Model.Registry.list_models(:groq)

# Common Groq models and their characteristics:
groq_models = [
  # Ultra-fast small models
  %{name: "llama-3.1-8b-instant", use_case: "Fast responses, general chat"},
  %{name: "gemma-7b-it", use_case: "Instruction following, fast inference"},

  # Larger models with higher capability
  %{name: "llama-3.1-70b-versatile", use_case: "Complex reasoning, high quality"},
  %{name: "mixtral-8x7b-32768", use_case: "Long context, multilingual"}
]
```

### Together AI Models

Together AI offers a diverse model marketplace:

```elixir
# List available Together AI models
together_variants = [:together, :together_ai, :togetherai]
models_by_provider = Enum.find_value(together_variants, fn variant ->
  case Jido.AI.Model.Registry.list_models(variant) do
    {:ok, models} when length(models) > 0 -> {variant, models}
    _ -> nil
  end
end)

# Common Together AI model categories:
model_categories = %{
  # Chat and instruction models
  chat: [
    "mistralai/Mixtral-8x7B-Instruct-v0.1",
    "togethercomputer/RedPajama-INCITE-Chat-3B-v1",
    "NousResearch/Nous-Hermes-2-Mixtral-8x7B-DPO"
  ],

  # Code generation models
  code: [
    "codellama/CodeLlama-34b-Instruct-hf",
    "WizardLM/WizardCoder-Python-34B-V1.0"
  ],

  # Specialized fine-tuned models
  specialized: [
    "togethercomputer/GPT-JT-Moderation-6B",
    "togethercomputer/LLaMA-2-7B-32K"
  ]
}
```

## Performance Optimization

### Latency Optimization

For minimum latency applications:

```elixir
# Use Groq for ultra-fast responses
{:ok, model} = Jido.AI.Model.from({:groq, [
  model: "llama-3.1-8b-instant",  # Fastest Groq model
  temperature: 0.0,                # Reduce randomness for speed
  max_tokens: 100                  # Limit response length
]})

# Optimize request parameters
{:ok, result} = Jido.AI.Actions.OpenaiEx.run(%{
  model: model,
  messages: messages,
  stream: false,  # Disable streaming for batch processing
  top_p: 1.0     # Use full probability mass
}, %{})
```

### Throughput Optimization

For high-volume applications:

```elixir
# Use Together AI for sustained throughput
{:ok, model} = Jido.AI.Model.from({:together, [
  model: "mistralai/Mixtral-8x7B-Instruct-v0.1",
  temperature: 0.7
]})

# Process requests concurrently
requests = ["request 1", "request 2", "request 3"]

tasks = Enum.map(requests, fn prompt ->
  Task.async(fn ->
    Jido.AI.Actions.OpenaiEx.run(%{
      model: model,
      messages: [%{role: :user, content: prompt}]
    }, %{})
  end)
end)

results = Task.await_many(tasks, 30_000)  # 30 second timeout
```

### Resource Management

Optimize resource usage for production:

```elixir
# Configure connection pooling (if available)
config = %{
  pool_size: 10,
  max_overflow: 5,
  timeout: 30_000,
  pool_timeout: 5_000
}

# Monitor resource usage
initial_memory = :erlang.memory(:total)

# Perform operations...
{:ok, result} = Jido.AI.Actions.OpenaiEx.run(params, %{})

final_memory = :erlang.memory(:total)
memory_used = final_memory - initial_memory

IO.puts("Memory used: #{memory_used} bytes")
```

## Advanced Features

### Streaming Responses

For real-time applications:

```elixir
# Enable streaming for real-time responses
{:ok, model} = Jido.AI.Model.from({:groq, [
  model: "llama-3.1-8b-instant"
]})

# Use streaming with callback handling
{:ok, stream} = Jido.AI.Actions.OpenaiEx.run(%{
  model: model,
  messages: messages,
  stream: true,
  stream_callback: fn chunk ->
    IO.write(chunk.content)
  end
}, %{})
```

### Context Length Handling

For long-context applications:

```elixir
# Use models with large context windows
long_context_models = [
  # Groq models with extended context
  {:groq, "mixtral-8x7b-32768"},      # 32K context

  # Together AI long-context models
  {:together, "togethercomputer/LLaMA-2-7B-32K"}  # 32K context
]

# Handle long prompts efficiently
{:ok, model} = Jido.AI.Model.from({:groq, [
  model: "mixtral-8x7b-32768"
]})

# For very long contexts, consider chunking
long_text = "..." # Your long text here

if String.length(long_text) > 30000 do
  # Implement chunking strategy
  chunks = Jido.AI.Prompt.Splitter.split(long_text, max_size: 30000)

  results = Enum.map(chunks, fn chunk ->
    Jido.AI.Actions.OpenaiEx.run(%{
      model: model,
      messages: [%{role: :user, content: chunk}]
    }, %{})
  end)
else
  # Process normally
  {:ok, result} = Jido.AI.Actions.OpenaiEx.run(%{
    model: model,
    messages: [%{role: :user, content: long_text}]
  }, %{})
end
```

### Function Calling and Tools

For advanced AI applications:

```elixir
# Define tools for function calling
tools = [
  MyApp.WeatherTool,
  MyApp.CalculatorTool
]

{:ok, model} = Jido.AI.Model.from({:groq, [
  model: "llama-3.1-70b-versatile"  # Model with function calling support
]})

{:ok, result} = Jido.AI.Actions.OpenaiEx.run(%{
  model: model,
  messages: messages,
  tools: tools,
  tool_choice: %{type: "auto"}
}, %{})
```

## Error Handling and Reliability

### Robust Error Handling

```elixir
defmodule MyApp.HighPerformanceAI do
  def safe_request(provider, model_name, messages) do
    case Jido.AI.Model.from({provider, [model: model_name]}) do
      {:ok, model} ->
        case Jido.AI.Actions.OpenaiEx.run(%{
          model: model,
          messages: messages
        }, %{}) do
          {:ok, result} ->
            {:ok, result}

          {:error, %{type: "rate_limit"}} ->
            # Handle rate limiting with backoff
            :timer.sleep(1000)
            safe_request(provider, model_name, messages)

          {:error, %{type: "context_length_exceeded"}} ->
            # Handle context length issues
            truncated_messages = truncate_messages(messages)
            safe_request(provider, model_name, truncated_messages)

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, {:model_creation_failed, reason}}
    end
  end

  defp truncate_messages(messages) do
    # Implement message truncation logic
    Enum.take(messages, -5)  # Keep last 5 messages
  end
end
```

### Fallback Strategies

```elixir
defmodule MyApp.FallbackStrategy do
  @providers [
    {:groq, "llama-3.1-8b-instant"},      # Primary: fastest
    {:together, "mistralai/Mixtral-8x7B-Instruct-v0.1"},  # Secondary: reliable
    {:openai, "gpt-3.5-turbo"}             # Fallback: always available
  ]

  def request_with_fallback(messages) do
    request_with_fallback(@providers, messages)
  end

  defp request_with_fallback([], _messages) do
    {:error, :all_providers_failed}
  end

  defp request_with_fallback([{provider, model} | rest], messages) do
    case MyApp.HighPerformanceAI.safe_request(provider, model, messages) do
      {:ok, result} ->
        {:ok, result, provider}

      {:error, _reason} ->
        request_with_fallback(rest, messages)
    end
  end
end
```

## Monitoring and Observability

### Performance Monitoring

```elixir
defmodule MyApp.PerformanceMonitor do
  def monitored_request(provider, model, messages) do
    start_time = :os.system_time(:millisecond)
    initial_memory = :erlang.memory(:total)

    result = case Jido.AI.Model.from({provider, [model: model]}) do
      {:ok, jido_model} ->
        Jido.AI.Actions.OpenaiEx.run(%{
          model: jido_model,
          messages: messages
        }, %{})
      error -> error
    end

    end_time = :os.system_time(:millisecond)
    final_memory = :erlang.memory(:total)

    metrics = %{
      provider: provider,
      model: model,
      latency_ms: end_time - start_time,
      memory_delta: final_memory - initial_memory,
      success: match?({:ok, _}, result),
      timestamp: DateTime.utc_now()
    }

    # Log metrics
    Logger.info("Request metrics", metrics)

    # Store metrics for analysis
    MyApp.MetricsStore.record(metrics)

    result
  end
end
```

### Cost Tracking

```elixir
defmodule MyApp.CostTracker do
  # Approximate cost per 1K tokens (update with current pricing)
  @cost_per_1k_tokens %{
    groq: %{
      "llama-3.1-8b-instant" => %{input: 0.05, output: 0.05},
      "llama-3.1-70b-versatile" => %{input: 0.59, output: 0.79}
    },
    together: %{
      "mistralai/Mixtral-8x7B-Instruct-v0.1" => %{input: 0.60, output: 0.60}
    }
  }

  def calculate_cost(provider, model, input_tokens, output_tokens) do
    case get_in(@cost_per_1k_tokens, [provider, model]) do
      %{input: input_cost, output: output_cost} ->
        input_cost_total = (input_tokens / 1000) * input_cost
        output_cost_total = (output_tokens / 1000) * output_cost
        total_cost = input_cost_total + output_cost_total

        %{
          input_cost: input_cost_total,
          output_cost: output_cost_total,
          total_cost: total_cost,
          currency: "USD"
        }

      nil ->
        {:error, :pricing_not_available}
    end
  end
end
```

## Production Deployment

### Configuration Management

```elixir
# config/prod.exs
config :jido_ai, :high_performance_providers,
  groq: %{
    api_key: {:system, "GROQ_API_KEY"},
    default_model: "llama-3.1-8b-instant",
    timeout: 30_000,
    retry_attempts: 3
  },
  together: %{
    api_key: {:system, "TOGETHER_API_KEY"},
    default_model: "mistralai/Mixtral-8x7B-Instruct-v0.1",
    timeout: 45_000,
    retry_attempts: 2
  }

# Runtime configuration
defmodule MyApp.Config do
  def get_provider_config(provider) do
    Application.get_env(:jido_ai, :high_performance_providers)[provider]
  end
end
```

### Health Checks

```elixir
defmodule MyApp.HealthCheck do
  def check_providers do
    providers = [:groq, :together]

    results = Enum.map(providers, fn provider ->
      case health_check_provider(provider) do
        :ok -> {provider, :healthy}
        {:error, reason} -> {provider, {:unhealthy, reason}}
      end
    end)

    healthy_count = Enum.count(results, fn {_provider, status} -> status == :healthy end)

    %{
      providers: results,
      healthy_count: healthy_count,
      total_count: length(providers),
      overall_status: if(healthy_count > 0, do: :healthy, else: :unhealthy)
    }
  end

  defp health_check_provider(provider) do
    case Jido.AI.Model.from({provider, [model: "test"]}) do
      {:ok, _model} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
```

## Best Practices

### 1. Model Selection Guidelines

- **Groq**: Use for ultra-low latency requirements (< 500ms)
- **Together AI**: Use for high throughput and diverse model access
- **Context Length**: Choose models based on your maximum context requirements
- **Capabilities**: Verify function calling support if needed

### 2. Performance Optimization

- Use appropriate model sizes for your use case
- Implement proper connection pooling
- Monitor memory usage and implement limits
- Use streaming for real-time applications
- Implement request batching where possible

### 3. Reliability Patterns

- Always implement fallback providers
- Use exponential backoff for retries
- Monitor error rates and adjust strategies
- Implement circuit breakers for automatic failover
- Log all requests for debugging and analysis

### 4. Cost Management

- Track token usage and costs
- Implement budget limits and alerts
- Choose cost-effective models for your use case
- Cache responses where appropriate
- Monitor and optimize prompt efficiency

### 5. Security Considerations

- Never log API keys or sensitive data
- Use environment variables for API keys
- Implement request rate limiting
- Validate all user inputs
- Use session-based authentication for multi-tenant applications

## Troubleshooting

### Common Issues

#### 1. Provider Not Found
```elixir
# Check available providers
providers = Jido.AI.Provider.providers()
IO.inspect(providers)

# Verify provider naming (together vs together_ai vs togetherai)
```

#### 2. Authentication Errors
```elixir
# Verify API key is set
api_key = System.get_env("GROQ_API_KEY")
if is_nil(api_key), do: raise "GROQ_API_KEY not set"

# Test authentication
Jido.AI.ReqLlmBridge.SessionAuthentication.set_for_provider(:groq, api_key)
```

#### 3. Model Not Available
```elixir
# List available models for provider
{:ok, models} = Jido.AI.Model.Registry.list_models(:groq)
model_names = Enum.map(models, fn model ->
  Map.get(model, :name, Map.get(model, :id))
end)
IO.inspect(model_names)
```

#### 4. Performance Issues
```elixir
# Enable detailed logging
Logger.configure(level: :debug)

# Monitor memory usage
:erlang.memory() |> IO.inspect()

# Check for memory leaks
:observer.start()  # If running in development
```

### Debugging Tools

```elixir
# Debug provider discovery
defmodule Debug do
  def providers do
    Jido.AI.Provider.providers()
    |> Enum.each(fn {provider, adapter} ->
      IO.puts("#{provider}: #{adapter}")
    end)
  end

  def models(provider) do
    case Jido.AI.Model.Registry.list_models(provider) do
      {:ok, models} ->
        IO.puts("Found #{length(models)} models for #{provider}")
        Enum.each(models, fn model ->
          name = Map.get(model, :name, Map.get(model, :id, "unknown"))
          IO.puts("  - #{name}")
        end)

      {:error, reason} ->
        IO.puts("Error listing models for #{provider}: #{inspect(reason)}")
    end
  end
end
```

## Conclusion

High-performance providers like Groq and Together AI offer significant advantages for applications requiring speed and scale. By following this guide, you can:

- Effectively configure and use high-performance providers
- Optimize for your specific latency and throughput requirements
- Implement robust error handling and fallback strategies
- Monitor performance and costs in production
- Troubleshoot common issues

For additional support, refer to the provider-specific documentation and the Jido AI integration guides.