# Jido AI Provider Integration Guide

## Overview

Jido AI delivers a framework for integrating multiple AI providers into your Jido Agents. This guide explores the provider architecture, model configuration, and best practices for leveraging AI services through a unified interface. The provider system enables seamless switching between services like Anthropic, OpenAI, and more, while maintaining consistent interaction patterns. It builds upon popular Hex Packages to manage the AI integration such as `Instructor`, `Langchain`, and `OpenaiEx`.

## Provider Architecture

Jido AI implements a modular architecture where each provider adapter conforms to the `Jido.AI.Model.Provider.Adapter` behavior. This standardizes how you interact with diverse AI services while preserving their unique capabilities.

### Core Components

- **Provider Adapters**: Specialized modules implementing provider-specific API requirements
- **Model Registry**: Central repository for discovering and accessing available models
- **Credential Management**: Secure API key handling through the Keyring system

## Available Providers

Jido AI supports multiple provider integrations:

| Provider | Module | Description |
|----------|--------|-------------|
| Anthropic | `Jido.AI.Provider.Anthropic` | Access to Claude models for advanced natural language tasks |
| OpenAI | `Jido.AI.Provider.OpenAI` | Access to GPT models, DALL-E, and embeddings |
| OpenRouter | `Jido.AI.Provider.OpenRouter` | Unified access to multiple AI providers through a single API |
| Cloudflare | `Jido.AI.Provider.Cloudflare` | Access to Cloudflare's AI Gateway and Workers AI models |

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

The `Jido.AI.Model` struct offers a unified representation of any AI model:

```elixir
%Jido.AI.Model{
  id: String.t(),              # Unique identifier for the model
  name: String.t(),            # Human-readable name
  provider: atom(),            # Provider identifier (e.g., :anthropic, :openai)
  model: String.t(),           # Provider-specific model identifier
  base_url: String.t(),        # API base URL
  api_key: String.t(),         # API key for authentication
  temperature: float(),        # Temperature setting for generation
  max_tokens: non_neg_integer(), # Maximum tokens to generate
  max_retries: non_neg_integer(), # Maximum number of retry attempts
  architecture: Architecture.t(), # Model architecture information
  created: integer(),          # Creation timestamp
  description: String.t(),     # Model description
  endpoints: list(Endpoint.t()) # Available API endpoints
}
```

## API Key Management

Jido AI provides flexible API key management through the `Jido.AI.Keyring` module:

```elixir
# Set an API key for a provider
Jido.AI.Keyring.set_session_value(:anthropic_api_key, "your-api-key")

# Get an API key (checks session, environment variables, and default config)
api_key = Jido.AI.Keyring.get(:anthropic_api_key)

# Create a model using the stored API key (automatically retrieves from Keyring)
{:ok, model} = Jido.AI.Model.from({:anthropic, [model: "claude-3-5-haiku"]})
```

API keys can be provided through multiple methods (in order of precedence):
1. Direct specification in model options
2. Session values in the `Jido.AI.Keyring` module
3. Environment variables (e.g., `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`)
4. Application configuration

## Prompt Management

Jido AI includes a comprehensive prompt management system for creating, formatting, and organizing prompts:

```elixir
# Create a simple prompt
prompt = Jido.AI.Prompt.new(:user, "Explain quantum computing")

# Create a prompt with a system message and user message
prompt = Jido.AI.Prompt.new(%{
  messages: [
    %{role: :system, content: "You are a helpful assistant specializing in physics"},
    %{role: :user, content: "Explain quantum computing"}
  ]
})

# Create a templated prompt with parameter substitution
template = Jido.AI.Prompt.Template.from_string!(
  "Explain <%= @topic %> in <%= @style %> terms"
)

# Format the template with values
formatted = Jido.AI.Prompt.Template.format(template, %{
  topic: "quantum computing",
  style: "simple"
})
```

## Provider-Specific Configuration

### Anthropic Provider

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
- `max_tokens`: Maximum tokens to generate

### OpenAI Provider

```elixir
{:ok, openai_model} = Jido.AI.Model.from({:openai, [
  model: "gpt-4o",
  temperature: 0.7,
  max_tokens: 1024
]})
```

Key configuration options:
- `model`: OpenAI model identifier (e.g., "gpt-4o", "gpt-3.5-turbo")
- `temperature`: Controls randomness (0.0 to 2.0)
- `max_tokens`: Maximum tokens to generate

### OpenRouter Provider

```elixir
{:ok, router_model} = Jido.AI.Model.from({:openrouter, [
  model: "anthropic/claude-3-opus-20240229",
  max_tokens: 2000
]})
```

Key configuration options:
- `model`: Provider and model in format "provider/model"
- `temperature`: Controls randomness (0.0 to 1.0)
- `max_tokens`: Maximum tokens to generate

### Cloudflare Provider

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

### Listing and Fetching Models

Each provider implements endpoints to retrieve model information. Jido AI automatically caches this data locally to minimize API calls.

```elixir
# List all OpenAI models
{:ok, models} = Jido.AI.Provider.models(:openai)

# List models with refresh option to fetch latest from API
{:ok, fresh_models} = Jido.AI.Provider.models(:anthropic, refresh: true)

# Get information about a specific model
{:ok, model_info} = Jido.AI.Provider.get_model(:anthropic, "claude-3-5-haiku")
```

### Model Caching with Mix Tasks

Jido AI provides mix tasks to help manage model information:

```bash
# Fetch and cache models for a provider
mix jido.ai.provider.fetch_models --provider anthropic

# Refresh cached models for all providers
mix jido.ai.provider.fetch_models --all --refresh
```

This allows you to pre-cache model information for faster application startup and offline usage.

### Model Standardization

```elixir
# Standardize model names for comparison
standardized_name = Jido.AI.Provider.standardize_model_name("claude-3-7-sonnet-20250219")
# Returns "claude-3.7-sonnet"
```

### Cross-Provider Model Information

```elixir
# Get combined information for equivalent models across providers
{:ok, combined_info} = Jido.AI.Provider.get_combined_model_info("gpt-4")

# Compare pricing across providers
pricing_by_provider = combined_info.pricing_by_provider
```

## Action Integration

Jido AI includes a range of action modules that work with the provider system to perform common AI tasks. These are covered in detail in separate documentation, but include:

- `Jido.AI.Actions.Instructor.*` - For structured outputs using the Instructor pattern
- `Jido.AI.Actions.Langchain.*` - For tool/function integration
- `Jido.AI.Actions.OpenaiEx.*` - For direct OpenAI API interactions

These actions can be used directly with your Model instances.

## Error Handling and Resilience

```elixir
defmodule MyApp.ResilientModelAccess do
  def with_fallback_providers(task_fn) do
    # Try multiple providers in sequence
    providers = [:anthropic, :openai, :openrouter]
    
    Enum.reduce_while(providers, {:error, "All providers failed"}, fn provider, acc ->
      case attempt_with_provider(provider, task_fn) do
        {:ok, result} -> {:halt, {:ok, result}}
        {:error, _reason} -> {:cont, acc}
      end
    end)
  end
  
  defp attempt_with_provider(provider, task_fn) do
    case create_model_for_provider(provider) do
      {:ok, model} -> task_fn.(model)
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
end
```

## Custom Provider Adapters

To create a custom provider adapter, implement the `Jido.AI.Model.Provider.Adapter` behavior:

```elixir
defmodule MyApp.CustomProvider do
  @behaviour Jido.AI.Model.Provider.Adapter
  
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
  
  @impl true
  def base_url do
    "https://api.custom-provider.com"
  end
  
  @impl true
  def list_models(opts \\ []) do
    # Implementation details...
  end
  
  @impl true
  def model(model, opts \\ []) do
    # Implementation details...
  end
  
  @impl true
  def normalize(model, opts \\ []) do
    # Implementation details...
  end
  
  @impl true
  def request_headers(opts) do
    # Implementation details...
  end
  
  @impl true
  def validate_model_opts(opts) do
    # Implementation details...
  end
  
  @impl true
  def build(opts) do
    # Implementation details...
  end
  
  @impl true
  def transform_model_to_clientmodel(client_atom, model) do
    # Implementation details...
  end
end
```

## Complete Example: Document Processing

```elixir
defmodule MyApp.DocumentProcessor do
  alias Jido.AI.Model
  alias Jido.AI.Prompt
  
  def process_document(text, opts \\ []) do
    with {:ok, model} <- get_model(opts),
         {:ok, summary} <- summarize_document(model, text),
         {:ok, topics} <- extract_key_topics(model, text) do
      {:ok, %{summary: summary, topics: topics}}
    else
      {:error, reason} -> {:error, "Document processing failed: #{inspect(reason)}"}
    end
  end
  
  defp get_model(opts) do
    provider = Keyword.get(opts, :provider, :anthropic)
    model_id = Keyword.get(opts, :model, "claude-3-5-haiku")
    
    Model.from({provider, [
      model: model_id,
      temperature: 0.3,
      max_tokens: 1000
    ]})
  end
  
  defp summarize_document(model, text) do
    # Implementation using one of the Action modules...
  end
  
  defp extract_key_topics(model, text) do
    # Implementation using one of the Action modules...
  end
end
```

## Best Practices

1. **API Key Security**:
   - Store API keys in environment variables or use the Keyring module
   - Implement proper access control for key management
   - Consider using HashiCorp Vault or similar services for production

2. **Model Selection**:
   - Use capabilities data to select suitable models for specific tasks
   - Consider pricing differences between providers for equivalent models
   - Use smaller models for drafts and larger models for final outputs

3. **Performance Optimization**:
   - Cache model information using the provided Mix tasks
   - Set appropriate token limits for each task
   - Optimize prompts to reduce token usage

4. **Error Resilience**:
   - Implement provider fallbacks
   - Use exponential backoff for retries
   - Have graceful degradation strategies

5. **Integration Architecture**:
   - Separate model configuration from business logic
   - Use dependency injection for model instances
   - Create adapters for specific AI tasks in your domain

## Conclusion

The Jido AI provider system offers a flexible, robust architecture for integrating multiple AI services into your Elixir applications. By leveraging standardized interfaces, you can easily switch between providers, implement fallbacks, and build resilient AI-powered features while maintaining clean, consistent code.

As AI systems continue to evolve, Jido AI's modular design allows your applications to adapt and incorporate new capabilities with minimal changes to your core logic.