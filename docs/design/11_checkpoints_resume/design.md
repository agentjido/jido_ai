> Target seam design. This document is pending approval.

# Checkpoints and resume design

## Architecture and contract status

- Architecture category: [Checkpoints and resume](../ARCHITECTURE.md).
- Owning subsystem: Execution.Checkpoint, standalone ReAct Checkpoint/State/Token, and Orchestration recovery integration.
- Complete target: Preserve advanced atomic resource restoration, linked resume identity, no-repeat completed work, bounded codecs, and uncertain-effect decisions. Storage and durable deduplication services remain host concerns.
- Decision boundary: Decide new-run lineage, effect identity, and atomic binding restoration without assuming exactly-once effects or extending resume to all methods automatically.
- Current implementation, module links, example proof, and exact differences:
  [alignment](alignment.md). This design is a target, not an API reference.

The requirements and proposed signatures below remain pending approval.
Illustrative types are not evidence that a module or function exists. A
requirement is not removed merely because the current implementation differs.
Use the alignment matrix to distinguish current behavior from the full target.

## Proposed batch and boundary recovery contract

The [private request boundary](../07_request_sessions/design.md#proposed-data-boundary)
separates receipt, commit, and checkpoint acknowledgment. Stable batch and
entry IDs can link commits, snapshots, and recovery, but do not prove durable
deduplication or exactly-once behavior. An unknown commit result is not
permission to retry.

Runtime identifies safe positions; Orchestration coordinates checkpoint
handling and request lifetime; core owns validation and commit. Durable
storage remains host-owned. Sharing pending-input and checkpoint control at
safe positions remains a proposal. Recovery lookup, duplicate handling,
snapshot/batch consistency, and durability evidence need explicit contracts.
Preserve standalone ReAct token behavior and retained advanced recovery work.

## Recovery versus completed context

Under the [selected commit policy](../07_request_sessions/design.md#selected-context-commit-policy),
active, failed, or cancelled work can remain recovery evidence without
advancing the completed context. Resume evidence and default model input
are different views of the same canonical log. Recovery does not imply
successful settlement. Exact snapshot/promotion references remain open.

## Selected attempt and retry policy

The [request identity decision](../07_request_sessions/design.md#selected-request-and-attempt-meanings)
separates logical requests from execution attempts. The former requirement for
a new run_id is replaced by a new attempt identity; current ReAct run_id can
remain an adapter value. Exact representation and migration remain open.

`RES-REQ-030`: When execution restarts or resumes, Orchestration shall retain the logical request ID and assign a new execution attempt ID.

`RES-REQ-031`: Orchestration shall preserve prior execution attempt outcomes.

`RES-REQ-032`: If an external effect is uncertain, then the retry or resume owner shall block automatic repetition until evidence proves no effect occurred, a supported deduplication guarantee makes retry safe, or the caller explicitly authorizes repetition.

Cancellation is not proof of effect termination. An uncertain core commit
remains subject to the existing no-retry rule; external-effect permission does
not imply permission to repeat an unknown Agent commit. Preserve native ReqLLM,
canonical Session/Thread, all methods, and advanced recovery capabilities.
No new structs or named-document approval are selected.

## Content permission constraint

Apply the [selected content permissions](../12_observation_diagnostics/design.md#selected-content-permissions).
Retained evidence does not authorize rich-content or reasoning storage.
Storage needs its own permission; stream permission is insufficient. Preserve
permitted identity, ordering, outcomes, and bounded metadata without forbidden
payloads. Redacted data does not imply sufficient recovery input; resolve that
case explicitly rather than reconstructing missing content. Native ReqLLM
execution data remains unchanged.

## Unresolved Session activation restart policy

[Session-scoped activation](../09_skills_resources/design.md#selected-resource-and-activation-ownership)
survives ordinary request completion, cancellation, and worker failure.
Survival across AgentServer/resource-owner restart is not decided. Do not
assume activation restoration or clearing from the retained checkpoint targets.
The preliminary rebuild-and-clear proposal is not an approved recovery policy.

## Scope and owner

- Owner: Jido AI checkpoint helpers, ReAct checkpoint and token values, resume validation, and generated Agent checkpoint integration. Core Jido owns Agent checkpoints and persistence.
- In scope: Portable AI progress data, strict versioning, sanitization, active-session normalization, skill and model bindings, completed-effect records, explicit resume, and delivery guarantees.
- Out of scope: Persistence adapters, live Exec state, process restore, provider clients, durable queues, distributed recovery, rollback, and exactly-once execution.

## V2 capability anchor

V2 supplied Agent checkpoint helpers, ReAct continuation tokens, sanitization of process-local values, and resume behavior. V3 keeps portable AI resume data but places Agent identity, version, state checkpointing, optimistic revision, storage, and restore in core Jido.

| V2 capability | V3 target |
| --- | --- |
| Jido AI Agent checkpoint | Core `Jido.Agent.checkpoint/2` and `restore/3` |
| Strategy continuation token | Versioned AI method checkpoint with no live executor |
| Sanitized worker fields | No worker fields in portable state; reject unsupported data |
| Resume old worker | Start a new Flow execution with a new run ID |
| Checkpoint storage | Core `Jido.Persistence` and host adapter |
| Active stream restore | Mark interrupted; attach a new sink only to a new run |

## Model

There are two different artifacts.

### Core Agent checkpoint

Core Jido owns the envelope, Agent module, Agent version, identity, complete Agent state, callback, encoding validation, persistence revision, and restore. Jido AI can participate through generated or user-composed Agent checkpoint and restore callbacks, but it does not replace the envelope.

### AI execution checkpoint

An optional AI execution checkpoint is portable method progress:

```elixir
%Jido.AI.Checkpoint{
  version: pos_integer(),
  profile_id: atom(),
  method: atom(),
  request_id: String.t(),
  run_id: String.t(),
  phase: atom(),
  context: Jido.Session.t(),
  method_state: map(),
  result_state: map(),
  completed_calls: [map()],
  effects: [map()],
  remaining_limits: map(),
  bindings: map(),
  metadata: map()
}
```

The checkpoint records semantic progress only. It never records `%Jido.Exec{}` state, compiled Runic state, PID, task, monitor, stream, anonymous function, provider client, open file, timer, or credential.

Restore and resume are separate operations:

1. Core restore creates a valid Agent value from a stored Agent checkpoint.
2. Jido AI restore normalization marks a pending session with no matching live runtime as `:interrupted`.
3. An explicit resume request validates the AI checkpoint, rebinds trusted resources, assigns a new run ID, and starts a new Flow execution.

Completed external effects have at-least-once uncertainty. If an external effect completed but the checkpoint was not stored after that completion, resume can repeat it. Tool idempotency keys and host compensation policy are the only protections.

## Requirements

### Core ownership

`RES-REQ-001`: Jido AI Agent persistence shall use `Jido.Agent.checkpoint/2`, `Jido.Agent.restore/3`, and `Jido.Persistence` public contracts.

`RES-REQ-002`: Jido AI shall not define a competing Agent checkpoint envelope, persistence adapter, revision scheme, or restore supervisor.

`RES-REQ-003`: A generated AI Agent checkpoint callback shall compose with the core default checkpoint and shall preserve Agent module, version, identity, and complete portable state.

`RES-REQ-004`: A Jido AI restore callback shall return a fully validated Agent of the requested module and version through the core restore contract.

### Portable AI progress

`RES-REQ-005`: An AI execution checkpoint shall have a type and version and shall contain only portable semantic data.

`RES-REQ-006`: An AI execution checkpoint shall identify profile, method, request, original run, phase, context, method state, result state, remaining limits, completed calls, effects, and required binding references.

`RES-REQ-007`: Checkpoint creation shall reject a live Exec state, compiled workflow, PID, task, monitor, stream sink, function, client, secret, or unsupported struct.

`RES-REQ-008`: A checkpoint shall store stable registry references for executable modules, schemas, skills, and provider-independent models instead of live values.

`RES-REQ-009`: Remaining limits shall never be greater than the limits of the original request.

`RES-REQ-010`: Completed tool calls shall keep their call ID, tool identity, portable result, effect identity, and idempotency metadata.

### Active session checkpoint and restore

`RES-REQ-011`: A core Agent checkpoint can contain a pending request record, but it shall not claim that the matching live session task is saved.

`RES-REQ-012`: When an Agent restores with a pending request and no live runtime ownership, Jido AI shall normalize the record to `:interrupted` before new request admission.

`RES-REQ-013`: Restore shall not start a model call, tool call, Flow, stream, or session automatically unless the host explicitly selects an approved auto-resume policy.

`RES-REQ-014`: A restored stream sink shall always be absent; a resumed caller shall attach a new sink to the new run.

`RES-REQ-015`: A restored runtime resource shall be re-resolved from trusted host context and shall never be taken from checkpoint data.

### Explicit resume

`RES-REQ-016`: Resume shall validate Agent identity, Agent version, AI checkpoint version, profile ID, method compatibility, skill versions, registry references, and remaining limits before work starts.

`RES-REQ-017`: Resume shall retain the logical request ID and create a new execution attempt ID.

`RES-REQ-018`: Resume shall create a new canonical Flow execution and shall not reconstruct a live Exec or Runic state.

`RES-REQ-019`: Resume shall not repeat a completed model or tool step when its complete portable result is present and accepted by the method contract.

`RES-REQ-020`: If a required prior result is absent or incompatible, resume shall fail or restart from an explicitly approved safe phase; it shall not guess.

`RES-REQ-021`: Resume shall report the previous and new execution attempt IDs, resumed phase, skipped completed work, and delivery-risk metadata.

### Delivery and idempotency

`RES-REQ-022`: The public resume contract shall state that external effects are not exactly once.

`RES-REQ-023`: When a tool declares idempotency support, Jido AI shall reuse its stable effect or call idempotency key on resume.

`RES-REQ-024`: When a non-idempotent completed effect has uncertain checkpoint status, resume shall require an explicit host decision or return a blocked-resume error.

`RES-REQ-025`: Checkpoint success shall not imply that later Signal delivery, stream delivery, or external side effects are durable.

### Versions

`RES-REQ-026`: An AI checkpoint decoder shall accept only the current V3 version and shall reject every other version.

`RES-REQ-027`: A checkpoint without an explicit current version shall fail before restore or resume work starts.

`RES-REQ-028`: Jido AI shall not import V2 Agent, Strategy, session, or ReAct checkpoint formats.

`RES-REQ-029`: A failed decode or validation shall not modify the stored source checkpoint.

## Public contract

Core operations remain authoritative:

```elixir
Jido.Agent.checkpoint(agent, context \\ %{}) :: {:ok, map()} | {:error, term()}
Jido.Agent.restore(agent_module, checkpoint, context \\ %{}) ::
  {:ok, Jido.Agent.t()} | {:error, term()}
```

Recommended Jido AI operations:

```elixir
Jido.AI.Checkpoint.new(attrs) ::
  {:ok, Jido.AI.Checkpoint.t()} | {:error, Jido.AI.Error.t()}

Jido.AI.Checkpoint.sanitize(agent_or_progress) ::
  {:ok, map()} | {:error, Jido.AI.Error.t()}

Jido.AI.Resume.prepare(agent, checkpoint, bindings, opts \\ []) ::
  {:ok, Jido.AI.Execution.Input.t()} | {:error, Jido.AI.Error.t()}

Jido.AI.Resume.start(server, checkpoint, opts \\ []) ::
  {:ok, Jido.AI.Request.Handle.t()} | {:error, Jido.AI.Error.t()}
```

`Resume.start/3` is explicit session admission. It does not run during core Agent restore by default.

## Invariants

- `RES-INV-001`: Core Jido owns Agent checkpoint envelopes and persistence.
- `RES-INV-002`: An AI checkpoint contains semantic data, not live execution state.
- `RES-INV-003`: Restore does not silently restart external work.
- `RES-INV-004`: Resume always creates a new run ID and a new Flow execution.
- `RES-INV-005`: Remaining limits never increase during resume.
- `RES-INV-006`: Runtime resources are re-resolved from trusted context.
- `RES-INV-007`: External effects have no exactly-once guarantee from Jido AI.
- `RES-INV-008`: Failed decode or validation leaves the source unchanged.

## Downstream guarantees

| Consumer seam | Guaranteed contract |
| --- | --- |
| 12 Observation | Original and resumed run correlation plus delivery-risk metadata |
| 90 Delivery | One current V3 checkpoint format and explicit removals |
| Host persistence | Portable Agent and AI data with no live resource |
| Host orchestration | Explicit resume input and external-effect risk data |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `RES-DEC-001` | Does core restore auto-resume pending AI work? | No | Prevents unexpected external effects during process start |
| `RES-DEC-002` | What is the external-effect guarantee? | At-least-once uncertainty with explicit idempotency support | States the real boundary |
| `RES-DEC-003` | Is V2 checkpoint import required for V3.0? | No | Keeps one checkpoint contract |
| `RES-DEC-004` | How long are AI checkpoint versions supported? | Current version only until a new policy is approved | Prevents implicit format support |
