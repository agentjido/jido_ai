# TODO Backlog (Actionable)

Generated: 2026-02-21

Only sections with actionable findings are listed below.

## Summary
- Total issues: 13
- P0: 3
- P1: 7
- P2: 2
- P3: 1

## By Section
### core (7)
- [core/p0-cancel-overwrites-completed-request.md](./core/p0-cancel-overwrites-completed-request.md): [P0] Cancel path can overwrite already-completed request state
- [core/p1-callback-wrapper-masks-bad-arity-as-timeout.md](./core/p1-callback-wrapper-masks-bad-arity-as-timeout.md): [P1] Callback wrapper advertises arity 1-3 but invokes arity-1 only and reports timeout
- [core/p1-thread-role-normalization-crashes-to-messages.md](./core/p1-thread-role-normalization-crashes-to-messages.md): [P1] Thread accepts roles that `to_messages/2` cannot project
- [core/p1-tool-adapter-crashes-on-non-module-atoms.md](./core/p1-tool-adapter-crashes-on-non-module-atoms.md): [P1] `ToolAdapter.to_action_map/1` crashes on atom inputs that are not action modules
- [core/p2-request-policy-option-silently-forced-reject.md](./core/p2-request-policy-option-silently-forced-reject.md): [P2] `request_policy` option is accepted by API but silently forced to `:reject`
- [core/p2-tool-telemetry-duration-unit-mismatch.md](./core/p2-tool-telemetry-duration-unit-mismatch.md): [P2] Tool execution telemetry emits native monotonic `duration` while contract requires `duration_ms`
- [core/p3-thread-inspect-last-roles-reversed.md](./core/p3-thread-inspect-last-roles-reversed.md): [P3] `Inspect` output for thread "last" roles is reversed

### quality-quota (3)
- [quality-quota/p0-quota-store-ets-bootstrap-race.md](./quality-quota/p0-quota-store-ets-bootstrap-race.md): [P0] Quota ETS table bootstrap is race-prone and raises under concurrent first access
- [quality-quota/p0-retrieval-store-ets-bootstrap-race.md](./quality-quota/p0-retrieval-store-ets-bootstrap-race.md): [P0] Retrieval ETS table bootstrap is race-prone under concurrent first writes
- [quality-quota/p1-quota-store-add-usage-loses-updates.md](./quality-quota/p1-quota-store-add-usage-loses-updates.md): [P1] Quota counter updates are non-atomic and can lose increments

### signals (1)
- [signals/p1-llm-response-tool-call-helpers-crash-on-nonmap-result.md](./signals/p1-llm-response-tool-call-helpers-crash-on-nonmap-result.md): [P1] LLMResponse helper functions crash when `result` tuple payload is not a map/turn

### directives (1)
- [directives/p1-normalize-directive-messages-can-return-non-list.md](./directives/p1-normalize-directive-messages-can-return-non-list.md): [P1] Directive message normalization can return non-list values despite list contract

### cli-mix (1)
- [cli-mix/p1-jido-ai-task-crashes-on-unsupported-format.md](./cli-mix/p1-jido-ai-task-crashes-on-unsupported-format.md): [P1] `mix jido_ai` crashes with `CaseClauseError` on unsupported `--format` values

## Notes
- Clean sections were removed from this actionable list per request.
- Detail files remain the source of truth for reproduction and acceptance criteria.
