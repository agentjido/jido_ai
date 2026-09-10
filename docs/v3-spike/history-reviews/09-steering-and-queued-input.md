# History review 09: steering an active request

Reviewed on 2026-09-06 against `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
This pass completes two more source reviews. The total is 72 of 126.
All v3 port checks remain pending. No runtime tests ran.

The review read both complete diffs, both PR descriptions and all discussion
on issue 224. It also checked the final queue, control, runner and history
projection code. The acceptance cases below are specified work.

## Commit dispositions

| Commit | Final requirement to retain | Required cases |
| --- | --- | --- |
| `ef176f67` / PR 225 | Visible user input can join an active ReAct request. Preserve one handle, bounded FIFO input, consumption events, atomic closure and owned cleanup. | HIST-21: same request, consumption, final closure, guards, bounds, queue failure, cleanup, limits, refs |
| `45157844` / PR 235 | One ReAct control path serves the public and generated helpers. Preserve wrapper defaults, supported options and explicit control outcomes. | HIST-21: public helpers, control timeout; rerun the shared behavior cases |

## Retain the accepted scope from the user report

[Issue 224](https://github.com/agentjido/jido_ai/issues/224) describes people
and peer agents that need to correct work while a model or tool is busy.
Its initial proposal includes global routing, hidden input and automatic start
when idle. The [final maintainer decision](https://github.com/agentjido/jido_ai/issues/224#issuecomment-4137695363)
expressly leaves those features for separate follow-up work.

[PR 225](https://github.com/agentjido/jido_ai/pull/225) adds explicit `steer`
and `inject` controls for an active ReAct request. Both append visible user
input. Neither creates a request handle or changes ordinary busy rejection.
Input is a string; later support for rich query content does not establish
multimodal steering. Other reasoning methods do not gain steering in this PR.

An accepted control means queued. The runner drains input into its conversation
before a model step and emits `input_injected`. The Agent then records that
consumption in history. Input can be lost if the run ends before consumption.
The queue is not a durable input log. The final issue decision accepts this
tradeoff. Preserve it in the migration guide and the new result contract.

The PR body also mentions a test-module rename. That path is absent from the
complete merged diff. Do not count the body alone as an additional source change.
The rename is present in PR 229, now covered by
[review 12](12-observation-and-token-reporting.md).

## HIST-21: extend the live request Agent in catalog 05

Use one report Agent and the unified mock server. The first model request asks
for a real search Action. Hold that Action at a test barrier. A caller says
“Focus on the auth module.” A peer sends “Include expired tokens.” Release
the Action. The next model request must include its actual result and both
new user messages in accepted order. Await the original request handle.

Repeat with the first model's final answer held at the server boundary. Input
accepted before closure makes the same request continue to a second answer.
Observe the first answer as an intermediate model event. Only the final request
event completes `await`. Use barriers, public events and captured HTTP bodies;
do not replace provider decoding or real Action execution.

| Variant | Required evidence |
| --- | --- |
| `HIST-21/same-request` | Steer and inject during a held model call and during real tool work. Retain one request handle and run identity, FIFO messages and one terminal event. Ordinary `ask` still rejects busy input. Await returns the final answer after the new input. |
| `HIST-21/consumption` | After enqueue, history has no new user entry. After drain, the canonical event and history projection contain the consumed input. Fail or cancel before drain and verify that undrained input is absent from history and a later request. Do not claim crash-safe delivery between drain, event delivery and commit. |
| `HIST-21/final-closure` | Test both orders at the completion boundary. Input accepted first prevents an empty seal and continues the run. An empty queue sealed first rejects later input. A model final-answer event alone cannot complete the request. Hold output repair after sealing; steering remains closed even while repair work is active. |
| `HIST-21/guards` | Reject idle, stale expected request ID, blank input and a closed queue without queue/history changes or new provider work. Trim accepted text. An omitted expected ID targets the active request; the guard does not grant authority. Document unsupported content shapes at the public boundary. |
| `HIST-21/bounds` | Fill the default 64-item queue while execution is held. The next control returns `queue_full` and retains the earlier items in order. Drain permits more input. Test a supported lower-level positive limit and invalid-limit fallback. Do not claim an existing Agent DSL limit option that the baseline does not forward. |
| `HIST-21/queue-failure` | Remove the queue before drain and before final closure. The request fails with a structured queue error and emits no false completion. Preserve the error distinction from a valid empty queue. A subsequent request can start with a new queue. |
| `HIST-21/cleanup` | Complete, fail, cancel and kill the owning process with queued input. Monitor queue/worker shutdown and reject late input. Nothing from the prior queue enters a later run or restored Agent. Restore follows the interrupted-request policy from HIST-12. |
| `HIST-21/limits` | Retain hard reasoning/model budgets with pending input. Test termination before drain, and drain after a final answer that exhausts the iteration budget. Consumption does not prove another provider call occurred. Keep termination reason, transcript and usage truthful. |
| `HIST-21/refs` | Preserve source markers and supported extra refs in consumed user history, with input ID/time in the runtime event. Both controls use user role. Unknown metadata does not become a system instruction. Keep actual event request/run correlation separate from caller-supplied message refs. |
| `HIST-21/public-helpers` | Run the same steer/inject cases through `ReAct`, `Jido.AI` and generated Agent helpers. Preserve default/explicit source markers, expected ID, refs, timeout options and rejected outcomes. All paths reach one implementation and enqueue at most once per successful invocation. |
| `HIST-21/control-timeout` | Delay control handling beyond the caller wait. A timeout does not prove that input was rejected or that execution stopped. Observe the eventual queue/result and retain request isolation. Do not retry automatically without an explicit duplicate-input policy. |

FIFO means acceptance order at the queue. It does not define wall-clock order
for concurrent callers. The queue normalizes text and rejects blank content.
Its optional lower-level capacity is a positive integer; invalid values use 64.
The baseline Agent helper does not expose that capacity setting.

## Completion, failure and persistence boundaries

The runner uses `drain_result`, which preserves availability errors. The older
`drain` helper returns an empty list on failure, and `has_pending?` returns
false. Those lossy helpers cannot decide whether a request is complete.
Atomic `seal_if_empty` provides that decision without a check-then-close race.

On a normal final answer, the runner seals an empty queue before output
validation or repair. A non-empty queue is drained and the iteration advances.
On the next loop, the iteration limit can stop work before another model call.
The separate hard-limit path seals unconditionally and can leave input
undrained. Thus the normal completion rule must not imply unlimited continuation
or guaranteed model delivery for every accepted control.

The baseline queue monitors its owner. The Agent starts it without a link and
stops it at terminal events or worker exit. The extracted helper permits some
transitional statuses, including `completed`, only with an active request ID;
the sealed queue remains the final authority. Do not use a status name alone
to decide whether steering is open.

Caller message refs currently override fallback refs with the same key. Source
is then added to the history projection. Keep that compatibility rule explicit,
while the canonical event envelope retains its actual runtime identity. Input
ID and time are event data, not proof of a durable exactly-once input receipt.

## One control owner in the v3 design

[PR 235](https://github.com/agentjido/jido_ai/pull/235) moves control construction
into `Jido.AI.Reasoning.ReAct` and queue lifecycle into `ReAct.PendingInput`.
The compatibility wrapper defaults the input source to `/jido/ai`; generated
helpers use `/ai/react/agent`; direct ReAct uses `/ai/react`. Explicit input
source overrides remain supported. The Signal envelope source is `/ai/react`
through all three paths. Test these separately from message refs.

The old control call reads `last_pending_input_control` from private strategy
state to convert the Server reply into a queued or rejected result. V3 needs
one explicit control result correlated with the control and active request.
Specify that result at the AI command boundary. Do not restore private
strategy state solely to retrieve an acknowledgement.

The profile needs a steering capability within session request policy. Keep
one bounded input owner and one completion decision. Reuse core Agent Turns
and owned runtime work; the feature does not require another scheduler or
global input registry. New durable input, priority queues, hidden roles and
automatic start need separate examples and decisions before they enter scope.

At the authoring pass, prove every source form lowers to the same request
policy and diagnostics. At the live-runtime pass, prove the queue/closure
cases before simplifying state ownership. At recovery, retain consumed
portable history and rebuild resources without replaying undrained input.

## Baseline evidence

Source: [queue](../../../lib/jido_ai/pending_input_server.ex),
[control API](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/react.ex),
[control helper](../../../lib/jido_ai/reasoning/react/pending_input.ex),
[runner](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/react/runner.ex),
[projection](../../../lib/jido_ai/reasoning/react/strategy.ex),
[compatibility wrapper](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai.ex), and
[generated helpers](../../../lib/jido_ai/agent/definition.ex).

Tests: [Agent steering integration](../../../test/jido_ai/integration/react_steering_integration_test.exs),
[queue](../../../test/jido_ai/pending_input_server_test.exs),
[runner](../../../test/jido_ai/react/runtime_runner_test.exs),
[strategy](../../../test/jido_ai/strategy/react_test.exs), and
[Agent helpers](../../../test/jido_ai/agent_test.exs).

The existing integration test uses model stubs and timing delays. Retain its
behavior as a reference; the v3 example must use the shared HTTP mock and
deterministic barriers. No excluded or specified test is passing port evidence.

## Standalone queue execution evidence: 2026-09-07

[14_07](../../../examples/14_resume/14_07_standalone_input/README.md) adds 13 real
integration cases. A caller-supplied queue serves the native Session directly.
FIFO refs, real tool work, final-response continuation, missing-queue failures,
owned cleanup, maximum iterations and closure before repair extend PR 225's
existing evidence. ReAct's Agent return format and the shared queue extend
PR 235's control-path evidence. Checkpoint resume binds a fresh queue and keeps
consumed history, without claiming durable queued-input delivery.

The focused set passes 57 checks, including retained root queue tests. All
historical statuses stay pending until the remaining package and recovery
gates pass. The ownership distinction is explicit: borrowed queues are sealed;
queues created by Session are stopped.

## Position after queued final-answer input: 2026-09-07

[14_10](../../../examples/14_resume/14_10_failure_position/README.md) adds one partial
PR 225 reference. Input received with a final response advances the reasoning
position. If the next transformer rejects, terminal State keeps that position
without inventing another model call. Queue durability and owner-loss recovery
remain separate requirements.
