# Summary: Phase 1 Section 1.2 - Directive Enhancement

**Date**: 2026-01-03
**Branch**: `feature/phase1-config-module`
**Status**: Complete

## What Was Implemented

Enhanced the directive module (`lib/jido_ai/directive.ex`) with three major improvements and added a new signal type.

### New/Enhanced Directives

| Directive | Purpose |
|-----------|---------|
| `ReqLLMStream` | Enhanced with `system_prompt`, `model_alias`, `timeout` fields |
| `ReqLLMGenerate` | Non-streaming LLM generation using `ReqLLM.Generation.generate_text/3` |
| `ReqLLMEmbed` | Embedding generation using `ReqLLM.Embedding.embed/3` |

### New Signal

| Signal | Purpose |
|--------|---------|
| `EmbedResult` | Result signal for embedding generation (`ai.embed_result` type) |

### Key Features

1. **Model Alias Resolution**: Both `ReqLLMStream` and `ReqLLMGenerate` support `model_alias` field that resolves via `Jido.AI.Config.resolve_model/1`

2. **System Prompt Handling**: Both LLM directives support `system_prompt` field which is prepended to context messages as a system role message

3. **Timeout Support**: All directives support `timeout` field passed to HTTP options as `receive_timeout`

4. **Error Classification**: DirectiveExec implementations classify errors into categories: `:rate_limit`, `:auth`, `:timeout`, `:provider_error`

5. **Batch Embedding**: `ReqLLMEmbed` supports both single text and batch (list of texts) embedding

## Test Coverage

- **19 tests** in `test/jido_ai/directive_test.exs`
- Tests for ReqLLMStream with all new fields
- Tests for ReqLLMGenerate schema and creation
- Tests for ReqLLMEmbed with single and batch texts
- Tests for EmbedResult signal creation

## Files Changed

| File | Action |
|------|--------|
| `lib/jido_ai/directive.ex` | Enhanced (added ReqLLMGenerate, ReqLLMEmbed, 3 DirectiveExec impls) |
| `lib/jido_ai/signal.ex` | Enhanced (added EmbedResult signal) |
| `test/jido_ai/directive_test.exs` | Created |
| `notes/features/phase1-section1.2-directive-enhancement.md` | Created |
| `notes/planning/architecture/phase-01-reqllm-integration.md` | Updated (marked 1.2 complete) |

## ReqLLM APIs Used

- `ReqLLM.stream_text/3` - Streaming text generation (existing)
- `ReqLLM.Generation.generate_text/3` - Non-streaming text generation
- `ReqLLM.Embedding.embed/3` - Embedding generation

## Design Decisions

1. **DirectiveExec Per Directive**: Each directive has its own DirectiveExec protocol implementation for async execution
2. **Signal Reuse**: ReqLLMGenerate reuses ReqLLMResult signal (same response format as streaming)
3. **Separate EmbedResult**: Embedding has its own signal type due to different response structure
4. **Helper Functions**: Common helper functions (resolve_model, build_messages, classify_error) are duplicated per DirectiveExec to avoid module coupling

## How to Run

```bash
# Run tests
mix test test/jido_ai/directive_test.exs

# Example usage
alias Jido.AI.Directive

# Streaming with model alias
directive = Directive.ReqLLMStream.new!(%{
  id: "call_1",
  model_alias: :fast,
  system_prompt: "Be concise.",
  context: [%{role: :user, content: "Hello"}]
})

# Non-streaming generation
directive = Directive.ReqLLMGenerate.new!(%{
  id: "gen_1",
  model: "anthropic:claude-haiku-4-5",
  context: [%{role: :user, content: "Hello"}]
})

# Embedding
directive = Directive.ReqLLMEmbed.new!(%{
  id: "embed_1",
  model: "openai:text-embedding-3-small",
  texts: ["Hello", "World"]
})
```

## Next Steps

- Continue with Phase 1 Section 1.3 (Signal Enhancement)
- Or Phase 1 Section 1.4 (Tool Adapter Enhancement)
