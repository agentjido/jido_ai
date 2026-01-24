# Feature: Type and Undefined Issues Fixes (Section 9.4)

## Status: ✅ Complete

## Problem Statement

The compiler shows 6 warnings related to undefined types, structs, and module attributes:

1. **TimeoutError Struct** - `TimeoutError` is undefined in `llm_difficulty.ex`
2. **Undefined Module Attribute** - `@default_threshold` used before definition in `majority_vote.ex`
3. **ReqLLM.chat/1 Undefined** - Using incorrect ReqLLM API in `llm_difficulty.ex`
4. **Unreachable Error Clauses** - 3 files have unreachable `{:error, _}` pattern matches
5. **Candidate.new/1 Error Clause** - Unreachable error pattern in `candidate.ex`

### Specific Issues

#### 9.4.1 TimeoutError Struct (1 warning)
- **File:** `lib/jido_ai/accuracy/estimators/llm_difficulty.ex`
- **Location:** Line 277
- **Issue:** `TimeoutError` is not a built-in Elixir struct
- **Fix:** Use `Jido.Error.TimeoutError` (available from the jido dependency)

#### 9.4.2 Undefined Module Attribute (1 warning)
- **File:** `lib/jido_ai/accuracy/consensus/majority_vote.ex`
- **Location:** Line 26
- **Issue:** `@default_threshold` is used in defstruct before being defined (line 32)
- **Fix:** Move `@default_threshold 0.8` before the defstruct

#### 9.4.3 ReqLLM.chat/1 Undefined (1 warning)
- **File:** `lib/jido_ai/accuracy/estimators/llm_difficulty.ex`
- **Location:** Line 264
- **Issue:** `ReqLLM.chat/1` is undefined or private
- **Fix:** Use `ReqLLM.Generation.generate_text/3` which is the correct API

#### 9.4.4 Unreachable Error Clauses (3 warnings)
- **Files:**
  - `lib/jido_ai/accuracy/verifiers/static_analysis_verifier.ex` (line 137)
  - `lib/jido_ai/accuracy/verifiers/unit_test_verifier.ex` (line 307)
  - `lib/jido_ai/accuracy/search/mcts.ex` (line 190)
- **Issue:** Pattern matches on `{:error, _}` that never match because the wrapped functions always return `{:ok, ...}`
- **Fix:** Remove unreachable error clauses

#### 9.4.5 Candidate.new/1 Error Clause (1 warning)
- **File:** `lib/jido_ai/accuracy/candidate.ex`
- **Location:** Line 116 in `new!/1`
- **Issue:** The `{:error, reason}` pattern in the case statement never matches because `new/1` only returns `{:ok, candidate}`
- **Fix:** Remove unreachable error clause (keep only the `{:ok, candidate}` pattern)

## Solution Overview

1. **TimeoutError:** Replace with `Jido.Error.TimeoutError`
2. **Module Attribute:** Reorder code to define `@default_threshold` before defstruct
3. **ReqLLM API:** Change from `ReqLLM.chat/1` to `ReqLLM.Generation.generate_text/3`
4. **Unreachable Clauses:** Remove unreachable error pattern matches
5. **Candidate Error Clause:** Remove unreachable error pattern in `new!/1`

### Changes Required

| File | Change |
|------|--------|
| `lib/jido_ai/accuracy/estimators/llm_difficulty.ex` | Replace TimeoutError, use ReqLLM.Generation.generate_text/3 |
| `lib/jido_ai/accuracy/consensus/majority_vote.ex` | Move @default_threshold before defstruct |
| `lib/jido_ai/accuracy/verifiers/static_analysis_verifier.ex` | Remove unreachable error clause |
| `lib/jido_ai/accuracy/verifiers/unit_test_verifier.ex` | Remove unreachable error clause |
| `lib/jido_ai/accuracy/search/mcts.ex` | Remove unreachable error clause |
| `lib/jido_ai/accuracy/candidate.ex` | Remove unreachable error clause in new!/1 |

## Technical Details

### ReqLLM API Change

The current code uses:
```elixir
case ReqLLM.chat([
  model: model,
  messages: [%{role: "user", content: prompt}],
  timeout: timeout
]) do
```

Should be changed to:
```elixir
case ReqLLM.Generation.generate_text(model, messages, timeout: timeout) do
```

Where `messages` is a list of message maps with `:role` and `:content` keys.

### Module Attribute Order

Elixir module attributes must be defined before use:
```elixir
# Before (warning):
defstruct threshold: @default_threshold
@default_threshold 0.8

# After (no warning):
@default_threshold 0.8
defstruct threshold: @default_threshold
```

## Success Criteria

1. `mix compile` produces zero type/undefined warnings
2. `mix test` passes with no regressions
3. No functional changes to existing code behavior

## Implementation Plan

### Step 1: Fix TimeoutError and ReqLLM API (9.4.1 & 9.4.3)

**File:** `lib/jido_ai/accuracy/estimators/llm_difficulty.ex`

Changes:
- Replaced `TimeoutError` with `Jido.Error.TimeoutError` in rescue clause
- Changed `ReqLLM.chat/1` to `ReqLLM.Generation.generate_text/3`
- Refactored to build messages list separately for clarity

**Status:** ✅ Complete

### Step 2: Fix Undefined Module Attribute (9.4.2)

**File:** `lib/jido_ai/accuracy/consensus/majority_vote.ex`

Moved `@default_threshold 0.8` from line 32 to line 26, before the defstruct that uses it.

**Status:** ✅ Complete

### Step 3: Fix Unreachable Error Clauses (9.4.4)

**Files:**
- `lib/jido_ai/accuracy/verifiers/static_analysis_verifier.ex`
- `lib/jido_ai/accuracy/verifiers/unit_test_verifier.ex`
- `lib/jido_ai/accuracy/search/mcts.ex`

Removed unreachable `{:error, _reason}` or `{:error, _}` pattern matches. Updated to use direct pattern matching since `verify/3` and `run_single_simulation/7` always return `{:ok, ...}`.

**Status:** ✅ Complete

### Step 4: Fix Candidate.new!/1 Error Clause (9.4.5)

**File:** `lib/jido_ai/accuracy/candidate.ex`

Removed unreachable `{:error, reason}` clause in `new!/1`. Since `new/1` only returns `{:ok, candidate}`, simplified to use pattern matching.

**Status:** ✅ Complete

### Step 5: Verification

Compiled and tested:
- `mix compile` - All type/undefined warnings fixed
- `mix test` - 150 tests pass (1 pre-existing failure in TAP format parsing)

**Status:** ✅ Complete

## Notes

### Jido.Error.TimeoutError

The `Jido.Error.TimeoutError` is available from the `jido` dependency. It's the standard timeout error type used throughout the Jido framework.

### verify/3 Return Type

The `verify/3` function in verifiers always returns `{:ok, VerificationResult}` - it never returns `{:error, _}`. This is by design to make batch processing simpler.

### Candidate.new/1 Return Type

The `new/1` function always returns `{:ok, candidate}` because struct creation with valid inputs doesn't fail in this pattern. Validation errors are handled differently.

## Current Status

- **Step 1:** ✅ Complete
- **Step 2:** ✅ Complete
- **Step 3:** ✅ Complete
- **Step 4:** ✅ Complete
- **Step 5:** ✅ Complete

## What Works

All type and undefined warnings in section 9.4 have been resolved:
1. **TimeoutError** - Fixed by using Jido.Error.TimeoutError
2. **@default_threshold** - Fixed by reordering code
3. **ReqLLM.chat/1** - Fixed by using ReqLLM.Generation.generate_text/3
4. **Unreachable error clauses** - Fixed by removing unreachable patterns in 3 files
5. **Candidate.new!/1** - Fixed by simplifying pattern matching

## What's Next

Section 9.5 (Verification and Testing) and the remaining Unreachable Clauses section still need to be completed in Phase 9.

After implementation, run:
```bash
mix compile  # Should have zero type/undefined warnings
mix test     # All tests should pass
```
