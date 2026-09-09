> Target seam design. This document is pending approval.

# AI capabilities and policy design

## Scope and owner

- Owner: Jido AI capability definitions and the Chat, Planning, Reasoning, ModelRouting, Policy, Retrieval, and Quota modules.
- In scope: Capability options, profile contributions, Plugin declarations, owned Plugin state, AI controls, model and tool policy, retrieval enrichment, quota admission, and host store behaviors.
- Out of scope: The core Plugin framework, authoritative billing, durable memory, application supervision, generic workflows, and product policy.

## V2 capability anchor

V2 provided reusable AI Plugins for chat, planning, reasoning, model routing, policy, retrieval, and quota. V3 retains these user capabilities but does not require every capability to be a runtime Plugin. A capability can contribute static profile data, Actions, routes, or one core Plugin declaration.

| V2 capability | V3 target |
| --- | --- |
| Chat Plugin state | Declared Agent history field plus profile policy |
| Reasoning and Planning Plugins | Method and plan configuration from seam 05 |
| ModelRouting Plugin | Pure selection policy used by seam 02 |
| Policy Plugin | Ordered controls at input, model, operation, and output boundaries |
| Retrieval Plugin and store | AI query and enrichment policy plus host-supervised store behavior |
| Quota Plugin and counters | Correlated AI admission and usage accounting plus host-supervised authoritative store |
| Plugin stack | Deterministic declarations with conflict validation |

## Model

A capability is a declarative unit:

```elixir
@callback id() :: atom()
@callback option_schema() :: Zoi.schema()
@callback contribute(options, context) ::
  {:ok, Jido.AI.Capability.Contribution.t()} |
  {:error, Jido.AI.Error.t()}
```

A contribution can contain:

- A portable profile fragment.
- Action or Flow targets.
- Core Agent routes.
- Core Plugin declarations.
- Schema fields that the Agent author explicitly accepts.
- Validation and feature constraints.

A contribution cannot contain a running process, unregistered function, provider client, or implicit application child.

Operational capability Plugins follow the core V3 Plugin sequence:

```text
live admit -> pure prepare -> Action or Flow -> candidate
           -> core commit -> Plugin state reduction -> runtime dispatch
```

Capability order is explicit:

1. Policy admission and input controls.
2. Retrieval enrichment.
3. Model routing and quota admission.
4. Model and operation controls.
5. Output controls.
6. Usage and quota settlement.

This order is semantic policy order. Core Plugin callback order remains the core contract. Capability lowering must reject an order that cannot produce the semantic order safely.

## Requirements

### Capability definition and composition

`CAP-REQ-001`: Each capability shall have a stable ID, option schema, contribution contract, owned state, runtime needs, and dependency declaration.

`CAP-REQ-002`: Capability construction shall be inert and shall perform no store access, process start, model call, or tool call.

`CAP-REQ-003`: Capability contributions shall lower to public Profile, Action, Flow, route, schema, and Plugin contracts.

`CAP-REQ-004`: When two capabilities claim the same profile field, Agent schema field, route identity, Plugin module, Plugin state key, or Directive type, lowering shall reject the conflict unless an explicit composition rule exists.

`CAP-REQ-005`: Capability ordering shall be deterministic and visible through authoring inspection.

`CAP-REQ-006`: A capability shall not depend on private state or callbacks from another capability.

### Chat, reasoning, and planning

`CAP-REQ-007`: The Chat capability shall store conversation history only in the Agent domain field declared by the author.

`CAP-REQ-008`: The Reasoning capability shall select and configure a registered seam 05 method and shall not implement a separate method runner.

`CAP-REQ-009`: The Planning capability shall create, validate, or revise plan values and shall not execute a generic plan outside Flow or a host orchestrator.

### Routing and controls

`CAP-REQ-010`: ModelRouting shall return a portable model alias, routing reason, and safe metadata through the seam 02 selection contract.

`CAP-REQ-011`: A control shall run as a declared Action through `Jido.Exec` at one of the `:input`, `:model`, `:operation`, or `:output` stages.

`CAP-REQ-012`: A control shall return `:ok`, a normalized error, or an allowed operation-stage interrupt.

`CAP-REQ-013`: A control interrupt shall not bypass candidate validation, effect policy, or session settlement.

`CAP-REQ-014`: Controls shall share the request deadline and shall not create an unbounded independent task.

### Retrieval

`CAP-REQ-015`: Retrieval shall define a provider-neutral store behavior for recall, upsert, delete or clear, readiness, and error normalization.

`CAP-REQ-016`: The host shall supervise each retrieval store process; a capability call shall not start an implicit store.

`CAP-REQ-017`: Retrieval results shall have stable IDs, text or content, score, safe metadata, and deterministic ordering.

`CAP-REQ-018`: Retrieval enrichment shall identify its source and shall remain within configured item and byte limits.

`CAP-REQ-019`: Agent checkpoints shall not contain the external retrieval store or claim to restore it.

### Quota

`CAP-REQ-020`: Quota admission shall correlate one reservation with the model-call identifier before provider invocation.

`CAP-REQ-021`: Quota settlement shall record known usage once for the matching reservation and shall handle unknown final usage explicitly.

`CAP-REQ-022`: A quota store shall reject duplicate active call identifiers and shall not double-count a repeated terminal report.

`CAP-REQ-023`: The host shall supervise the authoritative quota store and define its durability; Jido AI shall not imply durability for an in-memory store.

`CAP-REQ-024`: Quota policy shall return a stable allow or reject decision before the guarded provider call.

### Failure and runtime ownership

`CAP-REQ-025`: A capability Plugin shall own at most one state key and shall use an optional runtime root only for real live state.

`CAP-REQ-026`: When a required capability resource is unavailable, the request shall fail with a capability-specific normalized error before dependent work starts.

`CAP-REQ-027`: A capability shall not silently disable an explicitly requested policy, retrieval, quota, or control feature.

## Public contract

Recommended capability value:

```elixir
%Jido.AI.Capability.Contribution{
  profile: map(),
  actions: [module()],
  flows: [Jido.Flow.t()],
  routes: [Jido.Signal.Router.Route.t()],
  plugins: [Jido.Plugin.declaration()],
  schema_fields: map(),
  constraints: [term()]
}
```

Recommended retrieval behavior:

```elixir
@callback recall(namespace, query, opts) ::
  {:ok, [Jido.AI.Retrieval.Result.t()]} | {:error, term()}
@callback upsert(namespace, item, opts) :: {:ok, term()} | {:error, term()}
@callback clear(namespace, opts) :: {:ok, non_neg_integer()} | {:error, term()}
@callback ready?(opts) :: :ok | {:error, term()}
```

Recommended quota behavior:

```elixir
@callback admit(scope, call_id, limits, opts) ::
  {:ok, reservation} | {:error, :quota_exceeded | term()}
@callback progress(reservation, usage) :: :ok | {:error, term()}
@callback settle(reservation, usage_or_unknown) :: :ok | {:error, term()}
@callback status(scope, limits, opts) :: {:ok, map()} | {:error, term()}
```

The built-in retrieval and quota stores can remain supported in-memory adapters. Their documentation must state that restart loses data unless a host supplies a durable adapter.

## Invariants

- `CAP-INV-001`: Capability construction is inert.
- `CAP-INV-002`: Capability composition is deterministic and conflict-safe.
- `CAP-INV-003`: History remains Agent domain state.
- `CAP-INV-004`: Reasoning and planning capabilities do not own execution engines.
- `CAP-INV-005`: External stores are host-supervised.
- `CAP-INV-006`: Quota call identity is correlated and counted at most once per store window.
- `CAP-INV-007`: A requested capability never fails open silently.
- `CAP-INV-008`: A capability Plugin owns at most one portable state key.

## Downstream guarantees

| Consumer seam | Guaranteed contract |
| --- | --- |
| 09 Skills | Safe capability and Plugin contribution rules |
| 10 Authoring | Validated capability options and deterministic stack assembly |
| 11 Checkpoints | Portable capability state and explicit external-store boundary |
| 12 Observation | Capability IDs, policy decisions, and safe resource status |
| 90 Delivery | Explicit supported and experimental capability set |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `CAP-DEC-001` | Which capabilities are base V3 commitments? | Chat, ModelRouting, and Policy; keep Planning, Reasoning, Retrieval, and Quota as supported optional capabilities | Keeps the base small without removing V2 features |
| `CAP-DEC-002` | Are built-in retrieval and quota stores production-supported? | Supported in-memory adapters with explicit nondurability | Gives a useful default without false persistence claims |
| `CAP-DEC-003` | Must every capability be a Plugin? | No | Allows static profile and Flow contributions without unnecessary runtime state |
| `CAP-DEC-004` | What happens on composition conflict? | Reject during authoring | Prevents hidden order-dependent behavior |
