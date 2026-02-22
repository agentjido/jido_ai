# [P1] Directive message normalization can return non-list values despite list contract

## Summary
`normalize_directive_messages/1` is typed as returning `list()`, but fallback clause returns arbitrary term (`context`) unchanged.

Severity: `P1`  
Type: `logic`, `api`

## Impact
Directive builders can pass non-list values into downstream ReqLLM calls, causing type mismatch failures away from the original call site.

## Evidence
- Spec declares list return: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/directive/helpers.ex:97`.
- Fallback returns raw context: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/directive/helpers.ex:100`.

Observed validation command (2026-02-21):
```bash
mix run -e '
msgs = Jido.AI.Directive.Helpers.build_directive_messages(%{foo: :bar}, nil)
IO.puts("shape=#{inspect(msgs)} is_list?=#{inspect(is_list(msgs))}")
'
```

Observed output:
```text
shape=%{foo: :bar} is_list?=false
```

## Reproduction / Validation
1. Call `build_directive_messages/2` with map lacking `:messages`.
2. Observe non-list return value.

## Expected vs Actual
Expected: always return list (possibly `[]`) or return explicit validation error.  
Actual: arbitrary term can escape normalization.

## Why This Is Non-Idiomatic (if applicable)
Function specs and runtime behavior should align at module boundaries, especially normalization helpers.

## Suggested Fix
Change fallback to `[]` or `raise ArgumentError` / `{:error, :invalid_messages_shape}` and enforce it consistently at call sites.

## Acceptance Criteria
- [ ] `normalize_directive_messages/1` always returns list or explicit error.
- [ ] Specs match implementation.
- [ ] Add tests for invalid context shapes.

## Labels
- `priority:P1`
- `type:logic`
- `type:api`
- `area:directives`

## Related Files
- `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/directive/helpers.ex`
