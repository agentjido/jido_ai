# ReqLLM Integration Architecture

This guide provides a technical deep-dive into how Jido AI integrates with ReqLLM to provide unified access to 57+ AI providers and 2000+ models.

## Overview

ReqLLM is a unified HTTP client for LLM providers, built on Req. Jido AI uses ReqLLM as its foundation, adding:
- Action-based abstractions
- Jido workflow integration
- Enhanced error handling
- Capability detection
- Advanced features (RAG, plugins, fine-tuning)

## Architecture Layers

```
┌─────────────────────────────────────────┐
│         Application Code                │
│    (Your Elixir Application)            │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│         Jido.AI Public API              │
│   (Jido.AI.chat, Jido.AI.embeddings)   │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│      Jido.AI Action Layer               │
│  (Actions, Workflows, Sensors)          │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│     Jido.AI Provider Adapters           │
│  (Provider-specific optimizations)      │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│           ReqLLM Core                   │
│  (Unified HTTP client for LLMs)        │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│         Req HTTP Client                 │
│    (Elixir HTTP client)                 │
└─────────────────┬───────────────────────┘
                  │
         ┌────────┴────────┐
         │                 │
┌────────▼─────┐  ┌───────▼──────────┐
│  Provider A  │  │  Provider B...   │
│  (OpenAI)    │  │  (57+ total)     │
└──────────────┘  └──────────────────┘
```

## Component Details

### 1. ReqLLM Core

**Purpose:** Unified HTTP client for LLM providers

**Key Features:**
- Provider-agnostic request/response handling
- Automatic retry and backoff
- Request/response middleware
- Token counting
- Cost estimation

**Location:** External dependency (`req_llm`)

```elixir
# ReqLLM handles the HTTP communication
defmodule ReqLLM do
  def chat(provider, model, messages, opts \\ [])
  def embeddings(provider, model, input, opts \\ [])
  def stream(provider, model, messages, opts \\ [])
end
```

### 2. Jido.AI Provider Adapters

**Purpose:** Provider-specific optimizations and transformations

**Key Features:**
- Parameter translation
- Response normalization
- Provider-specific features
- Error mapping

**Location:** `lib/jido_ai/adapters/`

**Example:**
```elixir
defmodule Jido.AI.Adapters.OpenAI do
  @moduledoc """
  Adapter for OpenAI-specific features and optimizations.
  """

  def transform_params(params) do
    # Translate Jido.AI params to OpenAI format
    %{
      model: params.model,
      messages: transform_messages(params.messages),
      temperature: params.temperature,
      max_tokens: params.max_tokens,
      # OpenAI-specific parameters
      response_format: params.response_format,
      tools: params.tools
    }
  end

  def transform_response(response) do
    # Normalize OpenAI response to Jido.AI format
    %Jido.AI.Response{
      content: get_in(response, ["choices", 0, "message", "content"]),
      provider: :openai,
      model: response["model"],
      usage: transform_usage(response["usage"]),
      finish_reason: transform_finish_reason(response),
      tool_calls: transform_tool_calls(response),
      raw: response
    }
  end

  # Provider-specific feature support
  def supports_feature?(:vision), do: true
  def supports_feature?(:tools), do: true
  def supports_feature?(:json_mode), do: true
  def supports_feature?(:code_execution), do: true
  def supports_feature?(_), do: false
end
```

### 3. Jido.AI Action Layer

**Purpose:** Integration with Jido's action and workflow system

**Key Features:**
- Action-based abstractions
- Workflow composition
- Sensor integration
- State management

**Location:** `lib/jido_ai/actions/`

**Example:**
```elixir
defmodule Jido.AI.Actions.Chat do
  use Jido.Action,
    name: "chat",
    description: "Chat with an AI model",
    schema: [
      model: [type: :string, required: true],
      prompt: [type: :string, required: true],
      temperature: [type: :float, default: 0.7],
      max_tokens: [type: :integer, default: nil]
    ]

  @impl true
  def run(params, context) do
    # Parse provider and model
    {provider, model} = parse_model(params.model)

    # Get adapter for provider
    adapter = Jido.AI.Adapters.get_adapter(provider)

    # Transform parameters
    req_params = adapter.transform_params(params)

    # Call ReqLLM
    case ReqLLM.chat(provider, model, req_params) do
      {:ok, response} ->
        # Transform response
        normalized = adapter.transform_response(response)
        {:ok, normalized, context}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

### 4. Jido.AI Public API

**Purpose:** User-facing convenience functions

**Key Features:**
- Simple, clean API
- Sensible defaults
- Error handling
- Documentation

**Location:** `lib/jido_ai.ex`

**Example:**
```elixir
defmodule Jido.AI do
  @moduledoc """
  Public API for Jido AI functionality.
  """

  def chat(model, prompt, opts \\ []) do
    # Build params
    params = %{
      model: model,
      prompt: prompt,
      temperature: Keyword.get(opts, :temperature, 0.7),
      max_tokens: Keyword.get(opts, :max_tokens),
      system: Keyword.get(opts, :system),
      stream: Keyword.get(opts, :stream, false)
    }

    # Run action
    Jido.AI.Actions.Chat.run(params, %{})
  end

  def embeddings(model, input, opts \\ []) do
    params = %{model: model, input: input}
    Jido.AI.Actions.Embeddings.run(params, %{})
  end
end
```

## Data Flow

### Request Flow

```
1. User calls Jido.AI.chat("openai:gpt-4", "Hello")
                  │
                  ▼
2. Jido.AI.chat/3 builds parameters
                  │
                  ▼
3. Jido.AI.Actions.Chat.run/2 invoked
                  │
                  ▼
4. Provider adapter transforms parameters
   (Jido.AI format → OpenAI format)
                  │
                  ▼
5. ReqLLM.chat/4 handles HTTP request
   - Retrieves API key from Keyring
   - Builds HTTP request
   - Applies middleware
   - Sends to OpenAI API
                  │
                  ▼
6. OpenAI API responds with completion
                  │
                  ▼
7. ReqLLM receives and validates response
                  │
                  ▼
8. Provider adapter normalizes response
   (OpenAI format → Jido.AI format)
                  │
                  ▼
9. Response returned to user
```

### Streaming Flow

```
1. User calls Jido.AI.chat(..., stream: true)
                  │
                  ▼
2. ReqLLM.stream/4 opens SSE connection
                  │
                  ▼
3. Stream emits chunks as they arrive
   ┌──────────────────────┐
   │ Chunk 1: "Hello"     │
   │ Chunk 2: " world"    │
   │ Chunk 3: "!"         │
   └──────────────────────┘
                  │
                  ▼
4. Each chunk transformed to Jido.AI format
                  │
                  ▼
5. Stream returned to user
```

## Key Design Decisions

### 1. Why ReqLLM?

**Rationale:**
- Unified interface for 57+ providers
- Active maintenance and updates
- Built on Req (modern, well-tested)
- Growing ecosystem

**Alternatives Considered:**
- Custom HTTP client: High maintenance burden
- OpenAI-only: Limited provider support
- LangChain: Different architecture, Python-focused

### 2. Provider Adapter Pattern

**Rationale:**
- Allows provider-specific optimizations
- Maintains clean separation of concerns
- Easy to add new providers
- Testable in isolation

**Implementation:**
```elixir
# Adapter protocol
defmodule Jido.AI.Adapter do
  @callback transform_params(map()) :: map()
  @callback transform_response(map()) :: Jido.AI.Response.t()
  @callback supports_feature?(atom()) :: boolean()
end

# Provider-specific implementations
defmodule Jido.AI.Adapters.OpenAI, do: @behaviour Jido.AI.Adapter
defmodule Jido.AI.Adapters.Anthropic, do: @behaviour Jido.AI.Adapter
defmodule Jido.AI.Adapters.Groq, do: @behaviour Jido.AI.Adapter
```

### 3. Action-Based Architecture

**Rationale:**
- Consistent with Jido SDK patterns
- Enables workflow composition
- Provides state management
- Supports telemetry and monitoring

**Example Workflow:**
```elixir
defmodule MyApp.ResearchWorkflow do
  use Jido.Workflow

  workflow do
    # Step 1: Query with Perplexity (search-enabled)
    step :search, Jido.AI.Actions.Chat,
      model: "perplexity:llama-3.1-sonar-large-128k-online",
      prompt: "Latest Elixir developments"

    # Step 2: Analyze with GPT-4
    step :analyze, Jido.AI.Actions.Chat,
      model: "openai:gpt-4",
      prompt: fn ctx -> "Analyze: #{ctx.search.content}" end

    # Step 3: Summarize with Claude
    step :summarize, Jido.AI.Actions.Chat,
      model: "anthropic:claude-3-sonnet",
      prompt: fn ctx -> "Summarize: #{ctx.analyze.content}" end
  end
end
```

### 4. Response Normalization

**Rationale:**
- Consistent API across all providers
- Easier error handling
- Simpler testing
- Better documentation

**Normalized Response Structure:**
```elixir
defmodule Jido.AI.Response do
  @type t :: %__MODULE__{
    content: String.t(),
    provider: atom(),
    model: String.t(),
    usage: usage(),
    finish_reason: atom(),
    tool_calls: [tool_call()] | nil,
    raw: map()
  }

  @type usage :: %{
    prompt_tokens: integer(),
    completion_tokens: integer(),
    total_tokens: integer()
  }

  @type tool_call :: %{
    id: String.t(),
    type: String.t(),
    function: %{
      name: String.t(),
      arguments: String.t()
    }
  }
end
```

## Integration Points

### 1. Keyring Integration

**Purpose:** Secure credential management

```elixir
defmodule Jido.AI.Keyring do
  @moduledoc """
  Secure storage for API keys and credentials.
  """

  def set(provider, key) when is_atom(provider) do
    # Store in ETS or external secret manager
    :persistent_term.put({__MODULE__, provider}, key)
    :ok
  end

  def get(provider) when is_atom(provider) do
    case :persistent_term.get({__MODULE__, provider}, nil) do
      nil -> check_environment(provider)
      key -> {:ok, key}
    end
  end

  defp check_environment(provider) do
    # Check environment variables
    env_var = provider_to_env_var(provider)
    case System.get_env(env_var) do
      nil -> {:error, :key_not_found}
      key -> {:ok, key}
    end
  end
end
```

### 2. Model Registry

**Purpose:** Dynamic model discovery and capability detection

```elixir
defmodule Jido.AI.Model.Registry do
  @moduledoc """
  Registry for discovering and querying available models.
  """

  def discover_models(opts \\ []) do
    provider = Keyword.get(opts, :provider)

    models = if provider do
      ReqLLM.list_models(provider)
    else
      # Get models from all providers
      Enum.flat_map(supported_providers(), &ReqLLM.list_models/1)
    end

    {:ok, models}
  end

  def search(filters) do
    {:ok, all_models} = discover_models()

    filtered = Enum.filter(all_models, fn model ->
      match_filters?(model, filters)
    end)

    {:ok, filtered}
  end

  defp match_filters?(model, filters) do
    Enum.all?(filters, fn {key, value} ->
      case key do
        :capability -> has_capability?(model, value)
        :provider -> model.provider == value
        :context_length -> model.context_length >= value
        _ -> true
      end
    end)
  end
end
```

### 3. Feature Detection

**Purpose:** Runtime capability checking

```elixir
defmodule Jido.AI.Features do
  @moduledoc """
  Feature detection for models and providers.
  """

  @features %{
    rag: [:cohere, :anthropic, :google],
    code_execution: [:openai],
    plugins: [:openai, :anthropic, :google],
    fine_tuning: [:openai, :cohere, :google, :together]
  }

  def supports?(model, feature) when is_binary(model) do
    case Jido.AI.Model.from(model) do
      {:ok, model_struct} -> supports?(model_struct, feature)
      {:error, _} -> false
    end
  end

  def supports?(%Jido.AI.Model{} = model, feature) do
    provider_supports?(model.provider, feature) or
    model_specific_support?(model, feature)
  end

  def provider_supports?(provider, feature) do
    providers = Map.get(@features, feature, [])
    provider in providers
  end

  defp model_specific_support?(model, :fine_tuning) do
    # Check if model name indicates fine-tuning
    String.contains?(model.model, ["ft:", "fine-tuned", "custom"])
  end

  defp model_specific_support?(_, _), do: false
end
```

## Performance Considerations

### 1. Connection Pooling

ReqLLM uses Req's connection pooling:

```elixir
# Automatic connection reuse
# No configuration needed - handled by Req/Finch
```

### 2. Request Batching

For embeddings and batch operations:

```elixir
defmodule Jido.AI.Batch do
  def embeddings_batch(model, texts) when is_list(texts) do
    # ReqLLM handles batching internally
    ReqLLM.embeddings(model, texts)
  end

  def chat_batch(model, prompts) do
    # Concurrent requests with Task.async_stream
    prompts
    |> Task.async_stream(
      fn prompt -> Jido.AI.chat(model, prompt) end,
      max_concurrency: 10,
      timeout: 30_000
    )
    |> Enum.to_list()
  end
end
```

### 3. Caching

Optional response caching:

```elixir
defmodule Jido.AI.Cache do
  use GenServer

  def chat_cached(model, prompt, opts \\ []) do
    cache_key = cache_key(model, prompt, opts)

    case get_cached(cache_key) do
      {:ok, cached} ->
        {:ok, cached}
      :miss ->
        case Jido.AI.chat(model, prompt, opts) do
          {:ok, response} ->
            put_cached(cache_key, response)
            {:ok, response}
          error -> error
        end
    end
  end

  defp cache_key(model, prompt, opts) do
    :crypto.hash(:sha256, :erlang.term_to_binary({model, prompt, opts}))
    |> Base.encode16()
  end
end
```

## Error Handling

### Error Type Hierarchy

```elixir
defmodule Jido.AI.Error do
  @type t :: %__MODULE__{
    type: error_type(),
    message: String.t(),
    provider: atom(),
    status: integer() | nil,
    details: map()
  }

  @type error_type ::
    :authentication_error |
    :rate_limit |
    :timeout |
    :connection_error |
    :api_error |
    :validation_error |
    :model_not_found |
    :unsupported_feature

  defstruct [:type, :message, :provider, :status, :details]
end
```

### Error Translation

```elixir
defmodule Jido.AI.Errors do
  def translate_reqllm_error(reqllm_error) do
    case reqllm_error do
      %{status: 401} ->
        %Jido.AI.Error{
          type: :authentication_error,
          message: "API key invalid or missing",
          status: 401
        }

      %{status: 429} ->
        %Jido.AI.Error{
          type: :rate_limit,
          message: "Rate limit exceeded",
          status: 429,
          details: extract_rate_limit_details(reqllm_error)
        }

      %{reason: :timeout} ->
        %Jido.AI.Error{
          type: :timeout,
          message: "Request timed out",
          details: %{timeout: reqllm_error.timeout}
        }

      _ ->
        %Jido.AI.Error{
          type: :api_error,
          message: "Unknown error",
          details: reqllm_error
        }
    end
  end
end
```

## Testing Strategy

### 1. Unit Tests

Test adapters in isolation:

```elixir
defmodule Jido.AI.Adapters.OpenAITest do
  use ExUnit.Case, async: true

  alias Jido.AI.Adapters.OpenAI

  describe "transform_params/1" do
    test "transforms basic parameters" do
      params = %{
        model: "gpt-4",
        prompt: "Hello",
        temperature: 0.7
      }

      result = OpenAI.transform_params(params)

      assert result.model == "gpt-4"
      assert result.temperature == 0.7
    end
  end

  describe "transform_response/1" do
    test "normalizes OpenAI response" do
      openai_response = %{
        "choices" => [%{"message" => %{"content" => "Hi"}}],
        "usage" => %{"total_tokens" => 10}
      }

      result = OpenAI.transform_response(openai_response)

      assert result.content == "Hi"
      assert result.usage.total_tokens == 10
    end
  end
end
```

### 2. Integration Tests

Test with real providers:

```elixir
defmodule Jido.AI.IntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  test "chat with OpenAI" do
    {:ok, response} = Jido.AI.chat("openai:gpt-4", "Say 'test'")
    assert is_binary(response.content)
    assert response.provider == :openai
  end

  test "fallback chain works" do
    providers = ["invalid:model", "openai:gpt-4"]

    result = Enum.reduce_while(providers, nil, fn provider, _acc ->
      case Jido.AI.chat(provider, "test") do
        {:ok, response} -> {:halt, {:ok, response}}
        {:error, _} -> {:cont, nil}
      end
    end)

    assert {:ok, _} = result
  end
end
```

### 3. Mock Testing

Use mocks for CI/CD:

```elixir
defmodule Jido.AI.MockAdapter do
  @behaviour Jido.AI.Adapter

  def transform_params(params), do: params

  def transform_response(_response) do
    %Jido.AI.Response{
      content: "Mocked response",
      provider: :mock,
      model: "mock-model",
      usage: %{prompt_tokens: 5, completion_tokens: 5, total_tokens: 10}
    }
  end

  def supports_feature?(_), do: true
end
```

## Extending the Integration

### Adding a New Provider Adapter

```elixir
# 1. Create adapter module
defmodule Jido.AI.Adapters.NewProvider do
  @behaviour Jido.AI.Adapter

  @impl true
  def transform_params(params) do
    # Transform to provider format
  end

  @impl true
  def transform_response(response) do
    # Normalize to Jido.AI format
  end

  @impl true
  def supports_feature?(feature) do
    # Declare supported features
  end
end

# 2. Register adapter
defmodule Jido.AI.Adapters do
  @adapters %{
    openai: Jido.AI.Adapters.OpenAI,
    anthropic: Jido.AI.Adapters.Anthropic,
    new_provider: Jido.AI.Adapters.NewProvider  # Add here
  }

  def get_adapter(provider) do
    Map.get(@adapters, provider, Jido.AI.Adapters.Default)
  end
end

# 3. Add tests
defmodule Jido.AI.Adapters.NewProviderTest do
  use ExUnit.Case
  # ... test cases
end
```

## Summary

The ReqLLM integration provides Jido AI with:

1. **Unified Access:** 57+ providers through single interface
2. **Provider Optimization:** Adapters for provider-specific features
3. **Action Integration:** Seamless Jido workflow composition
4. **Flexibility:** Easy to extend and customize
5. **Reliability:** Battle-tested HTTP client foundation
6. **Performance:** Connection pooling, batching, caching

**Key Benefits:**
- Reduced maintenance (ReqLLM handles provider updates)
- Consistent API across all providers
- Easy provider switching and fallback
- Advanced features (RAG, plugins, fine-tuning)
- Production-ready error handling

## Next Steps

- [Breaking Changes](breaking-changes.md) - Version migration guide
- [Migration Guide](from-legacy-providers.md) - Practical migration scenarios
- [Provider Matrix](../providers/provider-matrix.md) - All provider details
- [Advanced Features](../features/) - Use specialized capabilities
