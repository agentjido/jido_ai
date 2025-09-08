# ReqLLM Provider System Architecture Report

## Table of Contents
1. [Provider DSL Architecture](#1-provider-dsl-architecture)
2. [Models.dev Integration](#2-modelsdev-integration) 
3. [Provider Implementation Pattern](#3-provider-implementation-pattern)
4. [Model Spec System](#4-model-spec-system)
5. [Registry Pattern](#5-registry-pattern)
6. [Testing Implications](#6-testing-implications)

---

## 1. Provider DSL Architecture

### Core Macro Implementation

The `ReqLLM.Provider.DSL` module provides a powerful macro system that generates complete AI provider implementations with minimal boilerplate. The `__using__/1` macro performs three critical functions:

#### 1.1 Auto-generates Behavior Implementations

The DSL macro automatically generates implementations of the `ReqLLM.Provider.Adapter` behavior, including:

- `spec/0` - Returns provider configuration and metadata
- `provider_info/0` - Returns provider identification information  
- `generate_text/3` - Standard text generation with HTTP orchestration
- `stream_text/3` - Streaming text generation with SSE handling
- Helper functions like `models/0` and `get_model/1`

**Key Implementation Details:**
```elixir
# Generated behavior implementation with HTTP orchestration
@impl ReqLLM.Provider.Adapter
def generate_text(model, messages, opts \\ []) do
  with {:ok, request} <- build_request(messages, [], build_opts),
       request_with_spec <- ReqLLM.Core.HTTP.with_provider_spec(request, spec()),
       {:ok, response} <- ReqLLM.Core.HTTP.send(request_with_spec, http_opts),
       {:ok, parsed} <- parse_response(response, [], opts) do
    # Return handling logic
  end
end
```

The generated implementations handle the common HTTP orchestration while delegating provider-specific logic to the `build_request/3` and `parse_response/3` callbacks.

#### 1.2 Registers Providers in :persistent_term Registry

Auto-registration occurs via the `@after_compile {ReqLLM.Provider.Registry, :auto_register}` hook:

```elixir
# In DSL macro
@after_compile {ReqLLM.Provider.Registry, :auto_register}

# Registry auto_register callback
def auto_register(env, _bytecode) do
  try do
    spec = env.module.spec()
    register(env.module, spec.id)
  rescue
    _ -> :ok  # Silently ignore compilation failures
  end
end
```

This enables O(1) provider lookup without manual registry maintenance. Providers are stored in `:persistent_term` for fast access across the entire BEAM VM.

#### 1.3 Wires Configuration from Options

The macro processes configuration options and generates module attributes:

```elixir
# Required options validation
unless id, do: raise ArgumentError, "ReqLLM.Provider.DSL requires :id option"
unless base_url, do: raise ArgumentError, "ReqLLM.Provider.DSL requires :base_url option"
unless auth, do: raise ArgumentError, "ReqLLM.Provider.DSL requires :auth option"

# JSON metadata path resolution
json_path = if metadata_file do
  Path.join(:code.priv_dir(:req_llm), "models_dev/#{metadata_file}")
end
```

### 1.4 Metadata Loading and Model Generation

The DSL automatically loads and parses JSON metadata files from `priv/models_dev/`:

```elixir
{provider_meta, models_map} =
  cond do
    json_path && File.exists?(json_path) ->
      json_path
      |> File.read!()
      |> Jason.decode!()
      |> then(fn data ->
        prov = Map.get(data, "provider", %{})
        models_data = Map.get(data, "models", [])
        
        models = Map.new(models_data, fn model_data ->
          model = ReqLLM.Model.new(
            id,
            model_data["id"],
            modalities: parse_modalities(model_data["modalities"]),
            capabilities: parse_capabilities(model_data),
            cost: parse_cost(model_data["cost"]),
            limit: parse_limit(model_data["limit"])
          )
          
          {model_data["id"], model}
        end)
        
        {prov, models}
      end)
  end
```

---

## 2. Models.dev Integration

### 2.1 Metadata Synchronization Process

The `mix req_llm.model_sync` task provides the complete metadata synchronization pipeline:

**Data Flow:**
1. **Fetch** - Downloads `https://models.dev/api.json` with all provider/model metadata
2. **Process** - Extracts models per provider and enhances with local configuration
3. **Store** - Saves normalized JSON files to `priv/models_dev/*.json`

**Implementation Details:**
```elixir
defp save_provider_files(models_data, verbose?) do
  models_data
  |> Enum.each(fn {provider_id, provider_data} ->
    models = process_provider_models(provider_data["models"] || %{}, provider_id)
    
    if not Enum.empty?(models) do
      provider_file = Path.join(@providers_dir, "#{provider_id}.json")
      config = get_provider_config(provider_id)
      
      provider_json = %{
        "provider" => %{
          "id" => provider_id,
          "name" => provider_data["name"] || format_provider_name(provider_id),
          "base_url" => config["base_url"],
          "env" => config["env"] || [],
          "doc" => provider_data["description"] || "AI model provider"
        },
        "models" => prune_model_fields(models)
      }
      
      File.write!(provider_file, Jason.encode!(provider_json, pretty: true))
    end
  end)
end
```

### 2.2 JSON File Structure

Each provider JSON file contains enhanced metadata:

```json
{
  "provider": {
    "id": "openai",
    "name": "OpenAI",
    "base_url": "https://api.openai.com/v1",
    "env": ["OPENAI_API_KEY"],
    "doc": "OpenAI model provider"
  },
  "models": [
    {
      "id": "gpt-4",
      "modalities": {"input": ["text"], "output": ["text"]},
      "capabilities": {"reasoning": true, "tool_call": true},
      "cost": {"input": 0.03, "output": 0.06},
      "limit": {"context": 8192, "output": 4096}
    }
  ]
}
```

### 2.3 Runtime Metadata Enhancement

The `Model.with_metadata/1` function enriches basic model specs with full metadata:

```elixir
@spec with_metadata(String.t()) :: {:ok, t()} | {:error, String.t()}
def with_metadata(model_spec) when is_binary(model_spec) do
  with {:ok, base_model} <- from(model_spec),
       {:ok, full_metadata} <- load_full_metadata(model_spec) do
    enhanced_model = %{
      base_model
      | limit: get_in(full_metadata, ["limit"]) |> map_string_keys_to_atoms(),
        modalities: get_in(full_metadata, ["modalities"]) |> map_string_keys_to_atoms(),
        capabilities: build_capabilities_from_metadata(full_metadata),
        cost: get_in(full_metadata, ["cost"]) |> map_string_keys_to_atoms()
    }
    
    {:ok, enhanced_model}
  end
end
```

### 2.4 Provider-specific Configuration

Local configuration is merged with models.dev data for missing provider-specific details:

```elixir
defp get_provider_config("openai") do
  %{
    "base_url" => "https://api.openai.com/v1",
    "env" => ["OPENAI_API_KEY"]
  }
end

defp get_provider_config("anthropic") do
  %{
    "base_url" => "https://api.anthropic.com/v1",
    "env" => ["ANTHROPIC_API_KEY"]
  }
end
```

**Current Provider Coverage:** The system supports 43+ providers with JSON metadata files in `priv/models_dev/`, including major providers like OpenAI, Anthropic, Google, Mistral, and many others.

---

## 3. Provider Implementation Pattern

### 3.1 Minimal Callback Requirements

Providers only need to implement two callbacks:
- `build_request/3` - Construct HTTP requests
- `parse_response/3` - Parse HTTP responses

**Example from OpenAI Provider:**
```elixir
defmodule ReqLLM.Provider.BuiltIns.OpenAI do
  use ReqLLM.Provider.DSL,
    id: :openai,
    base_url: "https://api.openai.com",
    auth: {:header, "authorization", :bearer},
    metadata: "openai.json",
    default_temperature: 1,
    default_max_tokens: 4096

  @impl true
  def build_request(input, provider_opts, request_opts) do
    # Provider-specific request construction
    spec = spec()
    # ... model selection, parameter handling
    url = URI.merge(spec.base_url, "/v1/chat/completions") |> URI.to_string()
    # ... construct Req.Request struct
  end

  @impl true  
  def parse_response(response, provider_opts, request_opts) do
    # Provider-specific response parsing
    # ... handle both streaming and non-streaming responses
    # ... extract text, tool calls, metadata
  end
end
```

### 3.2 Common Plugin Stack Integration

All HTTP requests automatically receive the common plugin stack via the generated `generate_text/3` implementation:

**Plugin Stack Components:**
- **Kagi Plugin** - Authentication injection based on provider spec
- **TokenUsage Plugin** - Token counting and cost calculation
- **Stream Plugin** - Server-Sent Events (SSE) handling
- **Splode Plugin** - Standardized error handling

**Integration Point:**
```elixir
# In generated generate_text/3
with {:ok, request} <- build_request(messages, [], build_opts),
     request_with_spec <- ReqLLM.Core.HTTP.with_provider_spec(request, spec()),
     {:ok, response} <- ReqLLM.Core.HTTP.send(request_with_spec, http_opts) do
  # Plugin stack is applied in ReqLLM.Core.HTTP.send/2
end
```

### 3.3 Error Handling and Response Metadata

Responses include rich metadata in `response.private[:req_llm]`:

```elixir
%Req.Response{
  body: "Generated text response",
  private: %{
    req_llm: %{
      usage: %{input_tokens: 50, output_tokens: 25, total_cost: 0.075},
      provider: :openai,
      model: "gpt-4"
    }
  }
}
```

---

## 4. Model Spec System

### 4.1 Three Flexible Formats

The model specification system supports three input formats, all parsed into `%ReqLLM.Model{}` structs:

#### 4.1.1 String Format (Simple)
```elixir
# Format: "provider:model_name"
"openai:gpt-4"
"anthropic:claude-3-sonnet"

# Parsed by ReqLLM.Model.from/1
model = ReqLLM.model("openai:gpt-4")
```

#### 4.1.2 Tuple Format (With Options)  
```elixir
# Format: {:provider, [options]}
{:openai, model: "gpt-4", temperature: 0.7, max_tokens: 1000}
{:anthropic, model: "claude-3-sonnet", temperature: 0.3}

# Runtime parameters override defaults
model = ReqLLM.Model.from({:openai, model: "gpt-4", temperature: 0.7})
```

#### 4.1.3 Model Struct Format (Full Control)
```elixir
# Direct struct creation with all fields
%ReqLLM.Model{
  provider: :openai,
  model: "gpt-4", 
  temperature: 0.7,
  max_tokens: 1000,
  metadata: %{...}  # Enhanced with models.dev data
}
```

### 4.2 Provider Allow-list Security

String parsing uses a curated provider allow-list to prevent atom-bombing attacks:

```elixir
@valid_providers [
  :openai,
  :anthropic, 
  :openrouter,
  :google,
  :mistral,
  # ... 40+ more providers
]
```

Only pre-defined provider atoms can be created from string input, ensuring system security while supporting the full range of models.dev providers.

### 4.3 Metadata Enhancement Flow

Models can be enhanced with rich metadata from the JSON files:

```elixir
# Basic model spec
model = ReqLLM.model("openai:gpt-4")

# Enhanced with capabilities, costs, limits  
enhanced = ReqLLM.Model.with_metadata(model)

# enhanced.metadata contains:
# - capabilities: [:generate_text, :tool_calling, :reasoning]
# - pricing: %{input: 0.03, output: 0.06}  # per 1K tokens
# - context_length: 8192
# - modalities: [:text]
```

---

## 5. Registry Pattern

### 5.1 Auto-registration via @after_compile Hook

The registry uses compile-time auto-registration to eliminate manual provider list maintenance:

```elixir
# In ReqLLM.Provider.Registry
def auto_register(env, _bytecode) do
  try do
    spec = env.module.spec()
    register(env.module, spec.id)
  rescue
    _ -> :ok  # Handle compilation failures gracefully
  end
end
```

This hook is triggered for every module that uses the Provider DSL, ensuring automatic registration without explicit calls.

### 5.2 :persistent_term Storage for O(1) Lookups

Provider modules are stored in `:persistent_term` for maximum performance:

```elixir
@registry_key :req_llm_providers

@spec register(module(), atom()) :: :ok
def register(module, provider_id) when is_atom(provider_id) do
  current_providers = get_all_providers()
  updated_providers = Map.put(current_providers, provider_id, module)
  :persistent_term.put(@registry_key, updated_providers)
  :ok
end

defp get_all_providers do
  :persistent_term.get(@registry_key, %{})
rescue
  ArgumentError -> %{}
end
```

This provides O(1) lookup performance across the entire BEAM VM with no process overhead.

### 5.3 Provider Module Detection

The registry automatically detects provider modules by naming conventions:

```elixir
defp is_provider_module?(module) do
  module_name = Atom.to_string(module)

  String.contains?(module_name, "Providers.") or
    String.contains?(module_name, "Provider.BuiltIns.") or  
    String.ends_with?(module_name, "Provider")
end
```

### 5.4 Runtime Provider Access

The registry provides both safe and unsafe access patterns:

```elixir
# Safe access with error tuples
case ReqLLM.Provider.Registry.fetch(:openai) do
  {:ok, module} -> # Use module
  {:error, :not_found} -> # Handle missing provider
end

# Unsafe access with exceptions
module = ReqLLM.Provider.Registry.fetch!(:openai)  # Raises on not found

# List all registered providers
providers = ReqLLM.Provider.Registry.list_providers()
# => [:openai, :anthropic, :google, ...]
```

---

## 6. Testing Implications

### 6.1 Provider Contract Testing

The minimal callback pattern enables focused testing of provider-specific logic:

**What to Test per Provider:**
- `build_request/3` - Verify correct HTTP request construction
- `parse_response/3` - Verify response parsing for all response types
- Model-specific behavior (e.g., reasoning models vs. standard chat)
- Tool calling support and parsing
- Error handling for provider-specific error formats

### 6.2 Capability Verification System

The capability system enables automated testing of provider contracts:

```elixir
# Test all capabilities for a provider
mix req_llm.verify openai:gpt-4 --format debug

# Test specific capabilities only
mix req_llm.verify anthropic --only generate_text,stream_text
```

**Custom Capability Implementation:**
```elixir
defmodule MyApp.Capabilities.CustomFeature do
  @behaviour ReqLLM.Capability

  def id, do: :custom_feature
  def advertised?(model), do: model.capabilities[:custom_feature] == true
  def verify(model, _opts) do
    # Test implementation
  end
end
```

### 6.3 Models.dev Integration Testing

**Key Test Areas:**
- Verify `mix req_llm.model_sync` successfully fetches and stores metadata
- Test that provider JSON files are properly parsed by the DSL
- Validate that `Model.with_metadata/1` correctly enhances models
- Ensure metadata changes don't break existing provider implementations

### 6.4 Registry Testing

**Critical Test Scenarios:**
- Auto-registration occurs for all Provider DSL users
- Provider lookup performance remains O(1)
- Registry survives application restarts
- Duplicate provider IDs are handled gracefully
- Module recompilation updates registry correctly

---

## Summary

The ReqLLM provider system demonstrates sophisticated macro-based code generation that achieves:

1. **Minimal Implementation Burden** - Only 2 callbacks required per provider
2. **Automatic Infrastructure** - Registry, HTTP orchestration, plugin stack all generated
3. **Authoritative Metadata** - models.dev as single source of truth for 43+ providers  
4. **Performance Optimization** - O(1) provider lookup via :persistent_term
5. **Security** - Provider allow-list prevents atom-bombing attacks
6. **Testing Support** - Capability verification and contract testing built-in

This architecture successfully balances developer productivity with system performance and security, making it straightforward to add new AI providers while maintaining consistent behavior across the entire ecosystem.
