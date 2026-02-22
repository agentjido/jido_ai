# [P1] Callback wrapper advertises arity 1-3 but invokes arity-1 only and reports timeout

## Summary
`validate_callback/1` accepts callback arities 1, 2, and 3, but execution always invokes `callback.(arg)` (arity 1). Arity mismatch crashes are then surfaced as `{:error, :callback_timeout}`.

Severity: `P1`  
Type: `logic`, `idiomatic`

## Impact
Misclassified failures hide real root cause (`BadArityError`) and lead to incorrect operational diagnosis as timeouts.

## Evidence
- Arity validation accepts 1/2/3: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/validation.ex:104`.
- Wrapper always calls one argument: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/validation.ex:316`.
- Exit path maps to `:callback_timeout`: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/validation.ex:301`.

Observed validation command (2026-02-21):
```bash
mix run -e '
{:ok, sup} = Task.Supervisor.start_link()
{:ok, wrapped} = Jido.AI.Validation.validate_and_wrap_callback(fn _a, _b -> :ok end, task_supervisor: sup)
IO.inspect(wrapped.(:foo))
'
```

Observed output:
```text
(BadArityError) ... called with 1 argument
result={:error, :callback_timeout}
```

## Reproduction / Validation
1. Provide valid arity-2 callback.
2. Wrap it with `validate_and_wrap_callback/2`.
3. Invoke wrapped callback once.
4. Observe `BadArityError` in task and returned timeout tuple.

## Expected vs Actual
Expected: either reject non-arity-1 callbacks or invoke with matching arity/context and return explicit execution error.  
Actual: arity mismatch is treated as timeout.

## Why This Is Non-Idiomatic (if applicable)
Error mapping should preserve cause. Conflating execution exceptions with timeout semantics is non-idiomatic and hinders observability.

## Suggested Fix
- Align validation with invocation contract (accept only arity 1) OR
- Support all accepted arities with explicit args.
- Return a non-timeout error on callback crash (for example `{:error, :callback_execution_failed}`).

## Acceptance Criteria
- [ ] Callback validation and invocation arity contracts match.
- [ ] Bad arity is not reported as timeout.
- [ ] Add tests for arity-1/2/3 behavior and error classification.

## Labels
- `priority:P1`
- `type:logic`
- `type:idiomatic`
- `area:core`

## Related Files
- `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/validation.ex`
