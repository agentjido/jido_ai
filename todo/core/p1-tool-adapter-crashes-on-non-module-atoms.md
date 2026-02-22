# [P1] `ToolAdapter.to_action_map/1` crashes on atom inputs that are not action modules

## Summary
`to_action_map/1` filters list input only by `is_atom/1`, then calls `module.name()`. Non-module atoms pass filter and crash with `UndefinedFunctionError`.

Severity: `P1`  
Type: `logic`, `api`

## Impact
Invalid tool input causes hard runtime crash instead of safe rejection/ignore path.

## Evidence
- List path filters only by `is_atom/1`: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/tool_adapter.ex:175`.
- It immediately invokes `module.name()`: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/tool_adapter.ex:178`.

Observed validation command (2026-02-21):
```bash
mix run -e 'Jido.AI.ToolAdapter.to_action_map([:not_a_module])'
```

Observed output:
```text
** (UndefinedFunctionError) function :not_a_module.name/0 is undefined
```

## Reproduction / Validation
1. Call `to_action_map([:not_a_module])`.
2. Observe `UndefinedFunctionError`.

## Expected vs Actual
Expected: non-action atoms should be filtered/rejected with structured error.  
Actual: crash from direct callback invocation.

## Why This Is Non-Idiomatic (if applicable)
Public normalization helpers in Elixir generally avoid raising on malformed input when a safe fallback path exists.

## Suggested Fix
Validate candidate module capabilities before using:
- `Code.ensure_loaded?/1`
- `function_exported?(module, :name, 0)`
- optionally schema/action behavior checks.

## Acceptance Criteria
- [ ] `to_action_map/1` does not raise on non-module atoms.
- [ ] Invalid entries are dropped or returned as explicit error tuples.
- [ ] Add tests for malformed atom/list/map inputs.

## Labels
- `priority:P1`
- `type:logic`
- `type:api`
- `area:core`

## Related Files
- `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/tool_adapter.ex`
