# Milestone 1: Jido AI authoring and lowering

Status: first production authoring slice implemented. The complete design remains the migration target. See [implementation progress](implementation.md).
Updated: 2026-09-06. This is the single plan that replaces the earlier
`agent-dsl` and `jidoka-dsl` brainstorms. See the [full migration plan](migration-plan.md)
for runtime ports and root dependency cutover.

The first milestone defines the authoring contract and its executable acceptance
foundation. Extending the compiler is the next implementation stage. Do not
claim that the existing root AI package runs on v3 because a fixture does.

## Architecture decision

Extend the existing `Jido.Agent` authoring path. All AI authoring forms must
produce the same validated AI profile data, then lower into an ordinary
`%Jido.Agent{}` definition whose routes select ordinary Actions or `%Jido.Flow{}`
executables. Core retains Agent construction, validation, Plugin composition,
state ownership, live execution, and persistence.

There is no second AI Agent runtime type and no AI-specific Flow engine.
The shared AI profile is static authoring input, not live state or a checkpoint.
Provider clients and process handles enter through transient execution context.

```text
AI Spark DSL ───────┐
AI Builder helpers ├─> validated AI profile data ─> common AI lowering
Direct data ───────┤                                  │
JSON + registry ───┘                                  ▼
                                          ordinary Jido.Agent definition
                                                     │
                                   Signal selects Action or Jido.Flow
                                                     │
                                              Jido.Exec / Runic
                                                     │
                                      complete candidate + directives
                                                     │
                                          AgentServer commit boundary
```

Flow formats lower to a Flow; Agent formats lower to an Agent. They share the
architecture but are separate value types. AI connects them by producing Flow
route targets inside a core Agent definition.

## Existing foundation and extension gap

| Surface | Current implemented path | Reuse for AI |
| --- | --- | --- |
| Flow DSL | Spark entities → `Jido.Flow.DSL.Lowerer` → canonical Flow | Use public Flow constructors/Builder for generated AI operations |
| Flow Builder/direct data | Validated components → `Jido.Flow.new` / Builder.build | One shared graph independent of authoring form |
| Flow JSON | `Jido.Flow.Codec` + trusted Registry → canonical Flow | Store approved references and data, not source code |
| Flow compilation | Canonical Flow → validation → native Runic workflow | Keep compilation, concurrency, cancellation, limits and diagnostics in Exec |
| Agent DSL | Spark Agent/routes entities → core configuration → canonical Agent constructor | Add AI entities and lower them before core construction |
| Agent Builder/direct data | `Jido.Agent.Builder` / `Jido.Agent.new` → neutral definition | Feed the same lowered fields into the current validator |
| Agent JSON | `Jido.Agent.Codec` + trusted Registry → neutral Agent; instantiate separately | Reuse the lowered definition format after AI authoring validation |

Source evidence:

- [Flow lowerer](../../../jido_action/lib/jido_flow/dsl/lowerer.ex),
  [Builder](../../../jido_action/lib/jido_flow/builder.ex),
  [Codec](../../../jido_action/lib/jido_flow/codec.ex), and
  [compiler](../../../jido_action/lib/jido_flow/compiler.ex).
- [Flow parity tests](../../../jido_action/test/jido_flow/canonical_authoring_test.exs).
- [Agent DSL compiler](../../../jido/lib/jido/agent/dsl/compiler.ex),
  [Builder](../../../jido/lib/jido/agent/builder.ex), and
  [Codec](../../../jido/lib/jido/agent/codec.ex).
- [Agent format parity tests](../../../jido/test/examples/01_basic/authoring_formats_test.exs).

The inspected core originally did not forward Spark extensions and assumed
every entity under `agent` was a Plugin. The migration now adds the generic
`Jido.Agent.Extension.lower_agent/2` contract. It forwards declared extensions
and lowers foreign entities before core validation. Do not add AI policy to core or copy the core compiler into AI.

The extension must define ordering, source locations, field conflicts, route
conflicts, and generated helper conflicts. Keep Plugin declarations in their
existing order. The same lowering function must be available without Spark.

## Canonical AI authoring contract

Use a validated profile value (proposed name: `Jido.AI.Profile`) with a stable
profile ID and these fields:

| Field | Static meaning |
| --- | --- |
| instructions/context | Prompt policy and schema for transient application input |
| models | Named roles, application model references, generation options and fallback rules |
| reasoning | Method and bounded method-specific settings |
| tools | Named operation records: kind, executable/source reference, schemas, context projection, retry and approval policy |
| controls | Ordered input/model/operation/output controls and shared limits |
| skills | Trusted module/path references, activation and resource bounds |
| memory | Domain history/summary fields and compaction policy |
| result | Output schema, validation mode, repair bound, trusted repair callback and domain result field |
| requests | One-Turn or session execution and busy/stream/steering policy |

The [history review](history-reviews/01-authoring-and-cli.md) adds two constraints.
Model roles must accept the full supported ReqLLM input, including rich aliases.
Labels cannot replace model configuration. Reuse the public `Jido.AI` resolver.

Prompt normalization must preserve default, disabled and explicit-text meanings.
Resolve a bare prompt attribute in the caller's compile context before lowering.
Legacy Agent declarations and direct reasoning calls have different empty-prompt
rules. Apply those rules in compatibility frontends, then use one normalized
policy across the new DSL, Builder, data and JSON forms. Prove the exact model
message; a successful compile alone cannot detect a lost prompt.

The [output/control review](history-reviews/04-output-and-controls.md) adds
input-format and runtime constraints. Normalize known profile fields once before
common lowering. Test string-keyed schemas separately from outer option maps,
including unknown and conflicting keys. A cleanup of internal key access must
not remove supported imported data.

Keep output validation independent of authoring. Use the shared model operation
for each repair attempt, with current runtime bindings, model controls and usage
accounting. Preserve configured repair callbacks by trusted identity; direct
legacy callback overrides remain a separate compatibility boundary. Check the
whole prepared tool batch before any Action starts. Pass the effective attempt
timeout to Exec, and distinguish it from caller wait and total request limits.

The [tool/composition review](history-reviews/05-tools-and-composition.md)
requires an AI declaration to compose with ordinary core routes and Plugins.
Keep caller route attributes, static parameters and capability choices through
legacy conversion. Use one validated tool catalog to derive provider schemas
and execution lookup. Reject duplicate public names before a catalog commit.
Define when a runtime catalog change takes effect for active or pending work.

Keep before/after tool callbacks at the AI boundary around core execution.
Ordinary Action/Flow calls must remain usable without the AI transforms.
Before runs before validation, retry and preflight; after runs after the final
attempt, followed by effect filtering. Preserve call ID, public name and
executable identity. Retry counts do not establish callback replay semantics
after restore. Prove both paths with the reported long-key alias example.

The [stream/checkpoint review](history-reviews/07-streams-and-checkpoints.md)
requires explicit completion and recovery rules. A transport error is a failed
request. Preserve the legacy accepted partial-content finish-reason case through
compatibility conversion; the result contract still validates that content.
Public event projections retain available call/run/request sequence data.
Stream sinks stay in runtime resources. Restore an interrupted stream as failed
with `stream_interrupted`; a new request obtains new resources. Preserve the
consumer's persistence extension through the supported core boundary.

The [public-stream review](history-reviews/08-request-stream-contract.md)
keeps event delivery in runtime policy. One owned emitter assigns sequence
numbers to normal events and tool keepalives. Keepalive is optional and cannot
extend the operation deadline. A consumer receive timeout stops observation;
it is separate from request cancellation. Preserve PID sinks and document
mailbox ownership. A declared stream is not a durable queue or replay log.

The [steering review](history-reviews/09-steering-and-queued-input.md) defines
the session input policy. `steer` and `inject` add visible user input to the
active ReAct request through one bounded FIFO owner. A queued acknowledgement
is separate from consumption and history commit. Empty-queue closure must be
atomic; after closure, input is rejected even during output repair. Hard limits
still stop work. Preserve one request handle, idle rejection, optional expected
request ID and best-effort delivery. Use an explicit correlated control result
instead of reading private strategy state. Durable input, hidden roles and
automatic start remain separate proposals.

The [lifecycle/execution review](history-reviews/10-lifecycle-and-execution-policy.md)
keeps common request ownership across reasoning methods while preserving their
phase and result rules. Project compatible public Signals from the canonical
events with actual usage and committed completion. Normalize logging controls
into observer policy; `log_level` is not a supported v3 Exec run option.

The [telemetry/usage review](history-reviews/11-telemetry-usage-and-payloads.md)
requires explicit observer and business context boundaries. Carry call IDs in
observer metadata without changing an Action's input. Use one usage adapter
for counters and provider metadata, and one sanitizer with distinct telemetry
and tool-transport profiles. Preserve permitted nested tool payloads and
redaction. Profiles lower observation policy once for model tools and ordinary
routes; imported policy cannot bypass execution validation.

Validate the profile before lowering. Construction must not contact providers,
MCP servers, browsers, skill resource providers, or tools. Static source catalogs
use host-owned registries. Runtime discovery is explicit work with its own
validation and lifecycle; it is not an import-time side effect.

Proposed data boundary: `Jido.AI.Authoring.lower(agent_definition, profiles)`
returns `{:ok, canonical_agent_definition}` or a structured error. Exact helper
names can change, but all forms must call this same boundary. AI Builder helpers
must compose with the core Builder or definition; they must not introduce an
independent Agent validation path.

Each form lowers to the same graph and configuration. Preserve source locations
outside semantic equality. Use deployed modules for generated inline work and
trusted stable IDs for stored executable/schema/control references. Do not make
module names from imported strings or serialize closures. A high-level AI JSON
reader is an authoring frontend; lowered Agent JSON still uses core Codec.

Registry and artifact identity need explicit tests. Core Codec identifies
executable targets; it does not automatically invent a durable identity for an
arbitrary runtime-generated AI Flow. Choose registered Flow modules or explicit
stable Flow entries supported by the registry. Prove round-trip execution.
Builder, JSON, and direct-data routes need not generate Elixir helper functions,
but their input, configuration, graph, errors and execution must match the DSL.

## Minimum authoring scope

The first implementation proves one bounded AI profile inside an ordinary
Agent. Keep the complete sketch below as the desired later vocabulary.

| Include in the first authoring slice | Add through later feature examples |
| --- | --- |
| Instructions, named model roles and explicit generation settings | More fallback and per-request override cases through shared operations |
| Bounded ReAct, Action tools, ordinary Flow tools | Other reasoning methods, dynamic catalogs and specialist delegation |
| Input/model/operation/output controls and explicit limits | Shared accounting, interception and existing interrupt behavior |
| Typed output and a bounded repair rule | Skills, multimodal history, compaction and restore |
| One-Turn execution, mixed ordinary routes and one Plugin | Session admission, streaming/steering APIs and standalone token resume |
| Equivalent DSL, Builder, direct data and source-profile JSON | Optional new MCP/browser/handoff adapters and stronger durable approval |

These later examples remain required when they preserve current AI features.
The optional new adapters and stronger guarantees are separate additions.

Keep route bindings separate from model/reasoning policy in the normalized
authoring data. DSL routes and the temporary `profile.routes` shorthand in the
pending data fixture must become the same ordered route bindings before core
validation. Do not add another route DSL inside the AI block. Define the exact
public input shape through the first four-format example; retain one public
lowering boundary and one set of core validation rules.

Keep the first helper contract simple: a one-Turn route returns its complete
committed Agent result through the existing core helper. Session `ask`/`await`
has separate admission and completion semantics. The first authoring example
must not make one helper name return both meanings based on hidden settings.

## Desired DSL

Use Jidoka's concepts of models, controls and model-callable operations within
one named `ai` block. Keep ordinary Agent state, Plugins and routes around it.
Sources: [Agent DSL](https://jidoka.hexdocs.pm/agent-dsl.html),
[controls](https://jidoka.hexdocs.pm/controls.html), and
[orchestration](https://jidoka.hexdocs.pm/agent-orchestration.html).


This syntax is not implemented. Application modules stand in for their actual
implementations. Model roles resolve through application configuration.

```elixir
defmodule MyApp.SupportAgent do
  use Jido.Agent,
    name: "support",
    extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{
             case_id: Zoi.string() |> Zoi.default(""),
             messages: Zoi.list(Zoi.map()) |> Zoi.default([]),
             summary: Zoi.string() |> Zoi.default(""),
             last_reply: Zoi.map() |> Zoi.default(%{})
           })

    plugin MyApp.Audit

    ai :support do
      instructions """
      Help the customer resolve their support case.

      Use order records and published policy as evidence.
      Obtain a refund quote before requesting a refund.
      Ask for missing information when needed.
      Give a clear answer with the next action.
      """

      context Zoi.object(%{
                tenant_id: Zoi.string(),
                user_id: Zoi.string()
              })

      models do
        model :answer, :capable do
          generation temperature: 0.2, max_tokens: 4_096
          fallback :backup, on: [:rate_limited, :unavailable]
        end

        model :backup, :fast
        model :summarize, :fast
      end

      reasoning :react do
        model :answer
        tool_concurrency 4
      end

      tools do
        action MyApp.GetOrder,
          as: :get_order,
          forward_context: [:tenant_id, :user_id]

        flow MyApp.QuoteRefund,
          as: :quote_refund,
          description: "Calculate the permitted refund.",
          forward_context: [:tenant_id],
          timeout: 10_000

        action MyApp.IssueRefund,
          as: :issue_refund,
          forward_context: [:tenant_id, :user_id],
          retries: 0,
          approval: [
            when: MyApp.RefundNeedsReview,
            expires_in: 300_000
          ]

        subagent MyApp.EvidenceAgent,
          as: :check_evidence,
          forward_context: [:tenant_id],
          timeout: 20_000,
          max_calls: 2

        handoff MyApp.BillingAgent,
          as: :transfer_to_billing,
          forward_context: [:tenant_id, :user_id]

        mcp :helpdesk,
          only: ["search_articles", "get_article"],
          prefix: "helpdesk_"

        browser :manuals,
          mode: :read_only,
          allow: ["https://docs.example.com"]
      end

      skills do
        skill MyApp.Skills.CustomerSupport
        load_path "priv/skills/support", activation: :lazy

        resources max_file_bytes: 1_000_000,
                  max_text_bytes: 64_000,
                  binary: :allow
      end

      controls do
        max_iterations 8
        max_model_calls 12
        max_tool_calls 16
        max_total_tokens 24_000
        timeout 60_000

        input MyApp.AuthorizeCase
        input MyApp.ValidateCustomerInput

        model MyApp.CheckModelRequest

        operation MyApp.EnforceTenantBoundary

        operation MyApp.CheckRefundLimit,
          only: [:issue_refund]

        output MyApp.RequireEvidence
        output MyApp.CheckCustomerReply
      end

      memory do
        history :messages
        summary :summary

        compact after_messages: 40,
                keep_last: 12,
                model: :summarize
      end

      result Zoi.object(%{
               answer: Zoi.string(),
               evidence: Zoi.list(Zoi.string()),
               next_action:
                 Zoi.enum([:none, :ask_customer, :review, :handoff])
             }),
             into: :last_reply,
             max_repairs: 2

      requests do
        mode :session
        on_busy :reject
        streaming true
        steering true
      end
    end
  end

  routes do
    signal_source "/support"

    route "support.ask", ai(:support) do
      define :answer, args: [:query]
    end

    route "support.close", MyApp.CloseCase do
      define :close, args: [:reason]
    end
  end
end
```

## Exact execution rules to prove

1. Models are roles. Fallbacks must support the requested tools and output
   format. Resolve application defaults at a defined request boundary and
   retain the selected values for diagnostics and token compatibility.
2. Controls run in declaration order at input, every model call, operation,
   and validated output boundaries. Stop on rejection or interrupt. Every
   fallback and repair call passes model controls and shared budgets.
3. Resolve a tool from a trusted registry, apply the before-tool interceptor,
   validate arguments, run operation controls and approval, then execute with
   its retry policy. Run the after-tool interceptor once after final completion,
   then filter effects. Approval binds to the validated operation and arguments.
4. Input/model/output controls return a continue or rejection decision.
   Operation controls can also request approval. Arbitrary business work stays
   in Actions/Flows. Do not silently turn policy rejection into model fallback.
5. A tool Flow returns tool data. The terminal Agent Action assembles complete
   candidate state and preserves unrelated fields. Actions cannot write protected
   Plugin keys. Define ordered reduction or rejection for parallel state changes.
6. `max_iterations` counts reasoning cycles. `max_model_calls` includes repair,
   fallback, compaction and delegated work. Count failed/cancelled provider work.
   Token accounting can stop new work; it cannot undo incurred usage.
7. Session execution commits request/approval bookkeeping through separate
   Turns. Final conversation output commits after validation and controls.
   Approval uses portable pending-work data, not live Exec objects. Define
   active-work timeout separately from approval expiry and caller wait timeout.
8. `answer` generated by core is a live command helper. AI `ask`/`await` is a
   separate request interface. The session admission route must return a clearly
   typed admission result; it must not pretend to return the final answer.
   Do not retain ambiguous helper behavior from the brainstorm sketch above.
9. Memory fields remain declared Agent domain fields. Preserve message order,
   tool/result pairs, multimodal content and active skills during compaction.
10. Subagents return work to the parent. Handoffs change routing ownership for
    later messages. Both need correlation, context projection and cleanup tests.

The full sketch shows the desired vocabulary across the migration. First implement one bounded
profile with model roles, Action/Flow tools, controls and typed output. Session,
skill and adapter features enter through their own acceptance examples.

## Reasoning methods

A method selects a recipe over shared operations, not a core Strategy.
ReAct uses bounded iteration/continuation; tools use Map; deterministic domain
work uses subflows. ToT/GoT preserve their traversal and result metadata.
TRM preserves refinement/halt rules. Adaptive selects the same callable method
implementations. Keep pure parsers and algorithms where their behavior is valid.

```elixir
reasoning :tree_of_thoughts do
  model :answer
  branching_factor 3
  beam_width 2
  max_depth 4
  max_nodes 24
  top_k 3
end
```

The typed support reply in the full sketch is not the full ToT result. Retain
ranked candidates, termination, usage and search details, or select an explicit
application projection.

## Ordinary Flow tool


The model can request a refund quote. The application defines its calculation
with an ordinary Flow. The same Flow is also usable directly through
`Jido.Exec`.

```elixir
defmodule MyApp.QuoteRefund do
  use Jido.Flow,
    name: "quote_refund",
    schema: Zoi.object(%{order_id: Zoi.string()})

  flow do
    step "order",
      action: MyApp.GetOrder,
      params: %{order_id: input(:order_id)}

    step "policy",
      action: MyApp.GetRefundPolicy,
      params: %{product_type: result("order", :product_type)}

    step "quote",
      action: MyApp.CalculateRefund,
      params: %{
        order: result("order"),
        policy: result("policy")
      }

    output result("quote")
  end
end
```

## Milestone examples

Use matching IDs for source, ExUnit tests, and profile documents, following core.
The root project compiles checked examples in the `:dev` and `:test`
environments. Example tests use the `:example` tag and do not run by default.
Use `mix examples` to run the complete checked catalog.

| ID | Executable acceptance target |
| --- | --- |
| 01_01_authoring_formats | Core DSL, Builder, direct and JSON Agent forms use the same model Action/Flow; equal state and live commit |
| 01_02_tool_flow | Model-selected approved Action and nested Flow; tool ID/order, real tool result in follow-up input, validation before effects |
| 01_03_structured_output | Real schema request; invalid object feedback, bounded repair, complete-state commit and exhaustion preservation |
| 01_04_controls | Explicit input/output policy and model failure; zero calls on input rejection and no commit on output rejection |
| 01_05_streaming | Real SSE deltas visible before final commit; live cancellation and worker cleanup; provider receive timeout is tested in the shared server suite |
| 01_06_ai_extension | Pending nested AI DSL, common lowering, core Builder/data/JSON execution of lowered results, invalid profiles before model calls; add source-profile JSON parity during implementation |

The first five are foundation/application examples. They show the behavior the
AI compiler must produce; they do not implement an alternative AI framework.
The sixth must exercise the actual future AI extension and public lowering API.

The initial pending data specification uses `routes: ["ai.ask"]` on a profile
to select its generated route. The DSL uses `route "ai.ask", ai(:assistant)`
for the same intent. The lowerer must normalize both and reject conflicts.
The examples pass `model`, `model_options`, and an observer in transient context.
These are fixture bindings, not a final public override policy. Define a trusted
runtime binding boundary before exposing AI authoring to external input.

The pending tests specify a small starting slice. They do not yet cover the
whole desired DSL, source-profile JSON import, or its diagnostics. Each remains
an authoring exit requirement. Keep `pending_dsl` separate from `integration`,
because ExUnit include filters can override an exclusion on the same test.

Use one local mock server with text, object, tool-batch, fragmented tool-delta,
embedding, usage, HTTP error, malformed response, disconnection and barrier
support. Scripts match exact request fields. Record request history, remaining
script, unexpected requests and held workers. No prompt-substring heuristics and
no scripted tool results in place of real Action execution.

Retain the published consumer test DSL as a thin frontend to that same server.
The [public-helper review](history-reviews/15-public-test-helpers.md) defines
`expect_react` compatibility, per-request script progress and failure conversion.
The test DSL must not add a second synthetic-response path inside the AI runtime.

The [skill history review](history-reviews/16-skill-discovery-and-lazy-loading.md)
adds a catalog constraint. One skill definition must supply both the disclosed
index and the loader's selected Specs. Prepare trusted filesystem catalogs at
runtime; do not read bodies while compiling the Agent definition. Keep a stable
session owner across Flow workers. Skill metadata does not grant tool permission.
Use normal loading Actions and the shared mock to prove actual instruction and
resource delivery. No additional skill compiler or execution engine is needed.

The [lifecycle review](history-reviews/18-skill-lifecycle-and-conformance.md)
adds trusted request bindings and instruction origin to this contract. Bind the
selected catalog and executed Action identity before work starts. Ordinary input
cannot grant trusted origin through refs. Define host catalog changes, session
cleanup and portable state in the runtime contract. Do not add DSL fields for
internal durability flags or registry tables.

## Done for authoring implementation

The [Signal history review](history-reviews/13-signals-and-catalog-setup.md)
also constrains generated AI events. Use static core Signal schemas and one
envelope implementation. Preserve the required AI event/data contracts through
explicit compatibility adapters. Constructor options cannot replace validated
data or the declared event type. Document schema metadata and error changes;
do not introduce another Signal DSL inside the AI extension.

- All four frontends produce equivalent canonical Agent and Flow data.
- The nested AI block compiles through the core extension mechanism.
- Definitions remain inert and portable; imports use typed trusted registries.
- Field/tool/role/profile/route conflicts give useful source or data-path errors.
- Ordinary Agent routes and Plugins compose with AI configuration.
- Real model/tool transcripts, complete-state commits and errors match across
  forms. Generated helper differences are documented and tested.
- Pending authoring tests pass when enabled and lose their pending tag.
- Existing core/Flow tests remain valid; no second execution engine is added.

This is the first part of the [package migration](migration-plan.md).
Requests, all reasoning methods, Plugins, skills, stored data and the release
cutover remain required work after the authoring contract is established.

## Session implementation checkpoint

The current production extension also accepts:

```elixir
requests do
  mode :session
  on_busy :reject
  max_requests 100
  streaming true
end
```

The default remains `mode :turn`, with streaming off. Session routes lower to
an admission Action with a core Plugin. The task executes the same reasoning
Flow as one-Turn work. See [02_01](../../examples/02_requests/02_01_session/README.md)
for confirmed admission, awaits, SSE, tools/objects, usage, cancellation and
failure tests. Public macro helpers, steering, history, keepalives, all legacy
options and durable restore still need implementation. This block is a tested
subset of the desired DSL above.

## Steering and history implementation checkpoint

The production extension now also accepts `steering true` inside session
`requests`, and `memory do history :messages end`. The history field must be
declared in the domain schema and differ from `result.into`. The default has
steering off and no history field. See [02_02](../../examples/02_requests/02_02_steering/README.md)
for the 13 live cases. Full macro/API parity, compaction, context operations,
durable conversion and source JSON with enabled history remain open.

## Request transformation implementation checkpoint

The production extension accepts a transformer in `reasoning` and a repair
callback in `result`:

```elixir
reasoning :react do
  model :answer
  request_transformer MyApp.RequestPolicy
end

result Zoi.object(%{answer: Zoi.string()}),
  into: :reply,
  max_repairs: 2,
  repair_fun: &MyApp.Repair.normalize/4
```

The transformer applies to normal and repair requests before model controls.
Repair keeps business tools and streaming disabled. The callback can return
a repaired object, which must pass the declared schema. External captures
become module/function references. Source JSON resolves those references through
the core trusted Registry. No closure is stored in the profile.

See [02_05](../../examples/02_requests/02_05_request_transform/README.md) for the same
configuration executed through DSL, data, Builder and source JSON. The tests
also cover direct `Output.repair/5` overrides, fresh repair credentials, model
changes and limits. Full output events, standalone ReAct and durable callback
restore remain required. These checks do not close the authoring milestone.

## Output and telemetry implementation checkpoint

Output now emits start, repair, validated or failed events and retains output
metadata on request records. Object generation through a provider schema tool
goes to output validation. It does not enter business-tool dispatch.

The AI profile also accepts:

```elixir
observability %{emit_telemetry?: true, emit_llm_deltas?: false}
```

Both flags are booleans and default to enabled when omitted. `emit_telemetry?`
controls AI telemetry. `emit_llm_deltas?` controls delta capture and its telemetry,
for both native and public Agents. Request events still occur when telemetry
alone is disabled. Suppressing deltas preserves internal provider activity and
the complete model response.
DSL, data, Builder and source JSON execute the same configuration in
[02_06](../../examples/02_requests/02_06_output_contract/README.md). Other observation
options, full lifecycle Signals and durable recovery remain required.

## Implemented effect policy and commit boundary

The [02_10 example](../../examples/02_requests/02_10_tool_effects/README.md) adds
`effect_policy(...)` at the AI profile and reasoning scopes. The effective
policy is their intersection. Source data, Builder and JSON use the same
normalizer. The public `strategy_effect_policy` option maps to reasoning scope.

Tools return ordinary values plus complete state proposals and typed core
Directives. One assembler validates candidate state and rejects conflicting
parallel field changes. Later tool rounds receive that candidate. Native
one-Turn routes use a terminal Action around the shared reasoning Flow so core
can receive both complete state and Directives. Session completion uses the
same assembler against current committed state. Core owns final commit and
post-commit dispatch.

## Implemented tool callbacks

The [02_12 example](../../examples/02_requests/02_12_tool_callbacks/README.md) adds
`tool_interceptor MyApp.ToolCallbacks` within `ai`. It is an optional trusted
module reference in the same profile used by data, Builder and source JSON.
Without it, the host Agent's optional tool callbacks apply. This includes the
public `Jido.AI.Agent` wrapper. Missing hooks act as identity operations.

The before callback can change arguments only. The shared path resolves tools,
prepares arguments, validates the complete batch, runs operation controls and
executes tools with their retry limits. ReAct collects the whole tool batch
before after callbacks run in call order. Effects are filtered after each
callback. The request transformer sees the effective policy, current candidate
state and completed tool results. Core Exec owns deadlines and cancellation.

The example implements the PR 347 long-key alias workflow with real Actions.
Direct core Exec does not invoke AI callbacks. The later
[09_05 example](../../examples/09_reasoning/09_05_tot_api/README.md) proves this alias
workflow for ToT. Standalone AI helpers and pending-work replay remain required.

## Implemented preflight and tool limits

The [02_13 example](../../examples/02_requests/02_13_tool_limits/README.md) exposes
`timeout`, `max_retries` and `retry_backoff` on both `action` and `flow` tools.
Timeout and backoff use milliseconds. The timeout is positive; retry values
can be zero. Omitted retry fields keep catalog defaults and are omitted from
source documents. All four source formats lower to one execution contract.

Argument preparation and full-batch validation precede all native operation
controls. A native operation control can return `{:interrupt, value}` as well
as `:ok` or `{:error, reason}`. Other control stages keep their existing return
contract. The transient legacy `__tool_guardrail_callback__` runs after all
native checks and before any tool starts. Its original prepared `arguments`
remain available; `validated_arguments` adds the schema-converted map.
Interruption remains a failed request with an interrupt reason. Durable
approval and resume remain a separate requirement.

Core Exec owns callback and tool lifetime. The request deadline bounds all
work; each tool attempt has its own shorter timeout. The named Action, Flow
and direct Exec example runs real tools beyond 31 seconds with a 45-second
budget. Retryable tool errors can use the remaining configured attempts;
core timeouts retain their explicit `retry: false` decision. See the example
for the retry compatibility limits and required legacy facade evidence.

## Implemented session stream activity

The [02_14 example](../../examples/02_requests/02_14_stream_activity/README.md) adds
optional `idle_timeout` and `tool_heartbeat` values under `requests`, in
milliseconds. These settings require `mode :session`. Static DSL, data,
Builder and source JSON use the same validated fields. Omitted values do not
add fields to existing source documents.

`idle_timeout: 0` uses automatic calculation; `tool_heartbeat: 0` disables
tool keepalives. Public Agent and request helpers retain `stream_timeout_ms`,
the older `stream_receive_timeout_ms` alias, and `tool_heartbeat_ms` through
one conversion. Positive tool keepalives preserve runtime and consumer idle
limits during actual tool work. They do not extend tool or request deadlines.
Provider chunks reset internal idle time, including tool arguments without
visible text. They do not create public keepalives outside tool execution.

The session event owner assigns every sequence and owns the timers. There is
no second heartbeat process or sequence handoff. Timer references are transient.
Cancellation, final completion, failure and owner exit stop them. Standalone
execution and durable event recovery still need their port and examples.

## Implemented early tool activity

The [02_15 example](../../examples/02_requests/02_15_early_tool_activity/README.md)
emits a named tool-activity delta while the model still supplies arguments.
The event keeps the existing `:llm_delta` kind, `chunk_type: :tool_call`, and
tool name as its payload. Complete decoding, full-batch admission and controls
still precede tool execution. Empty names emit no delta.

`observability.emit_llm_deltas?` is the shared capture switch for native and
public Agents. Disabling it suppresses public deltas and their telemetry;
provider activity and complete model responses continue. The telemetry master
switch alone still permits enabled request deltas. This corrects the earlier
native telemetry-only interpretation and avoids a second capture option.
All source forms use the same existing profile field. Live `ai.llm.delta`
Signal projection, other methods and durable replay remain required.

The [14_06 example](../../examples/14_resume/14_06_trace_and_cycles/README.md)
adds `observability.redact_tool_args?` (default true). It hides sensitive keys
in tool-start event arguments and leaves execution inputs intact. Standalone
Config's flat `capture_deltas?` and `redact_tool_args?` options lower to these
same native flags. The legacy `capture_thinking?` and `capture_messages?`
options remain accepted without independent filtering behavior.

## Implemented typed Signal boundary

The [02_16 example](../../examples/02_requests/02_16_typed_signals/README.md) uses
static core Signal schemas for all ten public AI definitions. A small adapter
handles known input keys, duplicate rejection, explicit nil and metadata
accessors. Core owns constructors, errors and the CloudEvents envelope.
No new Agent DSL field or second Signal DSL is introduced.

`Jido.AI.Signal.from_event/2` projects canonical events. `emit/1` returns core
Emit Directives for an ordinary Agent Action. The example proves real outbound
Plugin preparation and dispatch, including a committed-state delivery failure.
The [02_17 example](../../examples/02_requests/02_17_signal_delivery/README.md) adds
automatic session delivery. The existing `observability` block accepts
`emit_signals?` (default true). `emit_llm_deltas?` still controls capture before
sequence assignment. There is no new publication DSL.

The session owns events; a bounded transient queue submits Emit batches through
the owning Agent. A final receipt confirms core dispatch, not receiver handling.
Publication adds normal commits and persistence writes. The request result and
the transient delivery report have separate success criteria. Unknown outcomes
are not retried. Core owns committed outbound work and its Directive timeout.
Durable Signal replay and all other reasoning methods remain required.

## Implemented linear methods

The [09_01 example](../../examples/09_reasoning/09_01_linear/README.md) adds
`reasoning :chain_of_thought` and `reasoning :chain_of_draft` to the existing
AI block. Use the same named model, controls, result and request declarations.
DSL, data, Builder and source JSON produce the same Flow behavior. Direct Flow
and ordinary Agent execution use that Flow too.

The simplification pass retains one model operation, output validator, session
owner and event path. Method data selects the default prompt and plain-text
conclusion parser. Declared structured output keeps its validated value; rich
content keeps its order. Linear profiles reject tools and steering. Bounded
object repair remains available through the existing output contract.

The public CoT/CoD Agent wrappers apply their historical prompt defaults before
common lowering. They keep think/draft helpers and printable state fields.
Native empty instructions select the declared method's prompt. Events and
telemetry retain the method, with `:cot` and `:cod` labels. The profile records
the new total request budget and provider timeout mapping. Old Strategy, worker,
CLI and capability entry points remain unported; no second DSL or executor is
added to preserve those implementation types.


The [09_02 example](../../examples/09_reasoning/09_02_method_api/README.md) makes method
selection explicit: namespace `method/0` returns the value used in the existing
reasoning map. Result getters read committed records with an optional request
ID. No new DSL block is needed. The old Strategy module names are read-only
compatibility adapters; core Agent and Flow keep execution ownership.


## Implemented AoT method settings

The [09_03 example](../../examples/09_reasoning/09_03_aot/README.md) adds the existing
single-generation AoT algorithm. Use `reasoning :algorithm_of_thoughts` with
`options(profile: :short, search_style: :dfs, examples: [], require_explicit_answer: true)`.
Options are method data. Named models retain temperature and token settings.
An invalid method option fails before provider work. Empty method settings are
omitted from normalized profiles so existing source-JSON registries need no new
atom identifier.

The shared lowerer and Flow keep all execution. A small method adapter owns
prompt framing and result parsing. AoT returns its complete result map with
search metrics and termination data. Its declared result schema validates the
answer field; the Agent domain field receives the complete envelope. Shared
Output repair can repair that typed answer without discarding method metadata.
No new request owner, executor, tool DSL or graph language is introduced.

## Implemented native Tree of Thoughts

The [09_04 example](../../examples/09_reasoning/09_04_tot/README.md) adds
`reasoning :tree_of_thoughts`. Search settings use `reasoning.options`; model,
tool and control declarations use the common DSL. A small data adapter selects
the next phase. The existing Flow runs every model and tool call. The ranked
result remains a map. Parser repair has a separate bounded counter and cannot
run tools. Native text input works; steering and typed ToT output are explicit
pending contracts. The later public ToT checkpoint below adds facade and
callback evidence; the full old API mapping remains open.

## Implemented public ToT mapping

The [09_05 example](../../examples/09_reasoning/09_05_tot_api/README.md) uses the same
reasoning, model, tool, control and request declarations for public ToT. The
wrapper supplies method defaults to the shared lowerer. `strategy_opts/0` reads
declared settings. It does not choose a runtime. No new DSL block is needed.

Before callbacks prepare arguments before Action validation. After callbacks
receive the raw final retry result. The common path filters effects, updates
candidate state and supplies the next model input. The alias workflow runs in
both a session and an ordinary Agent turn. A later callback failure prevents
all proposed domain changes from committing, while completed tool work remains
visible in failure evidence. Direct core Exec uses the original Action contract.

Method limits remain reasoning data. Provider timeouts remain model settings;
the public `max_duration_ms` compatibility option also supplies a provider
timeout unless `llm_timeout_ms` is specified. The hard request deadline remains
a common control. Public call-budget defaults are documented in the profile.
Retained tree inspection uses request records. Live frontier inspection and
durable resume still require their own contract and examples.

## Implemented native Graph of Thoughts

The [09_06 example](../../examples/09_reasoning/09_06_got/README.md) adds
`reasoning :graph_of_thoughts` through the existing options declaration. Models,
controls and requests retain the common syntax. A small method adapter supplies
phase contexts to the same Flow. Graph data stays in the retained Machine;
completed request metadata holds its snapshot. Successful output remains text.

`min_nodes_for_aggregation` exposes the existing Machine environment threshold
so a native example can exercise connection discovery. Explicit phase prompts
now take precedence over Machine defaults. Common call and time limits bound
the search. Tools, steering, rich input and typed output remain unsupported in
this method slice. Old public GoT helpers and durable graph inspection still
need their port.

The source review found that `aggregation_strategy` was stored but did not
select a distinct algorithm. Retaining that setting does not prove voting or
weighted aggregation. General branching and aggregation across several leaves
also need acceptance examples. Do not add a separate graph executor to satisfy
them; retain core Flow as the composition and execution layer.

## Implemented public GoT mapping

The [09_07 example](../../examples/09_reasoning/09_07_got_api/README.md) connects
`GoTAgent` to the common `Jido.AI.Agent` lowerer. The common Agent can select
GoT directly too. Public explore helpers retain text results and printable
state fields. Method settings stay in `reasoning.options`; the wrapper supplies
the existing model defaults and a finite graph call budget.

Namespace getters inspect retained request graphs with optional request IDs.
Old Strategy names keep read-only getters only. Bounded path inspection can
skip a parent cycle and retain another valid path. No new DSL block, executor
or graph-state owner is added. Live graph inspection remains required.

Busy admission now has one result through the request API and rejected stream:
`:busy`. Other typed admission errors stay unchanged. Admission-failure method
identity remains an observation gap because no runtime job has been created.

## Implemented native TRM

The [09_08 example](../../examples/09_reasoning/09_08_trm/README.md) adds `reasoning :trm`
with `max_supervision_steps` and `act_threshold` in the existing options field.
Each cycle runs reasoning, supervision and improvement through the shared Flow.
Common limits apply to every model call. Declare 15 model calls and iterations
for a full five-cycle example. Source data, Builder, source JSON, direct Flow
and ordinary Agent turns use the same definition and method.

The method selects the highest scored answer, keeps the existing zero-score
fallback and retains ACT convergence and stop precedence. Optional instructions
precede the required phase prompts. Metadata keeps the method state and actual
usage. Failure, cancellation and owner cleanup use the common Session. The
public TRMAgent macro, inspection helpers, CLI/capability APIs, input/state
conversion, richer output and durable recovery remain open.

## Implemented public TRM mapping

The [09_09 example](../../examples/09_reasoning/09_09_trm_api/README.md) lowers
TRMAgent through the common Agent. Its two method settings share native TRM
validation. The wrapper derives a bounded three-calls-per-cycle budget while
explicit limits take precedence. The common Agent can select TRM directly.

Reason helpers retain text results. Inspection keeps reviewed and current
answers distinct and supports an optional retained request ID. The old Strategy
name supplies only deprecated inspection and prompt delegates. No execution
callback or phase owner is added. Active inspection, custom command hooks,
legacy phase-input/state conversion, CLI/capability paths, complete provider
contracts and durable recovery remain required.

## Implemented native Adaptive selection

The [09_10 example](../../examples/09_reasoning/09_10_adaptive/README.md) adds
`reasoning :adaptive` with validated available methods, complexity thresholds,
an optional override and per-method options. A pure selector runs before shared
Flow preparation. It chooses one of the seven existing methods without a model
call. The same declarations work through DSL, data, Builder and source JSON.

ReAct and ToT receive the tool catalog; other methods keep tools disabled,
including after request transformation. Output and repair follow the selected
method. The outer Session remains Adaptive while observations also identify
the selected method. Each new request selects again. Public wrappers, old
phase-input/state conversion, live inspection, complete capability/CLI paths
and durable recovery remain open. Native rich selection and steering are
explicitly rejected. No additional executor or method owner was added.

## Public Adaptive checkpoint

The [09_11 example](../../examples/09_reasoning/09_11_adaptive_api/README.md) lowers
AdaptiveAgent through the same common Agent path. Nested method settings stay
literal data. Native Adaptive retains four settings; the wrapper alone accepts
the old unused default_strategy inspection field. Explicit strategy_override
controls selection. No second DSL or execution runtime is added. Shared method
call-limit formulas now serve Adaptive, ToT, GoT and TRM wrappers.

## Selected method control refinement

The [09_12 cases](../../examples/09_reasoning/09_12_method_controls/README.md) add
`:method_default` as a value for the three existing count controls. Timeout
remains an integer. The static profile retains this policy; the common Prepare
path resolves counts after method selection and request output settings. Fixed
methods and Adaptive use the same rule. Source-format parity includes actual
full TRM requests through DSL/data/Builder/JSON, direct Flow and Agent turns.

## Active Adaptive selection

The [09_13 cases](../../examples/09_reasoning/09_13_active_selection/README.md) make
prepared Adaptive selection visible through a core progress Turn before the
first provider call. This needs no DSL change. The existing Session owns its
one-use grant and canonical metadata. Caller policy context survives; core
binds the new Turn's current state.

## Callable reasoning: 2026-09-07

The [09_14 example](../../examples/09_reasoning/09_14_callable_reasoning/README.md) ports
RunStrategy through the same Profile and Authoring lowerer. One factory creates
a caller-owned Agent/Session for any of the seven supported methods. The factory
uses native source data and adds no DSL form or reasoning executor. The ordinary
Agent example composes that Action with its own state update. Capability Plugin
declarations and CLI use remain separate required ports.

## Reasoning capability refinement — 2026-09-07

[Example 16_01](../../examples/16_capabilities/16_01_reasoning/README.md)
keeps callable reasoning on the existing `plugin` and `route` declarations.
There is no extra AI capability DSL or alternate executor. Seven thin Plugins
share one state schema and command-preparation adapter. `RunCapability` calls
`RunStrategy`, which lowers through the common AI Profile, Agent, Session and
Flow. The native `ai` block can coexist with these explicit capability routes.

Each Plugin declares its fixed method and owns its defaults. `into` selects a
domain result field. The route Action returns the full candidate state. This
makes the v2 result merge explicit at the core commit boundary. Routes must be
declared; core v3 does not install routes from Plugin callbacks. The example
records each old callback and its replacement. Other capability families and
legacy default-Plugin conversion remain required.

## Planning capability refinement — 2026-09-07

[Example 08_01](../../examples/08_planning/08_01_planning/README.md) adds the three
Planning Actions and their capability to the existing Agent declarations.
The public prompts and parsed result maps remain. Core `plugin` and `route`
declarations select the operation and result field. The new common candidate
helper now serves both Planning and reasoning capabilities. It performs one
core Exec call and returns a complete Agent state. It adds no authoring syntax
or execution loop. A mixed Agent retains ordinary routes and separate Planning
and reasoning results.

One request helper handles defaults, supported model inputs, Zoi validation and
provider options for the three Actions. The core pre-validation callback retains
supplied-key information before schema defaults are added. This lets explicit
values equal to schema defaults keep their precedence. Actual mock requests
prove the result of this simplification. Catalog 08's validated plan execution
and repair remain required; a text plan is not executable code.

## Chat capability refinement: 2026-09-07

[Example 16_02](../../examples/16_capabilities/16_02_chat/README.md) adds a Chat Plugin
to ordinary `agent do` declarations and seven explicit routes. The same
shared capability binding used by Planning and reasoning owns the result field.
There is no new DSL keyword or alternate Agent compiler. Callable automatic
tools use core Flow dispatch with their existing turn/error contract. They
remain separate from native ReAct policy and session semantics.

## Prompt refinement: 2026-09-07

[09_15](../../examples/09_reasoning/09_15_prompt_policy/README.md) proves method-selected
prompt defaults through actual model requests. Keep one ReAct default and
resolve it after Adaptive selects ReAct. Normalize omitted/nil/false/empty
public prompt options in the common adapter. Native Adaptive nil selects the
default, while empty text suppresses the base ReAct prompt. Direct native
ReAct nil remains optional instructions. Keep these rules in the existing
profile; no extra DSL keyword or prompt-mode schema is needed.

## Dynamic configuration and public facade: 2026-09-07

[03_01](../../examples/03_tools/03_01_dynamic_catalog/README.md) ports direct and
live tool/prompt changes through portable `jido_ai_config` state owned by the
existing Runtime Plugin. One validated catalog supplies provider schemas and
lookup. Core configuration directives commit live changes. Ordinary Actions
cannot forge the protected key. An active request keeps its admitted catalog
and prompt; later requests use the committed update.

The existing DSL needs no new block. The lowerer supplies the configuration
routes, and native profiles can be selected explicitly. Direct Agent APIs
retain their return shapes. The actual `Jido.AI` facade now compiles from
`shared/facade.ex`; generation delegates remain shared with other callers.
The profile records the new configuration/history view and the Action
migration pattern. No private v2 Strategy state is retained.

Keep the remaining public option/metadata and active-context conversion,
standalone/worker, skill/resource and durable recovery requirements. Complete
root dependencies, full package, consumer, runtime-floor, migration and
rollback gates before treating the package as migrated.


## Implemented skill authoring: 2026-09-07

[18_02](../../examples/18_skills/18_02_skill_authoring/README.md) implements the
`skills` block in a ReAct Session profile. Use `skill Module`, `load_path
"directory"`, and `resource_policy` options. `activation: :lazy` is not an
option: file bodies are always loaded on selection. The earlier full example
is a proposal; its `resources` spelling is now `resource_policy`.

The block lowers to one static `Profile.skills` source. Public `agent_skills`,
source maps, Builder and JSON use that source and the existing core lowerer.
The Session prepares one catalogue per profile at live startup. Its selected
Specs supply the index, loading context and automatic Actions. Static creation
does not perform discovery. No extra compiler, executor or model server was
added. Module Plugins remain explicit Agent declarations.

The linked example defines trust, precedence, runtime-directory resolution,
empty/disabled behavior, live tool/prompt changes, and restore. Pure config
getters do not read transient catalogues; use `Session.skill_catalog/2` for live
Specs, index and diagnostics. Standalone and installed-package gates remain.


## Implemented base tool context: 2026-09-07

An AI profile accepts `tool_context %{...}` as a static base map. The same
`Profile.tool_context` field serves the public Agent option, native DSL, data,
Builder and JSON. It contains portable application values. Runtime identity,
state and skill bindings stay with their existing owners.

[03_02](../../examples/03_tools/03_02_tool_context/README.md) proves live replacement,
request precedence, active snapshots, projection, profile scope and restore.
An explicit `false` or `nil` is invalid; omission gives an empty map. No new
DSL block, compiler or process is needed.
