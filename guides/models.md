# Jido AI Provider Integration Guide

## Overview

Jido AI offers a robust foundation for integrating multiple AI providers into your Elixir applications. This guide explores the provider architecture, model configuration, and best practices for leveraging various AI services through a unified interface.

## Provider Architecture

Jido AI implements a modular provider architecture that allows you to integrate with various AI services through a consistent interface. Each provider adapter implements the `Jido.AI.Model.Provider.Adapter` behavior, enabling standardized interaction with different AI services.

### Core Components

- **Provider Adapters**: Specialized modules that implement provider-specific API requirements
- **Model Registry**: Central repository for discovering and accessing available models
- **Credential Management**: Secure handling of API keys and authentication tokens

## Available Providers

Jido AI supports multiple provider integrations:

| Provider | Module | Description |
|----------|--------|-------------|
| Anthropic | `Jido.AI.Provider.Anthropic` | Access to Claude models |
| OpenAI | `Jido.AI.Provider.OpenAI` | Access to GPT models, DALL-E, and more |
| OpenRouter | `Jido.AI.Provider.OpenRouter` | Unified access to multiple AI providers |
| Cloudflare | `Jido.AI.Provider.Cloudflare` | Access to Cloudflare's AI Gateway models |

## Model Configuration

### Creating a Model

You can create a model instance using the `Jido.AI.Model.from/1` function:

```elixir
# Using the Anthropic provider with Claude
{:ok, model} = Jido.AI.Model.from({:anthropic, [
  model: "claude-3-5-haiku",
  temperature: 0.7,
  max_tokens: 1024
]})

# Using OpenAI provider with GPT-4
{:ok, gpt4_model} = Jido.AI.Model.from({:openai, [
  model: "gpt-4",
  temperature: 0.5
]})

# Using OpenRouter for model access
{:ok, router_model} = Jido.AI.Model.from({:openrouter, [
  model: "anthropic/claude-3-opus-20240229",
  max_tokens: 2000
]})
```

### Model Structure

Each model is represented as a `Jido.AI.Model` struct with the following fields:

```elixir
%Jido.AI.Model{
  id: String.t(),             # Unique identifier for the model
  name: String.t(),           # Human-readable name
  provider: atom(),           # Provider identifier (e.g., :anthropic, :openai)
  model: String.t(),       # Provider-specific model identifier
  base_url: String.t(),       # API base URL
  api_key: String.t(),        # API key for authentication
  temperature: float(),       # Temperature setting for generation
  max_tokens: non_neg_integer(), # Maximum tokens to generate
  max_retries: non_neg_integer(), # Maximum number of retry attempts
  architecture: Architecture.t(), # Model architecture information
  created: integer(),         # Creation timestamp
  description: String.t(),    # Model description
  endpoints: list(Endpoint.t()) # Available API endpoints
}
```

## API Key Management

Jido AI provides flexible API key management through the `Jido.AI.Keyring` module:

```elixir
# Set an API key for a provider
Jido.AI.Keyring.set_session_value(:anthropic_api_key, "your-api-key")

# Create a model using the stored API key
{:ok, model} = Jido.AI.Model.from({:anthropic, [model: "claude-3-5-haiku"]})
```

API keys can be provided through multiple methods (in order of precedence):
1. Directly in the model options
2. Via the `Jido.AI.Keyring` module
3. Through environment variables (e.g., `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`)

## Provider-Specific Configuration

### Anthropic Provider

The Anthropic provider gives you access to Claude models:

```elixir
{:ok, claude_model} = Jido.AI.Model.from({:anthropic, [
  model: "claude-3-7-sonnet",
  temperature: 0.3,
  max_tokens: 2048
]})
```

Key configuration options:
- `model`: Claude model identifier (e.g., "claude-3-7-sonnet", "claude-3-5-haiku")
- `temperature`: Controls randomness (0.0 to 1.0)
- `max_tokens`: Maximum number of tokens to generate

### OpenAI Provider

The OpenAI provider enables access to GPT models and other OpenAI services:

```elixir
{:ok, openai_model} = Jido.AI.Model.from({:openai, [
  model: "gpt-4o",
  temperature: 0.7,
  max_tokens: 1024
]})
```

Key configuration options:
- `model`: OpenAI model identifier (e.g., "gpt-4o", "gpt-3.5-turbo")
- `temperature`: Controls randomness (0.0 to 1.0)
- `max_tokens`: Maximum number of tokens to generate

### OpenRouter Provider

OpenRouter provides unified access to multiple AI providers:

```elixir
{:ok, router_model} = Jido.AI.Model.from({:openrouter, [
  model: "anthropic/claude-3-opus-20240229",
  max_tokens: 2000
]})
```

Key configuration options:
- `model`: Provider and model in format "provider/model"
- `temperature`: Controls randomness (0.0 to 1.0)
- `max_tokens`: Maximum number of tokens to generate

### Cloudflare Provider

The Cloudflare provider gives access to Cloudflare's AI Gateway:

```elixir
{:ok, cloudflare_model} = Jido.AI.Model.from({:cloudflare, [
  model: "@cf/meta/llama-3-8b-instruct",
  account_id: "your-account-id"
]})
```

Key configuration options:
- `model`: Cloudflare model identifier
- `account_id`: Your Cloudflare account ID
- `email`: Your Cloudflare account email (optional)

## Working with Models

### Listing Available Models

You can list all available models from a provider:

```elixir
# List all OpenAI models
{:ok, models} = Jido.AI.Provider.models(:openai)

# List models with refresh option
{:ok, fresh_models} = Jido.AI.Provider.models(:anthropic, refresh: true)
```

### Fetching a Specific Model

To fetch details about a specific model:

```elixir
# Get information about a specific model
{:ok, model_info} = Jido.AI.Provider.get_model(:anthropic, "claude-3-5-haiku")
```

### Model Standardization

Jido AI provides standardization functions to normalize model names across providers:

```elixir
# Standardize model names for comparison
standardized_name = Jido.AI.Provider.standardize_model_name("claude-3-7-sonnet-20250219")
# Returns "claude-3.7-sonnet"
```

## Advanced Use Cases

### Cross-Provider Model Information

You can retrieve combined information about equivalent models across providers:

```elixir
# Get combined information for a model across providers
{:ok, combined_info} = Jido.AI.Provider.get_combined_model_info("gpt-4")
```

### Custom Provider Adapters

To create a custom provider adapter, implement the `Jido.AI.Model.Provider.Adapter` behavior:

```elixir
defmodule MyApp.CustomProvider do
  @behaviour Jido.AI.Model.Provider.Adapter
  
  # Implementation of callback functions...
  
  @impl true
  def definition do
    %Jido.AI.Provider{
      id: :custom_provider,
      name: "Custom Provider",
      description: "My custom AI provider implementation",
      type: :direct,
      api_base_url: "https://api.custom-provider.com",
      requires_api_key: true
    }
  end
  
  # Other required callbacks...
end
```

## Error Handling

Jido AI employs consistent error patterns throughout the provider system:

```elixir
case Jido.AI.Model.from({:anthropic, [model: "invalid-model"]}) do
  {:ok, model} ->
    # Handle successful model creation
    process_with_model(model)
    
  {:error, reason} ->
    # Handle error with meaningful message
    Logger.error("Failed to create model: #{reason}")
end
```

## Best Practices

1. **API Key Security**:
   - Never hardcode API keys in your application code
   - Use environment variables or the Keyring module
   - Consider using runtime configuration

2. **Model Selection**:
   - Use capabilities and tier information to select appropriate models
   - Consider costs when choosing between equivalent models from different providers
   - Cache model information to reduce API calls

3. **Error Resilience**:
   - Implement proper error handling for API failures
   - Consider implementing retries with backoff for transient errors
   - Use fallback models when primary models are unavailable

4. **Performance Optimization**:
   - Cache frequently used models and responses
   - Use smaller, faster models for non-critical tasks
   - Set appropriate token limits to control costs and response times

## Examples

### Complete Workflow Example

```elixir
defmodule MyApp.AI do
  alias Jido.AI.Model
  
  def summarize_text(text, opts \\ []) do
    with {:ok, model} <- get_summarization_model(opts),
         {:ok, prompt} <- build_summarization_prompt(text),
         {:ok, response} <- perform_completion(model, prompt) do
      {:ok, extract_summary(response)}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp get_summarization_model(opts) do
    provider = Keyword.get(opts, :provider, :anthropic)
    model = Keyword.get(opts, :model, "claude-3-5-haiku")
    
    Model.from({provider, [
      model: model,
      temperature: 0.3,
      max_tokens: 1000
    ]})
  end
  
  defp build_summarization_prompt(text) do
    {:ok, "Please summarize the following text concisely: #{text}"}
  end
  
  defp perform_completion(model, prompt) do
    # Implementation depends on your AI completion module
    YourApp.AI.Completion.generate(model, prompt)
  end
  
  defp extract_summary(response) do
    # Process the response to extract the summary
    response.text
  end
end
```

### Provider Fallback Example

```elixir
defmodule MyApp.ResilientAI do
  def complete_with_fallback(prompt) do
    providers = [:anthropic, :openai, :openrouter]
    
    Enum.reduce_while(providers, {:error, "All providers failed"}, fn provider, acc ->
      case attempt_completion(provider, prompt) do
        {:ok, result} -> {:halt, {:ok, result}}
        {:error, _reason} -> {:cont, acc}
      end
    end)
  end
  
  defp attempt_completion(provider, prompt) do
    # Try to create a model for the provider
    with {:ok, model} <- create_model_for_provider(provider),
         {:ok, result} <- perform_completion(model, prompt) do
      {:ok, result}
    else
      error -> error
    end
  end
  
  defp create_model_for_provider(:anthropic) do
    Jido.AI.Model.from({:anthropic, [model: "claude-3-5-haiku"]})
  end
  
  defp create_model_for_provider(:openai) do
    Jido.AI.Model.from({:openai, [model: "gpt-3.5-turbo"]})
  end
  
  defp create_model_for_provider(:openrouter) do
    Jido.AI.Model.from({:openrouter, [model: "google/gemini-pro"]})
  end
  
  defp perform_completion(model, prompt) do
    # Implementation depends on your AI completion module
    YourApp.AI.Completion.generate(model, prompt)
  end
end
```

## Conclusion

The Jido AI provider system offers a flexible and robust architecture for integrating multiple AI services into your Elixir applications. By leveraging the standardized provider interface, you can easily switch between providers, compare capabilities, and build resilient AI-powered features.

For specific implementation details, refer to the provider adapter modules and test cases in the codebase.