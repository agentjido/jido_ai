> Target seam design. This document is pending approval.

# Tool bridge and effect policy design

## Scope and owner

- Owner: `Jido.AI.ToolCatalog`, tool adapters, tool results, tool interceptors, tool sources, tool context, and AI effect policy.
- In scope: Tool discovery, catalog validation, provider schemas, tool-call normalization, admission, one Action attempt, result conversion, callbacks, effect proposals, and AI retry decisions.
- Out of scope: Flow scheduling, parallel workers, delay scheduling, browser adapters, Agent commit, durable transactions, and business compensation.

## V2 capability anchor

V2 let model providers call Jido Actions, supported tool maps and dynamic tool sources, ran interceptors, converted results for the model, emitted effects, and applied bounded retry policy. V3 retains this behavior and makes each local tool call a normal Action execution through `Jido.Exec`.

| V2 capability | V3 target |
| --- | --- |
| Action module as model tool | Validated catalog entry with generated provider schema |
| Dynamic tool registry | Request-scoped tool source with explicit trust and context |
| Tool interceptor | Named before-call and after-call policy callbacks |
| Tool effects | Portable state and Directive proposals, committed by core Jido |
| Parallel tool calls | `Jido.Flow.Map` with an explicit concurrency bound |
| Retry loop and sleep | AI retry decision plus Flow continuation; no sleep in the bridge |

## Model

The catalog has two entry types:

- **Local Action tool:** A declared `Jido.Action` target with a public name, description, input schema, safe metadata, and optional policy.
- **Provider-native tool:** A portable provider tool description that the model gateway can pass to an approved provider. It has no local Action target.

A tool call becomes a portable value with `id`, `name`, `arguments`, and safe provider metadata. The bridge resolves the call against the request's effective catalog. It applies policy and an interceptor before it creates a `Jido.Instruction` and calls `Jido.Exec`.

One attempt returns a `ToolResult`:

```elixir
%Jido.AI.ToolResult{
  call_id: String.t(),
  tool_name: String.t(),
  status: :ok | :error,
  model_content: String.t() | [map()],
  value: term(),
  effects: [Jido.AI.Effect.t()],
  error: Jido.AI.Error.t() | nil,
  retry: Jido.AI.RetryDecision.t(),
  metadata: map()
}
```

`value` is local-only unless its tool contract states that it is portable. `model_content`, effects, error, and metadata must be bounded and safe before they enter context, events, or state.

The bridge never owns a batch. Seam 04 uses `Jido.Flow.Map` for parallel calls and a continuation or `Jido.Flow.Iterate` for another bounded attempt. If policy requests a delay, a host-supplied Action must implement it. The bridge does not call `Process.sleep/1` and does not create a timer process.

## Requirements

### Catalog and schemas

`TLS-REQ-001`: When a local Action is added to a tool catalog, the bridge shall validate the Action and derive a provider-safe name, description, and input schema.

`TLS-REQ-002`: A tool catalog shall reject duplicate public names, invalid Action targets, invalid schemas, and unsupported provider-native entries.

`TLS-REQ-003`: A dynamic tool source shall return a validated list of catalog entries and shall identify its trust level and runtime resource needs.

`TLS-REQ-004`: When an allowlist is present, the effective catalog shall exclude every tool that is not explicitly allowed.

`TLS-REQ-005`: Tool context in a profile or request record shall be portable data; runtime resources shall be resolved through trusted binding.

### Call admission and execution

`TLS-REQ-006`: When a model proposes a tool call, the bridge shall normalize and validate its identifier, name, and arguments before execution.

`TLS-REQ-007`: When the call name is absent from the effective catalog, the bridge shall return a model-visible tool error without executing a fallback Action.

`TLS-REQ-008`: Before a local Action runs, the bridge shall apply effect policy and the configured interceptor.

`TLS-REQ-009`: A local tool attempt shall execute as one `Jido.Instruction` through the public `Jido.Exec` contract.

`TLS-REQ-010`: The bridge shall honor Action input validation, context validation, timeout, and result rules without an alternate execution path.

`TLS-REQ-011`: A provider-native tool shall never be executed as a local Action unless a separate approved adapter declares that mapping.

### Results and effects

`TLS-REQ-012`: Each tool attempt shall return one normalized `ToolResult` correlated with the original call identifier.

`TLS-REQ-013`: The model-visible result shall be bounded, transport-safe content and shall not contain a process, exception stack, credential, or arbitrary inspected runtime term.

`TLS-REQ-014`: When a tool proposes Agent state changes or Directives, the bridge shall return portable effect proposals and shall not commit them.

`TLS-REQ-015`: When the Action returns extra direct-caller data that Flow does not preserve, the bridge shall not depend on that data for Flow behavior.

`TLS-REQ-016`: An after-call interceptor shall receive the normalized result and shall not replace the call identifier or bypass effect validation.

### Batches and retries

`TLS-REQ-017`: The tool bridge shall not create workers or schedule a tool batch.

`TLS-REQ-018`: When multiple tool calls are selected, seam 04 shall execute them with `Jido.Flow.Map` and an explicit `max_concurrency` value.

`TLS-REQ-019`: Tool results returned to the model shall preserve the model's original tool-call order, independent of completion order.

`TLS-REQ-020`: The bridge shall classify retry eligibility from the tool contract, error category, attempt count, and AI policy.

`TLS-REQ-021`: A retry decision shall be portable data and shall include `retry?`, `attempt`, `max_attempts`, and an optional delay request.

`TLS-REQ-022`: The bridge shall not sleep, spawn a retry worker, or persist retry execution state.

## Public contract

Recommended public values:

```elixir
Jido.AI.ToolCatalog.t()
Jido.AI.ToolCatalog.Entry.t()
Jido.AI.ToolCall.t()
Jido.AI.ToolResult.t()
Jido.AI.Effect.t()
Jido.AI.RetryDecision.t()
```

Recommended operations:

```elixir
Jido.AI.ToolCatalog.new(entries) ::
  {:ok, ToolCatalog.t()} | {:error, Jido.AI.Error.t()}

Jido.AI.ToolCatalog.resolve(catalog, name) ::
  {:ok, ToolCatalog.Entry.t()} | {:error, Jido.AI.Error.t()}

Jido.AI.ToolAdapter.to_provider(catalog, provider, opts) ::
  {:ok, [map()]} | {:error, Jido.AI.Error.t()}

Jido.AI.ToolBridge.attempt(call, catalog, context) ::
  {:ok, Jido.AI.ToolResult.t()} | {:error, Jido.AI.Error.t()}
```

Interceptor callbacks are named and module-based:

```elixir
@callback before_tool(call, entry, context) ::
  {:ok, call, context} | {:error, term()}

@callback after_tool(call, result, context) ::
  {:ok, result} | {:error, term()}
```

An interceptor module is part of trusted code. An encoded profile can name an allowlisted module but cannot carry an anonymous function.

## Invariants

- `TLS-INV-001`: A local tool attempt uses `Jido.Exec` exactly once.
- `TLS-INV-002`: The bridge does not commit Agent state or dispatch Directives.
- `TLS-INV-003`: Tool-call identity and order are stable.
- `TLS-INV-004`: Model-visible tool content is bounded and safe.
- `TLS-INV-005`: The bridge does not own workers, batch scheduling, delay, or durable retry state.
- `TLS-INV-006`: Runtime resources do not enter portable tool context.
- `TLS-INV-007`: Browser tools remain Actions or adapters owned by `jido_browser`.

## Downstream guarantees

| Consumer seam | Guaranteed contract |
| --- | --- |
| 04 AI execution | One-attempt Action execution, stable ordered results, effects, and retry decisions |
| 05 Reasoning | Validated tool availability and result content |
| 08 Capabilities | Explicit tool admission and policy hooks |
| 09 Skills | A normal catalog path for skill Actions |
| 10 Authoring | Portable tool and tool-source definitions |
| 12 Observation | Stable tool-call identifiers and safe metadata |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `TLS-DEC-001` | Can an Action return core Directives as tool effects? | Yes, but only through a validated effect proposal that core Jido later commits | Preserves V2 effects without bypassing commit |
| `TLS-DEC-002` | Who executes retry delay? | A host-supplied Action used by seam 04 | Keeps the bridge process-free and uses Flow |
| `TLS-DEC-003` | Are raw local tool values public? | No; only the declared model content and effect data are portable | Prevents arbitrary terms from leaking |
| `TLS-DEC-004` | Can untrusted profiles name interceptor modules? | Only through an allowlisted registry | Keeps codec authoring safe |
