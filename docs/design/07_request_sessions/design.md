> Target seam design. This document is pending approval.

# Request orchestration and active input design

## Architecture and contract status

- Architecture category: [Request orchestration and active input](../ARCHITECTURE.md).
- Owning subsystem: Request, Orchestration and Coordinator, PendingInputServer, Thread.Control, and core Plugin integration.
- Complete target: Define one request contract across authored and standalone paths, plus advanced linked delegation, handoff, bounded active input, and explicit delivery/cancellation guarantees.
- Decision boundary: Resolve record/error semantics and cancellation replies before changing current API shapes. Define child/peer delegation as linked work above core topology, not a new Agent model.
- Current implementation, module links, example proof, and exact differences:
  [alignment](alignment.md). This design is a target, not an API reference.

The requirements and proposed signatures below remain pending approval.
Illustrative types are not evidence that a module or function exists. A
requirement is not removed merely because the current implementation differs.
Use the alignment matrix to distinguish current behavior from the full target.

## Selected request and attempt meanings

User-selected on 2026-09-15. Keep the logical request ID on retry/resume;
create a new execution attempt ID for each restarted or resumed execution.
Preserve prior attempt outcomes. ReAct run_id alone is not a unique attempt
ID. No new struct or wire-field name is selected by this decision.

Distinguish execution failure (model/tool/method/timeout/worker), commit
failure, delivery failure, uncertain outcome, cancellation, and superseded
attempt. A failed attempt does not necessarily fail its logical request.
Delivery failure does not change the committed outcome. Cancellation closes
the request but cannot prove that external effects stopped.

Recommended delegation link: originating request/attempt, delegated request,
and target Agent. This is separate from core child/peer topology. Parent policy
applies before parent Thread commit. Late or superseded results cannot replace
committed outcomes. Peer cancellation targets selected work; core owns child
lifecycle. Existing duplicate/late rejection policy remains in force.

The [uncertain-effect rule](../11_checkpoints_resume/design.md#selected-attempt-and-retry-policy)
blocks automatic retry without evidence, supported deduplication, or explicit
caller authority. These are meaning and policy decisions, not approval of
this document or a new runtime framework.

## Selected conversation commit policy

User-selected on 2026-09-15: retain execution evidence in the canonical log,
but advance the default model conversation only after successful settlement.
This selects the Jidoka pattern, not its runtime or named-document approval.

`SES-REQ-043`: The Orchestration Coordinator shall retain admitted input, consumed steering input, and committed intermediate work in the canonical Session/Thread log for evidence and recovery.

`SES-REQ-044`: When request settlement succeeds, the Orchestration Coordinator shall advance the completed conversation used by the default model projection.

`SES-REQ-045`: If a request fails or is cancelled, then the Orchestration Coordinator shall leave the completed conversation unchanged.

`SES-REQ-046`: While steering input remains queued and unconsumed, the Orchestration Coordinator shall exclude it from conversation history.

`SES-REQ-047`: While a linked parent request is active, when a new delegated result is accepted, the parent Orchestration Coordinator shall append that result once to the parent Thread through core commit APIs.

`SES-REQ-048`: If a delegated result is duplicate or arrives after parent settlement, then the parent Orchestration Coordinator shall reject it.

Core retains topology, child lifecycle, validation, and commit ownership.
Preserve Agent + DSL + Profile, native ReqLLM contracts, all eight methods,
and advanced capabilities. Promotion metadata and receipt schemas remain open.

## Proposed data boundary

This recommendation applies the [data-focused direction](../00_boundary_invariants/design.md#selected-direction-data-focused-foundation).
It is not an approved adapter API or implementation plan.

Use one concrete private request-scoped adapter with tagged, validated data
carrying request_id/run_id. Execution facts go out; control decisions return.

| Proposed category | Data |
| --- | --- |
| Progress | Activity, method position, inspection, usage increments |
| Entries | Stable entry batch defined in seam 01 |
| Execution boundary | Position, optional checkpoint snapshot, ability to finish |
| Outcome | Result/error, metadata, effect plan |

Use distinct accepted, committed, rejected, and commit-unknown replies. Receipt
does not mean commit. A checkpoint acknowledgment does not prove durable
storage. Preserve current wait-for-entry-commit behavior unless an explicit
decision changes it; no retry follows an unknown commit result.

Orchestration owns request lifetime, pending-input order/queue, entry commit
coordination, checkpoint coordination, and settlement. Coordinator keeps
process lifetime and ordered commit work together. Core validates and commits.

[EntryBatch and CommitReceipt](../01_ai_values/design.md#proposed-entry-batch-and-receipt-values)
supply proposed identity and order data. Safe execution positions belong to
Runtime. Combining input and checkpoint control at those positions remains
open, as do exact tags, validation, reply compatibility, conflict handling,
and durable recovery semantics. This is not a generic framework or event store.

## Content permission constraint

Apply the [selected content permissions](../12_observation_diagnostics/design.md#selected-content-permissions).
Retained evidence does not authorize rich-content or reasoning storage.
Storage needs its own permission; stream permission is insufficient. Preserve
permitted identity, ordering, outcomes, and bounded metadata without forbidden
payloads. Redacted data does not imply sufficient recovery input; resolve that
case explicitly rather than reconstructing missing content. Native ReqLLM
execution data remains unchanged.

## Scope and owner

- Owner: `Jido.AI.Request`, `Jido.AI.Orchestration`, request record Actions, Orchestration Plugin runtime, pending-input behavior, and public request convenience calls.
- In scope: Request IDs, handles, committed records, admission, Turn and session modes, await, stream, sync, cancellation, steering, injection, settlement, retention, and inspection.
- Out of scope: Generic job queues, private AgentServer protocols, durable workflows, model and tool semantics, provider transports, and durable event logs.

## V2 capability anchor

V2 supplied `ask`, `ask_sync`, request handles, await, streams, cancellation, steering, per-request options, busy policy, correlation, and standalone ReAct. V3 keeps this public experience but uses core AgentServer calls, Plugin admission, committed request records, post-commit session work, and the shared AI Flow.

| V2 capability | V3 target |
| --- | --- |
| Request handle with server identity | Explicit local-only handle plus portable committed record |
| Strategy busy state | Orchestration Plugin admission and one committed pending record |
| Worker start during request | Post-commit session Directive dispatch |
| Worker completion callback | Correlated public settlement command and Turn |
| Stream sink in request data | Process-local sink owned by Orchestration Coordinator |
| Steering mailbox | Bounded correlated control queue at approved operation points |
| Standalone runner | Thin local session facade over the same Agent and Flow contracts |

## Model

Profiles select one of two modes.

### Turn mode

One admitted query Signal resolves to the canonical AI Flow. Model and tool I/O complete before the Turn returns. Core Jido validates and commits one final candidate. Turn mode has no long-lived AI Orchestration Coordinator and does not provide live steering.

### Session mode

The request lifecycle is:

```mermaid
stateDiagram-v2
    [*] --> Admitted: admission Turn commits
    Admitted --> Active: start-work Directive dispatches
    Active --> WaitingInput: method requests control input
    WaitingInput --> Active: accepted steering input
    Active --> Completed: settlement Turn commits result
    Active --> Failed: settlement Turn commits error
    Active --> Cancelled: cancel Turn commits first
    WaitingInput --> Cancelled: cancel Turn commits first
    Admitted --> Failed: runtime start failure settles
    Completed --> [*]
    Failed --> [*]
    Cancelled --> [*]
```

The committed `Orchestration.Record` uses stable terminal status values. `Active` and `WaitingInput` are live inspection states unless the Agent commits a specific progress snapshot. The Orchestration Coordinator owns live tasks, Exec handles, stream sinks, control queues, and transient completions.

The public `Request.Handle` is local-only because it contains an AgentServer reference. It is not stored in Agent state or encoded. The portable request record contains IDs, query, profile and method IDs, status, terminal result or error, timestamps, bounded metadata, and retention policy.

## Requirements

### Admission and identity

`SES-REQ-001`: Every AI request shall have a nonempty request ID and run ID before admission commits.

`SES-REQ-002`: A request ID shall identify the logical request and a run ID shall identify one live execution attempt.

`SES-REQ-003`: When the same request ID already exists in retained Agent state, admission shall reject the request as a duplicate.

`SES-REQ-004`: For the first V3 release, session admission shall reject a new request while another request record is pending for the same Agent.

`SES-REQ-005`: `ask/3` shall return a handle only after the admission candidate and request record commit successfully.

`SES-REQ-006`: Untrusted request input shall not set a runtime stream sink, provider client, credential, or transport option.

### Request modes

`SES-REQ-007`: Turn mode shall execute the canonical AI Flow inside one core Turn and shall return only after the final candidate commits or the Turn fails.

`SES-REQ-008`: Session mode shall commit admission before it starts model or tool work.

`SES-REQ-009`: Session mode shall start live work only from a validated post-commit Directive owned by the Orchestration Plugin.

`SES-REQ-010`: Turn and session modes shall use the same effective profile, model gateway, tool bridge, reasoning method, limits, output validation, and result contract.

### Records and settlement

`SES-REQ-011`: A committed request record shall be portable and shall not contain a server reference, PID, task, monitor, stream sink, provider object, or Exec handle.

`SES-REQ-012`: The Orchestration Plugin shall own request records under one declared Agent state key.

`SES-REQ-013`: The Orchestration Coordinator shall match settlement to the logical request and active execution attempt and reject stale or duplicate settlement.

`SES-REQ-014`: A successful settlement shall assemble the complete candidate Agent, update the declared result and history fields, update the request record, and return approved Directives in one Turn result.

`SES-REQ-015`: A failed settlement shall preserve the prior domain state except for the terminal request record and approved failure metadata.

`SES-REQ-016`: A committed request outcome shall be authoritative even if a later terminal stream item cannot be delivered.

`SES-REQ-017`: Request retention shall never evict pending work and shall use a deterministic order for terminal record eviction.

### Await and stream

`SES-REQ-018`: `await/2` shall use public AgentServer or session APIs and shall select the record by request ID.

`SES-REQ-019`: An await timeout shall not change the committed request status or cancel the request unless the caller explicitly requests cancellation.

`SES-REQ-020`: A request stream shall be an ordered best-effort live view and shall not be described as a durable event log.

`SES-REQ-021`: A request stream shall contain exactly one terminal item when its sink remains available through termination.

`SES-REQ-022`: If a stream sink terminates, the request shall continue unless profile policy explicitly requires stream ownership.

### Cancellation and active input

`SES-REQ-023`: A cancellation request shall name a request ID or resolve unambiguously to the single pending request.

`SES-REQ-024`: If cancellation commits before settlement, the record shall become `:cancelled`, pending continuations shall stop, and later settlement shall be stale.

`SES-REQ-025`: If settlement commits before cancellation, cancellation shall return `:request_already_finished` and shall not replace the terminal result.

`SES-REQ-026`: The cancellation contract shall state that it cannot roll back a model call, tool call, or other external effect that completed before cancellation.

`SES-REQ-027`: Steering and injection shall be available only for a method and profile that declare active-input support.

`SES-REQ-028`: A control item shall include a control ID, kind, visible content, expected request ID, source, and bounded references.

`SES-REQ-029`: A control acknowledgement shall state whether the item was queued, rejected, or applied; a queued result shall not claim consumption.

`SES-REQ-030`: The live control queue shall be bounded and shall not be stored as a generic Agent mailbox.

### Standalone use and inspection

`SES-REQ-031`: Standalone request APIs shall use the same public Agent, Plugin, Flow, Exec, and request contracts as authored Agents.

`SES-REQ-032`: A standalone facade shall own and stop any local AgentServer that it creates.

`SES-REQ-033`: Session inspection shall separate the committed request record from transient live samples.

`SES-REQ-034`: Inspection shall bound trace and metadata size and shall mark truncated data.

### Delegation and topology

These are retained advanced target requirements, not implemented API claims.
Core Jido owns topology and child lifecycle. A topology relationship is distinct
from the relationship between delegating and delegated requests.

`SES-REQ-035`: When an Agent delegates work, Orchestration shall correlate the delegated request with its originating request and target Agent identity.

`SES-REQ-036`: When Orchestration sends delegated work, it shall transfer only context selected by the configured delegation policy.

`SES-REQ-037`: When a delegated result arrives, the originating Orchestration shall apply the parent request policy before proposing a parent Thread update.

`SES-REQ-038`: If the parent request is terminal when a delegated result arrives, then Orchestration shall apply an explicit late-result policy without silently replacing the committed outcome.

`SES-REQ-039`: When a caller cancels delegated work on a peer, Orchestration shall cancel only the selected work unless the host separately authorizes stopping that Agent.

`SES-REQ-040`: Where delegation is enabled, Orchestration shall validate finite depth, concurrency, and request-budget limits before admitting delegated work.

`SES-REQ-041`: When a host authorizes a handoff, Orchestration shall record which request owner is responsible for subsequent completion and cancellation.

`SES-REQ-042`: When Orchestration emits a delegation lifecycle event, it shall include the parent and delegated request identities through seam 12's observation contract.

Fan-out collection policy, target resolution, handoff authority, shared budget
accounting, and recovery semantics remain decisions. Model-facing adaptation is
owned by 03; topology integration by 06; recovery by 11; observation by 12.
No new transport, supervisor, or delegation module is selected here.

## Public contract

Recommended local handle:

```elixir
%Jido.AI.Request.Handle{
  id: String.t(),
  run_id: String.t(),
  server: Jido.AgentServer.server(),
  profile_id: atom()
}
```

The handle is explicitly local-only. Recommended portable record:

```elixir
%Jido.AI.Orchestration.Record{
  id: String.t(),
  run_id: String.t(),
  profile_id: atom(),
  method: atom(),
  query: Jido.AI.Query.t(),
  status: :pending | :completed | :failed | :cancelled | :interrupted,
  result: term() | nil,
  error: Jido.AI.Error.t() | nil,
  inserted_at: integer(),
  completed_at: integer() | nil,
  metadata: map()
}
```

Candidate target API, not the current callable API. In particular, cancellation
reply shape and terminal status vocabulary need the decisions in alignment.
Use current source for executable examples:

```elixir
AgentModule.ask(server, query, opts \\ []) ::
  {:ok, Request.Handle.t()} | {:error, Jido.AI.Error.t()}

AgentModule.ask_stream(server, query, opts \\ []) ::
  {:ok, %{request: Request.Handle.t(), events: Enumerable.t()}} |
  {:error, Jido.AI.Error.t()}

AgentModule.ask_sync(server, query, opts \\ []) ::
  {:ok, term()} | {:error, Jido.AI.Error.t()}

Jido.AI.Request.await(handle, opts \\ []) ::
  {:ok, term()} | {:error, term()}

Jido.AI.Orchestration.cancel(handle_or_server, opts \\ []) ::
  {:ok, :cancelled} | {:error, term()}

Jido.AI.Orchestration.steer(handle_or_server, content, opts \\ []) ::
  {:ok, Jido.AI.ControlAck.t()} | {:error, term()}
```

## Invariants

- `SES-INV-001`: A request ID identifies one logical request; a run ID identifies one execution attempt.
- `SES-INV-002`: A session starts live work only after admission commit.
- `SES-INV-003`: One Agent has at most one pending AI session in the first V3 release.
- `SES-INV-004`: A request record is portable; a request handle is local-only.
- `SES-INV-005`: Settlement and cancellation are correlated and stale-safe.
- `SES-INV-006`: A committed result is authoritative over live stream delivery.
- `SES-INV-007`: Steering is bounded AI control, not a generic mailbox.
- `SES-INV-008`: Standalone use does not have a separate AI execution engine.

## Downstream guarantees

| Consumer seam | Guaranteed contract |
| --- | --- |
| 08 Capabilities | Stable admission, request state, controls, and settlement hooks |
| 09 Skills | Request-scoped activation and runtime lifetime |
| 10 Authoring | Stable `:turn` and `:session` profile modes and generated calls |
| 11 Checkpoints | Portable request records and explicit active-run semantics |
| 12 Observation | Stable request and run correlation and terminal states |
| 90 Delivery | Public V2 request experience with V3 runtime ownership |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `SES-DEC-001` | How many sessions can be pending per Agent? | One for the first V3 release | Keeps Plugin state and steering deterministic |
| `SES-DEC-002` | Is the request handle portable? | No | Keeps process identity out of data contracts |
| `SES-DEC-003` | Does await timeout cancel work? | No | Separates caller patience from request policy |
| `SES-DEC-004` | What wins a cancellation race? | The first committed terminal transition | Uses core commit as the authority |
| `SES-DEC-005` | Is the event stream durable? | No | Keeps durable event delivery outside Jido AI |
