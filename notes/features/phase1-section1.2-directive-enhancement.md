# Feature: Phase 1 Section 1.2 - Directive Enhancement

## Problem Statement

The current directive module has only two directives:
- `ReqLLMStream` - For streaming LLM responses
- `ToolExec` - For executing Jido.Actions as tools

Missing functionality:
1. `ReqLLMStream` lacks convenience fields (system_prompt, model_alias, timeout)
2. No non-streaming LLM directive for simpler use cases
3. No embedding generation directive

**Impact**: Developers must use streaming for all LLM calls (overkill for simple requests) and cannot generate embeddings through the directive system.

## Solution Overview

1. **Enhance ReqLLMStream** - Add `system_prompt`, `model_alias`, and `timeout` fields
2. **Create ReqLLMGenerate** - Non-streaming directive using `ReqLLM.Generation.generate_text/3`
3. **Create ReqLLMEmbed** - Embedding directive using `ReqLLM.Embedding.embed/3`
4. **Create EmbedResult signal** - Signal for embedding completion (needed by ReqLLMEmbed)

## Technical Details

### ReqLLM API Used
- `ReqLLM.Generation.generate_text/3` - Non-streaming text generation
- `ReqLLM.Embedding.embed/3` - Embedding generation (single or batch)

### Files to Modify/Create
- `lib/jido_ai/directive.ex` - Enhance ReqLLMStream, add ReqLLMGenerate, ReqLLMEmbed
- `lib/jido_ai/signal.ex` - Add EmbedResult signal
- `test/jido_ai/directive_test.exs` - Unit tests

## Success Criteria

1. ReqLLMStream accepts `system_prompt`, `model_alias`, `timeout` fields
2. `model_alias` resolves via `Jido.AI.Config.resolve_model/1`
3. ReqLLMGenerate calls `ReqLLM.Generation.generate_text/3` and sends ReqLLMResult
4. ReqLLMEmbed calls `ReqLLM.Embedding.embed/3` and sends EmbedResult
5. All directives have working DirectiveExec implementations
6. Unit tests pass for all new functionality

## Implementation Plan

### Step 1: Enhance ReqLLMStream (1.2.1)
- [x] 1.2.1.1 Add `system_prompt` field for convenience
- [x] 1.2.1.2 Add `model_alias` field that resolves via Config
- [x] 1.2.1.3 Add `timeout` field for request timeout
- [x] 1.2.1.4 Improve error classification in DirectiveExec

### Step 2: Create ReqLLMGenerate (1.2.2)
- [x] 1.2.2.1 Create `Jido.AI.Directive.ReqLLMGenerate` module
- [x] 1.2.2.2 Define schema: id, model, context, tools, max_tokens, temperature
- [x] 1.2.2.3 Implement DirectiveExec that calls `ReqLLM.Generation.generate_text/3`
- [x] 1.2.2.4 Send ReqLLMResult signal on completion

### Step 3: Create ReqLLMEmbed and EmbedResult (1.2.3)
- [x] 1.2.3.1 Create `Jido.AI.Directive.ReqLLMEmbed` module
- [x] 1.2.3.2 Define schema: id, model, texts, metadata
- [x] 1.2.3.3 Implement DirectiveExec that calls `ReqLLM.Embedding.embed/3`
- [x] 1.2.3.4 Create corresponding EmbedResult signal

### Step 4: Unit Tests (1.2.4)
- [x] Test ReqLLMStream with system_prompt field
- [x] Test ReqLLMStream with model_alias resolution
- [x] Test ReqLLMGenerate schema and new!
- [x] Test ReqLLMEmbed schema and new!
- [x] Test EmbedResult signal creation

## Current Status

**Status**: Complete
**What works**: All directives implemented with DirectiveExec, EmbedResult signal added, 19 tests passing
**What's next**: Commit and merge to v2 branch
**How to run**: `mix test test/jido_ai/directive_test.exs`

## Notes/Considerations

- `model_alias` resolution happens in DirectiveExec, not in schema parsing
- `system_prompt` is prepended to context messages as a system message
- Embedding supports both single text and batch (list of texts)
- Timeout is passed to Req HTTP options
