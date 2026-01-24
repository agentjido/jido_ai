# Phase 2 Review Fixes - Feature Plan

**Branch**: `feature/phase2-review-fixes`
**Status**: In Progress
**Created**: 2026-01-04

## Problem Statement

The Phase 2 comprehensive review identified 3 blockers, 10 concerns, and 7 suggestions that need to be addressed before the tool system is production-ready.

## Solution Overview

Address all review findings in priority order:
1. Fix all blockers (security/architecture issues)
2. Address all concerns (testing gaps, code quality, security)
3. Implement suggested improvements (optional enhancements)

---

## Implementation Plan

### Part 1: BLOCKERS (Must Fix) ✅ COMPLETED

#### 1.1 Remove Stacktraces from Error Responses ✅
- [x] 1.1.1 Modify `format_exception/3` in executor.ex to exclude stacktrace from returned map
- [x] 1.1.2 Log stacktrace server-side using Logger instead
- [x] 1.1.3 Rename `format_stacktrace/1` to `format_stacktrace_for_logging/1` (internal use only)
- [x] 1.1.4 Add test to verify stacktraces are not in error responses

#### 1.2 Sanitize Parameters in Telemetry Events ✅
- [x] 1.2.1 Create `sanitize_params/1` function to redact sensitive keys
- [x] 1.2.2 Define list of sensitive key patterns (api_key, password, token, secret, etc.)
- [x] 1.2.3 Apply sanitization in `start_telemetry/2`
- [x] 1.2.4 Add tests to verify sensitive params are redacted (including nested params)

#### 1.3 Deprecate ToolAdapter Registry Functions ✅
- [x] 1.3.1 Add @deprecated tags to registry functions in ToolAdapter
- [x] 1.3.2 Updated ToolAdapter moduledoc to point to Tools.Registry
- [x] 1.3.3 Add Logger.warning deprecation messages when registry functions are called
- [x] 1.3.4 All deprecation warnings now show at compile-time and runtime

---

### Part 2: CONCERNS (Should Address) ✅ COMPLETED

#### 2.1 Testing Gaps ✅
- [x] Added security tests for stacktrace removal (test/jido_ai/tools/executor_test.exs)
- [x] Added telemetry sanitization tests
- [x] Added nested parameter sanitization tests
- [x] Existing parameter normalization tests cover edge cases

#### 2.2 Code Quality ✅

##### 2.2.1 safe_get/safe_update Logging
- [x] Added Logger.warning on retry in safe_get/safe_update in Registry
- [x] Includes attempt number and operation context

##### 2.2.2 build_json_schema Duplication
- [x] Reviewed - both are trivial one-liner wrappers to ActionSchema.to_json_schema
- [x] Not worth extracting - keeping as-is

##### 2.2.3 @doc false on Private Helpers
- [x] Added @doc false to safe_get, safe_update in Registry
- [x] Added @doc false to action?, tool?, has_action_functions?, module_behaviours

#### 2.3 Security ✅

##### 2.3.1 Rate Limiting Documentation
- [x] Added documentation about rate limiting being caller's responsibility in Tool moduledoc
- [x] Added example of using Hammer for rate limiting

##### 2.3.2 Context Validation Documentation
- [x] Documented expected context structure in Tool behavior moduledoc
- [x] Added security note about untrusted context sources

##### 2.3.3 Fix Result Truncation for Base64
- [x] Updated format_binary to use max_raw_size = max_result_size * 0.75
- [x] Updated tests to verify correct truncation at new threshold

---

### Part 3: SUGGESTIONS (Nice to Have) ✅ COMPLETED

#### 3.1 Add @spec to Private Functions ✅
- [x] Added @spec to key private functions in executor.ex (execute_with_timeout, execute_internal, execute_action, execute_tool)
- [x] Added @spec to emit_telemetry in registry.ex

#### 3.2 Document Context Structure ✅
- [x] Added comprehensive context documentation in Tool behavior moduledoc
- [x] Documented common context keys (agent_id, conversation_id, user_id, metadata)

#### 3.3 Create Shared Test Fixtures
- [ ] Deferred - existing inline test modules work well
- [ ] Can be addressed in future refactoring if test duplication becomes problematic

#### 3.4 Add Registry Telemetry Events ✅
- [x] Added telemetry for register operations ([:jido, :ai, :registry, :register])
- [x] Added telemetry for unregister operations ([:jido, :ai, :registry, :unregister])
- [x] Documented telemetry events in Registry moduledoc

---

## Success Criteria

1. [x] All 3 blockers fixed and tested
2. [x] All 10 concerns addressed
3. [x] Suggested improvements implemented where practical
4. [x] All existing tests still pass (152 tests, 0 failures)
5. [x] New tests added for fixes (security tests for stacktrace, telemetry sanitization)
6. [x] No security vulnerabilities in error responses or telemetry

## Current Status

**What Works**: All fixes implemented and tested
**Completed**: All blockers, concerns, and suggestions (except shared test fixtures - deferred)
**How to Run**: `mix test test/jido_ai/tools/ test/jido_ai/integration/`

---

## Notes

- The review mentioned "test uses bare `use Tool`" - need to verify if this is actually an issue or if alias handles it
- Rate limiting is documented as "out of scope" per discussion - will document as caller responsibility
- Some suggestions may be deferred if they require significant refactoring
