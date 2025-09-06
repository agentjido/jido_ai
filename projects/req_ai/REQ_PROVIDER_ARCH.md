# ReqAI Provider Architecture

## Overview

ReqAI is designed as a Req-native LLM client with an API modeled after the Vercel AI SDK (`generate_text`/`stream_text`). This document outlines the architectural approach for building a clean, extensible provider system that leverages Req's plugin architecture effectively.

## Core Design Principles

### 1. Three-Stage Provider Contract

ReqAI uses a **three-callback contract** that gives providers control over key stages while maximizing code reuse:

```elixir
@callback build_request(model, prompt_or_msgs, opts) :: Req.Request.t()
@callback send_request(request :: Req.Request.t(), opts) :: 
            {:ok, Req.Response.t()} | {:ok, Enumerable.t()} | {:error, term}
@callback parse_response(resp_or_stream, context, opts) :: 
            {:ok, term} | {:error, ReqAI.Error.t()}
```

- **`build_request/3`**: Returns a fully-prepared `Req.Request` (headers, URL, body, stream config)
- **`send_request/2`**: Executes the request (optional override, defaults to `Req.run` with plugins)
- **`parse_response/3`**: Translates raw response/stream into domain results

This separation enables:
- **Composability**: Req plugins can transform requests/responses without provider changes
- **Multiple transports**: HTTP, SSE, WebSocket, gRPC with same builder/parser
- **Testability**: Unit test builders, parsers, and HTTP layer separately
- **Flexibility**: Most providers only override `build_request/3` and `parse_response/3`

### 2. Req Plugin-Centric Architecture

Cross-cutting concerns are handled by composable Req plugins in a standard pipeline:

```elixir
Req.new(base_url)
|> ReqAI.Plugins.Kagi.attach(provider)        # API key injection
|> ReqAI.Plugins.Retry.attach(policy)         # Retry with backoff
|> ReqAI.Plugins.Json.attach()                # JSON encode/decode
|> ReqAI.Plugins.Splode.attach()              # Error reporting
|> ReqAI.Plugins.Telemetry.attach()           # OpenTelemetry
|> ReqAI.Plugins.Stream.attach(opts)          # SSE streaming (if enabled)
```

**Plugin Responsibilities**:
- **Kagi Plugin**: Uses Kagi for API key resolution and injection
- **JSON Plugin**: Built into Req for encode/decode  
- **Stream Plugin**: Generic parser for `text/event-stream` → chunks
- **Retry Plugin**: Unified backoff using `Model.max_retries`
- **Splode Plugin**: Normalizes provider errors into `ReqAI.Error` structs with telemetry
- **Telemetry Plugin**: OpenTelemetry tracing and cost accounting

### 3. Modular Architecture with Injectable Components

Providers can override specific components while inheriting shared behavior:

```elixir
defmodule ReqAI.Provider.OpenAI do
  use ReqAI.Provider.Macro,
    json: "openai.json",
    base_url: "https://api.openai.com/v1"
    # Uses default builder/parser modules

  # Only override specific callbacks when needed
end

defmodule ReqAI.Provider.Anthropic do
  use ReqAI.Provider.Macro,
    json: "anthropic.json", 
    base_url: "https://api.anthropic.com",
    builder: ReqAI.Request.Builder.Anthropic,    # Custom request format
    parser: ReqAI.Response.Parser.Anthropic      # Custom response parsing
end
```

**Shared Modules**:
- `ReqAI.Request.Builder` - OpenAI-style chat completion defaults
- `ReqAI.Request.Builder.Anthropic` - Anthropic message format
- `ReqAI.Response.Parser` - OpenAI JSON + streaming chunks  
- `ReqAI.Response.Parser.Anthropic` - Claude response format
- `ReqAI.HTTP.Default` - Standard Req pipeline with plugins

## Architecture Components

### 1. Model System

**Model Metadata Integration**:
- Compile-time fetch from `models.dev` API
- Store as JSON files in `priv/models_dev/{provider}.json`
- Rich metadata: pricing, context limits, capabilities, modalities
- Runtime configuration via `Model.from/1` with flexible input formats

**Model Struct** (using TypedStruct):
```elixir
defmodule ReqAI.Model do
  use TypedStruct
  
  typedstruct do
    field :provider, atom(), enforce: true
    field :model, String.t(), enforce: true
    field :temperature, float(), default: 1.0
    field :max_tokens, integer()
    field :max_retries, integer(), default: 3
    # Rich metadata from models.dev
    field :cost, Model.Cost.t()
    field :limits, Model.Limits.t()
    field :capabilities, Model.Capabilities.t()
  end
end
```

### 2. Provider Registry

Compile-time registry using a simple map approach with proper namespacing:

```elixir
defmodule ReqAI.Provider.Registry do
  @providers %{
    openai: ReqAI.Provider.OpenAI,
    anthropic: ReqAI.Provider.Anthropic,
    google: ReqAI.Provider.Google,
    azure_openai: ReqAI.Provider.AzureOpenAI
  }
  
  def get(provider), do: Map.get(@providers, provider)
  def list, do: Map.keys(@providers)
end
```

### 3. Core API (Vercel AI SDK Style)

**Synchronous + Streaming Twins**:
```elixir
{:ok, string} = ReqAI.generate_text(model, prompt, opts)
{:ok, stream} = ReqAI.stream_text(model, prompt, opts)
```

Both functions use the same execution path - streaming version returns the `Req.Request` stream, non-streaming version reduces the stream to a binary.

### 4. Configuration & API Keys (Kagi Integration)

**Kagi-Based Configuration Flow**:
- Use Kagi for robust configuration and API key management
- Support multiple environment variable names per provider
- Runtime override capabilities with session isolation
- Hot reload support for development

```elixir
# Provider configuration in Kagi
config :kagi,
  providers: %{
    openai: [env_vars: ["OPENAI_API_KEY", "OPENAI_KEY"]],
    anthropic: [env_vars: ["ANTHROPIC_API_KEY", "CLAUDE_API_KEY"]]
  }

# Runtime API
ReqAI.Config.api_key(:openai)          # Via Kagi
ReqAI.Config.put_key(:openai, "sk-...") # Runtime override
```

### 5. Error Handling (Splode Integration)

Use Splode for consistent error handling with telemetry and reporting:

```elixir
defmodule ReqAI.Error do
  use Splode,
    error_classes: [
      api: ReqAI.Error.API,
      validation: ReqAI.Error.Validation,
      network: ReqAI.Error.Network
    ]
end
```

**Splode Plugin** converts provider errors into structured exceptions with:
- Consistent error taxonomy
- Automatic telemetry reporting  
- Rich error context and metadata
- Provider-agnostic error handling patterns

## Implementation Strategy

### Phase 1: Core Infrastructure
1. **Provider Behavior**: Three-callback contract (`build_request`, `send_request`, `parse_response`)
2. **Shared Modules**: Extract `Request.Builder.*`, `Response.Parser.*`, `HTTP.*` as injectable components
3. **Provider Macro**: Generate defaults with overrideable `:builder`, `:parser`, `:http` options
4. **Base Plugins**: Kagi auth, Splode errors, retry, telemetry, streaming

### Phase 2: Provider Implementations  
1. **ReqAI.Provider.OpenAI**: Reference implementation using default components
2. **ReqAI.Provider.Anthropic**: Custom builder/parser to validate override system
3. **Registry**: Compile-time provider map with proper namespacing

### Phase 3: Advanced Features
1. **Tool Calling**: Provider-agnostic request builders for function calling
2. **Multi-modal Support**: Image/audio/video content types in builders/parsers
3. **Additional Providers**: Google, Azure OpenAI, local models with transport overrides

## Benefits of This Approach

### Maximum Provider Control
- Providers can override any stage: request building, HTTP transport, or response parsing
- Injectable components allow surgical customization without rewriting shared logic
- Three-callback contract gives providers fine-grained control while preserving defaults

### Battle-Tested Foundation
- Leverages Req's mature plugin ecosystem for HTTP concerns
- Kagi provides robust configuration management with environment precedence
- Splode ensures consistent error handling with telemetry integration

### Clean Separation of Concerns
- Request builders focus purely on API-specific JSON formatting
- Response parsers handle provider-specific streaming/JSON patterns  
- HTTP layer manages transport, retry, auth via composable plugins
- Each concern can be tested and evolved independently

### Developer Experience
- Familiar Vercel AI SDK patterns (`generate_text`/`stream_text`)
- Provider namespace clarity (`ReqAI.Provider.OpenAI` not `ReqAI.OpenAI`)
- Transparent HTTP layer - providers work alongside Req, not wrapping it
- Hot reloadable configuration via Kagi for development workflow

## Migration from Jido.AI

The refined architecture maintains Jido.AI's proven patterns while addressing complexity:

- **Preserve**: Rich model metadata, three-stage processing (build→send→parse), macro-based provider generation
- **Refine**: Replace complex behavior with injectable components, leverage mature libs (Kagi/Splode)
- **Enhance**: Better provider control, cleaner plugin composition, explicit module boundaries

This approach gives providers **more control** than Jido.AI while **reducing overall complexity** through better separation of concerns and leveraging proven Elixir libraries.
