# History review 07: stream failures, order and checkpoints

Reviewed on 2026-09-06 against `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
This pass completes five more source reviews. The total is 67 of 126.
All v3 port checks remain pending. This pass changes documents only.
No runtime tests ran.

The review read each complete commit diff, all associated PR discussion, and
local reports 246, 287 and 327. Core issue 315 supplies related persistence
context. Final source was checked where later commits changed the same paths.

## Commit dispositions

| Commit | Final requirement to retain | Required cases |
| --- | --- | --- |
| `5601aa5e` / PR 239 | Reject blank terminal responses with failed finish reasons before successful model completion or assistant history. Keep usage and the structured error. Preserve the explicitly accepted partial-text case. | HIST-06: blank terminal, finish-reason inputs, accepted partial, transport failure, failed checkpoint |
| `2105a7af` / PR 247 | Emit optional early tool-call activity during model streaming, before tool execution. | HIST-07: early tool activity, unnamed fragments |
| `ce9e1968` / PR 271 | Retain available sequence and request/run metadata when converting runtime deltas into public Signals. | HIST-07: ordered deltas, optional metadata |
| `3f2ec9c6` / PR 288 | A dead provider cancellation process cannot turn successful stream cleanup into a caller crash. | HIST-06: cleanup exit |
| `8fb1d69f` / PR 332 | Stream sinks and owned process handles cannot enter durable checkpoints. Terminal paths release sinks. Restore active streams as failed, permit consumer checkpoint composition, and rebuild derived resources. | HIST-12: terminal sinks, cancel delivery, active stream, completed stream, fresh runtime, legacy conversion, callback identity, custom persistence, failed restore |

## HIST-06: distinguish provider status from transport failure

[PR 239](https://github.com/agentjido/jido_ai/pull/239) reports a Greeter that
returned a successful empty string when the user's provider account had no
credits. The direct facade already returned an error. Reproduce the visible
failure with the unified mock and real provider decoding. No credit or paid
provider setup is needed.

The source does not reject every incomplete response. The merged integration
test explicitly accepts non-empty text with `finish_reason: :incomplete`.
The target still accepts a non-empty result before checking the reason.
The later generated-media change uses `Turn.result/1`, so valid rich content
also counts as a result. A disconnected or failed transport is a different
path. Do not remove the accepted partial-result behavior under a broad rule
that every partial answer must fail.

| Variant | Required evidence |
| --- | --- |
| `HIST-06/blank-terminal` | Return a complete provider envelope with no final content and each failed reason: incomplete, error, cancelled, length and content filter. The Agent returns a structured failure, no successful request completion, no model-completed event and no phantom assistant entry. Retain reported usage. Compare the supported standalone and live APIs. |
| `HIST-06/finish-reason-inputs` | Preserve the documented atom/string reason conversion in direct result/response inputs and actual provider decoding. Cover stop/completed/end-turn, tool-calls/tool-use, max-tokens/max-output-tokens/length, and unknown values. Missing reason and blank successful stop remain distinct from an explicit failed reason. |
| `HIST-06/accepted-partial` | A complete provider response contains non-empty text and an incomplete reason. Preserve the accepted text behavior through compatibility APIs and retain the finish reason for inspection. Test a configured typed-output contract separately: its validator still decides whether the value can complete. Any stronger default rejection in the new API needs an explicit migration decision. |
| `HIST-06/transport-failure` | Deliver a visible text fragment, then a transport error or malformed/truncated response that the actual decoder reports as failure. The request fails, preserves prior committed domain/history state, and emits no successful completion. Repeat with a quiet disconnect before any content. A later request succeeds. |
| `HIST-06/failed-checkpoint` | Standalone ReAct emits its terminal failed checkpoint with the structured incomplete-response reason and usage. It contains the user input but no false assistant answer or after-model success checkpoint. Test that token contract separately from Agent persistence. |

The baseline's blank check compares the result to an empty string. It does
not trim whitespace or reject blank success with a missing/stop reason.
Do not silently add stricter public behavior during migration. The direct
facade and reasoning runner have separate public return shapes; compare
failure meaning and documented wrappers instead of requiring identical tuples.

For `HIST-06/cleanup-exit`, consume a successful stream and confirm its actual
provider work has ended. Stream cleanup must preserve the successful result
and keep the caller alive. A focused cleanup test must also exercise a
cancel callback that calls a known dead GenServer, as the original regression
test does. Do not replace the real provider decoder in the full Agent example.
Check that cleanup runs once and does not cancel a later request.

[Issue 287](https://github.com/agentjido/jido_ai/issues/287) reports a `:noproc`
exit after successful stream consumption. [PR 288](https://github.com/agentjido/jido_ai/pull/288)
uses an explicit `try/catch` around the cancel callback. The issue's code
example differs from the immediate parent diff, but both identify the same
observable requirement: cleanup of dead provider work cannot crash the caller.

## HIST-07: early activity and ordered content are separate contracts

[Issue 246](https://github.com/agentjido/jido_ai/issues/246) describes a model
that spends 30–60 seconds generating a document tool's arguments. Users see
no activity until tool execution. [PR 247](https://github.com/agentjido/jido_ai/pull/247)
connects the provider's tool-chunk callback to the runtime delta stream.

For `HIST-07/early-tool-activity`, have the unified mock send a named tool-call
fragment and hold the remaining arguments behind a barrier. With delta capture
enabled, observe `chunk_type: :tool_call` before releasing that barrier.
No Action starts until the full arguments are decoded and admitted. Complete
the stream, execute a real document Action, and verify its reconstructed input
and the next model request. With capture disabled, suppress public deltas
while preserving execution and internal activity tracking.

The baseline emits the tool name as the delta. It does not expose the raw
argument fragment, tool-call ID or argument index through this callback.
An empty name produces no delta. Preserve early activity without describing
it as an existing complete argument-stream API. If the new API exposes raw
fragments, define that as an explicit extension with typed correlation and
payload controls.

For `HIST-07/unnamed-fragments`, send a first named fragment followed by
argument-only fragments. Use the actual provider decoder. Verify both the
final arguments and activity/idle-timeout behavior with capture enabled and
disabled. Source inspection found a gap to test: the baseline counts all
tool chunks as visible, but suppresses empty-name deltas. Internal progress
must not depend on whether a public name delta was emitted. This is a static
finding, not a reproduced runtime failure.

[PR 271](https://github.com/agentjido/jido_ai/pull/271) preserves sequence data
when ReAct and CoT convert runtime events into `ai.llm.delta` Signals.
Delivery order alone cannot reconstruct a transcript reliably.

- `HIST-07/ordered-deltas`: run live ReAct and CoT examples. Capture real runtime
  deltas and their public projections. Preserve sequence, call ID, run ID and
  request ID, plus ReAct iteration. Reorder the captured public delivery at a
  test consumer and reconstruct text by sequence within the same call. Keep
  content, thinking and tool activity separate. Sequence gaps are valid because
  other event kinds share the runtime sequence; do not require consecutive
  numbers for text deltas alone.
- `HIST-07/optional-metadata`: existing minimal Signal inputs remain valid.
  CoT carries its available metadata; absent optional fields must not become
  fabricated values. Test atom- and string-keyed supported event input at the
  conversion boundary. A new run or call cannot reuse another call's text.

Use the shared mock and an event collector that belongs to the test. No global
telemetry handler or unrelated request may satisfy these assertions. The later
[public-stream review](08-request-stream-contract.md) completes the canonical
event and keepalive source reviews and adds public transport cases.

## HIST-12: a stream cannot resume through an old process handle

[Issue 327](https://github.com/agentjido/jido_ai/issues/327) comes from a
production deployment that changed Erlang node naming. Stored request PIDs
made checkpoints unreadable in a fresh runtime. Removing the active sink only
after completion could not protect checkpoints taken during execution.

The final [PR 332](https://github.com/agentjido/jido_ai/pull/332) stores an active
streamed request as `status: :failed`, `error: :stream_interrupted` and
`stream_interrupted: true`. It clears the sink and resets active ReAct work.
An early section of its commit message describes a pending status and a
general residual-handle warning scan. Those are not the final implementation.
Use the final code, tests and guide.

| Variant | Required evidence |
| --- | --- |
| `HIST-12/terminal-sinks` | Complete, fail and cancel real streamed requests. Release each sink and owned runtime subscription at the terminal boundary. Preserve result/error and request metadata. A terminal record contains no sink, including when the consumer exits first. |
| `HIST-12/cancel-delivery` | Cancel a blocked request whose worker does not acknowledge cancellation. Send the terminal cancellation event before removing the sink, close the consumer stream, and record the cancellation error. A late worker event cannot deliver another terminal result or affect the next request. |
| `HIST-12/active-stream` | Checkpoint during a blocked stream. The live request keeps its runtime binding; the stored copy contains no process handle and records stream interruption. Restore it as failed with the documented old-handle result. New runtime resources permit a later successful request. |
| `HIST-12/completed-stream` | Complete a real tool round and final answer, checkpoint, then restore. Preserve the completed result, canonical tool/history data and domain state. Do not fail an already completed request or restore the old sink. |
| `HIST-12/fresh-runtime` | Write a checkpoint in one OS runtime with a unique node name. Decode and restore in a fresh runtime with another name, using the actual supported storage codec. Where the format is Erlang terms, use `binary_to_term` with `[:safe]`; preload only trusted application modules. A same-runtime round trip does not close this case. Scan both map keys and values for disallowed live values in the acceptance assertion. |
| `HIST-12/legacy-conversion` | Use the explicit old-to-new conversion for supported old payloads, including active sink fields and already marked interrupted records. Completed/failed/timeout records preserve terminal meaning. Reject unreadable or unsupported input without replacing stored data. Keep this conversion distinct from current v3 restore. |
| `HIST-12/callback-identity` | Keep provider tool descriptions serializable by trusted executable identity. Rebuild derived schemas and runtime resources from the current allowed catalog. The provider placeholder does not execute an Action. A real later tool call still executes once through core. |
| `HIST-12/custom-persistence` | A consumer's supported checkpoint extension still runs and retains AI portability rules. Include an externalized domain value with a restore failure. Compose through current core persistence APIs; do not retain a copied v2 override chain merely to match private code. |
| `HIST-12/failed-restore` | A stored session exists but decode, migration or restore fails. Return a structured failure. Do not start a replacement session or overwrite existing state. A genuinely absent record can still create a new Agent. Use the actual core persistence/start boundary. |

The [checkpoint override review finding](https://github.com/agentjido/jido_ai/pull/332#discussion_r3647658023)
led to an explicit overridable wrapper and a consumer regression test.
Preserve that extension behavior when the public persistence API changes.
The [map-key review finding](https://github.com/agentjido/jido_ai/pull/332#discussion_r3647658031)
also matters to acceptance. The final production helper is a targeted reset,
not a general sanitizer for arbitrary domain values. Its test scans map keys
and values. Do not claim that the old helper makes every payload portable.

The final tests prove a same-runtime safe term round trip and one live completed
stream. The commit message reports a manual cross-VM verification, but the
checked-in tests do not automate that boundary. The new fresh-runtime example
must prove it. No unsafe decode fallback belongs in the migration acceptance.

The related [core issue 315](https://github.com/agentjido/jido/issues/315)
describes a failed thaw that starts a new Agent and later conflicts with the
stored journal. Preserve the failed-restore case at the v3 integration boundary.
The issue's unrelated approval comment does not change this persistence
requirement. Core issue context does not add its commits to the AI audit range.

In v3, process handles stay in owned runtime resources from the start. Keep
history, request results and interrupted-work data in the portable Agent state.
Do not rebuild the removed TaskSupervisor Plugin checkpoint hook or strategy
state layout. Standalone resume tokens, Agent restore and offline v2 conversion
remain three separate contracts.

## Baseline evidence and simplification gates

Source: [runner](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/react/runner.ex),
[Turn](../../../lib/jido_ai/turn.ex),
[ReAct projection](../../../lib/jido_ai/reasoning/react/strategy.ex),
[CoT projection](../../../lib/jido_ai/reasoning/chain_of_thought/strategy.ex),
[delta Signal](../../../lib/jido_ai/signals/llm_delta.ex),
[request](../../../lib/jido_ai/request.ex),
[request stream](../../../lib/jido_ai/request/stream.ex),
[checkpoint](../../../lib/jido_ai/checkpoint.ex),
[Agent persistence wrapper](../../../lib/jido_ai/agent/definition.ex), and
[tool adapter](../../../lib/jido_ai/tool_adapter.ex).

Tests: [incomplete Agent response](../../../test/jido_ai/integration/react_incomplete_response_test.exs),
[runtime runner](../../../test/jido_ai/react/runtime_runner_test.exs),
[Turn](../../../test/jido_ai/turn_test.exs),
[delta schema](../../../test/jido_ai/signal_test.exs),
[ReAct](../../../test/jido_ai/strategy/react_test.exs),
[CoT](../../../test/jido_ai/strategy/chain_of_thought_test.exs), and
[checkpoint](../../../test/jido_ai/checkpoint_test.exs).

At the live-request simplification gate, rerun blank versus accepted-partial
responses, early tool activity, delta ordering and cleanup exits. At recovery,
rerun interrupted streams, custom persistence and fresh-runtime restore.
Keep the actual provider and core persistence paths in those cases.

## Explicit standalone State conversion: 2026-09-07

[14_09](../../../examples/14_resume/14_09_state_migration/README.md) converts portable
standalone State with caller-supplied phase, counts, domain and remaining time.
It proves real failure after a completed tool can restart without repeating it.
Unresolved or partial tool work requires reconciliation. Old v2 emits its model
checkpoint before filling pending tools, so the converter reads the assistant
history. These cases extend baseline standalone coverage. They do not satisfy
HIST-12's old Agent namespace, persisted sink or custom persistence requirements.


## Native request inspection evidence: 2026-09-07

[02_22](../../../examples/02_requests/02_22_request_inspection/README.md) adds 14 real
integration cases. The linked history rows gain partial evidence for raw
failure inspection, per-call thinking, completed tool results, correlated
trace prefixes and portable recovery. A durable lost completion reply retains
the saved answer and prefix. A cancellation race preserves live stream order.
The stored prefix and committed outcome are distinct; this is not a complete
durable journal or delivery receipt. Old Agent conversion and the remaining
CLI, context/skill, package and recovery gates stay open.


## Native context-operation evidence: 2026-09-07

[02_23](../../../examples/02_requests/02_23_context_operations/README.md) adds 28 cases
for real Agent context operations. The linked ledger references cover core
Thread request refs, pending-operation recovery, durable terminal application
and accepted-history compaction. The original skill call and result now replace
conflicting assistant/result copies. Typed ReqLLM calls are supported.
Actual LoadSkill/callback/catalog provenance and resource loading still need
the complete skill port. This evidence does not close those history rows or
the old Agent conversion and root package gates.
