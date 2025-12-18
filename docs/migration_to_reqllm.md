# Migration to Direct ReqLLM Integration

## Overview

This document describes the migration from the `req_llm_bridge` compatibility layer to direct ReqLLM integration in the Jido AI codebase.

## Changes Summary

### 1. Removed Components (~1,300 lines)

#### Deleted Files:
- `lib/jido_ai/req_llm_bridge.ex` (762 lines)
- `lib/jido_ai/model/registry/metadata_bridge.ex` (520 lines)
- `lib/jido_ai/req_llm_bridge/` directory (16 modules)
- `test/jido_ai/req_llm_bridge/` directory (all test files)

### 2. Model Format Changes

#### Before (Jido.AI.Model):
```elixir
%Jido.AI.Model{
  id: "claude-3-5-sonnet-20241022",
  name: "Claude 3.5 Sonnet",
  provider: :anthropic,
  api_key: "...",
  reqllm_id: "anthropic:claude-3-5-sonnet-20241022"  # Computed field
}
```

#### After (ReqLLM.Model):
```elixir
%ReqLLM.Model{
  provider: :anthropic,
  model: "claude-3-5-sonnet-20241022",
  max_tokens: 8192,
  max_retries: 3,
  capabilities: %{tool_call: true, reasoning: false, ...},
  modalities: %{input: [:text], output: [:text]},
  cost: %{input: 3.0, output: 15.0}
}
```

### 3. API Changes

#### Model Creation:
```elixir
# Before
{:ok, model} = Jido.AI.Model.from("anthropic:claude-3-5-sonnet")
# Returns Jido.AI.Model struct

# After
{:ok, model} = Jido.AI.Model.from("anthropic:claude-3-5-sonnet")
# Returns ReqLLM.Model struct
```

#### Provider Build Functions:
```elixir
# Before
def build(opts) do
  # ... validation ...
  {:ok, %Jido.AI.Model{...}}
end

# After
def build(opts) do
  # ... validation ...
  ReqLLM.Model.from({:provider, model_name, opts})
end
```

### 4. Updated Components

#### Actions:
- `lib/jido_ai/actions/req_llm/chat_completion.ex` - Direct ReqLLM calls
- `lib/jido_ai/actions/text_completion.ex` - Uses ReqLLM.Model
- `lib/jido_ai/actions/openaiex.ex` - Updated for ReqLLM.Model
- `lib/jido_ai/actions/openai_ex/embeddings.ex` - Updated for ReqLLM.Model

#### Providers:
- All provider modules (`openai.ex`, `anthropic.ex`, `cloudflare.ex`, `google.ex`, `openrouter.ex`)
- Now return `ReqLLM.Model` structs from `build/1`

#### Tree of Thoughts:
- `thought_generator.ex` - Uses ReqLLM.Model.from directly
- `thought_evaluator.ex` - Uses ReqLLM.Model.from directly

### 5. Direct ReqLLM Usage

All LLM calls now go directly through ReqLLM API:
```elixir
# Text generation
ReqLLM.generate_text(model, messages)

# Streaming
ReqLLM.stream_text(model, messages)

# Embeddings
ReqLLM.embed(model, input)
```

### 6. Authentication

Authentication now uses JidoKeys/ReqLLM integration directly:
```elixir
# API keys are handled through ReqLLM's authentication system
ReqLLM.Model.from({:provider, model, [api_key: key]})
```

## Breaking Changes

### For Library Users:

1. **Model Struct Change**: Code expecting `Jido.AI.Model` structs will need updates
   - The `id` field is now accessed via `model.model`
   - The `name` field is not directly available (may be in metadata)
   - The `provider` field remains the same

2. **Registry Returns**: `Registry.list_models/1` now returns `ReqLLM.Model` structs

3. **Test Updates Required**: Tests asserting on `Jido.AI.Model` need updating

### Migration Steps for Users:

1. Update code that pattern matches on `%Jido.AI.Model{}`
2. Access model ID via `model.model` instead of `model.id`
3. Use `ReqLLM.Model` type specs instead of `Jido.AI.Model.t()`
4. Update tests to expect `ReqLLM.Model` structs

## Benefits

1. **Reduced Complexity**: Removed ~1,300 lines of bridge code
2. **Direct Integration**: No translation layer between formats
3. **Better Performance**: Fewer conversions and transformations
4. **Unified Model Format**: Consistent with ReqLLM ecosystem
5. **Richer Metadata**: Access to capabilities, modalities, cost information

## Known Issues

Currently, tests are failing because they expect `Jido.AI.Model` structs but receive `ReqLLM.Model` structs. These tests need to be updated to work with the new model format.

## Next Steps

1. Update all tests to work with `ReqLLM.Model` structs
2. Update any documentation referencing `Jido.AI.Model`
3. Consider adding a thin compatibility layer for gradual migration (if needed)