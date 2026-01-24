# Feature: Phase 1 Review Fixes

## Problem Statement

The Phase 1 comprehensive review identified 3 blockers, 29 concerns, and 25 suggestions that need to be addressed before Phase 2.

**Blockers:**
1. `ToolExec.new!/1` is not tested
2. `ReqLLMPartial.new!/1` is not tested
3. `classify_error` is duplicated 4 times with primitive implementation in directive.ex

**Impact**: Test coverage gaps and significant code duplication (~200 lines) reducing maintainability.

## Solution Overview

Address all items in priority order: blockers first, then concerns, then suggestions.

## Implementation Plan

### Phase A: Fix Blockers (Critical)

#### A.1 Add ToolExec.new!/1 Tests
- [ ] Add describe block for ToolExec in directive_test.exs
- [ ] Test creation with required fields
- [ ] Test default values (arguments: %{}, context: %{}, metadata: %{})
- [ ] Test raises on missing required fields

#### A.2 Add ReqLLMPartial.new!/1 Tests
- [ ] Add describe block for ReqLLMPartial in signal_test.exs
- [ ] Test creation with required fields (call_id, delta)
- [ ] Test default chunk_type is :content
- [ ] Test chunk_type: :thinking

#### A.3 Fix classify_error Duplication (Blocker from Redundancy Review)
- [ ] Remove duplicate classify_error from directive.ex (3 copies)
- [ ] Use Helpers.classify_error/1 in DirectiveExec implementations
- [ ] Ensure all error types are properly classified

### Phase B: Fix Concerns

#### B.1 QA/Test Coverage Concerns (4 items)
- [ ] Add validation test when neither model nor model_alias provided
- [ ] Add schema/0 function test for directives
- [ ] Fix unused variable warning in helpers_test.exs line 336

#### B.2 Architecture Concerns (4 items)
- [ ] Extract shared directive helpers to reduce duplication
  - extract_text
  - normalize_tool_call
  - build_messages/normalize_messages
  - add_timeout_opt
  - resolve_model
  - classify_response
  - add_tools_opt
  - parse_arguments
- [ ] Document tight coupling to ReqLLM error structure (acceptable trade-off)
- [ ] Note: Agent registry supervision is out of scope for this fix

#### B.3 Security Concerns (5 items)
- [ ] Add warning log when JSON parsing fails (parse_arguments)
- [ ] Note: Other security items are enhancements, not blockers

#### B.4 Consistency Concerns (4 items)
- [ ] Add @doc false to schema/0 functions
- [ ] Use ArgumentError instead of plain string raises in new!/1

#### B.5 Redundancy Concerns (8 items - covered by A.3 and B.2)
- Already addressed by extracting shared helpers

#### B.6 Elixir Idioms Concerns (4 items)
- [ ] Rename is_tool_call?/1 to tool_call?/1 (keep is_tool_call? as deprecated alias)
- [ ] Fix unused errors = [] in config.ex validate/0
- [ ] Refactor validate_defaults to use functional pattern

### Phase C: Implement Suggestions (Low Priority)

- [ ] Add streaming flow integration test (partial -> partial -> result)
- [ ] Alias error modules at top of helpers.ex
- [ ] Add @doc false to schema/0 functions (done in B.4)

## Current Status

**Status**: In Progress
**Started**: 2026-01-03

### Progress
- [x] Created feature branch: feature/phase1-review-fixes
- [x] Created planning document
- [ ] Phase A: Fix Blockers
- [ ] Phase B: Fix Concerns
- [ ] Phase C: Implement Suggestions
- [ ] Run tests and verify all pass
- [ ] Write summary

## Files to Modify

| File | Changes |
|------|---------|
| test/jido_ai/directive_test.exs | Add ToolExec tests, validation tests |
| test/jido_ai/signal_test.exs | Add ReqLLMPartial tests, rename is_tool_call? |
| lib/jido_ai/directive.ex | Extract shared helpers, use Helpers.classify_error |
| lib/jido_ai/signal.ex | Add tool_call?/1, deprecate is_tool_call?/1 |
| lib/jido_ai/helpers.ex | Add shared directive helpers, add error module aliases |
| lib/jido_ai/config.ex | Fix validate/0, refactor validate_defaults |
| test/jido_ai/helpers_test.exs | Fix unused variable warning |

## Notes/Considerations

- Extracting shared helpers to Helpers module ensures single source of truth
- The is_tool_call? -> tool_call? rename keeps backward compatibility
- Agent registry supervision is deferred to a future enhancement
- Security hardening items are noted but deferred for production readiness
