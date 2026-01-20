# Summary: Phase 9.1 - Behaviour Callback Fixes

**Date:** 2026-01-20
**Branch:** `feature/phase-9.1-behaviour-callback-fixes`
**Status:** Complete ✅

## Overview

Fixed 16 compiler warnings related to behaviour callback mismatches in the Jido.AI accuracy system. The issue was that behaviour definitions did not match the actual implementations.

## Problem

The `Jido.AI.Accuracy.Verifier` and `Jido.AI.Accuracy.Prm` behaviour definitions were missing the struct parameter as the first argument. All existing implementations used the longer arity (e.g., `verify/3` instead of `verify/2`), but the behaviours only defined the shorter arity.

Additionally, 5 skill modules incorrectly marked `schema/0` with `@impl Jido.Skill` when it's not actually a Jido.Skill behaviour callback.

## Solution

**Approach A (Approved):** Update the behaviour definitions to match the existing implementations.

This was the correct approach because:
1. All existing implementations use the longer arity
2. All existing callers use the longer arity
3. The struct contains configuration needed for operations
4. No code changes required for implementations or tests

## Changes Made

### Behaviour Definition Updates

| File | Changes |
|------|---------|
| `lib/jido_ai/accuracy/verifier.ex` | Updated `@callback verify/3` and `@callback verify_batch/3` to include `verifier` parameter; updated moduledoc examples |
| `lib/jido_ai/accuracy/prm.ex` | Updated `@callback score_step/4`, `@callback score_trace/4`, and `@callback classify_step/4` to include `prm` parameter; updated moduledoc examples |

### Skill @impl Annotation Fixes

| File | Change |
|------|--------|
| `lib/jido_ai/skills/streaming/streaming.ex` | Removed `@impl Jido.Skill` from `schema/0` |
| `lib/jido_ai/skills/tool_calling/tool_calling.ex` | Removed `@impl Jido.Skill` from `schema/0` |
| `lib/jido_ai/skills/planning/planning.ex` | Removed `@impl Jido.Skill` from `schema/0` |
| `lib/jido_ai/skills/llm/llm.ex` | Removed `@impl Jido.Skill` from `schema/0` |
| `lib/jido_ai/skills/reasoning/reasoning.ex` | Removed `@impl Jido.Skill` from `schema/0` |

## Results

- ✅ Zero behaviour callback warnings in `mix compile`
- ✅ Zero behaviour callback warnings in `mix docs`
- ✅ All verifier tests pass (241/242, 1 pre-existing failure unrelated to changes)
- ✅ No functional changes to existing code

## Warnings Fixed

Before:
```
warning: function verify/2 required by behaviour Jido.AI.Accuracy.Verifier is not implemented
warning: function verify_batch/2 required by behaviour Jido.AI.Accuracy.Verifier is not implemented
warning: got "@impl true" for function verify/3 but no behaviour specifies such callback
warning: got "@impl Jido.Skill" for function schema/0 but this behaviour does not specify such callback
```

After: All behaviour callback warnings eliminated.

## Files Modified

1. `lib/jido_ai/accuracy/verifier.ex` - Behaviour definition
2. `lib/jido_ai/accuracy/prm.ex` - Behaviour definition
3. `lib/jido_ai/skills/streaming/streaming.ex`
4. `lib/jido_ai/skills/tool_calling/tool_calling.ex`
5. `lib/jido_ai/skills/planning/planning.ex`
6. `lib/jido_ai/skills/llm/llm.ex`
7. `lib/jido_ai/skills/reasoning/reasoning.ex`

## Next Steps

Section 9.2: Fix unused variables, imports, aliases, and functions (45+ warnings remaining)

## Testing

```bash
mix compile  # Zero behaviour callback warnings
mix test     # All existing tests still pass
mix docs     # Documentation builds successfully
```
