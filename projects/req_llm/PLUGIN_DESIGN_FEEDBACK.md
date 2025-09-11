# ReqLLM Plugin Design Feedback & Analysis

## Executive Summary

ReqLLM is currently implementing a **parallel plugin system** rather than leveraging Req's native plugin architecture. While functional, this approach sacrifices composability, option validation, documentation generation, and the full power of Req's step pipeline system.

## Current State Analysis

### What We're Missing

**Core Plugin Features:**
- ❌ `register_options/2` - No option validation or defaulting
- ❌ `merge_options/2` - Used minimally (only Anthropic base_url)  
- ❌ `append_request_steps/3` & `prepend_response_steps/3` - Not used
- ❌ Proper Req plugin composition via `Req.attach/3`

**Advanced Features We Could Leverage:**
- ❌ `put_private/3` & `update_private/3` - Internal state management
- ❌ `halt_request/2` & `halt_response/2` - Early termination on validation errors
- ❌ `put_bearer_auth/2` - Clean authentication handling
- ❌ Plugin stacking and composition with other Req plugins
- ❌ Automatic documentation via `Req.Docs`

### Current Architecture Issues

**1. Plugin Isolation**
- Each provider reinvents streaming, parsing, and auth logic
- No shared steps between providers
- Cannot compose with Req ecosystem (JSON, Retry, RateLimiter, Telemetry)

**2. Option Management**
- Manual option handling without validation
- No documentation for provider-specific options
- Options scattered across provider implementations

**3. Documentation Architecture**
- `@rawdocs` exists outside Req's plugin documentation system
- No automatic option documentation via `register_options/2`
- Documentation can drift from implementation

## The @rawdocs Architecture Assessment

### Current Approach
The `@rawdocs` pattern stores provider metadata and documentation in module attributes, which is processed by `Provider.DSL` for registration.

### Issues with Current Design
1. **Documentation Isolation**: `@rawdocs` lives outside Req's plugin system
2. **No Option Docs**: Options aren't documented through `register_options/2`
3. **Manual Maintenance**: Documentation can drift from actual implementation
4. **Limited Discoverability**: Cannot use `Req.Docs.print/1` for option help

### Better Integration Strategy
```elixir
# Instead of @rawdocs, leverage register_options/2:
defmodule ReqLLM.Providers.Anthropic do
  use Req.Plugin
  use ReqLLM.Provider.DSL, id: :anthropic, base_url: "...", metadata: ...

  @impl Req.Plugin  
  def attach(request, opts) do
    request
    |> register_options([
      model: [
        required: true,
        type: :string,
        doc: "The Anthropic model to use (e.g., claude-3-5-sonnet-20241022)"
      ],
      temperature: [
        default: 0.7,
        type: :float,
        doc: "Controls randomness. Higher values make output more random"
      ],
      stream?: [
        default: false, 
        type: :boolean,
        doc: "Whether to stream the response"
      ]
    ])
    |> merge_options(opts)
    |> append_request_steps([
      {__MODULE__, :build_auth_step, []},
      {__MODULE__, :build_body_step, []}
    ])
    |> append_response_steps([
      {__MODULE__, :parse_response_step, []},
      {__MODULE__, :extract_usage_step, []}
    ])
  end
end
```

## Recommendations for Improvement

### Phase 1: Foundation Migration
1. **Convert to Real Req Plugins**
   - Implement `use Req.Plugin` in each provider
   - Move from custom `attach/3` to standard `attach/2`
   - Enable composition via `Req.attach/3`

2. **Implement Option Registration**
   - Replace manual option handling with `register_options/2`
   - Add validation and defaults for all provider options
   - Enable `mix req.docs` documentation generation

### Phase 2: Step Pipeline Adoption
1. **Modularize Request Steps**
   - Auth step: `put_bearer_auth/2` for API keys
   - Body building: JSON encoding with provider-specific formatting
   - Base URL handling: Use built-in `Req.Steps.put_base_url/1`

2. **Modularize Response Steps**
   - Streaming parser step (shared across providers)
   - Usage extraction step (shared logic)
   - Error mapping step (HTTP status → ReqLLM.Error)

### Phase 3: Advanced Integration
1. **Cross-Provider Step Sharing**
   ```elixir
   # Shared steps that work across providers
   ReqLLM.Steps.StreamParser
   ReqLLM.Steps.UsageExtractor  
   ReqLLM.Steps.ErrorMapper
   ReqLLM.Steps.RateLimitHandler
   ```

2. **Ecosystem Composition**
   ```elixir
   # Enable users to compose with other Req plugins
   Req.new()
   |> Req.attach(Req.JSON)                     # JSON encoding/decoding
   |> Req.attach(ReqLLM.Providers.Anthropic)   # AI provider
   |> Req.attach(Req.Retry)                    # Automatic retries
   |> Req.post(url: "/chat", json: messages)
   ```

## Benefits of Migration

### For Users
- **Type Safety**: Early option validation prevents runtime errors
- **Composability**: Mix ReqLLM with other Req plugins seamlessly  
- **Documentation**: Auto-generated option docs via `mix req.docs`
- **Consistency**: Same patterns as other Req ecosystem tools

### For Maintainers  
- **Code Reuse**: Shared steps reduce duplication across providers
- **Testing**: Test individual steps in isolation
- **Debugging**: Clear separation of concerns in the pipeline
- **Future-Proofing**: Easy to add circuit breakers, metrics, etc.

## Migration Path

### Backward Compatibility
Keep existing `ReqLLM.attach/2` as a thin wrapper around `Req.Request.attach/3` to maintain API compatibility during transition.

### Incremental Rollout
1. Start with one provider (Anthropic) as a proof-of-concept
2. Extract common patterns into shared steps
3. Migrate remaining providers one by one
4. Deprecate custom plugin system in favor of native Req plugins

## Conclusion

The current design works but leaves significant value on the table. By embracing Req's native plugin architecture, ReqLLM can become a first-class member of the Req ecosystem while providing better type safety, documentation, and composability for users.

The key insight: **ReqLLM should be a collection of Req plugins, not a parallel plugin system.**
