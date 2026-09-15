> Target seam design. This document is pending approval.

# Package boundary and invariants design

## Architecture and contract status

- Architecture category: [Package boundary and invariants](../ARCHITECTURE.md).
- Owning subsystem: Jido.AI package boundary; core Jido, jido_action, jido_signal, and host interfaces.
- Complete target: Preserve the complete AI capability set above public lower-package contracts. Separate in-memory coordination from host-owned durability and external-effect guarantees.
- Decision boundary: Confirm the retry-delay boundary and the external-effect contract before changing execution mechanics. Release metadata is separate delivery work.
- Current implementation, module links, example proof, and exact differences:
  [alignment](alignment.md). This design is a target, not an API reference.

The requirements and proposed signatures below remain pending approval.
Illustrative types are not evidence that a module or function exists. A
requirement is not removed merely because the current implementation differs.
Use the alignment matrix to distinguish current behavior from the full target.

## Selected direction: data-focused foundation

User direction recorded on 2026-09-15: validated data, stable identity, explicit
order, and explicit state changes form the foundation. Processes and adapters
apply those contracts. This does not approve any named document.

Preserve all advanced capabilities, all eight reasoning methods, canonical
Session/Thread/Entry in this package, Agent + DSL + Profile, native ReqLLM
contracts, and core Jido topology, validation, and commit ownership.
The [request boundary proposal](../07_request_sessions/design.md#proposed-data-boundary)
applies this direction without a new generic framework, public execution
model, duplicate conversation store, or event store.

## Scope and owner

- Owner: Jido AI maintainers. Shared package boundaries require review from the owner of the affected package.
- In scope: Jido AI package ownership, dependency direction, stable terms, portable data, runtime resources, effect timing, and boundary checks.
- Out of scope: AI feature behavior, provider behavior, implementation phases, compatibility shims, and durable orchestration design.

## V2 capability anchor

V2 proved that one package can provide model integration, tool use, reasoning, requests, Plugins, Signals, skills, and observation. V3 retains these AI capabilities. V3 replaces the V2 Strategy runtime, worker ownership, state operations, and in-Turn execution Directives with the public contracts of the V3 packages.

| V2 concept | V3 expression |
| --- | --- |
| AI Agent and Strategy | Core `Jido.Agent` plus AI Profile, Actions, Flow, and Plugins |
| Strategy state update | Complete candidate Agent returned through a core Turn |
| LLM and tool execution Directives | AI Actions and `Jido.Flow` before commit |
| Worker and TaskSupervisor | `Jido.Exec` or an optional core Plugin runtime |
| AI event struct and dispatcher | Typed AI data in `Jido.Signal` and public Signal dispatch |
| Checkpointed runtime | Core Agent checkpoint plus portable AI resume data |

## Model

The dependency direction is:

```text
jido_action -> jido -> jido_ai -> host application
jido_signal -> jido
jido_action -> jido_ai
jido_signal -> jido_ai
```

`jido_ai` can depend directly on the public contracts of `jido_action`, `jido_signal`, and `jido`. No lower package can depend on `jido_ai`.

The boundary uses these terms:

- **Definition:** Portable static data that describes an Agent, AI profile, Action, Flow, Plugin options, or route.
- **Runtime binding:** A process-local resource, such as a provider client, store handle, or supervised runtime reference.
- **Turn request:** One Signal that resolves to one Action or Flow and produces one candidate Agent plus Directives.
- **AI request:** Correlated model and tool work with one terminal AI result. It can run in Turn mode or session mode.
- **Effect:** A declared change or external operation caused by AI work.
- **Checkpoint:** Portable state that can be validated without a live process.

Effect timing has three phases:

1. An Action or Flow can perform synchronous I/O before it returns a candidate.
2. Core Jido validates and commits the candidate.
3. Core Jido dispatches approved Directives and Plugin runtime work after commit.

Synchronous I/O before commit is not transactional. Jido AI does not claim rollback when candidate validation or commit fails.

## Requirements

### Package ownership

`BND-REQ-001`: The Jido AI package shall own only model-provider integration, AI data, AI reasoning, AI tool policy, AI request policy, AI capability policy, AI skill behavior, AI resume data, and AI observation semantics.

`BND-REQ-002`: The Jido AI package shall use `Jido.Action`, `Jido.Instruction`, `Jido.Flow`, and `Jido.Exec` as the only public computation and in-memory execution contracts.

`BND-REQ-003`: The Jido AI package shall use core `Jido.Agent`, Turn, Plugin, Directive, commit, AgentServer, checkpoint, and OTP runtime contracts without a competing implementation.

`BND-REQ-004`: The Jido AI package shall use `Jido.Signal` as the only Signal envelope and shall use public Signal routing, dispatch, and bus contracts.

`BND-REQ-005`: The Jido AI package shall consume browser functions only as Actions or explicit adapters owned by `jido_browser`.

`BND-REQ-006`: The host application shall own credentials, provider-client supervision, application stores, durable queues, deployment, distribution, domain tools, and product policy.

### Portable and runtime data

`BND-REQ-007`: When Jido AI accepts static definition data, it shall reject a process, port, reference, task, monitor, anonymous function, or other nonportable runtime value unless the public contract explicitly identifies a local-only field.

`BND-REQ-008`: When Jido AI needs a runtime resource, it shall resolve that resource from the caller context, Plugin runtime, or an explicit host registry after definition validation.

`BND-REQ-009`: Jido AI shall not store credentials or live runtime handles in Agent domain state, Plugin state, Signals, codecs, or checkpoints.

### Turn and effect semantics

`BND-REQ-010`: When AI work runs as a core Turn, it shall return a complete candidate Agent and validated Directives through the public Turn result contract.

`BND-REQ-011`: Jido AI shall not mutate private AgentServer state or dispatch post-commit work before core commit succeeds.

`BND-REQ-012`: When an Action or Flow performs external I/O before commit, the public contract shall state that rollback is not available and shall identify any idempotency requirement.

`BND-REQ-013`: When the same admitted command uses direct and live core execution, Jido AI shall preserve the same AI validation, Flow, candidate, and Directive semantics, except for behavior that requires an explicitly declared live runtime.

### Durability and compatibility

`BND-REQ-014`: Jido AI shall not describe `Jido.Exec` state, Flow step state, or an AI session process as a durable checkpoint.

`BND-REQ-015`: When durable orchestration is required, Jido AI shall expose portable commands, results, events, and resume data for a host-owned or separately owned orchestrator.

`BND-REQ-016`: V3 integration tests shall use compatible V3 package versions unless a test explicitly verifies V2 migration or compatibility.

## Public contract

The public package contract is the following ownership matrix:

| Contract | Owner |
| --- | --- |
| Action, Instruction, Flow, Exec, local continuation | `jido_action` |
| Signal envelope, serialization, routing, dispatch, local bus | `jido_signal` |
| Agent, Turn, candidate, commit, Plugin, Directive, AgentServer, core checkpoint | `jido` |
| Model gateway, AI values, tool bridge, reasoning, request policy, AI Plugins, skills, AI resume data, AI observation | `jido_ai` |
| Browser adapters and browser Actions | `jido_browser` |
| Credentials, clients, durable services, application domain, deployment, distributed work | Host application or a separate owning package |

A boundary conformance check shall reject code that requires private AgentServer state, private messages, generated core names, pre-commit Directive dispatch, PID identity, direct Runic access, a custom Signal envelope, or persisted live Exec state.

## Invariants

- `BND-INV-001`: No package below `jido_ai` depends on `jido_ai`.
- `BND-INV-002`: Every AI execution enters through a public Action, Flow, Exec, Agent, Plugin, or Signal contract.
- `BND-INV-003`: Portable state contains no secret or live runtime handle.
- `BND-INV-004`: Core Jido is the only owner of Agent validation and commit.
- `BND-INV-005`: `jido_action` is the only owner of Flow graph execution.
- `BND-INV-006`: `jido_signal` is the only owner of Signal transport mechanics.
- `BND-INV-007`: A pre-commit external effect has no implied rollback.
- `BND-INV-008`: Durable recovery is outside the in-memory Exec contract.

## Downstream guarantees

| Consumer seam | Guaranteed contract |
| --- | --- |
| 01–12 | Stable ownership, effect timing, and portability rules |
| 02–05 | Model and tool behavior can use Action and Flow without owning execution |
| 06–07 | Runtime integration can rely on candidate-before-commit and post-commit dispatch |
| 10–11 | Definitions and checkpoints can rely on the portable-data boundary |
| 90 | Migration can classify every V2 feature against one owner |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `BND-DEC-001` | Who owns durable AI orchestration for V3? | Host application unless a separate package is approved | Prevents durable workflow code from entering Jido AI |
| `BND-DEC-002` | Does Jido AI own any generic retry scheduler? | No | Keeps retry timing with the execution or host policy owner |
| `BND-DEC-003` | Must package metadata remove the workflow ownership claim? | Yes | Makes the public package description match the V3 boundary |
