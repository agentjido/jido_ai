# Feature: Behaviour Callback Fixes (Section 9.1)

## Status: Complete ✅

## Problem Statement

The compiler shows 16 warnings related to behaviour callback mismatches. The behaviour definitions for `Jido.AI.Accuracy.Verifier` and `Jido.AI.Accuracy.Prm` define callbacks that don't match the actual implementations.

### Specific Issues

1. **Verifier Behaviour** (`lib/jido_ai/accuracy/verifier.ex`):
   - Defines `verify/2` as `verify(candidate, context)`
   - Defines `verify_batch/2` as `verify_batch(candidates, context)`
   - But all implementations use 3-arity: `verify(verifier, candidate, context)`

2. **PRM Behaviour** (`lib/jido_ai/accuracy/prm.ex`):
   - Defines `score_step/3` as `score_step(step, context, opts)`
   - Defines `score_trace/3` as `score_trace(trace, context, opts)`
   - Defines `classify_step/3` as `classify_step(step, context, opts)`
   - But implementations use 4-arity: `score_step(prm, step, context, opts)`

3. **Skill Behaviour** (3 modules):
   - `schema/0` is incorrectly marked with `@impl Jido.Skill`
   - `schema/0` is NOT a Jido.Skill behaviour callback

### Root Cause

The behaviour definitions are missing the struct parameter as the first argument. All existing code, tests, and documentation use the longer arity versions.

## Solution Overview

**Update the behaviour definitions** to include the struct parameter, rather than updating all implementations. This is the correct approach because:

1. All existing implementations use the longer arity
2. All existing callers use the longer arity
3. The struct contains configuration needed for verification/PRM operations
4. This is a documentation fix, not a behaviour change

### Changes Required

| File | Change |
|------|--------|
| `lib/jido_ai/accuracy/verifier.ex` | Update `@callback verify/3` and `@callback verify_batch/3` |
| `lib/jido_ai/accuracy/prm.ex` | Update `@callback score_step/4`, `@callback score_trace/4`, `@callback classify_step/4` |
| `lib/jido_ai/skills/streaming/streaming.ex` | Remove `@impl Jido.Skill` from `schema/0` |
| `lib/jido_ai/skills/tool_calling/tool_calling.ex` | Remove `@impl Jido.Skill` from `schema/0` |
| `lib/jido_ai/skills/planning/planning.ex` | Remove `@impl Jido.Skill` from `schema/0` |
| `lib/jido_ai/skills/llm/llm.ex` | Remove `@impl Jido.Skill` from `schema/0` |
| `lib/jido_ai/skills/reasoning/reasoning.ex` | Remove `@impl Jido.Skill` from `schema/0` |

## Technical Details

### File Locations

**Behaviour Definitions:**
- `lib/jido_ai/accuracy/verifier.ex` - Lines 143, 173
- `lib/jido_ai/accuracy/prm.ex` - Lines 184, 216, 248

**Skill Modules:**
- `lib/jido_ai/skills/streaming/streaming.ex` - Line 149
- `lib/jido_ai/skills/tool_calling/tool_calling.ex` - Line 146
- `lib/jido_ai/skills/planning/planning.ex` - Line 130

### Affected Test Files

No test changes needed - tests already call the functions with the correct arity.

## Success Criteria

1. `mix compile` produces zero warnings for behaviour callback mismatches
2. `mix docs` produces zero warnings for behaviour callback mismatches
3. All tests pass: `mix test`
4. No functional changes to existing code

## Implementation Plan

### Step 1: Update Verifier Behaviour

**File:** `lib/jido_ai/accuracy/verifier.ex`

Update callback signatures from:
```elixir
@callback verify(candidate :: Candidate.t(), context :: context()) :: verify_result()
@callback verify_batch(candidates :: [Candidate.t()], context :: context()) :: verify_batch_result()
```

To:
```elixir
@callback verify(verifier :: term(), candidate :: Candidate.t(), context :: context()) :: verify_result()
@callback verify_batch(verifier :: term(), candidates :: [Candidate.t()], context :: context()) :: verify_batch_result()
```

Also update documentation examples to match.

**Status:** Complete ✅

### Step 2: Update PRM Behaviour

**File:** `lib/jido_ai/accuracy/prm.ex`

Update callback signatures from:
```elixir
@callback score_step(step :: String.t(), context :: context(), opts :: opts()) :: step_score_result()
@callback score_trace(trace :: [String.t()], context :: context(), opts :: opts()) :: trace_score_result()
@callback classify_step(step :: String.t(), context :: context(), opts :: opts()) :: classify_result()
```

To:
```elixir
@callback score_step(prm :: term(), step :: String.t(), context :: context(), opts :: opts()) :: step_score_result()
@callback score_trace(prm :: term(), trace :: [String.t()], context :: context(), opts :: opts()) :: trace_score_result()
@callback classify_step(prm :: term(), step :: String.t(), context :: context(), opts :: opts()) :: classify_result()
```

Also update documentation examples to match.

**Status:** Complete ✅

### Step 3: Fix Skill Schema @impl Annotations

**Files:**
- `lib/jido_ai/skills/streaming/streaming.ex`
- `lib/jido_ai/skills/tool_calling/tool_calling.ex`
- `lib/jido_ai/skills/planning/planning.ex`
- `lib/jido_ai/skills/llm/llm.ex`
- `lib/jido_ai/skills/reasoning/reasoning.ex`

Remove `@impl Jido.Skill` from the `schema/0` function in each module. The `schema/0` function is part of the `Zoi` schema pattern, not a Jido.Skill behaviour callback.

**Status:** Complete ✅

### Step 4: Verification

Run tests and compile to ensure no regressions:

```bash
mix compile
mix test
mix docs
```

**Status:** Complete ✅

## Results

- Zero behaviour callback warnings in `mix compile`
- Zero behaviour callback warnings in `mix docs`
- All verifier tests pass (241/242, 1 pre-existing failure)
- No functional changes to existing code

## Notes

### Design Decision

After analyzing the codebase, I determined that updating the behaviour definitions is the correct approach because:

1. **Consistency**: All implementations use the longer arity
2. **Usage**: All callers use the longer arity
3. **Documentation**: Even the behaviour documentation examples show the longer arity
4. **Practicality**: The verifier/PRM structs contain configuration needed for operations

### Behaviour Pattern in Elixir

The Elixir behaviour pattern typically expects the first parameter to be the module's state/config struct when the behaviour is for a "processor" type module. This is similar to:
- `GenServer` callbacks take `state` as a parameter
- `Plug` callbacks take `conn` as a parameter

Our verifiers and PRMs follow this pattern by taking their config struct as the first parameter.

## Current Status

- **Step 1:** Complete ✅
- **Step 2:** Complete ✅
- **Step 3:** Complete ✅
- **Step 4:** Complete ✅

## What Works

- All behaviour callback definitions now match their implementations
- All `@impl Jido.Skill` annotations removed from `schema/0` functions
- Code compiles with zero behaviour callback warnings
- All tests pass (except pre-existing API-related failures)

## What's Next

Section 9.2: Fix unused variables, imports, aliases, and functions.

## How to Test

```bash
mix compile  # Should have zero behaviour warnings
mix test     # All tests should pass
```
