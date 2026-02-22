# [P2] `request_policy` option is accepted by API but silently forced to `:reject`

## Summary
The agent macro accepts `:request_policy` and forwards it into strategy options, but ReAct strategy config coercion collapses all values to `:reject`.

Severity: `P2`  
Type: `api`, `docs`, `logic`

## Impact
Users can pass non-default `request_policy` values without error, but runtime behavior ignores them. This is silent configuration drift and can break concurrency expectations.

## Evidence
- Public agent options include `:request_policy`: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/agent.ex:183`.
- Strategy coercion branch maps all values to `:reject`: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/reasoning/react/strategy.ex:1173`.

Code excerpt behavior:
```elixir
case Keyword.get(opts, :request_policy, :reject) do
  :reject -> :reject
  _ -> :reject
end
```

## Reproduction / Validation
1. Define agent with `request_policy: :queue` (or any non-`:reject` value).
2. Trace runtime behavior for concurrent requests.
3. Observe it still behaves as `:reject` policy.

## Expected vs Actual
Expected: either support declared policies or reject unsupported values explicitly.  
Actual: unsupported values are silently accepted and coerced.

## Why This Is Non-Idiomatic (if applicable)
Idiomatic configuration handling in Elixir fails fast on invalid options rather than silently mutating user intent.

## Suggested Fix
- Validate allowed policies and raise on unsupported values, or
- Implement additional policy modes and document them precisely.

## Acceptance Criteria
- [ ] Passing unsupported `request_policy` returns explicit configuration error.
- [ ] Docs and runtime behavior are aligned.
- [ ] Add coverage for non-default policy input handling.

## Labels
- `priority:P2`
- `type:api`
- `type:docs`
- `type:logic`
- `area:core`

## Related Files
- `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/agent.ex`
- `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/reasoning/react/strategy.ex`
- `/Users/mhostetler/Source/Jido/jido_ai/guides/developer/configuration_reference.md`
- `/Users/mhostetler/Source/Jido/jido_ai/guides/user/first_react_agent.md`
