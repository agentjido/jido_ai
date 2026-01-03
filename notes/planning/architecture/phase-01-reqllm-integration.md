# Phase 1: Foundation Enhancement

This phase enhances the existing ReqLLM integration foundation. ReqLLM is a direct dependency and should be used directly throughout Jido.AI - no wrapper layers.

## Design Principle

**Use ReqLLM directly, not through adapters.** The existing codebase already follows this pattern:
- `Jido.AI.Directive.ReqLLMStream` calls `ReqLLM.stream_text()` directly
- `Jido.AI.ToolAdapter` converts Jido.Actions to `ReqLLM.Tool` structs
- Strategies and skills should call ReqLLM functions directly

This phase enhances the existing integration points, adds configuration, and improves error handling.

## Existing Modules (Reference)

```
lib/jido_ai/
├── directive.ex      # ReqLLMStream, ToolExec directives (uses ReqLLM directly)
├── signal.ex         # ReqLLMResult, ReqLLMPartial, ToolResult signals
├── tool_adapter.ex   # Jido.Action → ReqLLM.Tool conversion
└── error.ex          # Splode-based error handling
```

## New/Enhanced Modules

```
lib/jido_ai/
├── config.ex         # NEW: Configuration helpers for ReqLLM providers
├── directive.ex      # ENHANCE: Add new directives
├── signal.ex         # ENHANCE: Add new signals
├── tool_adapter.ex   # ENHANCE: Improve conversion
└── helpers.ex        # NEW: Common patterns and utilities
```

---

## 1.1 Configuration Module

Create a configuration module for managing ReqLLM provider settings.

### 1.1.1 Module Setup

Create the configuration module.

- [x] 1.1.1.1 Create `lib/jido_ai/config.ex` with module documentation
- [x] 1.1.1.2 Document that this configures ReqLLM (not wrapping it)
- [x] 1.1.1.3 Define configuration schema types

### 1.1.2 Provider Configuration

Implement provider configuration helpers.

- [x] 1.1.2.1 Implement `get_provider/1` to retrieve provider config
- [x] 1.1.2.2 Support OpenAI, Anthropic, Google, Ollama providers
- [x] 1.1.2.3 Validate provider configuration at startup
- [x] 1.1.2.4 Support environment variable overrides

### 1.1.3 Model Aliases

Implement named model aliases.

- [x] 1.1.3.1 Implement `resolve_model/1` for alias resolution
- [x] 1.1.3.2 Support aliases like `:fast`, `:capable`, `:reasoning`
- [x] 1.1.3.3 Map aliases to ReqLLM model specs (e.g., "anthropic:claude-haiku-4-5")
- [x] 1.1.3.4 Allow runtime configuration of aliases

### 1.1.4 Default Settings

Implement default settings management.

- [x] 1.1.4.1 Implement `defaults/0` for global defaults
- [x] 1.1.4.2 Support default temperature, max_tokens, etc.
- [x] 1.1.4.3 Allow per-agent default overrides

### 1.1.5 Unit Tests for Configuration

- [x] Test get_provider/1 returns config
- [x] Test resolve_model/1 resolves aliases
- [x] Test resolve_model/1 passes through direct specs
- [x] Test defaults/0 returns merged config
- [x] Test environment variable overrides
- [x] Test validation catches invalid config

---

## 1.2 Directive Enhancement

Enhance the existing directive module with additional capabilities.

### 1.2.1 ReqLLMStream Enhancement

Enhance the existing ReqLLMStream directive.

- [x] 1.2.1.1 Add `system_prompt` field for convenience
- [x] 1.2.1.2 Add `model_alias` field that resolves via Config
- [x] 1.2.1.3 Add `timeout` field for request timeout
- [x] 1.2.1.4 Improve error classification in DirectiveExec

### 1.2.2 ReqLLMGenerate Directive (Non-Streaming)

Add a non-streaming generate directive.

- [x] 1.2.2.1 Create `Jido.AI.Directive.ReqLLMGenerate` module
- [x] 1.2.2.2 Define schema: id, model, context, tools, max_tokens, temperature
- [x] 1.2.2.3 Implement DirectiveExec that calls `ReqLLM.Generation.generate_text/3` directly
- [x] 1.2.2.4 Send ReqLLMResult signal on completion

### 1.2.3 ReqLLMEmbed Directive

Add an embedding generation directive.

- [x] 1.2.3.1 Create `Jido.AI.Directive.ReqLLMEmbed` module
- [x] 1.2.3.2 Define schema: id, model, texts, metadata
- [x] 1.2.3.3 Implement DirectiveExec that calls ReqLLM embedding directly
- [x] 1.2.3.4 Create corresponding EmbedResult signal

### 1.2.4 Unit Tests for Directives

- [x] Test ReqLLMStream with system_prompt field
- [x] Test ReqLLMStream with model_alias resolution
- [x] Test ReqLLMGenerate non-streaming call
- [x] Test ReqLLMEmbed batch embedding
- [x] Test timeout handling
- [x] Test error classification

---

## 1.3 Signal Enhancement

Enhance the existing signal module with additional signal types.

### 1.3.1 New Signal Types

Add new signals for enhanced functionality.

- [ ] 1.3.1.1 Create `Jido.AI.Signal.EmbedResult` for embedding responses
- [ ] 1.3.1.2 Create `Jido.AI.Signal.ReqLLMError` for structured errors
- [ ] 1.3.1.3 Create `Jido.AI.Signal.UsageReport` for token/cost tracking

### 1.3.2 Enhanced Metadata

Improve metadata in existing signals.

- [ ] 1.3.2.1 Add `usage` field to ReqLLMResult (input/output tokens)
- [ ] 1.3.2.2 Add `model` field to ReqLLMResult (actual model used)
- [ ] 1.3.2.3 Add `duration_ms` field to ReqLLMResult
- [ ] 1.3.2.4 Add `thinking_content` field to ReqLLMResult (for extended thinking)

### 1.3.3 Signal Helpers

Add helper functions for signal creation.

- [ ] 1.3.3.1 Implement `from_reqllm_response/2` to create signals from ReqLLM responses
- [ ] 1.3.3.2 Implement `extract_tool_calls/1` helper
- [ ] 1.3.3.3 Implement `is_tool_call?/1` predicate

### 1.3.4 Unit Tests for Signals

- [ ] Test EmbedResult signal creation
- [ ] Test ReqLLMError signal creation
- [ ] Test UsageReport signal creation
- [ ] Test enhanced metadata in ReqLLMResult
- [ ] Test from_reqllm_response/2 conversion
- [ ] Test signal helper functions

---

## 1.4 Tool Adapter Enhancement

Enhance the existing tool adapter with additional capabilities.

### 1.4.1 Batch Conversion

Improve batch action conversion.

- [ ] 1.4.1.1 Add `from_actions/2` with options parameter
- [ ] 1.4.1.2 Support filtering actions by category/tag
- [ ] 1.4.1.3 Support action name prefixing

### 1.4.2 Schema Improvements

Improve JSON schema generation.

- [ ] 1.4.2.1 Handle nested Zoi schemas correctly
- [ ] 1.4.2.2 Add support for enum constraints
- [ ] 1.4.2.3 Add support for string format constraints
- [ ] 1.4.2.4 Generate better descriptions from schema metadata

### 1.4.3 Action Registry

Add optional action registry for tool management.

- [ ] 1.4.3.1 Implement `register_action/1` for runtime registration
- [ ] 1.4.3.2 Implement `list_actions/0` to get registered actions
- [ ] 1.4.3.3 Implement `get_action/1` to lookup by name
- [ ] 1.4.3.4 Implement `to_tools/0` to convert all registered actions

### 1.4.4 Unit Tests for Tool Adapter

- [ ] Test from_actions/2 with options
- [ ] Test nested schema conversion
- [ ] Test enum constraint handling
- [ ] Test action registry operations
- [ ] Test to_tools/0 conversion

---

## 1.5 Helper Utilities

Create helper utilities for common ReqLLM patterns.

### 1.5.1 Message Building

Implement message building helpers.

- [ ] 1.5.1.1 Create `lib/jido_ai/helpers.ex` with module documentation
- [ ] 1.5.1.2 Implement `build_messages/2` for context building
- [ ] 1.5.1.3 Implement `add_system_message/2` helper
- [ ] 1.5.1.4 Implement `add_tool_result/3` for tool result messages

### 1.5.2 Response Processing

Implement response processing helpers.

- [ ] 1.5.2.1 Implement `extract_text/1` from ReqLLM response
- [ ] 1.5.2.2 Implement `extract_tool_calls/1` from response
- [ ] 1.5.2.3 Implement `has_tool_calls?/1` predicate
- [ ] 1.5.2.4 Implement `classify_response/1` (tool_calls vs final_answer)

### 1.5.3 Error Handling

Implement error handling helpers.

- [ ] 1.5.3.1 Implement `wrap_error/1` to convert ReqLLM errors to Jido.AI.Error
- [ ] 1.5.3.2 Classify errors: rate_limit, auth, timeout, provider_error
- [ ] 1.5.3.3 Extract retry-after from rate limit errors

### 1.5.4 Unit Tests for Helpers

- [ ] Test build_messages/2 creates valid context
- [ ] Test add_system_message/2 prepends system
- [ ] Test add_tool_result/3 formats correctly
- [ ] Test extract_text/1 handles various response formats
- [ ] Test classify_response/1 detection
- [ ] Test wrap_error/1 error classification

---

## 1.6 Phase 1 Integration Tests

Comprehensive integration tests verifying all Phase 1 enhancements work together.

### 1.6.1 Directive Integration

Verify enhanced directives work with ReqLLM.

- [ ] 1.6.1.1 Create `test/jido_ai/integration/foundation_phase1_test.exs`
- [ ] 1.6.1.2 Test: ReqLLMStream with model alias resolution
- [ ] 1.6.1.3 Test: ReqLLMGenerate non-streaming flow
- [ ] 1.6.1.4 Test: ReqLLMEmbed embedding generation

### 1.6.2 Signal Flow Integration

Test signal creation and metadata.

- [ ] 1.6.2.1 Test: Full directive → signal flow with usage metadata
- [ ] 1.6.2.2 Test: Error signal creation on failure
- [ ] 1.6.2.3 Test: Tool result signal with action execution

### 1.6.3 Configuration Integration

Test configuration across components.

- [ ] 1.6.3.1 Test: Model alias resolution in directives
- [ ] 1.6.3.2 Test: Default settings applied correctly
- [ ] 1.6.3.3 Test: Provider config validation

---

## Phase 1 Success Criteria

1. **No Wrappers**: All code uses ReqLLM directly (no adapter/client layers)
2. **Configuration**: Model aliases and provider config working
3. **Enhanced Directives**: New directives for generate/embed
4. **Enhanced Signals**: Usage metadata and new signal types
5. **Tool Adapter**: Registry and improved schema conversion
6. **Helpers**: Common patterns extracted as utilities
7. **Test Coverage**: Minimum 80% for Phase 1 modules

---

## Phase 1 Critical Files

**New Files:**
- `lib/jido_ai/config.ex`
- `lib/jido_ai/helpers.ex`
- `test/jido_ai/config_test.exs`
- `test/jido_ai/helpers_test.exs`
- `test/jido_ai/integration/foundation_phase1_test.exs`

**Modified Files:**
- `lib/jido_ai/directive.ex` - Add ReqLLMGenerate, ReqLLMEmbed
- `lib/jido_ai/signal.ex` - Add EmbedResult, ReqLLMError, UsageReport
- `lib/jido_ai/tool_adapter.ex` - Add registry, improve schema
