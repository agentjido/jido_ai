# Feature: Phase 1 Section 1.1 - Configuration Module

## Problem Statement

Jido.AI needs a configuration module to manage ReqLLM provider settings, model aliases, and default parameters. Currently, model specifications are hardcoded directly in code (e.g., `"anthropic:claude-haiku-4-5"`). This creates several issues:

- No centralized way to configure providers
- No model aliases for semantic naming (`:fast`, `:capable`, `:reasoning`)
- No default settings management
- No environment variable overrides

**Impact**: Developers must hardcode model specs everywhere, making it difficult to switch providers or adjust settings without code changes.

## Solution Overview

Create `lib/jido_ai/config.ex` - a configuration module that:

1. Provides provider configuration helpers
2. Implements model alias resolution
3. Manages default settings (temperature, max_tokens, etc.)
4. Supports environment variable overrides

**Key Design Decision**: This module provides *configuration helpers* for ReqLLM, not a wrapper. All actual LLM calls still go directly to ReqLLM.

## Technical Details

### File Location
- `lib/jido_ai/config.ex` - Main configuration module
- `test/jido_ai/config_test.exs` - Unit tests

### Dependencies
- Uses Elixir Application configuration
- No new dependencies required

### Configuration Schema

```elixir
# In config/config.exs or runtime.exs:
config :jido_ai,
  providers: %{
    openai: [api_key: {:system, "OPENAI_API_KEY"}],
    anthropic: [api_key: {:system, "ANTHROPIC_API_KEY"}],
    google: [api_key: {:system, "GOOGLE_API_KEY"}],
    ollama: [base_url: "http://localhost:11434"]
  },
  model_aliases: %{
    fast: "anthropic:claude-haiku-4-5",
    capable: "anthropic:claude-sonnet-4-20250514",
    reasoning: "anthropic:claude-sonnet-4-20250514"
  },
  defaults: %{
    temperature: 0.7,
    max_tokens: 1024
  }
```

## Success Criteria

1. `get_provider/1` returns provider configuration
2. `resolve_model/1` resolves aliases to ReqLLM model specs
3. `resolve_model/1` passes through direct specs unchanged
4. `defaults/0` returns merged default configuration
5. Environment variable overrides work correctly
6. Invalid configuration raises at compile/startup time

## Implementation Plan

### Step 1: Module Setup (1.1.1)
- [x] 1.1.1.1 Create `lib/jido_ai/config.ex` with module documentation
- [x] 1.1.1.2 Document that this configures ReqLLM (not wrapping it)
- [x] 1.1.1.3 Define configuration schema types

### Step 2: Provider Configuration (1.1.2)
- [x] 1.1.2.1 Implement `get_provider/1` to retrieve provider config
- [x] 1.1.2.2 Support OpenAI, Anthropic, Google, Ollama providers
- [x] 1.1.2.3 Validate provider configuration at startup
- [x] 1.1.2.4 Support environment variable overrides

### Step 3: Model Aliases (1.1.3)
- [x] 1.1.3.1 Implement `resolve_model/1` for alias resolution
- [x] 1.1.3.2 Support aliases like `:fast`, `:capable`, `:reasoning`
- [x] 1.1.3.3 Map aliases to ReqLLM model specs
- [x] 1.1.3.4 Allow runtime configuration of aliases

### Step 4: Default Settings (1.1.4)
- [x] 1.1.4.1 Implement `defaults/0` for global defaults
- [x] 1.1.4.2 Support default temperature, max_tokens, etc.
- [x] 1.1.4.3 Allow per-agent default overrides

### Step 5: Unit Tests (1.1.5)
- [x] Test get_provider/1 returns config
- [x] Test resolve_model/1 resolves aliases
- [x] Test resolve_model/1 passes through direct specs
- [x] Test defaults/0 returns merged config
- [x] Test environment variable overrides
- [x] Test validation catches invalid config

## Current Status

**Status**: ✅ Complete
**What works**: All functionality implemented and tested (29 tests passing)
**What's next**: Commit and merge to v2 branch
**How to run**: `mix test test/jido_ai/config_test.exs`

## Notes/Considerations

- Model alias atoms should be simple: `:fast`, `:capable`, `:reasoning`
- Direct model specs (strings like `"anthropic:claude-haiku-4-5"`) should pass through unchanged
- Environment variables use `{:system, "VAR_NAME"}` tuple pattern
- Validation should happen at application startup, not runtime
