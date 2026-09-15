> Target seam design. This document is pending approval.

# Authoring and portable definitions design

## Architecture and contract status

- Architecture category: [Authoring and portable definitions](../ARCHITECTURE.md).
- Owning subsystem: Agent, DSL, Profile, Authoring, Portable, Configuration, and trusted reference resolution.
- Complete target: Preserve complete module/direct/codec authoring parity, advanced source declarations, safe registries, explicit defaults, and one lowering path. Avoid a second Agent or Flow DSL.
- Decision boundary: Reconcile target type names with the real Profile schema. Distinguish static declaration support, safe preflight, and executable behavior in every authoring form.
- Current implementation, module links, example proof, and exact differences:
  [alignment](alignment.md). This design is a target, not an API reference.

The requirements and proposed signatures below remain pending approval.
Illustrative types are not evidence that a module or function exists. A
requirement is not removed merely because the current implementation differs.
Use the alignment matrix to distinguish current behavior from the full target.

## Scope and owner

- Owner: `Jido.AI.Profile`, `Jido.AI.Agent`, `Jido.AI.DSL`, `Jido.AI.Authoring`, authoring codec, portable inspection, registries, and generated convenience APIs.
- In scope: Canonical AI profile data, module DSL, direct data, codec documents, validation, lowering, route targets, generated Flow, Plugin stack, public inspection, and authoring parity.
- Out of scope: Runtime model calls, tool execution, process startup, stores, a second Flow DSL, and behavior that exists only in one authoring form.

## V2 capability anchor

V2 provided `use Jido.AI.Agent`, agent options, reasoning-specific convenience agents, tools, system prompts, structured output, signal routes, and generated request functions. V3 retains the convenient authoring experience and expresses it as an extension of the V3 core Agent DSL with one portable Profile model.

| V2 capability | V3 target |
| --- | --- |
| Keyword options on `use Jido.AI.Agent` | Removed; use the canonical Spark DSL |
| System prompt and model option | Profile instructions and named model table |
| Reasoning selector | Registered method ID and validated options |
| Tool modules | Tool catalog entries and tool sources |
| Structured output | Seam 01 Output contract and declared Agent result field |
| Signal routes | Core Agent routes with an AI extension target |
| Generated `ask` functions | Thin calls to seam 07 request APIs |
| Serialized agent options | Versioned profile or complete Agent codec with trusted registries |

## Model

The canonical authoring value is `Jido.AI.Profile`:

```elixir
%Jido.AI.Profile{
  id: atom(),
  instructions: String.t() | action_ref() | nil,
  models: %{required(atom()) => Jido.AI.ModelEntry.t()},
  model_router: model_router_ref() | nil,
  reasoning: Jido.AI.Reasoning.Config.t(),
  controls: Jido.AI.Controls.t(),
  tools: [Jido.AI.ToolCatalog.Entry.t()],
  tool_sources: [Jido.AI.ToolSource.t()],
  tool_context: map(),
  skills: Jido.AI.Skill.Source.t() | nil,
  effect_policy: Jido.AI.EffectPolicy.t(),
  tool_interceptor: module_ref() | nil,
  result: Jido.AI.ResultConfig.t(),
  requests: Jido.AI.RequestConfig.t(),
  memory: Jido.AI.MemoryConfig.t(),
  observability: Jido.AI.ObservabilityConfig.t(),
  metadata: map()
}
```

The three primary authoring forms are:

1. **Core Agent DSL with AI extension:** The primary compile-time developer form.
2. **Direct data:** `Jido.AI.Profile.new/2` plus `Jido.AI.Authoring.lower/2` for programmatic construction.
3. **Codec document:** Versioned tagged data decoded through trusted registries.

`use Jido.AI.Agent` is the canonical convenience form. It uses `Jido.Agent` with
the `Jido.AI.DSL` Spark extension. It has no separate schema or runtime.

The lowering pipeline is:

```text
authoring input
  -> source-form validation
  -> canonical Profile
  -> cross-profile and Agent-schema validation
  -> canonical AI Flow per profile
  -> core routes and Plugin declarations
  -> neutral core Agent definition
  -> core Agent validation
```

The module DSL can define inline instructions and inline Action tools through the core inline Action compiler. The generated targets are ordinary Actions. For explicit custom workflow authoring, users use the standard `Jido.Flow` DSL and refer to AI Actions. Codec input cannot contain body code, anonymous functions, or unregistered executable targets.

## Requirements

### Canonical profile

`AUT-REQ-001`: Every AI authoring form shall produce one validated `Jido.AI.Profile` value before Agent lowering.

`AUT-REQ-002`: A Profile shall have a stable ID and shall reject unknown fields.

`AUT-REQ-003`: Profile construction shall be inert and shall not call a model, tool, store, registry callback that performs I/O, or process supervisor.

`AUT-REQ-004`: Profile validation shall enforce portable static data for every field that can enter Agent definitions, routes, Plugin options, or Flow data.

`AUT-REQ-005`: Profile validation shall reject an unknown model role, method, control, tool, skill source, output field, history field, or request mode before lowering completes.

`AUT-REQ-006`: Model aliases shall remain portable and shall resolve at request start through seam 02.

### Authoring parity

`AUT-REQ-007`: The core Agent DSL, direct Profile data, and codec form shall have semantic parity for every supported Profile field.

`AUT-REQ-008`: The same semantic Profile shall lower to the same Agent schema, routes, Plugin declarations, Flow semantics, and public inspection data independent of source form.

`AUT-REQ-009`: A source-form-only convenience shall expand to canonical Profile data and shall not create source-form-only runtime behavior.

`AUT-REQ-010`: `Jido.AI.Agent` shall accept only the V3 Spark DSL and shall
reject unsupported top-level AI options.

### DSL and inline authoring

`AUT-REQ-011`: The AI DSL shall extend the core `agent do` block through the public `Jido.Agent.Extension` contract.

`AUT-REQ-012`: An `ai` declaration shall define one Profile and shall make its ID available to core route targets.

`AUT-REQ-013`: Inline instructions and Action tools shall compile to ordinary named Action modules with core input, output, and context validation.

`AUT-REQ-014`: The DSL shall reject function calls or other unsafe evaluated forms in fields that require static literal data.

`AUT-REQ-015`: The DSL shall report source location for compile-time validation errors without storing source metadata in the canonical Profile.

`AUT-REQ-016`: Jido AI shall not define a second Flow declaration language; custom execution graphs shall use the standard `Jido.Flow` DSL.

### Lowering

`AUT-REQ-017`: Lowering shall accept only a neutral Agent definition without instance ID or state.

`AUT-REQ-018`: Lowering shall generate one canonical AI Flow or session admission target for each Profile.

`AUT-REQ-019`: Lowering shall add only the Plugins, state fields, and internal routes required by the selected Profile features.

`AUT-REQ-020`: Lowering shall reject duplicate Profile IDs, route conflicts, Plugin conflicts, output fields absent from the Agent schema, and history fields that conflict with result fields.

`AUT-REQ-021`: Lowering shall pass the complete definition through core Agent validation and shall return the core validation error without hiding its cause.

`AUT-REQ-022`: Lowering the same canonical input with the same registries shall be deterministic.

### Codecs and registries

`AUT-REQ-023`: A profile codec document shall have a type, version, complete Profile data, and stable registry references for executable or schema values.

`AUT-REQ-024`: A decoder shall not create atoms, load arbitrary code, evaluate source text, or accept an executable target that is absent from the trusted registry.

`AUT-REQ-025`: A decoder shall call the same canonical Profile validation and Agent lowering path as direct authoring.

`AUT-REQ-026`: Portable export shall redact credentials, provider options marked sensitive, approval callbacks, tool context marked private, and other runtime-only fields.

`AUT-REQ-027`: Public inspection shall distinguish declared Profile data, effective safe request data, generated Flow identity, and redacted runtime bindings.

### Generated API

`AUT-REQ-028`: An authored AI Agent shall expose Profile inspection and the request functions supported by its request mode.

`AUT-REQ-029`: Generated request functions shall be thin calls to seam 07 and shall not contain a second admission or execution path.

`AUT-REQ-030`: Default values that affect behavior shall be explicit in the canonical Profile and in portable inspection.

## Public contract

Recommended module authoring form:

```elixir
defmodule SupportAgent do
  use Jido.Agent,
    name: "support_agent",
    extensions: [Jido.AI.DSL]

  agent do
    schema do
      field :answer, :any
      field :messages, {:list, :any}, default: []
    end

    ai :support do
      instructions "Answer with concise technical guidance."

      models do
        model :default, "anthropic:claude-sonnet"
      end

      reasoning :react, tool_concurrency: 4

      tools do
        action MyApp.Search, as: :search, timeout: 5_000
      end

      controls max_iterations: 8, max_model_calls: 12, max_tool_calls: 16
      result into: :answer
      memory history: :messages
      requests mode: :session, streaming: true, steering: true
    end

    route "support.ask", ai: :support
  end
end
```

The precise DSL options remain subject to the core Spark extension grammar. The design requirement is semantic parity, not this exact syntax.

Recommended direct and codec API:

```elixir
Jido.AI.Profile.new(attrs, registries: registries) ::
  {:ok, Jido.AI.Profile.t()} | {:error, Jido.AI.Error.t()}

Jido.AI.Authoring.lower(neutral_agent, profiles) ::
  {:ok, Jido.Agent.t()} | {:error, term()}

Jido.AI.Authoring.Codec.encode(profiles, registry) ::
  {:ok, map()} | {:error, term()}

Jido.AI.Authoring.Codec.decode(neutral_agent, document, registry) ::
  {:ok, Jido.Agent.t()} | {:error, term()}

Jido.AI.Portable.inspect(source, opts \\ []) :: {:ok, map()} | {:error, term()}
Jido.AI.Portable.preflight(source, request, opts \\ []) :: {:ok, map()} | {:error, term()}
```

## Invariants

- `AUT-INV-001`: One canonical Profile is the source of AI authoring semantics.
- `AUT-INV-002`: Authoring and lowering are inert.
- `AUT-INV-003`: All authoring forms have semantic parity.
- `AUT-INV-004`: Codec input cannot introduce code or atoms outside trusted registries.
- `AUT-INV-005`: Lowering produces only public core Agent, Flow, route, Action, and Plugin values.
- `AUT-INV-006`: Defaults that change behavior are visible.
- `AUT-INV-007`: Generated convenience functions do not own runtime behavior.
- `AUT-INV-008`: Custom workflow authoring uses the standard Flow DSL.

## Downstream guarantees

| Consumer seam | Guaranteed contract |
| --- | --- |
| 11 Checkpoints | Stable Profile identity, Agent version, and portable definition rules |
| 12 Observation | Safe declared and effective configuration views |
| 90 Delivery | One V3 authoring target for docs and examples |
| Host applications | Module DSL, direct data, and codec parity |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `AUT-DEC-001` | Is `Jido.AI.Profile` the canonical authoring value? | Yes | Gives all forms one validation and lowering path |
| `AUT-DEC-002` | Does `use Jido.AI.Agent` remain public in V3? | Yes, as the canonical convenience form for `Jido.Agent` plus `Jido.AI.DSL` | Gives users one inert Spark authoring form |
| `AUT-DEC-003` | Can codec documents name modules? | Only by trusted registry ID | Prevents unsafe code and atom loading |
| `AUT-DEC-004` | Can Profile fields contain anonymous functions? | No; use registered module or MFA references where allowed | Preserves portability |
| `AUT-DEC-005` | Which form is the primary developer guide? | Core Agent DSL with `Jido.AI.DSL` | Aligns Jido AI with V3 authoring |
