# ReqLLM Provider Architecture Plan

## Executive Summary

This plan refactors the ReqLLM provider system to align with the new Req plugin-based architecture outlined in `REQ_LLM_CLIENT.md`. The goal is to simplify providers as pure Req plugins while moving orchestration logic to the core ReqLLM module, creating a unified model registry, and ensuring compile-time metadata loading drives capability detection.

## Current State Analysis

### What's Working Well
- ✅ **Compile-time metadata loading**: Providers load JSON metadata at compile time with `@external_resource`
- ✅ **Auto-registration**: Providers self-register via `@after_compile` hooks
- ✅ **TypedStruct foundations**: Model and Provider structs use TypedStruct
- ✅ **Capability system**: Clean behaviour-based capability verification
- ✅ **Provider-specific logic encapsulation**: Auth, request/response formats isolated per provider

### Current Problems
- ❌ **Over-engineered adapter pattern**: 10+ callback behaviour with duplicated logic
- ❌ **Mixed responsibilities**: Providers are both Req plugins AND SDK wrappers
- ❌ **Scattered orchestration**: `generate_text` exists on both providers and core module
- ❌ **No unified model registry**: Model lookup scattered across providers
- ❌ **Complex DSL**: Provider DSL generates too much boilerplate
- ❌ **Inconsistent with Req ecosystem**: Doesn't follow `req_embed` plugin patterns

## Target Architecture: Providers as Pure Req Plugins

### 1. Core Principle: Separation of Concerns

**Provider Plugins** (Pure Req Integration):
- Only handle HTTP request/response transformation for their specific API
- Implement minimal `ReqLLM.Plugin` behaviour with `attach/2` and `parse/2`
- Register models at compile-time but don't own orchestration logic
- Zero public API surface for end users

**Core ReqLLM Module** (Orchestration):
- Owns all public APIs: `generate_text/3`, `stream_text/3`, `generate_object/4`, `embed/3`
- Handles model spec resolution via unified registry
- Manages cross-cutting concerns: telemetry, retries, token counting
- Orchestrates provider plugins through standard Req patterns

**Provider Registry** (Global State):
- Single source of truth for all provider metadata and their models
- Compile-time `persistent_term` storage for fast, immutable lookups
- Runtime reloadable for pricing updates and new models
- Powers capability detection and model validation

### 2. Provider Plugin Behaviour (`ReqLLM.Provider.Adapter`)

Keep `ReqLLM.Provider.Adapter` as a Req plugin with minimal, essential callbacks:

```elixir
defmodule ReqLLM.Provider.Adapter do
  @moduledoc """
  Behaviour for provider plugins that integrate with Req.
  """

  @callback attach(Req.Request.t(), keyword()) :: Req.Request.t()
  @callback parse(Req.Response.t(), keyword()) :: {:ok, term()} | {:error, term()}
  
  # Optional callbacks for provider-specific endpoints
  @callback default_base_url() :: String.t()
  @callback default_api_path() :: String.t()
  
  @optional_callbacks default_base_url: 0, default_api_path: 0
end
```

### 3. Simplified Provider DSL

Dramatically reduce the DSL's surface area to only essential plugin logic:

```elixir
defmodule ReqLLM.Providers.Anthropic do
  use ReqLLM.Provider.DSL,
    id: :anthropic,
    base_url: "https://api.anthropic.com",
    auth: {:header, "x-api-key", :plain},
    metadata: "anthropic.json"

  @impl ReqLLM.Provider.Adapter
  def attach(req, opts) do
    model = opts[:model]
    messages = opts[:messages]
    stream? = opts[:stream?] || false

    req
    |> Req.merge(
         method: :post,
         url: "/v1/messages",
         headers: [{"anthropic-version", "2023-06-01"}],
         json: build_anthropic_body(model, messages, stream?, opts)
       )
  end

  @impl ReqLLM.Provider.Adapter
  def parse(response, opts) do
    case {response.status, opts[:stream?]} do
      {200, true} -> parse_streaming_response(response)
      {200, false} -> parse_response(response)
      {status, _} -> {:error, build_error(status, response.body)}
    end
  end

  # Private implementation helpers...
end
```

**Key Changes:**
- DSL only generates plugin registration and metadata loading
- No more `generate_text/3` or `stream_text/3` methods on providers
- Providers receive full context in `attach/2` call
- All provider-specific logic remains encapsulated

### 4. Unified Provider Registry

Create a global registry that consolidates provider metadata and enables the `{provider}:{model}` developer experience:

```elixir
defmodule ReqLLM.Provider.Registry do
  @moduledoc """
  Global persistent_term-backed registry for all LLM providers.

  Populated at compile-time by provider metadata,
  reloadable at runtime for pricing updates.
  """

  @registry_key :req_llm_providers

  # Called by provider DSL at compile-time
  def register(provider_id, provider_module, metadata) do
    providers = :persistent_term.get(@registry_key, %{})
    
    provider_info = %{
      id: provider_id,
      module: provider_module,
      base_url: metadata[:base_url],
      paths: metadata[:paths] || %{},
      models: metadata[:models] || %{}
    }
    
    updated = Map.put(providers, provider_id, provider_info)
    :persistent_term.put(@registry_key, updated)
  end

  # Core lookup functions
  def get_provider(provider_id) do
    case :persistent_term.get(@registry_key, %{}) do
      %{^provider_id => info} -> {:ok, info}
      _ -> {:error, :provider_not_found}
    end
  end

  def get_model(provider_id, model_id) do
    with {:ok, %{models: models}} <- get_provider(provider_id),
         {:ok, model} <- Map.fetch(models, model_id) do
      {:ok, model}
    else
      _ -> {:error, :model_not_found}
    end
  end

  # Convenience for model specs
  def get_model!(spec) when is_binary(spec) do
    [provider, model] = String.split(spec, ":", parts: 2)
    case get_model(String.to_atom(provider), model) do
      {:ok, model} -> model
      {:error, _} -> raise "Unknown model: #{spec}"
    end
  end

  # Developer experience helpers
  def list_providers do
    :persistent_term.get(@registry_key, %{}) |> Map.keys()
  end

  def list_models(provider_id \\ nil) do
    case provider_id do
      nil -> 
        for {pid, %{models: models}} <- :persistent_term.get(@registry_key, %{}),
            {mid, _} <- models, do: "#{pid}:#{mid}"
      pid ->
        case get_provider(pid) do
          {:ok, %{models: models}} -> Map.keys(models)
          _ -> []
        end
    end
  end

  def model_exists?(spec) do
    try do
      get_model!(spec)
      true
    rescue
      _ -> false
    end
  end
end
```

**Registry Benefits:**
- O(1) provider/model lookup with zero memory copying
- Single source of truth for capabilities, pricing, limits
- Compile-time population with static immutable data
- Powers `mix req_llm.verify` and other tooling
- Enables cross-provider features (fallback, comparison)

### 5. Core API Orchestration

Move all high-level APIs to the core `ReqLLM` module, which orchestrates provider plugins:

```elixir
defmodule ReqLLM do
  def generate_text(model_spec, messages, opts \\ []) do
    with {:ok, model} <- resolve_model_with_metadata(model_spec),
         {:ok, plugin_module} <- get_plugin_for_provider(model.provider),
         request <- build_base_request(opts),
         request <- plugin_module.attach(request, build_plugin_opts(model, messages, opts)),
         {:ok, response} <- Req.request(request, http_opts(opts)),
         {:ok, result} <- plugin_module.parse(response, opts) do

      emit_telemetry([:req_llm, :generate_text, :success], model, response)
      {:ok, response}
    else
      error ->
        emit_telemetry([:req_llm, :generate_text, :error], model_spec, error)
        error
    end
  end

  def stream_text(model_spec, messages, opts \\ []) do
    opts_with_stream = Keyword.put(opts, :stream?, true)
    generate_text(model_spec, messages, opts_with_stream)
  end

  # Helper functions
  def model(spec) do
    ReqLLM.Model.Registry.get_model!(spec)
  end

  def provider(provider) do
    case provider do
      :openai -> {:ok, ReqLLM.Providers.OpenAI}
      :anthropic -> {:ok, ReqLLM.Providers.Anthropic}
      _ -> {:error, ReqLLM.Error.unsupported_provider(provider: provider)}
    end
  end
end
```

**Orchestration Benefits:**
- Single place for cross-cutting concerns (telemetry, retries, timeouts)
- Consistent error handling and response formats
- Enables advanced features (fallback providers, token budgeting)
- Clean separation between HTTP transport and business logic
- Easier testing and mocking

### 6. Capability System Integration

Update capability modules to use the unified registry instead of provider-specific logic:

```elixir
defmodule ReqLLM.Capabilities.GenerateText do
  @behaviour ReqLLM.Capability

  def id, do: :generate_text

  def advertised?(model) do
    # All models support basic text generation
    true
  end

  def verify(model, opts) do
    # Use core API, not provider-specific methods
    case ReqLLM.generate_text("#{model.provider}:#{model.model}", "Hello!", opts) do
      {:ok, %Req.Response{body: text}} when is_binary(text) and text != "" ->
        {:ok, %{response_length: String.length(text)}}
      {:error, error} ->
        {:error, error}
    end
  end
end
```

**Capability Benefits:**
- Consistent with registry-driven architecture
- Tests actual end-user API, not provider internals
- Simplified implementation using core orchestration
- Better error reporting through unified error types

### 7. Implementation Phases

#### Phase 1: Foundation (Week 1)
- [ ] Create `ReqLLM.Plugin` behaviour
- [ ] Create `ReqLLM.Model.Registry` with ETS backend
- [ ] Update `ReqLLM.Model` struct with TypedStruct validation
- [ ] Add registry population to provider DSL

#### Phase 2: Provider Refactoring (Week 2)
- [ ] Simplify `ReqLLM.Provider.DSL` to only generate plugin code
- [ ] Refactor Anthropic provider to use new plugin pattern
- [ ] Refactor OpenAI provider to use new plugin pattern
- [ ] Create backward compatibility shims for old adapter methods

#### Phase 3: Core Orchestration (Week 3)
- [ ] Move `generate_text/3` logic from providers to core ReqLLM module
- [ ] Move `stream_text/3` logic from providers to core ReqLLM module
- [ ] Add comprehensive telemetry throughout orchestration
- [ ] Update error handling to use unified Splode error types

#### Phase 4: Integration & Testing (Week 4)
- [ ] Update all capability modules to use core APIs
- [ ] Create `ReqLLM.StreamChunk` struct for unified streaming
- [ ] Implement fixture-based testing with `ReqLLM.TestHelpers`
- [ ] Update documentation and examples

#### Phase 5: Cleanup & Release (Week 5)
- [ ] Mark old adapter behaviour as deprecated
- [ ] Run full test suite with backward compatibility
- [ ] Update `mix req_llm.verify` to use registry
- [ ] Add migration guide for provider authors

### 8. Migration Strategy

**Backward Compatibility:**
- Keep old adapter methods for one release cycle
- Add deprecation warnings pointing to new core APIs
- Provide automatic shim translation from old to new patterns
- Include clear migration guide in CHANGELOG

**Provider Migration:**
```elixir
# Old (deprecated but working)
ReqLLM.Providers.Anthropic.generate_text(model, messages, opts)

# New (recommended)
ReqLLM.generate_text("anthropic:claude-3-sonnet", messages, opts)
```

**Breaking Changes (Next Major Version):**
- Remove `ReqLLM.Provider.Adapter` behaviour entirely
- Remove `generate_text/stream_text` methods from provider modules
- Remove shim compatibility layer
- Require explicit provider registration for custom providers

### 9. Directory Structure (After Refactoring)

```
lib/req_llm/
├── req_llm.ex                    # Main API module (generate_text, stream_text, etc.)
├── plugin.ex                    # Plugin behaviour (attach/2, parse/2)
├── model/
│   ├── model.ex                 # Model struct (TypedStruct)
│   └── registry.ex              # Global model registry (ETS)
├── providers/
│   ├── openai.ex                # OpenAI plugin implementation
│   └── anthropic.ex             # Anthropic plugin implementation
├── provider/
│   ├── dsl.ex                   # Simplified DSL macro
│   └── spec.ex                  # Provider spec struct
├── capabilities/
│   ├── generate_text.ex         # Updated to use core API
│   ├── stream_text.ex           # Updated to use core API
│   ├── tool_calling.ex          # Updated to use core API
│   └── reasoning.ex             # Updated to use core API
├── stream_chunk.ex              # Unified streaming response struct
├── test_helpers.ex              # Fixture-based testing utilities
└── error.ex                     # Unified Splode error types
```

**Code Reduction:**
- Remove ~500 LOC of duplicated provider logic
- Remove ~300 LOC from complex adapter behaviour
- Add ~200 LOC for registry and orchestration
- **Net reduction: ~600 LOC** with cleaner architecture

### 10. Developer Experience Improvements

**Simplified Provider Creation:**
```elixir
defmodule ReqLLM.Providers.Custom do
  use ReqLLM.Provider.DSL,
    id: :custom,
    base_url: "https://api.custom.com",
    auth: {:header, "authorization", :bearer},
    metadata: "custom.json"

  def attach(req, opts), do: # minimal implementation
  def parse(response, opts), do: # minimal implementation
end
```

**Unified Model Access:**
```elixir
# List all available models
ReqLLM.models()
# => ["openai:gpt-4", "anthropic:claude-3-sonnet", ...]

# Get specific model with metadata
model = ReqLLM.model!("openai:gpt-4o")
model.capabilities.reasoning?  # => true
model.cost.input              # => 0.0025
```

**Consistent Core API:**
```elixir
# All models use same interface
ReqLLM.generate_text("openai:gpt-4", messages)
ReqLLM.generate_text("anthropic:claude-3-sonnet", messages)
ReqLLM.generate_text("custom:my-model", messages)

# Streaming just adds option
ReqLLM.stream_text("openai:gpt-4", messages, stream?: true)
```

## Conclusion

This provider architecture plan transforms ReqLLM from a collection of independent adapter modules into a cohesive Req ecosystem plugin with unified orchestration. By embracing the plugin pattern, centralizing model metadata in a registry, and moving high-level APIs to the core module, we achieve:

1. **Simplicity**: Providers become minimal, focused plugins
2. **Consistency**: All models accessed through unified APIs
3. **Maintainability**: Single orchestration point reduces duplication
4. **Extensibility**: Easy to add new providers and cross-provider features
5. **Developer Experience**: Intuitive model specs and comprehensive metadata
6. **Testing**: Simplified mocking and fixture-based testing

The phased implementation ensures backward compatibility while gradually migrating to the cleaner architecture, setting ReqLLM up for long-term success as a true Req ecosystem citizen.
