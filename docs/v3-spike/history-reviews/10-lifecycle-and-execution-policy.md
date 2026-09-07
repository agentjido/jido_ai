# History review 10: lifecycle and execution policy

Reviewed on 2026-09-06 against `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
This pass completes three more source reviews. The total is 75 of 126.
All v3 port checks remain pending. No runtime tests ran.

The review read all three complete diffs and PRs 231 and 241. It checked
current lifecycle, tool execution and test setup code. The AoT test discussion
on PR 309 supplies a further acceptance requirement; that later commit still
needs its own complete source review.

## Commit dispositions

| Commit | Final requirement to retain | Required cases |
| --- | --- | --- |
| `ab85df72` / PR 231 | Reasoning methods expose correlated request start/completion/failure Signals and telemetry. Retain active identity across phases and clear it at termination. | HIST-07: method lifecycle, phase identity, terminal delivery; HIST-14: method errors; HIST-20: lifecycle state |
| `82826ae3` | Live examples and integration tests start the supported complete Jido runtime. | RELEASE: runtime harness |
| `456ddfe3` / PR 241 | Direct AI tool execution honors explicit and global logging policy. Preserve caller precedence through all direct tool helpers. | HIST-13: action logging, logging precedence |

## A shared lifecycle must preserve each method's work

[PR 231](https://github.com/agentjido/jido_ai/pull/231) adds a generic runtime
event and lifecycle helpers for AoT, GoT and TRM. CoT receives worker-event
Signal and telemetry projection changes. CoD shares the CoT path. The broader
lifecycle contract also includes ReAct, ToT and Adaptive, but this commit does
not implement every method or prove every lifecycle through a live Server.

The baseline tests call strategy commands directly. They inspect returned
directives, self-cast Signal messages and telemetry. They establish useful
contracts but do not prove provider decoding, Server delivery, request tracking,
state commit or owned resource cleanup. Add those layers to the existing
method Agent families in catalog 09–11, using catalog 05's lifecycle assertions.

Use an AoT number puzzle, a GoT comparison and a TRM answer-review cycle. Give
the unified mock exact responses for their real prompts and phases. For AoT,
retain the parsed answer `(4 + (8 - 6)) * 4 = 24` and its reasoning result shape.
For GoT, complete a bounded graph and retain its selected result. For TRM,
exercise reasoning, supervision and improvement before the configured limit.
The final result must follow the method's selection rule; the last model text
is not automatically the selected answer.

| Variant | Required evidence |
| --- | --- |
| `HIST-07/method-lifecycle` | Run each supported method through its public Agent request API and real mock transport. Retain one correlated start and terminal outcome, correct result shape and matching `await` result. A busy second request receives its own rejection and leaves the accepted request active. |
| `HIST-07/phase-identity` | Use multiple model calls in GoT/TRM/ToT and Adaptive selection. Preserve the outer request ID across internal phases, with actual model-call IDs and method identity. A phase completion does not terminate the whole request. Retain available usage without double counting projected Signals. |
| `HIST-07/terminal-delivery` | Fail at each supported model phase; include worker loss and cancellation through the supported API. Close the right request, clear active ownership, reject stale/duplicate terminal input and accept a later request. Only committed completion can claim a committed result. Live progress may precede that commit. |
| `HIST-14/method-errors` | Compare the real source failure, runtime event, public Signal, stored request and caller result. Preserve structured causes in the canonical v3 path and document legacy text conversion. Keep cancellation distinct in telemetry even where a compatibility Signal represents it as request failure. |
| `HIST-20/lifecycle-state` | Test active-ID retention and terminal cleanup for the supported atom/string legacy status forms during conversion. Missing identity emits no invented completion. Repeated terminal input cannot publish another outcome or clear a later request. Use declared state and conversion rules rather than copying old strategy maps. |

The old helper emits only when it sees a transition into completed or error,
and resolves the request ID before terminal state clears it. This is not a
general exactly-once guarantee for arbitrary event replay or cross-terminal
transitions. V3 must use one request owner to reject stale/duplicate outcomes.
Test another request after both success and failure; do not infer restart
support from a unit test that only starts at idle.

## Preserve event meaning and report actual measurements

PR 231 initially retains a separate ReAct wrapper struct. PR 314 later removes
it in favor of constructor delegates that return the canonical runtime event.
Use the final contract from [review 08](08-request-stream-contract.md).

The CoT change supplies canonical three-part LLM results and metadata for
request/run identity, operation and strategy. It emits request start, completion,
failure and cancellation telemetry, plus model completion telemetry. The public
cancellation projection is `ai.request.failed`, while telemetry remains cancelled.
Document any new public cancellation shape through compatibility conversion.

The baseline lifecycle helper can label a non-delegated method as
`origin: :worker_runtime`, and sets request duration to zero. V3 should retain
the useful correlation and event names while reporting actual execution origin
and measured duration. Do not copy placeholder values as new guarantees.

Usage comes from non-empty state usage, then result usage, with explicit helper
options taking precedence. A supplied total is retained; otherwise input and
output totals are added. Later provider-usage fixes still need a complete audit.
The v3 examples must reconcile emitted usage with captured model calls, including
failed work, instead of summing every Signal that repeats the same usage.

TRM still formats its machine error into a string before lifecycle projection.
The current parity test expects `"Error: provider_down"`. Thus the raw snapshot
change in PR 223 does not prove that every method now produces structured
errors. Retain that legacy behavior where promised, while preserving the original
cause in the new canonical failure. Specify both sides of the migration.

The [PR 309 review](https://github.com/agentjido/jido_ai/pull/309#pullrequestreview-4468978518)
confirms that the AoT lifecycle test stays in the default stable suite. Do not
move this coverage behind a flaky or integration exclusion to make the port
pass. New full Agent examples can be excluded by default, with an explicit
required integration run at their migration gate.

## RELEASE/runtime-harness: use the complete runtime

Commit `82826ae3` replaces manual Registry, AgentSupervisor and TaskSupervisor
startup in four tests with a complete `{Jido, name: Jido}` instance. Preserve
the purpose through the actual v3 startup API. The replacement is test setup,
not a new production service.

For `RELEASE/runtime-harness`, run the weather, context, steering and await
rejection examples independently in a fresh test process/runtime, then in the
normal suite. Use the supported complete runtime and wait for readiness. Track
test-owned Agents and workers through shutdown. A prior test's global runtime
must not conceal a missing component. Use explicit ownership for shared
fixtures and retain per-test mock scripts and request records.

The existing setup conditionally uses the global `Jido` instance. This change
alone does not prove async isolation, crash cleanup or fresh consumer startup.
The new suite must establish these without starting only a convenient subset
of runtime components or using global persistent counters for scenario state.

## HIST-13: logging policy survives the Exec change

[PR 241](https://github.com/agentjido/jido_ai/pull/241) reports unwanted action
execution logs on every tool call. The normal strategy path supplied policy,
but direct `Turn` execution omitted it. The fix adds the global action log
level only when the caller did not supply one. All three direct tool paths
use that same execution helper.

| Variant | Required evidence |
| --- | --- |
| `HIST-13/action-logging` | Execute one real Action through direct module execution, named-tool execution, a tool batch and a model-driven Agent. Assert its result and execution count, then verify permitted logs and suppressed logs through the actual observer. A disabled logger alone cannot prove policy propagation. |
| `HIST-13/logging-precedence` | Cover explicit caller policy over global defaults, global fallback when omitted, and applicable instance policy for Agent work. Use positive enabled and negative suppressed cases. A later request retains its own policy. Isolate and restore any application environment changes. |

The v3 boundary has changed. At inspected Jido commit
`b48e089c6660ee836c4bd8e06540e692e3e9a868`, `action_exec_opts` selects execution
routing and timeout; its documentation says action logging belongs to Jido
observability. At Jido Action commit
`83e0b8c8e96f97d5b68f7835ef53743781fce5e1`, Exec rejects unknown run options,
including `log_level`. These are source observations, not new passing tests.

Therefore, map legacy AI logging options to the observer policy and send only
supported options to Exec. Copying the old fix directly would make tool
execution fail validation. The acceptance case must prove both successful
execution and correct logs. It cannot pass merely because an invalid execution
produces no old `Executing` message.

The current logging tests mutate global application config inside an async
test module. Run config-mutating migration cases with explicit isolation;
ordinary per-test policy cases can remain concurrent. Restore the exact prior
environment state, including whether a key existed.

At the shared-operation pass, verify logging conversion and real Exec options.
At the method pass, retain lifecycle identity and method-specific results with
one request/event owner. At the package pass, run stable parity tests and the
complete-runtime examples. These checks constrain simplification without
requiring another AI runtime or model mock.

## Baseline evidence

Source: [lifecycle helper](../../../lib/jido_ai/reasoning/request_lifecycle.ex),
[AoT](../../../lib/jido_ai/shared/aot_strategy.ex),
[CoT](../../../lib/jido_ai/shared/cot_strategy.ex),
[GoT](../../../lib/jido_ai/shared/got_strategy.ex),
[TRM](../../../lib/jido_ai/shared/trm_strategy.ex),
[TRM machine](../../../lib/jido_ai/shared/trm_machine.ex), and
[direct tools](../../../lib/jido_ai/shared/turn.ex).

Tests: [lifecycle parity](../../../test/jido_ai/integration/request_lifecycle_parity_test.exs),
[lifecycle helper](../../../test/jido_ai/reasoning/request_lifecycle_test.exs),
[direct tools](../../../test/jido_ai/turn_test.exs),
[weather](../../../test/jido_ai/examples/weather_agent_test.exs),
[context](../../../test/jido_ai/integration/react_context_lifecycle_integration_test.exs),
[steering](../../../test/jido_ai/integration/react_steering_integration_test.exs), and
[await rejection](../../../test/jido_ai/integration/request_await_rejection_test.exs).

## Native TRM evidence: 2026-09-07

[09_08](../../../examples/v3/profiles/09_08_trm.md) now supplies the real
answer-review cycle required above. Three phases share the outer request ID
and use distinct model/phase IDs. The selected scored answer reaches output
controls and commit; an unreviewed improvement does not replace it. A common
budget can stop between phases. Failures at all three phases keep their raw
causes and usage, while the retained Machine still prints its legacy error.

The example also tests cancellation in supervision and improvement, a deadline,
owner loss, no early domain write and later request success. Direct Machine
checks cover stale/repeated phase results and terminal replay. This does not
prove durable Session replay, old command-phase conversion or the public
TRMAgent wrapper, which remain separate gates. Native model observations use
the common Signal/telemetry path without duplicate Machine events.
