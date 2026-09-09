> Target seam design. This document is pending approval.

# Core runtime and Signal integration design

## Scope and owner

- Owner: Jido AI Agent extension, runtime Plugin, session Plugin integration, route targets, AI Directives, and typed AI Signal definitions.
- In scope: Static lowering to core Agents and Flows, command preparation, trusted runtime binding, Plugin state ownership, candidate and Directive formation, internal routes, typed AI event data, and public Signal dispatch.
- Out of scope: AgentServer internals, Agent commit, Flow execution internals, Signal envelopes, routing engines, buses, private server messages, and durable transport.

## V2 capability anchor

V2 connected AI Strategies to Agents with generated routes, Strategy state, AI Directives, typed Signals, and worker processes. V3 keeps the Agent-facing AI experience and replaces those mechanics with `Jido.Agent.Extension`, core Turns, `Jido.Plugin`, core Directives, direct Flow route targets, and `Jido.Signal`.

| V2 capability | V3 target |
| --- | --- |
| `use Jido.AI.Agent` | Core `use Jido.Agent` plus `Jido.AI.DSL` extension or a compatibility wrapper |
| Strategy route | Route to a canonical AI Flow or session-admission Action |
| Strategy state callback | Complete candidate Agent returned by a core Turn |
| AI runtime worker | Optional session Plugin runtime root only for live session state |
| State operation Directive | Candidate Agent or one Plugin-owned state Directive |
| AI event dispatch | Typed AI data inside `Jido.Signal` |

## Model

Jido AI integrates at four core extension points.

### Static authoring

`Jido.AI.DSL` is a `Jido.Agent.Extension`. It accepts portable AI profile declarations and AI route targets. It lowers them before runtime to:

- Validated core Agent schema fields.
- Canonical core routes.
- Canonical `Jido.Flow` values.
- Declared `Jido.Plugin` modules and options.

For Turn mode, a query route targets the generated AI Flow directly. For session mode, it targets one session-admission Action. Jido AI does not add a private route executor.

### Plugin roles

`Jido.AI.Runtime.Plugin` owns one portable AI configuration state key and pure command preparation. It resolves effective profiles from declared profiles plus approved portable overrides. It binds trusted request resources into Turn context. It does not need a child process for normal Turn mode.

`Jido.AI.Session.Plugin` owns one portable `:requests` state key and one optional runtime root. The runtime root owns live session tasks, Exec handles, stream sinks, control queues, and transient delivery state. These values never enter Agent state.

Capability Plugins from seam 08 each own their documented state key and optional runtime root.

### Candidate and effect path

```text
Signal -> Plugin admission -> pure preparation -> route -> Action or Flow
       -> candidate Agent + Directives -> core validation -> core commit
       -> Plugin state reduction -> post-commit Directive dispatch
```

Jido AI can prepare candidates and Directives. Core Jido owns validation, commit, ordering, failure handling, and runtime dispatch.

### Signal roles

AI Signals have two roles:

- **Command Signals** enter an Agent route and request AI admission, cancellation, control, or settlement.
- **Event Signals** report request, model, tool, usage, or completion facts after the owning stage establishes them.

Jido AI owns each type string and data schema. `jido_signal` owns the envelope, ID, source, serialization, router, dispatch, and bus.

## Requirements

### Agent extension and routes

`INT-REQ-001`: The AI Agent DSL shall implement the public `Jido.Agent.Extension` contract and shall lower static AI declarations to an ordinary neutral Agent definition.

`INT-REQ-002`: Lowering shall perform no model call, tool call, process start, store access, or other runtime side effect.

`INT-REQ-003`: Each AI route target shall resolve to a validated core Action or Flow before the Agent definition is accepted.

`INT-REQ-004`: Turn-mode AI routes shall target the canonical AI Flow without a second graph runner.

`INT-REQ-005`: Session-mode AI routes shall target one admission Action that returns a candidate and a post-commit start-work Directive.

`INT-REQ-006`: AI-generated routes shall use core route conflict validation and shall not override an explicit host route silently.

`INT-REQ-007`: Route-target options shall be owned and validated by the AI extension and shall reject unknown options.

### Plugin contracts

`INT-REQ-008`: Each AI Plugin shall declare at most one portable Agent state key through `state_spec/1`.

`INT-REQ-009`: AI Plugin `prepare/2` and `update_state/3` callbacks shall be pure and shall not use a live runtime resource.

`INT-REQ-010`: When an AI Plugin uses `admit/3`, the callback shall run through the core live-admission contract and shall return a validated command or error.

`INT-REQ-011`: An AI Plugin shall define `child_spec/1` only when it needs a connection, timer, live task owner, or other process-local state.

`INT-REQ-012`: A Plugin runtime shall receive only its public runtime reference and core callback context; it shall not read private AgentServer state.

`INT-REQ-013`: A Plugin state update shall reject a stale request ID, run ID, or Directive version without changing state.

### Trusted context and state

`INT-REQ-014`: Jido AI shall read provider resources, request-local trusted options, and stream sinks only from trusted core command context or Plugin runtime state.

`INT-REQ-015`: Signal data shall not override a trusted model client, credential, HTTP client, tool runtime resource, or stream sink.

`INT-REQ-016`: Message history shall be stored in a declared Agent domain field and shall be returned as part of the complete candidate Agent.

`INT-REQ-017`: Runtime bindings shall be removed before data enters an Agent candidate, Plugin state, Signal data, or checkpoint.

### Directives and commit

`INT-REQ-018`: Every AI Directive type shall be declared by exactly one Plugin and validated before commit.

`INT-REQ-019`: A Directive that updates Plugin state shall reduce only that Plugin's owned state key.

`INT-REQ-020`: A Directive that starts or delivers runtime work shall dispatch only after core commit succeeds.

`INT-REQ-021`: If core candidate validation or commit fails, Jido AI shall not dispatch post-commit runtime work.

`INT-REQ-022`: Jido AI shall not treat a successful pre-commit model or tool call as proof that Agent state committed.

### Signals

`INT-REQ-023`: Each public AI event Signal shall use a stable type string, default source, strict Zoi data schema, and portable data.

`INT-REQ-024`: AI event data shall include the correlation identifiers required by seam 12 for its lifecycle stage.

`INT-REQ-025`: Jido AI shall create, serialize, route, and dispatch AI Signals only through public `jido_signal` contracts.

`INT-REQ-026`: An event Signal shall not act as a private control message unless an explicit Agent route admits that type as a command.

`INT-REQ-027`: When an Agent has no route for an outbound AI event, event delivery shall follow the configured public dispatcher policy and shall not re-enter the same Agent by hidden default.

## Public contract

Recommended authoring surface:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    extensions: [Jido.AI.DSL]

  agent do
    schema do
      field :answer, :any
      field :messages, {:list, :any}, default: []
    end

    ai :assistant do
      model :default, "anthropic:claude-sonnet"
      reasoning :react
      result into: :answer
      memory history: :messages
    end

    route "support.ask", ai: :assistant
  end
end
```

This is a design-shape example. The final DSL syntax must follow the approved core Agent extension grammar.

Recommended Plugin ownership:

| Plugin | Portable state key | Runtime root |
| --- | --- | --- |
| `Jido.AI.Runtime.Plugin` | `:ai_config` | None by default |
| `Jido.AI.Session.Plugin` | `:requests` | Yes for session profiles |
| Capability Plugin | One declared capability key or none | Only when the capability needs live state |

Recommended public event types:

```text
ai.request.started
ai.request.completed
ai.request.failed
ai.llm.delta
ai.llm.response
ai.tool.started
ai.tool.result
ai.usage
ai.embed.result
```

Internal settlement and control Signal types use the `jido.ai.session.*` namespace and are not provider event contracts.

## Invariants

- `INT-INV-001`: Static lowering has no runtime side effect.
- `INT-INV-002`: Every AI route resolves through the public core router to a validated Action or Flow.
- `INT-INV-003`: Each Plugin owns at most one state key.
- `INT-INV-004`: Runtime handles never enter portable state.
- `INT-INV-005`: Core Jido is the only commit owner.
- `INT-INV-006`: Runtime Directives dispatch only after commit.
- `INT-INV-007`: AI event data and Signal transport have different owners.
- `INT-INV-008`: An event does not become a command without explicit admission and routing.

## Downstream guarantees

| Consumer seam | Guaranteed contract |
| --- | --- |
| 07 Sessions | Public admission, state, runtime, Directive, and settlement boundaries |
| 08 Capabilities | One-state-key Plugin composition and optional runtime rules |
| 09 Skills | Safe integration of activated Actions and Plugins |
| 10 Authoring | Stable extension and route-target lowering contracts |
| 11 Checkpoints | Portable Agent and Plugin state without runtime handles |
| 12 Observation | Typed event data with public Signal transport |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `INT-DEC-001` | Does Turn mode route directly to Flow? | Yes | Removes a wrapper execution layer and uses the core route contract |
| `INT-DEC-002` | Does Runtime Plugin need a process? | No by default | Keeps provider resources host-bound and avoids idle processes |
| `INT-DEC-003` | Where does conversation history live? | In a declared Agent domain field | Follows the core complete-candidate model |
| `INT-DEC-004` | What happens to an unhandled AI event? | Use an explicit dispatcher or no-op target; never hidden self-routing | Prevents event loops |
