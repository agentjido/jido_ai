# History review 08: public request streams and keepalives

Execution update, 2026-09-07:
[02_18](../../../examples/02_requests/02_18_admission/README.md) now checks rejection
events through live core Agents. Canonical method identity follows the declared
route, including custom paths and conflicting method/profile claims in input.
Raw errors and request IDs survive. Busy rejection closes only the new stream;
a duplicate ID cannot close the original request. This is partial PR 262/314
evidence. Durable delivery and the remaining runtime/package checks stay open.

Reviewed on 2026-09-06 against `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
This pass completes three more source reviews. The total is 70 of 126.
All v3 port checks remain pending. No runtime tests ran.

The review read all three complete diffs and associated PR discussion, plus
issue 257. Earlier PR 193 and issue 195 provide timeout context from before
the audit range. Their descriptions were read; this is not a full review of
their pre-release source changes.

## Commit dispositions

| Commit | Final requirement to retain | Required cases |
| --- | --- | --- |
| `80109dd1` / PR 262 | A caller can consume request events through `ask_stream` or a PID sink and still await the final result. Include rejection and worker-failure delivery. | HIST-07: public stream, mailbox sink, request isolation, consumer timeout, terminal failure |
| `f3a873d8` / PR 314 | One canonical runtime event struct includes injected input. Preserve legacy constructor delegates and incidental graph/type behavior. | HIST-07: canonical envelope; HIST-20: graph traversal, valid Agent state; RELEASE: event documentation, current type checks |
| `aae99061` / PR 308 | Optional tool-execution keepalives preserve both idle layers and unique monotonic event sequences. Thread the option through all supported request/runtime paths. | HIST-07: keepalive layers, keepalive order, keepalive options, keepalive cleanup |

## One public request example replaces private event wiring

[Issue 257](https://github.com/agentjido/jido_ai/issues/257) records a Discord
use case: send streamed text to another process while keeping Agent request
tracking and `ask/await`. The merged [PR 262](https://github.com/agentjido/jido_ai/pull/262)
adds both the enumerable and PID sink. PubSub and arbitrary sink adapters in
the issue are proposals; they were not implemented by this commit.

Use the catalog 05 Agent with the unified mock. The model selects one real
Action, receives its result, and returns a final answer. The consumer observes
the request through the public API. It must not inspect a private worker
mailbox or replace provider decoding to obtain the expected events.

| Variant | Required evidence |
| --- | --- |
| `HIST-07/public-stream` | `ask_stream` returns a request handle and enumerable. Consume real canonical events through model, tool and final result. All events belong to that request. The stream ends at the terminal event, and `await` returns the same completed result. Preserve supported per-request tools, model options, timeouts and refs. |
| `HIST-07/mailbox-sink` | `ask` accepts a PID or `{:pid, pid}` and sends the documented tagged messages to that process. Nil disables delivery. Invalid sinks fail before dispatch or provider work. A dead sink does not crash the Agent. Show a separate consumer using its own sink. |
| `HIST-07/request-isolation` | Interleave events for two request IDs in one mailbox. Each enumerable yields only its own events and leaves the other's events available. Stop after its first terminal event. A stale event cannot satisfy a later request. |
| `HIST-07/consumer-timeout` | Hold a real request with a short enumerable receive timeout and a longer execution budget. Enumeration ends without claiming completion or cancelling the work. Release the barrier; `await` still returns the result. Repeat with early consumer halt. Test explicit request cancellation separately. |
| `HIST-07/terminal-failure` | A busy rejection or actual worker crash reaches the public stream as a correlated terminal failure. The stream does not wait forever for a normal worker completion. Preserve the structured error and prior domain state. A later request succeeds. Include the cancellation/sink-release cases from review 07. |

The baseline enumerable reads the process mailbox where it is enumerated.
`ask_stream` chooses its caller as the sink. Passing that enumerable to another
process does not transfer the mailbox or existing events. Preserve the direct
PID-sink path and document how to select the consumer. Do not promise a
transferable or replayable stream without an explicit new transport design.

The baseline `Request.create_and_send` returns after a successful Server cast.
That is dispatch, not confirmed runtime admission; a later rejection can still
arrive. The v3 plan requires a clear admission boundary. Document the difference
and prove the chosen accepted-handle contract through a committed admission
Turn. Keep legacy dispatch behavior explicit in compatibility conversion.

The public enumerable defaults to an infinite receive timeout. A finite
`stream_event_timeout_ms` halts enumeration when idle; its cleanup function
does not cancel the request. The runner's own idle timeout can terminate work.
These are distinct even though PR 308 describes both as aborting a run.
Preserve actual behavior and keep wait/consumer/runner/tool/request deadlines
separate in the new controls.

PID delivery has no backpressure. The required migration examples must not
depend on an unimplemented durable queue, PubSub transport or replay buffer.
Use explicit bounded observers where the application requires them.

## HIST-07: one canonical event entity

[PR 314](https://github.com/agentjido/jido_ai/pull/314) fixes consumers that
match `Jido.AI.Runtime.Event` and miss ReAct's separate struct. Final ReAct
runner, worker forwarding and request-stream helpers use the canonical struct.
Its supported kinds now include `input_injected` and, after PR 308, `keepalive`.

For `HIST-07/canonical-envelope`, run both standalone ReAct and the live Agent
stream. Every normal, tool, output, injected-input and terminal event uses
`Jido.AI.Runtime.Event`. A consumer matching that struct must receive all
supported kinds. Validate required fields, reject invalid kinds, and retain
call/run/request correlation. Injected input must use the same envelope when
it reaches the next model request.

The old `ReAct.Event` module remains a deprecated delegate for `new/1`,
`schema/0` and `kinds/0`; its constructor returns the canonical struct. It no
longer declares a separate struct. Preserve that final source compatibility
or document an explicit removal decision. Do not restore two event entities.

Synthetic failures and cancellations currently default to `seq: 0`, with
`run_id` equal to the request ID unless supplied. They are not proof of one
monotonic cursor across every failure path. Define how the v3 emitter assigns
sequence to a terminal event after a run has already emitted events. A
pre-admission rejection can have a different lifecycle from an active run.

For `RELEASE/event-documentation`, compile or execute the shipped public
stream snippets in the fresh consumer. The target guide still matches the
removed `%Jido.AI.Reasoning.ReAct.Event{}` struct. Change those examples to the
supported canonical entity during migration. A successful library compile
does not prove that a copied guide example works.

## HIST-07: keepalives must reach the consumer without changing results

[PR 308](https://github.com/agentjido/jido_ai/pull/308) describes long-running
tools that produce no events while working. Its keepalive is optional:
`tool_heartbeat_ms: 0` is off; a positive value emits `:keepalive` with
`data.source: :tool_execution` during tool execution. This differs from
internal progress during provider input streaming.

| Variant | Required evidence |
| --- | --- |
| `HIST-07/keepalive-layers` | Block a real Action beyond both short idle limits, within its longer tool budget. Enable a shorter heartbeat interval. Both standalone runner and public `ask_stream` remain active and receive keepalives; release the tool and verify the final result. Internal progress messages alone cannot satisfy the public case. |
| `HIST-07/keepalive-order` | Across the entire normal run, sequence values are unique and increasing. Every keepalive falls after tool start and before post-tool events. Repeat with parallel tools, retries and multiple rounds. A tool result, injected input or final answer cannot reuse a heartbeat sequence. |
| `HIST-07/keepalive-options` | Test Agent defaults and request overrides through ask/ask_sync/ask_stream, plus standalone Start/Continue/Collect paths. An explicit zero disables an enabled default for one request. Omitted or invalid high-level overrides preserve the configured value. A later request retains the Agent default. No keepalive appears by default. |
| `HIST-07/keepalive-cleanup` | Complete, fail, time out and cancel real tool work. Owned timers/processes stop; no keepalive reaches the next request. Kill the coordinator during a barrier and verify cleanup through process monitors. An unresponsive provider outside tool execution still times out normally. A heartbeat does not extend the tool's execution deadline. |

The [first review](https://github.com/agentjido/jido_ai/pull/308#pullrequestreview-4431824911)
rejected reuse of a captured sequence number. The accepted follow-up uses a
separate heartbeat process during the runner's blocked tool window, then
reports its highest allocated number before the runner resumes. The
[later review](https://github.com/agentjido/jido_ai/pull/308#pullrequestreview-4540145150)
confirms unique sequence coverage and removal of the unrelated changelog edit.

The v3 runtime can use one owned event emitter instead of copying that manual
range handoff. Whichever implementation is selected must preserve the observed
event order, stop on cleanup, and keep portable counters separate from live
timer/process handles. Include a stop/cleanup failure case so a missing
handshake cannot silently reuse sequence numbers.

The old test uses a 500 ms Action and a 250 ms runner idle timeout. It proves
the runner case, but does not enumerate `Request.Stream.events` with a short
consumer timeout. The new public example must cover that second layer. Use a
barrier and a per-test event owner instead of global persistent counters.

Earlier [PR 193](https://github.com/agentjido/jido_ai/pull/193) and
[issue 195](https://github.com/agentjido/jido_ai/issues/195) explain the existing
timeout and large-input requirements. They precede this audit's release base.
Keep the supported automatic runner timeout (`tool_timeout_ms + 60_000` when
configured as zero) and its explicit/legacy alias inputs. This formula does
not include all retry/backoff time and is not a total request deadline.
The config fingerprint omits heartbeat and stream idle timeout; changing
those transient settings must follow the documented token compatibility rule.

## Incidental source changes also need evidence

The canonical-event commit also replaces GoT ancestor/descendant traversal
from a MapSet accumulator with a visited list and reverses the result. It
removes a redundant nil fallback for valid Agent state and adds dependency
Dialyzer exceptions. These changes are absent from the title's event claim.

- `HIST-20/graph-traversal`: retain all reachable ancestor/descendant IDs with
  no duplicates. Cover a diamond, disconnected node, root/leaf and a bounded
  cycle. Do not turn incidental MapSet enumeration order into a public sorting
  requirement. Use the real GoT helper and include a method example that depends
  on the correct graph context.
- `HIST-20/valid-agent-state`: prove normal Agent construction and supported
  restore produce a valid state map before simplified internal reads. Invalid
  imported state must fail at the declared boundary, not fail later during a
  request because a fallback disappeared.
- `RELEASE/current-type-checks`: run Dialyzer against the actual v3 dependency
  set. Retain only relevant, explained dependency exceptions. Do not copy old
  dependency file/line ignores merely to keep a clean report.

The existing GoT tests check ancestor/descendant membership and root/leaf
results. They were not changed in this commit. The migration must retain that
behavior even though the primary commit purpose was streaming.

## Baseline evidence and simplification gates

Source: [Agent stream helper](../../../lib/jido_ai/agent/definition.ex),
[request dispatch](../../../lib/jido_ai/request.ex),
[public enumerable](../../../lib/jido_ai/request/stream.ex),
[canonical event](../../../lib/jido_ai/runtime/event.ex),
[deprecated delegate](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/react/event.ex),
[runner](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/react/runner.ex),
[config](../../../lib/jido_ai/reasoning/react/config.ex),
[GoT traversal](../../../lib/jido_ai/reasoning/graph_of_thoughts/machine.ex), and
[current type exceptions](../../../dialyzer.ignore-warnings).

Tests: [request](../../../test/jido_ai/request_test.exs),
[Agent](../../../test/jido_ai/agent_test.exs),
[runner](../../../test/jido_ai/react/runtime_runner_test.exs),
[strategy](../../../test/jido_ai/strategy/react_test.exs),
[GoT machine](../../../test/jido_ai/graph_of_thoughts/machine_test.exs), and
[optional paid smoke](../../../test/jido_ai/live/request_stream_live_test.exs).

Retain the optional paid smoke separately from required mock-backed acceptance.
It is excluded by default and can skip without credentials, so it cannot close
the migration gate. Do not add paid calls to this preparation pass.

At the live-runtime simplification pass, prove one event entity/emitter, both
idle layers and public failure delivery. At the method and package passes,
recheck GoT traversal, valid state, guide snippets and current type checks.


## Native request inspection evidence: 2026-09-07

[02_22](../../../examples/02_requests/02_22_request_inspection/README.md) adds 14 real
integration cases. The linked history rows gain partial evidence for raw
failure inspection, per-call thinking, completed tool results, correlated
trace prefixes and portable recovery. A durable lost completion reply retains
the saved answer and prefix. A cancellation race preserves live stream order.
The stored prefix and committed outcome are distinct; this is not a complete
durable journal or delivery receipt. Old Agent conversion and the remaining
CLI, context/skill, package and recovery gates stay open.
