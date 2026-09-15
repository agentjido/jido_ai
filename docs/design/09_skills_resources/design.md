> Target seam design. This document is pending approval.

# Skills and resources design

## Architecture and contract status

- Architecture category: [Skills and resources](../ARCHITECTURE.md).
- Owning subsystem: Skill discovery, source, specification, activation, registry, runtime, resources, providers, and Actions.Skill.
- Complete target: Keep rich skill and resource functionality, deterministic dependencies/collisions, trust boundaries, bounded loading, and versioned restoration. Do not remove advanced resource work because the current implementation is narrower.
- Decision boundary: Resolve explicit versus lazy registry ownership and atomic re-resolution. Define skill compatibility policy with checkpoint and authoring seams.
- Current implementation, module links, example proof, and exact differences:
  [alignment](alignment.md). This design is a target, not an API reference.

The requirements and proposed signatures below remain pending approval.
Illustrative types are not evidence that a module or function exists. A
requirement is not removed merely because the current implementation differs.
Use the alignment matrix to distinguish current behavior from the full target.

## Proposed reference trust boundary

The shared sanitizer for untrusted Thread references belongs conceptually in
the AI Thread reference layer, with Skill.Runtime as a consumer. Keep a
separate trusted skill-activation path. This recommendation preserves removal
of forged durable, skill_name, and skill_activation-kind fields; it does not
weaken activation authority.

See [value ownership](../01_ai_values/design.md#proposed-entry-batch-and-receipt-values).
Exact helper placement and compatibility remain open. No code move or named
document approval is implied.

## Selected resource and activation ownership

User-selected on 2026-09-15: one supervised AI resource owner per AgentServer,
through the existing core Plugin runtime child contract. Catalogs and resource
providers belong to that Agent runtime. Bind selected resources once before
execution through core Plugin runtime context; pass bindings explicitly to
workers. Lazy global Skill.Registry startup is not the default ownership model.

`SKL-REQ-027`: The AgentServer AI resource owner shall index skill activations by canonical Jido.Session.id.

`SKL-REQ-028`: The AgentServer AI resource owner shall share activations between requests in the same Session and isolate activations between different Sessions.

`SKL-REQ-029`: When a request completes, is cancelled, or loses its worker, the AI resource owner shall retain that Session's activations.

`SKL-REQ-030`: When a Session is explicitly closed, the AI resource owner shall clear that Session's activations.

`SKL-REQ-031`: When delegated work crosses unrelated processes, the target shall resolve permitted resource IDs through its own bindings and target Session activation scope without treating transfer as activation authority.

Session and Thread remain values without process references. Delegation
transfers permitted resource IDs and input, not the originating process or
activation authority. Core retains topology and child lifecycle ownership.

Open: activation survival across AgentServer/resource-owner restart. Rebuilding
catalogs/providers, clearing activations, and failing affected requests is only
a preliminary proposal, not an agreed restart policy. Cross-Agent shared
resources are outside this decision. No named document is approved.

## Scope and owner

- Owner: `Jido.AI.Skill`, Skill Spec, discovery, loader, registry, activation, prompt, runtime, diagnostics, resource policy, and resource provider modules.
- In scope: Module skills, runtime skill specs, SKILL.md discovery, manifests, trust, activation, prompt content, Action and Plugin contributions, resource references, resource limits, request scope, and diagnostics.
- Out of scope: A package manager, public marketplace, unrestricted filesystem access, arbitrary code loading, provider-client ownership, and an independent execution engine.

## V2 capability anchor

V2 supported module skills, runtime-loaded SKILL.md files, registries, prompt instructions, allowed tools, Actions, Plugins, resource loading, and skill-aware requests. V3 retains these capabilities and makes trust, portability, resource limits, and normal Action and Plugin integration mandatory.

| V2 capability | V3 target |
| --- | --- |
| Module skill macro | Compile-time validated `Jido.AI.Skill.Spec` |
| Runtime SKILL.md | Bounded discovery and parsing into the same Spec |
| Global registry lookup | Explicit host registry or session catalog |
| `allowed-tools` metadata | Advisory input to explicit host approval policy |
| Skill Actions and Plugins | Normal tool catalog and core Plugin declarations |
| Resource file reads | Approved provider with a strict resource policy |
| Dynamic prompt assembly | Deterministic request-scoped skill index and selected body |

## Model

A skill has one manifest and one body reference:

```elixir
%Jido.AI.Skill.Spec{
  name: String.t(),
  description: String.t(),
  license: String.t() | nil,
  compatibility: String.t() | nil,
  metadata: %{optional(String.t()) => String.t()},
  allowed_tools: [String.t()],
  source: {:module, module()} | {:file, String.t()} | :runtime,
  body_ref: {:inline, String.t()} | {:resource, reference()} | nil,
  actions: [module()],
  plugins: [module()],
  version: String.t() | nil,
  tags: [String.t()]
}
```

The source is descriptive. It does not grant trust. A Skill Source defines discovery roots, a trust policy, module and runtime specs, a resource provider, and hard bounds.

Activation has two phases:

1. **Catalog preparation:** A session runtime discovers and validates trusted skill specs. It builds a bounded index, but it does not run a model or Action.
2. **Request activation:** The request selects approved skills. Their prompt, Actions, Plugins, and resource context enter the normal Profile, tool, Plugin, and Flow paths.

Automatic filesystem discovery requires session mode because a live host runtime owns paths, change detection, and resource access. Static module or inline runtime specs can be used in Turn mode when they need no live resource.

## Requirements

### Specification and sources

`SKL-REQ-001`: A skill spec shall have a valid lowercase hyphenated name, nonempty bounded description, optional license and compatibility text, string metadata, an allowed-tool list, body reference, version, and tags.

`SKL-REQ-002`: Module skills and runtime specs shall produce the same validated semantic Skill Spec.

`SKL-REQ-003`: A runtime-supplied spec shall use an inline body or an approved portable resource reference and shall not claim a local source path.

`SKL-REQ-004`: A Skill Source shall validate paths, trust policy, specs, modules, resource policy, provider reference, and discovery bounds without reading files or invoking host callbacks.

`SKL-REQ-005`: Untrusted or encoded input shall not contain anonymous trust functions, arbitrary module atoms, or executable callbacks.

### Discovery and trust

`SKL-REQ-006`: Filesystem discovery shall inspect only approved roots and shall enforce maximum depth, directory count, skill count, and excluded-directory rules.

`SKL-REQ-007`: Discovery shall not follow a path outside an approved root after symlink and canonical-path resolution.

`SKL-REQ-008`: A discovered skill shall not enter the active catalog until its source trust policy and manifest validation succeed.

`SKL-REQ-009`: Duplicate skill names shall be an error unless an explicit source-precedence rule selects one and reports the shadowed source.

`SKL-REQ-010`: Discovery diagnostics shall identify rejected, shadowed, incompatible, truncated, and invalid skills without exposing file content or secrets.

### Activation and integration

`SKL-REQ-011`: Skill activation shall be request-scoped and shall return the exact selected skill names and versions.

`SKL-REQ-012`: A skill body and skill index shall enter model context in deterministic order and within configured byte limits.

`SKL-REQ-013`: A skill's `allowed_tools` field shall not approve a tool by itself; the host and profile tool policies shall make the final allow decision.

`SKL-REQ-014`: Skill Actions shall enter the effective `Jido.AI.ToolCatalog` and shall pass all tool validation and conflict rules.

`SKL-REQ-015`: Skill Plugins shall enter normal core Plugin composition and shall pass duplicate module, state-key, Directive, and option validation.

`SKL-REQ-016`: A skill shall not start a process or execute an Action during discovery or activation.

`SKL-REQ-017`: If a skill requires a live resource that is not available in Turn mode, profile validation or request admission shall return an explicit unsupported-mode error.

### Resources

`SKL-REQ-018`: All skill resource listing and loading shall use the configured resource provider and resource policy.

`SKL-REQ-019`: Resource policy shall enforce maximum resources, traversal depth, directory count, listing bytes, file bytes, text bytes, and binary handling.

`SKL-REQ-020`: Text APIs shall reject binary resource content.

`SKL-REQ-021`: Binary resource content shall be rejected by default and shall enter a query only through an explicitly allowed seam 01 content-part contract.

`SKL-REQ-022`: Resource data sent to a model shall be bounded and shall include a safe source reference for audit.

`SKL-REQ-023`: A resource provider shall not expose a host filesystem path to an untrusted caller unless policy explicitly allows that path view.

### Runtime and checkpoints

`SKL-REQ-024`: A live skill catalog shall be owned by the session Plugin runtime or an explicit host service and shall not be stored in Agent state.

`SKL-REQ-025`: A checkpoint shall record only selected skill identity, version, portable activation data, and resource references required for validation.

`SKL-REQ-026`: Resume shall re-resolve skill code and resources through approved registries and shall reject an incompatible version unless migration policy allows it.

## Public contract

Recommended public surface:

```elixir
Jido.AI.Skill.Spec.new(attrs) ::
  {:ok, Jido.AI.Skill.Spec.t()} | {:error, Jido.AI.Skill.Error.t()}

Jido.AI.Skill.resolve(reference, registry) ::
  {:ok, Jido.AI.Skill.Spec.t()} | {:error, Jido.AI.Skill.Error.t()}

Jido.AI.Skill.Discovery.scan(source, opts \\ []) ::
  {:ok, Jido.AI.Skill.Catalog.t()} | {:error, Jido.AI.Skill.Error.t()}

Jido.AI.Skill.Activation.activate(catalog, selection, context) ::
  {:ok, Jido.AI.Skill.Activation.t()} | {:error, Jido.AI.Skill.Error.t()}
```

Recommended resource behavior:

```elixir
@callback list(root_ref, policy, context) ::
  {:ok, [resource_ref()]} | {:error, term()}
@callback load(resource_ref, policy, context) ::
  {:ok, Jido.AI.Skill.Resource.t()} | {:error, term()}
```

The module macro remains a trusted compile-time authoring surface. Runtime registries return tagged tuples; they do not raise for normal lookup failures.

## Invariants

- `SKL-INV-001`: Source location does not grant trust.
- `SKL-INV-002`: Discovery and activation do not execute skill code.
- `SKL-INV-003`: Every discovery and resource operation is bounded.
- `SKL-INV-004`: `allowed_tools` is advisory until host and profile policy approve it.
- `SKL-INV-005`: Skill Actions and Plugins use the normal tool and Plugin contracts.
- `SKL-INV-006`: Live catalogs and filesystem handles never enter Agent state.
- `SKL-INV-007`: Resume revalidates skill identity and compatibility.

## Downstream guarantees

| Consumer seam | Guaranteed contract |
| --- | --- |
| 10 Authoring | Portable Skill Source and skill reference values |
| 11 Checkpoints | Stable skill identity, version, and resource references |
| 12 Observation | Safe discovery, activation, resource, and diagnostic metadata |
| 90 Delivery | One supported module and SKILL.md user model |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `SKL-DEC-001` | Do skills remain in `jido_ai` for V3? | Yes; defer extraction until the contract is stable | Avoids a package split during migration |
| `SKL-DEC-002` | Can encoded profiles name skill modules? | Only through a trusted registry | Prevents atom and code injection |
| `SKL-DEC-003` | Is automatic filesystem discovery allowed in Turn mode? | No | Gives discovery a clear live owner |
| `SKL-DEC-004` | Are binaries allowed by default? | No | Keeps model input and resource use safe |
