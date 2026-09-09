# Jido AI migration to Jido v3

Status: migration in progress. User kickoff received 2026-09-06. See the [implementation record](implementation.md).

Goal: complete the production migration and all required acceptance checks.
Preparation is complete. Production implementation started after the user's
migration kickoff. The refinement results, API inventory and complete
release-history audit are recorded below. This goal is not complete when the
isolated examples pass.

Move the complete `jido_ai` package to Jido v3. DSL authoring is milestone 1.
The final result must preserve current AI capabilities through v3 Agents,
Actions, Flows, and Plugins. A passing isolated example does not mean that
the package has been migrated.

The [tool inspection pass](react-inspection-test-transfer.md) retains all
78 ReAct cases. That pass reached 68 passing cases and ten required failures. Two native
inspection transfers and five new boundary cases preserve tool results and
typed Action errors. Buffered and streaming examples cover completion replay,
retained results and a later request. The focused group passes 16 cases.

The [initial-state transfer](react-initial-state-test-transfer.md) adds an explicit
conversation import before Server startup. Four retained ReAct cases, nine new
boundary cases and seven native/public integration examples cover history,
prompt/profile selection, required domain fields and later native reconstruction.
That pass reached 72/78 ReAct cases. Full old Agent checkpoint and Plugin-state
conversion remain required; this helper does not infer old runtime work.

The [terminal-state transfer](react-terminal-test-transfer.md) moves the final
six ReAct cases to public APIs. All 78 now pass, with no removed or skipped
case. Six native buffered/SSE examples cover completed and failed checkpoint
restore, usage, tool history and a later request. Standalone signed tokens
retain separate root evidence. Provider decoding and full old Agent conversion
remain separate requirements.

The root package now uses the local Jido v3, Jido Action beta and Jido Signal
beta projects. All production files remain under `lib`. The root build passes;
the latest complete root result is 2,070/2,430 passed, with 360 failures and
one existing exclusion. The StateOp test transfer consolidates repeated old
constructor checks; its case map records the count change. The subsequent tool
input repair retains existing tests and adds eight root cases and four examples.
The [runner transfer](runner-test-transfer.md) fixes 13 more failures, retains
all 58 original runner cases, and adds one root case and eight examples.
The [stream usage port](stream-usage-port.md) restores fallback accounting and
adds 12 passing root boundary tests. Eight new provider examples include four
required failures caused by ReqLLM numeric-string arithmetic. Those failures
remain part of the dependency gate. The [provider transfer](provider-test-transfer.md)
adds four integration cases, two mock contracts and three response-boundary
cases. Four retained runner cases now use real HTTP. A shared context fix
resolves six further failures without edits to those tests. The complete root
comparison resolves nine failures. The [incomplete response port](incomplete-response-port.md)
restores blank-response failure type and accepted partial images. It fixes one
unchanged root case and adds 16 passing integration cases. The remaining
wrapper-envelope and provider status requirements stay open. Fixing the
remaining groups is the next checkpoint. The [ReAct setup transfer](react-setup-test-transfer.md)
now maps all 78 old setup/lifecycle cases and ports 24 without changing the
count. Shared option preparation fixes and six HTTP examples cover declared,
runtime and request options in Session and Turn modes. The
[ReAct lifecycle transfer](react-lifecycle-test-transfer.md) moves 24 more cases
to native APIs. The full comparison adds no failing case. At that checkpoint, the 78-case file
had 48 passes and 30 required failures. Three added tool-context examples check
state and module identity in native Session, native Turn and public Agents.
The [context transfer](react-context-test-transfer.md) moves 18 more retained
cases and adds four passing boundary tests. It restores protected Thread IDs
and local message refs through the common model boundary. Three new examples
check tool rounds, steering and restored history through buffered/streamed and
public Agents. At the context checkpoint, the file had 66 passes and 12 required failures.
The complete failure comparison adds no failing case. Remaining checkpoint,
usage, inspection, initial-state and release checks stay required.
See the [root package checkpoint](root-package-checkpoint.md) for the baseline. Final release version selection remains deferred.

## Working structure

- [DSL milestone](agent-dsl.md) is the single authoring plan. It combines the
  earlier Agent and Jidoka drafts.
- [Feature port map](feature-map.md) accounts for the current feature families.
- [Public API map](public-api-map.md) records current entry points, generated
  wrapper differences and API cases, with a complete declared-source inventory.
- [Example catalog](examples.md) defines the acceptance behaviors.
- [Checked example catalog](../../examples/README.md) tests the actual local
  foundation and supplies a shared mock model server.
- [Release-history audit](history-audit.md) tracks every commit after v2.0.0,
  PR feedback, user regressions and the v3 evidence required to preserve them.

Use the pinned v2 Git commit as the comparison baseline. The root project now
compiles checked examples and shared support in the `:dev` and `:test`
environments. Production builds compile `lib/` only.

The user's 2026-09-07 priority change sets the next three checkpoints:

1. Use compatible local v3 dependencies and compile every production file with
   warnings as errors.
2. Fix shared test support and obtain a complete root test result, including
   failures. Do not wait for the remaining feature ports before this result.
3. Fix shared failure causes until retained root behavior and acceptance cases
   pass against the same complete package.

Keep the temporary acceptance project and one shared mock during these checks.
Defer a large test-file move, unrelated DSL/example expansion, documentation
polish, full history closure and release/consumer/minimum-runtime checks until
after the first complete root result. These checks remain required for the goal.

## Migration order and exit checks

Perform the three preparation passes below before starting milestone 2. Complete
the historical source review for each feature group before porting that group.
Keep the numbered milestones as the delivery order. The review passes are
checks within that order, not separate feature projects.

| Milestone | Work | Required exit evidence |
| --- | --- | --- |
| 1 — Authoring contract and acceptance foundation | Unify the DSL; define canonical AI configuration and lowering; prove existing four-format Agent/Flow behavior; create excluded-by-default examples and one HTTP/SSE mock | A reviewed authoring contract, working foundation examples, explicit pending AI DSL tests, and a tested mock; no claim of package compatibility |
| 2 — Shared AI operations | Port model facade, model aliases, typed output/repair, query/attachments, tools, result envelopes, validation, context projection, and usage events | Direct Actions run through v3 Exec with recorded model input; current public result/error cases retained; tool state changes no longer require StateOps |
| 3 — Agent DSL and core extension | Add the minimal generic Agent extension support; implement AI profile validation/lowering, Builder and data input, trusted JSON import, generated routes and diagnostics | Pending milestone-1 DSL tests pass; equivalent forms produce the same canonical Agent and Flow and the same live result; malformed definitions perform no model/tool work |
| 4 — ReAct and live requests | Port bounded reasoning Flow; replace worker Strategies and DirectiveExec with owned runtime work; implement request admission/await, streaming, cancellation and steering | Examples 03–06 and request parity tests prove IDs, busy rejection, exact transcript, one terminal event, state preservation and process cleanup |
| 5 — All reasoning and capability Plugins | Port CoD, CoT, AoT, ToT, GoT, TRM, Adaptive; chat/planning/reasoning capability declarations; routing, policy, retrieval and quota | Examples 07–13 and 16 prove each method, limits, result metadata and Plugin ownership; one implementation serves direct and Agent use |
| 6 — Skills, recovery and tools with approval | Port trusted skills/catalog, resource providers, binary attachments, standalone token resume, Agent checkpoint conversion, interception/interrupts and child work | Examples 06, 12, 14, 15, 17; explicit recovery contracts and conversion tests; no process handles or closures in portable state |
| 7 — Package cutover and release checks | Change root dependency requirements, remove replaced v2 internals, port installers/CLI/docs and consumer examples, establish supported API changes | Full root suite and all accepted examples pass; compile/lint/type/docs/package checks; supported runtime matrix; fresh external consumer; migration guide and data procedure |

These are dependency groups, not a claim that the root package stays compilable
after every individual file edit. Perform the root cutover on the isolated
branch, preserve an executable v2 baseline, and commit complete changes that
meet their stated checks. Do not hide incompatible old modules by permanently
excluding them from compilation.

Milestones 2 and 3 can be developed against the isolated examples, but their
production result must live in `jido_ai`. Milestones 4–6 form the required
runtime and feature port before the final package gate. New adapters or stronger
durability are optional additions and must not obscure current feature parity.

## Preparation: three refinement passes

The history audit is complete for the pinned range: all 126 commits after
`v2.0.0` through `fc5bc143`, and all 103 associated merged PRs. The audit also
reads 40 selected local issue/original-PR references, two pre-release context
records and ten upstream context records. Each commit has a source decision
and required v3 cases. All 126 port checks remain pending.

The [audit and review index](history-audit.md) holds the detailed findings.
The [commit ledger](history-commits.md) links each source review, and the
[structured ledger](history-audit.json) records exact case IDs and pending
proof. The feature map also covers the initial v2.0 feature set. A reviewed
commit or an excluded example does not prove a migrated feature.

Use these decisions in all three preparation passes and all four later checks:

| Area | Decision to preserve during the port | First stage |
| --- | --- | --- |
| Authoring and options | One validated AI profile and one lowering path. Preserve rich model inputs, prompt defaults, actual HTTP options, data conversion and trusted callback references. Check all source forms before work starts. | 2–3 |
| Tools, objects and controls | Use real Actions and Flows. Preserve open/strict schemas, tool identity, full-batch preflight, callback order, per-attempt timeout and fresh repair bindings. A completed external tool effect cannot be undone by rejecting later state. | 2–4 |
| Content and providers | Preserve file refs, MIME, binary attachments, generated media and thinking through actual provider encoding, decoding and restore. Include normal/SSE custom headers and the real worker file request. | 2, 4, 6 |
| Requests and observation | Keep admission, busy rejection, ordered events, bounded steering, failure results, usage and cleanup. Preserve caller timeout versus cancellation and accepted incomplete content versus failed transport. Keep the default AoT lifecycle coverage. | 4–5 |
| Runtime and Plugins | Core owns execution and state commit. AI owns AI policy and result projection. Use current Plugin callbacks, common observation policy and core Signal validation. Keep ordinary routes, dynamic tools and supported Plugin choices. | 3–5 |
| Skills and recovery | Use one prepared catalog and resource contract. Preserve lazy loading, parser diagnostics, bounded resources, opaque IDs and binary transport. Bind tenant identity and policy to runtime resources. Rebuild handles on restore; do not serialize them. | 4, 6 |
| Public consumer APIs | Preserve supported direct calls, deterministic test helpers, installers and non-interactive CLI. Record changed API/state shapes and rollback. A module rename is not a reason to drop behavior. | 2–7 |
| Dependencies and release | Test the declared runtime floor with fresh dependencies. Preserve optional cloud packages, provider contracts, docs formats and release configuration. Do not use a dependency bump or historical CI result as v3 proof. | Cutover and 7 |

The [last source review](history-reviews/21-dependencies-and-consumer-compatibility.md)
adds the gateway header case and the Elixir 1.18 dependency regression. It also
records the empty dependency commit and mixed maintenance changes. No history
row can disappear during simplification. Reuse case IDs when several commits
fix the same workflow; package-only changes use named package checks.

### Pass 1 — Check example and feature coverage

Compare the feature map with the current source and tests. Separate proven
behavior, missing acceptance cases, and optional new capabilities. Give each
missing case a milestone, a concrete result, and a failure case.

Initial result, 2026-09-06: the 18 catalog families cover the intended feature
scope. More executable cases are needed inside those families. The existing
suite proves 14 Agent/Flow cases and 13 mock cases. It does not prove full
ReAct, AI request admission, steering, history restore, or shared accounting.
The three pending authoring tests also do not prove source-profile JSON or
full DSL/data equality. The [example priority table](examples.md#implementation-priorities)
now defines the next work.

The [API inventory](public-api-map.md) now maps all 175 production source files
to API cases and baseline tests. It records literal functions and quoted
templates without executing macros. It corrects the generated `await_many`
assumption and identifies old Strategy introspection and public result shapes.
Before each feature port, compile a real consumer and link the exact v3 tests.
The source index does not prove macro-expanded compatibility or runtime behavior.
Reuse one example for several boundaries when the application task stays the same.

### Pass 2 — Simplify authoring and module ownership

Start with one bounded AI profile: named models, a ReAct recipe, Action/Flow
tools, explicit controls, and typed output. Keep the full support-agent sketch
as the desired later surface. Do not require new browser, MCP, handoff, or
durable approval capabilities to complete existing feature parity.

Use one validated AI profile representation and one common lowering path.
Core owns Agent construction, Flow compilation, execution, and commits. AI owns
model/tool policy, reasoning data, context projection, and result interpretation.
Keep pure parsing and search algorithms. Do not copy the v2 scheduler, add an
AI Agent runtime type, or keep separate direct-call and Agent implementations.

Initial result: add a [minimum authoring scope](agent-dsl.md#minimum-authoring-scope)
and a clear normalization rule for route bindings. First extend the existing
`01_06` specification with a small mixed AI/ordinary Agent and all four source
forms. Do not add a public convenience layer until an example demonstrates
what it removes from application code.

### Pass 3 — Review failure and migration boundaries

Trace each important failure from request input through provider/tool work,
state assembly, commit, and cleanup. Identify the owner of every task, request
record, history field, budget, and pending operation. Keep caller timeout,
execution timeout, cancellation, and provider disconnection separate.

Initial result: add acceptance cases for an interrupted SSE stream after a
partial token, cancellation followed by a new request, reversed tool completion
order, tool work followed by failure, and usage after failed work. The current
stream example checks explicit cancellation; it does not yet prove that a
transport failure after partial text cannot commit that answer. This differs
from a complete provider envelope with non-empty text and an incomplete finish
reason, which v2 explicitly accepts. Preserve that compatibility case and
retain output validation as a separate finalization rule.

Core has advanced to `b25084ee`. Its implemented Plugin contract includes
`prepare_dispatch/4` and `await_ready/2` in addition to the earlier callbacks.
The generic Agent authoring extension is still missing. The foundation suite
was rerun on this core: 27 passed and 3 pending DSL cases were excluded.
Refresh this source check when core changes again.

Keep the original v2 revision available for comparison. The root dependency
change must be integrated with the production modules needed to compile on v3.
Milestone 7 verifies and finalizes that change; it is not a promise to keep every
intermediate file compatible with both versions. Until the root compile gate
passes, report isolated-operation results separately from package results.
Do not remove old feature modules merely to obtain a green build.

These are completed first review passes over the plan and current fixtures.
The new cases are specified work, not passing tests. Production implementation
has not started. Resolve each remaining design choice with its first small
example during the applicable milestone.

After the full history audit, repeat the preparation checks. The results on
2026-09-06 are:

| Pass | Refinement result | Work kept for implementation |
| --- | --- | --- |
| Coverage | Keep 18 example families. Place the 22 historical scenario families and their variants inside them. Add the stream-header and minimum-runtime cases. Reuse the existing worker-file case for the later dependency fix. | Add each executable case with its production port and record the exact test result. |
| Simplification | Keep detailed source findings in one review index. The main plan retains decisions and stage order. Share case IDs across commits and use package checks for maintenance-only changes. | Prove one AI profile/lowerer and replace temporary example operations with production operations. |
| Failure and migration | Preserve the PR-derived boundaries for state commit, external effects, stream failure, current callback bindings, tenant resources and optional dependencies. Require fresh consumer and runtime-floor evidence. | Resolve each named boundary through the actual v3 Agent and provider transport. Source review alone cannot close it. |

These passes refined the plan before implementation. The user has now authorized
the migration. Production work has started; a passing package check is still required
before the dependency change can be considered complete.

## Refinement and simplification during implementation

Use this cycle for each feature: add its acceptance case, implement the smallest
complete behavior, simplify the changed code, then rerun the affected checks.
Do not change the accepted behavior to make simplification easier. If a boundary
changes, update the plan, example, and source mapping together.

| Checkpoint | Refinement and simplification work | Exit evidence |
| --- | --- | --- |
| After milestones 2–3 | Review the starter DSL, source-form parity, diagnostics, route/Plugin composition and module ownership; remove duplicate normalization and fixture operations replaced by production code | One validated profile and lowering path; real production operations in the examples; authoring acceptance cases pass |
| After milestone 4 | Review request admission, busy handling, streaming, steering, cancellation and usage ownership; remove duplicate request state and nested scheduling layers | Each runtime resource has one owner; lifecycle and failure cases pass, including the next request after cancellation |
| After milestones 5–6 | Review every feature row, direct/Agent result parity, skills, token resume and state conversion; share common operations while retaining method-specific algorithms | Every retained feature has evidence; conversion and recovery tests pass; no second reasoning engine or mock server |
| Before milestone 7 completes | Review the public API, dependency set, examples, migration guide and package contents; remove temporary duplicate fixtures and obsolete v2 internals | Full package checks pass; no required pending test remains; fresh consumer and rollback procedure are verified |

Each checkpoint also reconciles the historical commit/PR ledger for that feature
group. Link the real v3 test names and run evidence. Keep feedback-derived cases
through simplification, including repaired edge cases that do not appear as
top-level features in the package overview.

Keep each pass limited to the completed feature group. Prefer a local deletion
or a smaller function over a new abstraction. Add a shared abstraction when
two real call sites have the same contract. Record what changed and which tests
prove preserved behavior. A code review without changes can close a pass when
the evidence shows that no simplification is needed.

## Breaking contract map

| Current dependency | Required change | Main affected code |
| --- | --- | --- |
| `Jido.Agent.Strategy`, Strategy State/Snapshot, instruction dispatch | Use AI reasoning data plus Action/Flow execution; retain pure search and parsing algorithms | `agent.ex`, `agents/strategies/*`, `reasoning/*/strategy.ex`, ReAct/CoT worker modules |
| `on_before_cmd` / `on_after_cmd` | Explicit request preparation/finalization and v3 Plugin callbacks | `agent.ex`, convenience agents, `request.ex` |
| `Agent.StateOp` / `StateOps` | Typed tool effects and explicit complete domain-state assembly; protected Plugin keys remain protected | `effects/*`, tool and reasoning execution |
| `AgentServer.State` / `DirectiveExec` | Public command context and owned Plugin runtime dispatch | `directive/*`, task supervisor integration |
| `await_completion` and old snapshots | Explicit request admission, completion Signals and AI result lookup over public APIs | `request.ex`, generated helpers, CLI adapters |
| `Jido.Thread.Agent` and old checkpoint hooks | Agent-owned history, portable AI data, explicit restore and resource reconstruction | ReAct Strategy, `checkpoint.ex`, `agent.ex` |
| Old Plugin manifests/mounts/routes | Canonical declarations and implemented preparation, admission, state, dispatch and runtime-readiness callbacks | `plugins/*`, `plugin_stack.ex` |
| Old tracing and observation contracts | Keep AI event meaning and adapt correlation to v3 Turn/commit/directive events | `observe.ex`, directive helpers, usage/signals |

Do not port against pending core design documents. The current implemented
Plugin callbacks and Agent/Server APIs are the target until core changes them.

## API and behavior decisions

Use v3 `agent do` as the intended primary authoring interface. Keep pure helper
functions and result contracts where practical. A convenience macro may remain
as a wrapper over the same lowering path. Do not preserve removed core private
structs as the new public AI architecture.

Before root cutover, give every documented AI entry point one disposition:
retained, renamed with a migration example, replaced with an explicit new call,
or removed by a named decision. Include all eight reasoning methods, direct
LLM/tool/planning/retrieval Actions, dynamic tool registration, request helpers,
standalone ReAct, skill/resource tools, and CLI/install commands.

Important behavior checks:

- `ask` admission and `await` completion remain separate. A best-effort cast is
  not admission. Normal ReAct busy rejection is the default compatibility
  target; adding concurrent requests is a separate feature.
- Streaming progress is transient. A final validated result and intermediate
  request bookkeeping have different commit boundaries.
- Await success confirms the answer commit. Core dispatches final Directives
  after that commit; a later Directive failure does not undo the answer.
  Completion rejection must not repeat model, tool or effect work. See the
  [completion example](../../examples/02_requests/02_11_completion/README.md).
- Controls, request transforms, tool interception, argument validation,
  approval, retry, and result filtering need one explicit order.
  The [02_12 callback example](../../examples/02_requests/02_12_tool_callbacks/README.md)
  implements argument preparation before validation/controls, retries, ordered
  result callbacks after batch collection, then effect filtering. The
  [09_05 ToT example](../../examples/09_reasoning/09_05_tot_api/README.md) now proves
  the same path for tree search. Pending-work replay remains required.
  The [02_13 limit example](../../examples/02_requests/02_13_tool_limits/README.md)
  adds the transient legacy preflight after native controls, with whole-batch
  rejection and callback cleanup. It also proves real Action/Flow tools beyond
  31 seconds. Core timeouts now carry an explicit no-retry decision, which AI
  retains. The migration guide must state this v2-to-v3 change. Permitted
  retries use the v3 typed Action error contract; legacy error-map inputs and
  direct AI execution facades still need their compatibility examples.
- The [02_14 stream activity example](../../examples/02_requests/02_14_stream_activity/README.md)
  uses the session event owner for idle timers and tool keepalives. Provider
  chunk activity resets runtime idle time; public keepalives apply during tool
  work only. Keep caller enumeration timeout separate from runtime idle,
  attempt timeout and total request deadline. Standalone paths and durable
  sink/sequence recovery remain required.
- The [02_15 early-activity example](../../examples/02_requests/02_15_early_tool_activity/README.md)
  preserves tool-name deltas before argument completion and executes the real
  document Action only after admission. Native and public Agents share the
  existing delta capture flag. Provider activity remains independent of public
  capture. Port the separate Signal projection without inventing missing tool
  IDs or making early activity an execution guarantee. A declared tool round
  with no usable call or text now fails with `{:incomplete_response, :tool_calls}`
  before history or model completion, while usage remains counted. In v2 an
  empty round could continue until a limit applied. Record this behavior change
  in the migration guide; blank successful stops and object validation remain
  separate cases.
- The [02_16 Signal example](../../examples/02_requests/02_16_typed_signals/README.md)
  replaces the internal AI Signal DSL with static core schemas. Record the new
  schema metadata, Zoi errors, explicit timestamps, duplicate-key rejection and
  protected type/data options in the final migration guide. Pure projection and
  explicit core Emit delivery are tested. The [02_17 session example](../../examples/02_requests/02_17_signal_delivery/README.md)
  adds automatic delivery, bounded queues, one-use grants and core dispatch
  receipts. Record the extra Agent commits, transient status API, queue limits,
  default `emit_signals?` flag and timeout/restart limits in the migration guide.
  Durable delivery and other methods remain required.
  Shared Turn helpers now use core Exec; all legacy execution options and
  per-run logging behavior still need their final compatibility disposition.
- Count model usage even when later execution fails or is cancelled. A shared
  budget must include nested calls; token reporting does not prove a hard
  external-provider spend cap.
- Preserve ToT/AoT structured results and method-specific diagnostics. Preserve
  multimodal context and recent skill resource-provider/binary features.
- Retain current limits unless a migration decision changes them. Do not add
  automatic retry to effects whose external outcome is unknown.

## State and stored data

Use four separate data classes: canonical static authoring configuration,
portable Agent/Plugin state, local Flow execution data, and transient runtime
resources. Model clients, stream sinks, tasks and callback closures belong in
the last class. Agent serialization and AI token serialization are separate.

Current interrupted streamed Agent requests restore as failed. Preserve that
behavior for the first port. Any durable approval/resume feature must store
explicit AI pending-work data and revalidate correlation and authority on resume.
Exec execution structs are not deployment-safe checkpoints.

New pending v3 request records reserve 512 string bytes for a small terminal
failure. Completed and cancelled records release the reserve. Under a state
limit, failure details can be replaced by an explicit `details_elided?` marker.
Earlier v3 records default the reserve to nil and do not have this space
guarantee. This schema addition is not an offline v2 conversion procedure.

If a Plugin rejects every completion or storage rejects the write, the owner
reports `completion_uncommitted` while the real request record remains pending.
An unknown write or call result is `completion_uncertain`; it must not trigger
replay. Agent or owner loss can prevent delivery, and await on a stopped PID
returns `agent_server_unavailable`. Durable error and sink recovery remain
required migration work.

Define and test an offline conversion procedure for old stored Agents. Read
with the old application; map history, result and pending work into the new
schema; validate with v3; then write with the new persistence API. Keep a backup
and reject unsupported formats explicitly. Test completed, interrupted, failed,
and expired requests and standalone token compatibility independently.

Do not run v2 and v3 writers against the same records during conversion. A
rollback uses the old application and its backup; it must not interpret newly
written v3 records as v2 data.

## Test strategy and proof limits

Use one local mock LLM server for the new examples. Run real ReqLLM encoding,
HTTP/SSE decoding, Jido Actions, Flows, Agent validation and live commits. Record
actual requests and verify tool IDs, schemas, message history, usage, retries,
errors and unused/unexpected script entries. Use barriers and process monitors
for streaming, concurrency and cancellation.

Integration examples are excluded from default runs and can be enabled with
`--include integration`. Unimplemented AI DSL acceptance tests use the separate
`pending_dsl` tag. An ExUnit include filter overrides exclusions, so pending
tests must not also carry `integration`. They fail at the real missing feature when explicitly
enabled. Exclusion is not passing evidence. Do not write assertions that pass
because the feature is absent.

Use current v2 tests as behavior evidence, not as a requirement to retain old
private state layouts. Carry their important assertions into v3 examples.
Keep paid provider tests optional and separate. A local mock does not prove
all provider dialects, model quality, or production service behavior.

## Final package gate

- Root package resolves and compiles against the selected v3 dependency set.
- Run the named RELEASE checks in the
  [release/documentation review](history-reviews/06-release-and-documentation.md),
  and the [dependency/consumer review](history-reviews/21-dependencies-and-consumer-compatibility.md).
  Include both documentation formats, actual provider contracts and a fresh
  packaged consumer. Record the runtime, dependency graph and shared workflow
  revisions used for validation.
- The history audit has no unreviewed commit and no retained historical behavior
  without passing v3 evidence. All PR-derived integration cases run. Maintenance
  rows have the named release checks, and any newly included upstream commits
  have been audited. Removal of public behavior requires an explicit user decision.
- Every feature-map row has an accepted example or an explicit migration
  decision. Every required example runs; no pending tag hides a required port.
- The API inventory has no unmapped retained public surface. Verify real
  consumer exports, options and result shapes, including generated wrappers.
  Record replacement APIs for old Strategy introspection and directives.
- All current reasoning methods, skills, resource formats, direct actions,
  request helpers, CLI and installers have behavioral acceptance evidence.
- State preservation, control order, transcript order, limits, portability,
  interruption, restore, and worker cleanup pass meaningful failure tests.
- Root tests, examples, formatting, warnings-as-errors, lint, Dialyzer, docs,
  package build, and a fresh consumer pass. Verify Elixir 1.18/OTP 27 as the
  declared floor in addition to the development runtime.
- Publish a migration guide with dependency changes, API examples, state
  conversion and rollback instructions. Select final release ranges only after
  the dependency versions are published and verified.

The current preparation work establishes the migration contract and acceptance
foundation. The full goal also includes all seven production milestones.
None is marked complete from the isolated test result alone.

## Current evidence and next change

The user authorized implementation on 2026-09-06. The first production slice adds
AI profile validation, a Spark extension, common lowering, source-profile JSON,
and bounded model/tool Flows. The temporary acceptance project compiles these
production files against the local v3 trees. The root dependency cutover remains
pending, as required by the staged plan.

See the [implementation record](implementation.md) for exact test results,
source moves, the core extension, and the first simplification pass. No history
row is marked fully ported from a partial example. Continue with the missing
shared-operation and authoring cases, then session admission, streaming and
request APIs. Port the existing public facades through these shared operations
before removing their v2 runtime dependencies.

## Implemented tool-effect migration decision

The [02_10 example](../../examples/02_requests/02_10_tool_effects/README.md) tests the
first v3 effect path. Replace a tool's StateOp list with one complete state
proposal. Build that state from the trusted `context.agent_state` snapshot:

```elixir
next = %{context.agent_state | count: context.agent_state.count + 1}
{:ok, %{count: next.count}, [Jido.AI.Effects.state(next)]}
```

Use normal map operations to construct a complete replacement, including
nested changes or removal of optional fields. The assembler rejects parallel
or intervening writes to the same top-level field and preserves unrelated
committed changes. It applies core schema, size and Plugin ownership checks.
Later tool rounds see the accepted candidate. Failed or cancelled output does
not commit it. A normal terminal Agent Action returns complete state directly.

Use a typed core Directive for work that must follow the final state commit.
Core `Directive.Emit` remains available with an actual `Jido.Signal`.
`Jido.Plugin.Dispatch.send/2` requires the Dispatch Plugin. Replace the old
Schedule shape with `Jido.Plugin.Scheduler.schedule/2` and declare the Scheduler
Plugin. A scheduled message is a Signal. AI adds no timer owner.

Direct Action I/O is appropriate when the current model turn needs its result.
Filtering returned effects or rejecting later output cannot reverse that I/O.
Final delivery belongs after accepted output and core commit. The local-file
and notification-sink tests enforce this PR 318 decision.

The public Effects facade retains tuple normalization, policy intersection,
filtering and immutable application. `apply_result/3` returns the original
Agent, no Directives and an error in its fourth tuple element when a proposal
fails. It does not commit or dispatch. Stored tool effect data is inspection
data; it must not be replayed as a durable work request. The full migration and
rollback guide, all method ports and package validation remain required.

## Implemented CoT and CoD migration decisions

The [09_01 example](../../examples/09_reasoning/09_01_linear/README.md) ports the native
linear method profile and public CoT/CoD Agent helpers through the existing
Agent/Flow implementation. It also runs direct Flow and ordinary Agent calls.
Use `reasoning :chain_of_thought` or `reasoning :chain_of_draft`. Tools and
steering are invalid for these methods; structured output repair uses the
shared bounded path.

| Existing input or behavior | Current v3 mapping |
| --- | --- |
| CoT `think`, `think_sync`, `await` | Thin helpers over the common request API |
| CoD `draft`, `draft_sync`, `await` | Thin helpers over the same request API |
| `strategy_opts/0` | Legacy model/prompt inspection; execution reads the AI profile |
| Missing, nil, false or empty public prompt | Method-specific default; explicit text and module attributes remain |
| No `max_tokens` option on CoT/CoD | Provider default remains; explicit generation settings retain precedence |
| `llm_timeout_ms` | Provider `receive_timeout`; `llm_opts` can override it |
| Total linear request duration | New 60-second default; set `request_timeout_ms`, or native `controls.timeout`, for longer work |
| CoD Signal/telemetry strategy label inherited from CoT | Actual `:cod` label; canonical records/events hold `:chain_of_draft` |
| Plain model text | Parsed conclusion or unchanged text; raw text and steps remain in metadata |
| Rich content or typed objects | Original ordered or validated value; printable `last_result` at the public display boundary |

The parser fixes Unicode byte offsets, adjacent markers, indented conclusions
and false word-prefix matches. These are explicit corrections, not a claim of
identical malformed-input behavior. The shared recovery path now retries only
core's exact session-owner `:restarting` refusal in addition to existing reentry
refusals, within its five-second pre-admission deadline. Unknown commit results
still cannot be replayed.

Old Strategy/worker/Machine APIs, selection/introspection helpers, CLI adapters,
capability Plugins and old stored-state conversion remain required. In
particular, direct v2 CoD empty-prompt delegation still needs its own mapping.
Non-streamed generated media passes; streamed generated media remains open.
The isolated acceptance project does not close the root dependency or package
gates.


The [09_02 mapping](../../examples/09_reasoning/09_02_method_api/README.md) now resolves
linear method selection and inspection. Use namespace `method/0` and result
getters. Old Strategy module names keep deprecated getters only. Replace old
execution callbacks and action atoms with declared Agent routes and the shared
Session API. The retained CoT Machine compiles without Fsmx; its data API and
legacy telemetry remain. Direct v2 CoD's explicit empty-prompt fallback is
available by setting native instructions to the CoT default explicitly.
CLI, worker APIs, capability Plugins and complete state conversion remain open.


## Implemented AoT migration decisions

The [09_03 profile](../../examples/09_reasoning/09_03_aot/README.md) records the AoT
source mapping. Preserve one model generation with in-context search examples,
its prompt profiles/search preference, parser and complete structured result.
The native method options belong in the existing reasoning block. Generation
options stay with the model. Typed result schemas validate the AoT answer
field while the whole result map reaches the Agent field and output controls.

AoTAgent explore helpers now use the common Agent and Session. Namespace
method selection and result inspection replace old Strategy execution types;
the old module remains a deprecated getter. Machine/Result retain their data
APIs without Fsmx. Native option validation is strict; the public wrapper keeps
legacy example and temperature normalization. Shared request timeout and
infrastructure-failure rules apply.

The historical AoT Signal/telemetry lifecycle case stays in the default suite.
Its migrated temporary version uses real provider decoding and measured usage
and duration. New feature cases remain excluded integration tests. Transfer
the default case when the root mixed-method suite is ported. Do not treat the
still-v2 root file as passing or remove this coverage at package cutover.

## Implemented native ToT migration decisions

The [09_04 profile](../../examples/09_reasoning/09_04_tot/README.md) ports native tree
search through the common Flow. It retains separate generation/evaluation,
frontier selection, bounded parser repair, tool rounds, ranked results, usage
and request identity. The Machine and Result keep their module names in shared
code. The old Fsmx dependency is removed from this Machine. Node and branch
limits now bound actual accepted candidates before evaluation.

The 23 integration cases cover native execution and request boundaries. The 18
retained Machine/Result tests also pass on v3. The later public checkpoint below
adds helpers, namespace getters, Strategy inspection mapping and the exact
PR 347 alias workflow. CLI, capability and full failure/recovery matrices remain
open. Typed ToT results and rich input need explicit examples before acceptance.
Root dependency cutover and package gates remain pending.

## Implemented public ToT migration decisions

The [09_05 profile](../../examples/09_reasoning/09_05_tot_api/README.md) adds 28 public
API and callback cases. `ToTAgent` is a thin common-Agent wrapper. Namespace
getters read retained request records, including failed search nodes. Old
Strategy names remain read-only adapters. Old command execution moves to core
Agent/Flow and Session; custom command hooks still need an explicit migration.

The PR 347 alias case uses the same Actions in native sessions and ordinary
Agent turns. Raw final retry results reach the after callback before effect
filtering and model conversion. The old inbound result Signal maps to core-owned
execution plus canonical observations. Do not introduce a second executor to
retain that implementation detail. Before/after failures, denied alias effects
and later batch callback failure have real execution evidence.

The refinement pass separated method options, provider timeout and total
deadline. It retained the public duration-to-provider-timeout mapping and set a
derived finite public call budget so a valid search can exceed ten model calls.
The public profile documents the new limits. Active tree snapshots, runtime
model/state overrides, typed results, rich input, complete provider variants,
CLI/capability paths and durable recovery remain required. These tests do not
close any full history row or the production dependency gate.

## Implemented native GoT migration decisions

The [09_06 profile](../../examples/09_reasoning/09_06_got/README.md) ports the current
GoT generation, connection and synthesis phases through the common Flow. The
Machine retains its data API and legacy telemetry option without Fsmx. Native
phase observation uses the common path. Request metadata retains nodes, edges,
settings, termination and measured usage. Failure retains graph evidence.

The refinement pass found two baseline gaps: aggregation mode settings did not
select voting/weighted algorithms, and default search usually synthesized one
leaf. Keep distinct mode behavior, general branching and aggregation across
several leaves as explicit requirements. Settings-only tests do not close them.
Native phase prompt overrides now work; the profile records this correction.

The graph context example uses actual node IDs from the model request. One
request-based reply form extends the shared mock; no second server or graph
state injection is added. The default mock contract covers this reply form.
The integration example adds graph traversal evidence for PR 314, including
duplicate paths, disconnected nodes and a cycle.

Public GoT macros/getters, old Strategy mappings, runtime state overrides,
CLI/capability paths, typed/rich contracts, complete provider variants, active
graph inspection and durable recovery remain open. The root package cutover
still requires the full method, API, history and release gates.

## Implemented public GoT migration decisions

The [09_07 profile](../../examples/09_reasoning/09_07_got_api/README.md) adds public
GoT authoring, explore helpers and retained graph inspection through the shared
Agent/Flow/Session. It preserves successful text output, option inspection and
separate request results. The old Strategy has five deprecated getters only;
execution callbacks map to normal core routes and the shared request owner.

The refinement pass adds a bounded cycle case for path inspection. A valid
alternate parent path survives, and a graph with only cyclic parent chains
returns no path. Existing acyclic behavior stays covered. A real 14-call graph
also verifies the public budget derived from `max_nodes`.

Busy refusal had two error forms depending on when core rejected admission.
The request API now returns `{:error, :busy}` and sends the same stream reason
for both. Duplicate-ID protection and other typed errors remain covered.
Admission-failure events still need an authoritative method identity instead
of their legacy default; include custom routes in that next observation case.

Runtime state overrides, typed/rich contracts, distinct aggregation algorithms,
general graph construction, active inspection, CLI/capability paths, full
provider variants, durable conversion/recovery and all root package gates
remain open. No history row is closed by this public API slice.

## Implemented native TRM migration decisions

The [09_08 profile](../../examples/09_reasoning/09_08_trm/README.md) runs TRM phase work
through the existing Flow and request owner. The method stores phase data; it
does not execute provider work. The five support modules retain their names,
finite transitions replace Fsmx, and usage uses the shared nested merge.

The acceptance cases preserve the baseline selection and halt rules, including
the zero-score fallback, maximum-step precedence and the near-maximum ACT stop
that uses the legacy threshold termination value. Phase failures retain their
original causes and usage. Output controls see the selected answer. Required
phase prompts remain in place when native instructions are supplied.

The simplification pass retains two method settings and the existing controls
and model declarations. It adds no TRM runner or private tool executor. The
public wrapper must derive a finite three-calls-per-cycle budget; that wrapper,
namespace getters, old command/phase-input conversion, runtime overrides, CLI
and capability APIs, full provider/media contracts and durable state recovery
remain open. Package, consumer, minimum-runtime and rollback gates are unchanged.

## Implemented public TRM migration decisions

The [09_09 profile](../../examples/09_reasoning/09_09_trm_api/README.md) ports the
public macro and retained inspection APIs through the existing Agent lowerer.
The wrapper keeps `reason`, `reason_sync`, `await` and `strategy_opts`. It derives
a finite call budget from three model phases per cycle, preserving explicit
limits. It keeps the default alias, description, generation options and string
convenience fields. The common Agent can select TRM directly.

Six namespace getters read retained method data with optional request IDs.
Deprecated Strategy delegates retain those getter and prompt names. Execution
callbacks, action atoms and method-owned state move to core routes, Flow and
Session; they are not reintroduced as a parallel runtime. The simplification
pass keeps the macro to settings and public aliases. Custom command hooks,
legacy phase-input/state conversion, runtime overrides, active inspection,
CLI/capability entry points, complete provider/media behavior and durable
recovery still require examples and implementation before final acceptance.

## Implemented native Adaptive migration decisions

The [09_10 profile](../../examples/09_reasoning/09_10_adaptive/README.md) selects an
existing method before common Flow preparation. It uses the retained keyword
and complexity algorithm. Executable profiles reject unknown or empty method
sets, unavailable overrides and invalid method settings. Inert legacy analysis
retains its old fallback. No model call is used for selection.

The selected method supplies prompts, generation defaults, tools and output
policy. Common limits still apply. ReAct and ToT keep tool execution through
core Exec; other methods cannot enable tools through a request transformer.
Typed AoT repair keeps the selection. A later request selects again, and
ordinary core Actions remain available while the session is active.

Selection metadata is separate from the selected method's result. The outer
request remains Adaptive, with an explicit selected-method field in model/tool
observations, Signals and telemetry. The simplification pass extracted one
selector and kept the shared Flow and owner. Native options omit the baseline
`default_strategy` field because it was stored but unused in selection. Its
public compatibility mapping, public AdaptiveAgent/inspection APIs, printable
failures, custom hooks, old input/state conversion, runtime overrides, active
inspection, full CLI/capability/provider/media support and durable recovery
remain open. Package, consumer and rollback gates are unchanged.

## Public Adaptive checkpoint

The [09_11 profile](../../examples/09_reasoning/09_11_adaptive_api/README.md) records
the public Adaptive port and its 22 integration cases. The refinement pass
removes the old selection/dispatch runtime and keeps a thin authoring wrapper.
The shared selector and method Flow own execution. Public wrappers now use one
call-budget helper for ToT, GoT and TRM, including Adaptive choices.

Remaining work includes active inspection, custom command and state conversion,
runtime overrides, CLI/capability and skill/resource paths, complete provider
contracts and durable recovery. The root dependency, package, consumer, runtime
floor, migration and rollback gates remain required before completion.

## Selected method control refinement

The [09_12 refinement](../../examples/09_reasoning/09_12_method_controls/README.md)
fixes the initial combined Adaptive budget. Default count policy stays in the
existing controls and resolves through the common profile path at request start.
This also preserves typed-repair allowance after per-request output changes.
The refinement does not add another DSL layer or method runtime.

## Active Adaptive selection

The [09_13 profile](../../examples/09_reasoning/09_13_active_selection/README.md)
closes active Adaptive selection/score inspection. The first wider run caught
an old worker snapshot passed as caller context; core rejected it. The update
now drops runtime-owned fields and retains caller policy context. Progress uses
a one-use owner grant and current core state. It adds no execution owner.

Active method phase data, state/command conversion, runtime Agent-state options,
CLI/capability/skill paths, full provider and durable-recovery contracts, and
root package acceptance remain required.

## Callable reasoning migration decision: 2026-09-07

[09_14](../../examples/09_reasoning/09_14_callable_reasoning/README.md) moves RunStrategy
to one validated profile factory and the common Agent/Session/Flow implementation.
It retains isolated calls and their public result envelopes. An existing host
runtime is supplied through caller context; otherwise the core Agent is standalone.
Remove the old implicit global instance and seven internal runner wrappers. Their
behavior is proved through actual model requests, concurrent calls and monitored
cleanup. This closes that obsolete runner dependency, not milestone 5 or 7.
Capability Plugins, CLI use, complete option/metadata parity, nested AI tool
budgets, state conversion and package/release checks remain required.

## Milestone 5 checkpoint — reasoning Plugins, 2026-09-07

[Example 16_01](../../examples/16_capabilities/16_01_reasoning/README.md)
ports the seven reasoning capability Plugins. The refinement removes seven
copies of the old callback path. Existing core Plugin/route declarations bind
one shared adapter and `RunStrategy`; each result changes one declared domain
field in a complete candidate state. Tests cover mixed native AI profiles,
ordinary routes, Plugin order and defaults, actual method calls, failures and
cleanup. A core `state_spec/1` error-handling regression is fixed with public
Agent-constructor tests.

Milestone 5 remains open for the other capability families and complete method
parity. Root dependencies and lockfile remain at the v2 baseline. Root package,
consumer, minimum-runtime, migration and rollback gates remain required. No
release or history row is complete on the strength of this isolated build.

## Milestones 2 and 5 checkpoint — Planning, 2026-09-07

[Example 08_01](../../examples/08_planning/08_01_planning/README.md) ports all three
Planning Actions and the Planning capability. The full AI acceptance suite
passes 678 cases; the focused Planning/reasoning and native Plugin/API selection
passes 89. Model calls now use one provider boundary. A shared candidate helper
serves Planning and reasoning through core Exec. No DSL syntax was added.

The refinement found and corrected configured-default handling, current Agent
struct access, and score capture loss. Real HTTP responses and requests verify
the parser, model, option and usage behavior. The final core error-guard checks
also completed: 1,268 passed, the same 11 known research failures, one approved
exclusion, 93.9% coverage; lint, Dialyzer, docs and package checks passed.

The root dependency and lockfile cutover remains open. So do validated plan
execution/repair, Chat and other capability families, full public API/legacy
conversion, skills/resources, durable recovery, CLI and all release gates.

## Chat execution checkpoint: 2026-09-07

[Example 16_02](../../examples/16_capabilities/16_02_chat/README.md) now ports Chat and
its seven public Actions through the shared model/tool code and core Agent,
Flow and Exec. The refinement pass removed repeated default/model preparation
and the recursive tool executor. Planning shares the new input helper.

The tests exposed unsafe embedding telemetry access, an untyped-map key
conversion error and unchecked structured output. The port fixes them and
records the result/API changes. It also removes duplicate assistant messages
from later tool rounds and requests real embedding usage for observation.
The callback default no longer requires a global v2 task supervisor.

Continue with remaining capability Plugins and their operations, full facade/CLI
and skill/resource coverage, legacy state conversion and recovery. Keep failed
provider/output usage in the accounting gate. Complete the root dependency,
package, consumer, minimum-runtime and rollback checks before release.

## Routing and Policy refinement: 2026-09-07

[Example 16_03](../../examples/16_capabilities/16_03_routing_policy/README.md) executes
ModelRouting and Policy through the current core Plugin contract. Both use
committed configuration. Policy follows the approved structured-error decision.
Custom native AI routes receive the same validation and model selection as the
declared capabilities. Ordinary domain routes retain their input contract.

The simplification pass combines three copies of route binding and five copies
of option validation. It adds no DSL keyword, router, runtime process or model
executor. Actual HTTP tests exposed missing native model overrides, a mixed-key
input defect and a missing forced-object-tool response in the shared mock.
The port fixes all three and tests the streamed object protocol as well.

Continue with Retrieval, Quota and the default PluginStack contract. Keep
per-request native model evidence separate from within-loop provider changes,
WebSocket continuation and all public option forms. Those history cases and
the complete state conversion, recovery and package/release gates remain open.

## Retrieval refinement: 2026-09-07

[Example 07_01](../../examples/07_retrieval/07_01_memory/README.md) ports retrieval
Actions, ranking and enrichment. The unsupervised global ETS heir is replaced
by an explicitly supervised shared Store. It survives individual Agents and
caller tasks. A store restart starts empty. Core live admission may read it;
pure Plugin preparation does not. The existing core Flow can call RecallMemory
as an actual model tool.

The refinement keeps configuration in Plugin state, external memory with its
owner, and Action results in the declared domain field. It combines repeated
namespace/input handling and retains one model/tool execution path. Tests prove
that an unknown string key no longer discards known memory fields. Invalid text
conversion cannot kill the store. A later failed Agent commit does not undo a
completed write. Record these rules in the final consumer migration guide.

Continue with Quota accounting and default PluginStack integration. Complete
old memory import, full source forms, durable backup/restore and application
setup during the full migration and package gates. Root dependencies remain v2.

## Quota port and refinement: 2026-09-07

[13_01](../../examples/13_policy/13_01_quota/README.md) now exercises one external
quota owner through real Agent/Flow/Exec model work. The refinement uses one
call boundary for Chat, native reasoning, repair and nested built-in calls.
Atomic admission precedes the model invocation; completion records cost before
Agent commit. Cancellation and transport failure retain observed partial tokens.
Unknown and imported aggregate calls are explicit. Reset and expiry protect the
replacement window from old active call results.

The examples distinguish guarded calls from HTTP attempts and final requests.
They preserve legacy token fallback, status/reset envelopes and scope behavior.
V2 tuple/map import is validated before any write. The Store must be supervised;
there is no implicit global owner. See the profile for the changed zero-report
rule and the limits of window-local duplicate protection.

Continue with default PluginStack integration and the remaining full package
requirements. Resolve raw RunStrategy model-tool JSON schema export without
narrowing its public atom input. Preserve the open provider usage provenance,
source-format, state conversion, durable recovery, consumer, runtime-floor and
rollback gates. Root dependencies remain unchanged. The migration goal is active.

## Default Plugin integration and refinement: 2026-09-07

[16_04](../../examples/16_capabilities/16_04_plugin_stack/README.md) now uses one Plugin
composition helper behind all public Agent option adapters. Policy and
ModelRouting remain defaults. Optional Retrieval and Quota use supervised
application stores. Declared AI capability routes return into
`capability_result`, preserving typed model answers and request records.
Explicit route choices, static parameters and caller module attributes survive
conversion. Referenced executable modules are ready before core validation.

The private RunStrategy factory also uses the default list. It keeps core
Session/Exec ownership and the outer budget binding. No old TaskSupervisor,
second executor or additional mock was introduced. Map core-default overrides
still require explicit Memory/Thread/Identity state conversion; `false` does
not disable AI Policy. The next request pass must fix admission-failure method
identity and finish the documented public option/metadata gaps. Keep all
catalog, skill/resource, recovery, root dependency, consumer, runtime-floor and
migration/rollback gates in scope.

## Request admission and model options: 2026-09-07

[02_18](../../examples/02_requests/02_18_admission/README.md) fixes rejection events
through the declared route/profile binding. A synthetic event retains its raw
cause and correlation; duplicate IDs keep the original stream open. Missing
bindings report `unknown`. Concurrent definition replacement remains a separate
core gate.

[02_19](../../examples/02_requests/02_19_model_options/README.md) carries public model
overrides through the same runtime binding as native requests. Request options
use the existing effective-model normalizer. Invalid outer containers now fail
admission. The common mock supports buffered Responses text, tools and objects;
streaming Responses and WebSocket ownership remain open.

The refinement reuses route lookup, model resolution and option merging. It
adds no DSL term or execution owner. Continue with failed-call metadata and
the Adaptive default-prompt rule, then the remaining public API, skill/resource,
state conversion and runtime replacement work. Complete root dependency,
package, consumer, minimum-runtime, migration and rollback gates before release.

## Failed call metadata and Adaptive prompts: 2026-09-07

[02_20](../../examples/02_requests/02_20_call_counts/README.md) retains known started
model-operation counts after failure or cancellation. HTTP attempts and Quota
charges remain separate. Recovery preserves committed data and leaves an
uncommitted count unknown. Real provider, tool and repair work proves these
boundaries; duplicate observations cannot change a completed record.

[09_15](../../examples/09_reasoning/09_15_prompt_policy/README.md) resolves the shared
ReAct default after Adaptive selection. Public empty prompt values use their
default. Native empty instructions keep their current meaning. DSL, data,
Builder, trusted source JSON, direct Flow and ordinary Turn agree. The change
uses the current profile and lowerer without an additional DSL term.

Continue with the remaining public and runtime APIs, dynamic tools/prompts,
raw RunStrategy tool-schema export, skills/resources, state conversion and
recovery. Root dependency, full package, consumer, minimum-runtime, migration
and rollback checks remain required.

## Raw reasoning tool port: 2026-09-07

[09_16](../../examples/09_reasoning/09_16_reasoning_tool/README.md) closes the raw
RunStrategy model-tool schema gap. All seven methods execute through the
existing Action, core Exec and private Agent/Session. Native and public Agent
authoring work; DSL/data/Builder/source JSON agree. Shared Quota, cancellation,
provider errors and result envelopes survive the nested call.

The refinement uses Zoi's existing traversal for JSON export. Generic atom
fields export as strings; the original direct Action schema remains intact.
Model strings resolve only to existing atoms before ordinary validation.
Unknown names cannot allocate atoms. Open objects, strict export and defaults
keep their current behavior. No additional DSL term or executor is introduced.

Continue with dynamic tools and prompts, remaining facade and worker APIs,
skills/resources, old state conversion and recovery. Root dependencies, full
package validation, fresh consumers, supported runtime versions, migration
and rollback remain open.

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

## Public context and history refinement: 2026-09-07

[02_21](../../examples/02_requests/02_21_context_views/README.md) adds nine integration
cases for the compiled public context helpers. Committed history retains
thinking, timestamps, tool IDs, reasoning details and references through reads
and real model requests. String-keyed entries use the same conversion. Invalid
roles, tool calls and live values cannot commit through the replacement helper.

A real host Action changes history while a provider call is held. The active
call uses its admitted history. Its completion appends to the new committed
history, and the next request uses that history. Plain Agents and profiles
without history retain an absent view; a neutral definition no longer crashes.
Portable v3 reconstruction retains entries and fails pending work without replay.

The shared Context now uses its existing entry conversion for message import;
the duplicate converter was removed. History replacement uses ReqLLM's message
schema and the core Agent update path. New assistant and tool entries retain
request references. No DSL term, generated route, runtime owner or mock was added.

This is an explicit mapping from the old private `run_context` helpers to
committed domain history. Use Session steering/injection for active input.
Full legacy configuration views, old-state conversion, skill activation and
compaction, standalone/workers, durable recovery, root dependency/package,
consumer, minimum-runtime, migration and rollback checks remain required.

## Standalone authoring and token foundation: 2026-09-07

[14_01](../../examples/14_resume/14_01_standalone_authoring/README.md) starts the
standalone port with 12 integration cases. An existing ReAct Config lowers
through the same Profile, ToolCatalog, Agent and Flow path. Tests execute real
aliased tools, state effects, request transforms, typed repair, streaming,
limits and cancellation. Provider options and callbacks remain in live context.
Builder and Codec forms run the same definition. Config provider tool schemas
now retain public aliases, including two names for one Action.

The internal stream owner must supply explicit native request-time and total
tool-call limits; the old Config has neither field. This step does not change
the old public Runner's default limits or claim that its replacement is complete.
The next runtime step must preserve long tools and the legacy iteration result.

The actual Token and deprecated Event modules now compile from shared source.
Valid `rt2` data retains signing, expiry, fingerprint, compression and
cancellation semantics. Issuance and decoding reject live state, and decoding
checks request/run identity against the saved State. A different process can
restore valid data without any model request. This is not fresh-VM resume.

Core Exec's paused Execution is a live value with guards and references. It
must not be serialized as a token. The pending public run/stream/start/continue/
collect adapter must rebuild the common Flow from AI state. After-model,
after-tools and terminal checkpoints, pending tool recovery, sequence/identity,
queue ownership, trace filters, redaction and cycle handling remain required.
The current examples execute the lowerer's native Agent, not the old Runner.

Full standalone Actions/workers, skills/resources, legacy state conversion,
durable recovery, root dependency/package, consumer, runtime-floor, migration
and rollback checks remain open. No second executor or mock was added.


## Standalone runtime progress: 2026-09-07

[14_02](../../examples/14_resume/14_02_standalone_runtime/README.md) adds 18 integration
cases through the actual public ReAct API. The adapter owns a private v3 Agent
and uses the shared Session/Flow for all model and tool work. The old private
model/tool loop is removed. Lazy start, run identity, real tools, state effects,
typed repair, usage, terminal tokens and stream ownership have focused evidence.

Terminal continuation and cancellation-token paths work without model replay.
An untouched initial token starts through the same native runtime. The optional
State termination reason preserves iteration-limit meaning. Failed and cancelled
collections retain terminal usage. The focused run passed 41 checks.

Intermediate model/tool checkpoints are not yet emitted. Progressed state, query
append on resume and external queue binding are refused before provider work.
Their full port remains required. The profile records finite native default
limits and explicit overrides, remaining trace/redaction/cycle/provider behavior,
and the difference between token data and durable Agent recovery. Standalone
Actions, workers, skills/resources, state migration and the root package gates
remain open. Root Mix files still select v2. All history statuses remain pending.


## Native checkpoint resume: 2026-09-07

[14_03](../../examples/14_resume/14_03_checkpoint_resume/README.md) adds 17 integration cases through the actual public ReAct API.
The common Flow now pauses after a model response or a complete tool round.
The next stream pull releases it. Stopping at that boundary cancels the private
Agent before the next operation. Resume rebuilds an Agent and Session from AI
data and enters the existing native decision or model step.

Saved data retains pending calls, completed tool history, proposed domain state,
usage, counts, output repair state, identity, sequence and remaining execution
time. Current limits and tool permission apply again. Contract and module code
hashes reject changed targets or code. Provider options and credentials must be
supplied again. One example resumes in a new operating-system VM and confirms
that the completed tool does not run again. Core Exec values are never saved.

The focused run passed 60 checks, including 13 retained root token/pending-call
cases. Expiry prevents later continuation; it does not stop current execution.
The saved execution budget excludes offline storage time. Full quality results
are recorded in the [implementation record](implementation.md).

These tokens remain caller-owned and replayable. Partial tool batches, durable
single-consumer records, old progressed-state conversion, query append and
external queue binding remain open. This is not evidence for the Agent
persistence API or durable backup/restore. Trace/redaction, cycles, standalone
Actions/workers, skills/resources, root dependency/package, consumer,
minimum-runtime, migration and rollback checks remain required. All history
statuses remain pending. Root Mix files still select v2.


## Standalone Action port: 2026-09-07

[14_04](../../examples/14_resume/14_04_standalone_actions/README.md) adds 13 integration
cases for the actual Start, Continue, Collect and Cancel Actions. They execute
through v3 Exec. A portable Flow connects Start and Collect, and an Agent route
commits the aggregate result. The live stream stays in execution context.

The Actions retain public metadata functions and use the shared schema input
normalizer. Start now delegates to the public start function. One runner option
builder carries runtime resources and native limits for Start, Continue and
Collect. This fixes lost runtime context during token collection. The old
AgentServer State dependency is removed; transient nested context maps remain
supported. Cancellation stops the tool, private Agent and stream owner.

The focused run passed 28 checks, including 15 retained root helper tests.
A real multimodal Action request is linked to PR 278 in the history ledger.
No shape-only or mocked ReAct call is counted as live feature evidence.

Query append, old progressed-state conversion, complete trace/redaction/cycle
and provider behavior, workers and skills/resources remain required. Token
replay, durable Agent recovery, root dependency/package, consumer,
minimum-runtime, migration and rollback gates remain open. Root Mix files still
select v2. Full validation is recorded in [implementation](implementation.md).


## Native worker lifetime and failure: 2026-09-07

[14_05](../../examples/14_resume/14_05_worker_lifecycle/README.md) adds nine integration
cases through the public ReAct and CoT Agents. Task loss stops held work,
preserves observed usage and commits one failure. Later work succeeds, and late
old task data cannot finish the next request. Session-owner loss interrupts
stored requests; parent shutdown stops the complete owned process tree.
Wrong-run observations and old worker Signals cannot publish a result.

Task failure retains `:worker_crash` and now also records a portable exit reason
and `:worker_task` error type. A public ReAct file-ID request reaches the model
boundary, which is linked to PR 304. The focused lifecycle set passes 84 checks.
The shared mock changes only model responses; real tools and core tasks execute.

Four internal Worker Agent/Strategy modules and the obsolete callback-only
worker test are removed. Native Session task ownership replaces that separate
execution layer. The old parent ReAct Strategy remains unported and still has
old worker references. Its trace, inspection, context lane/compaction, skills,
resources and state conversion must be mapped before its retirement. Existing
root callback tests must also be transferred. This is not a root package pass.

Session-owner recovery does not restore the old volatile stream sink. Durable
terminal delivery, Agent persistence, full standalone behavior, root dependency,
package, consumer, minimum-runtime, migration and rollback gates remain open.
Root Mix files still select v2. All history statuses remain pending. See the
[implementation record](implementation.md) for full validation results.

## Trace and repeated-call refinement: 2026-09-07

[14_06](../../examples/14_resume/14_06_trace_and_cycles/README.md) completes this
standalone behavior slice with 13 integration cases and 82 focused checks.
The same observation map serves the Agent DSL and standalone Config. Completed
response data supplies checkpoint stream fields, so no second live trace
accumulator is added to Session. One tool metadata field supplies the native
checkpoint, failure record and standalone signature view.

The source review preserves inactive legacy trace flags rather than assigning
them new filtering behavior. Full argument comparison removes false repeated
calls caused by truncated text. Saving the warning and signature together
repairs the old after-tools checkpoint gap. Next work must still cover query
append, context lanes/compaction and old-state conversion. Parent inspection,
skills/resources, provider/recovery, root package, consumer, minimum-runtime,
migration and rollback gates remain required.

## Standalone input ownership refinement: 2026-09-07

[14_07](../../examples/14_resume/14_07_standalone_input/README.md) ports Config's
caller-supplied input queue. The native Session already used the same queue
module, so the port adds binding and ownership tracking without another queue
or loop. Closing a run seals borrowed input and stops only internally created
queues. Existing queue errors retain their runtime error type.

The 13 new integration cases and 57 focused checks prove limits, closure before
repair, real tool steering, cleanup and checkpoint queue rebinding. The caller
owns undrained input; accepted input is not durable delivery. No new DSL option
is needed. Query append remains next: its adapter must retain conversation,
request/run identity, sequence, usage and iteration semantics. It must not
silently replace continuation with a new empty run. Old State conversion and
full package gates remain required.

The query-append source review also found a counter distinction that needs an
explicit example. The old Runner increments State iteration after a tool round
and after consumed input at final closure. The current native adapter projects
model-call count, including at an after-tools checkpoint. Output repair can also
separate call count from reasoning iteration. Before query append is enabled,
map both counters and the next-step position. Keep request/run identity, history,
usage and limits; do not infer all counters from the final State iteration.
This is an open State compatibility gate, not a completed conversion claim.

## Native query append and counter refinement: 2026-09-07

[14_08](../../examples/14_resume/14_08_query_append/README.md) resolves the preceding
counter issue for native checkpoint and successful terminal State. The existing
checkpoint format now supports a next-model position and committed terminal
continuation. It preserves both native counters instead of estimating them
from one State field. Version-1 native data still resumes.

The 15 new cases and 58 focused checks prove history, identity, sequence, domain
state, pending-tool completion, repair counters, rich input and remaining limits.
The same Flow handles continuation. No second executor, queue or checkpoint
format was added. Appended input consumes the run budget and follows any saved
tool exchange. Nil and empty-string options retain their old no-append meaning.

Next, convert old State and failure/cancellation restart with explicit phase
and counter evidence. A terminal failure must not reuse a stale active pause
that can repeat completed effects. Parent trace/inspection, context lanes and
compaction, skills/resources, provider/recovery and all root package gates stay
open.

## Standalone State conversion refinement: 2026-09-07

[14_09](../../examples/14_resume/14_09_state_migration/README.md) adds an explicit
`ReAct.State.migrate/3` and 22 integration cases. The old Runner emits its model
checkpoint before it fills the pending tool list; conversion restores this list
from the saved assistant message. Complete tool history prevents completed work
from running again. Caller evidence supplies separate counters, remaining time
and reconciled domain state, which old tokens do not fully contain.

The pure converter shares tool defaults and the existing native checkpoint
validator. It preserves terminal completed/failed/cancelled results, can append
new input after explicit conversion, and rejects unresolved tool work. The
refinement cases prove actual model failure after tools, model/iteration limits,
and invalid history and reasons. The current package still needs automatic
failure-phase counter projection, old Agent/Strategy state and persistence
conversion. Do not use a stale active checkpoint to resume a failed request.
Next complete that failure matrix, then parent inspection/context lanes and
compaction, skills/resources and root dependency/package checks. Keep consumer,
minimum-runtime, migration and rollback gates required.

## Failure-counter refinement and parent port: 2026-09-07

[14_10](../../examples/14_resume/14_10_failure_position/README.md) resolves automatic
standalone reasoning-position projection on the tested terminal failure and
cancellation paths. Session records the position before model preparation and
at checkpoints. A shared helper keeps transformer State and model-step position
consistent. Output repair adds model calls without advancing reasoning.
Eighteen new cases and the shared worker/call-count suites prove this behavior.

Next begin the parent feature port: active/terminal AI inspection and bounded
request traces, then context replace/switch, operation deduplication, compaction
and durable skill/resource entries. The old ReAct Strategy remains only until
these features have native implementations and examples. Core snapshot is a
committed Agent/revision envelope; do not recreate the removed Strategy Snapshot
or another execution loop. Keep current request records and the common Session
as the execution source. Owner-loss/durable recovery, old Agent state and all
root package/consumer/runtime-floor/migration/rollback gates remain required.

### Parent source review for the next port

The remaining ReAct Strategy stores features that are not execution callbacks.
Its snapshot builder (lines 367–437 in the retained source) and context operations
(lines 901–1088 onward) define the following work. The root
`test/jido_ai/strategy/react_test.exs` remains the behavior source; its callback
harness is not v3 execution evidence.

| Parent feature | Native acceptance to build |
| --- | --- |
| Active inspection | Hold real model/tool work; inspect phase, reasoning position, IDs, model, usage, output state, pending calls, completed tool results and conversation. Read live ownership separately from portable state. |
| Terminal inspection | Keep result or raw failure, cancellation reason, duration and retained request identity; an older request is still selectable. |
| Request traces | Keep event order and request/run correlation. Retain at most 2,000 events per request and set the truncation flag on overflow. Test terminal retention and recovery with no sink or worker handle in stored data. |
| Thinking | Keep stream text/thinking and per-call thinking entries; do not confuse parent thinking history with the standalone State, which has no thinking_trace field. |
| Context replace | While idle, replace base history. During active work, defer it until success, failure, cancellation or worker loss. Preserve the configured prompt when replacement has nil prompt. |
| Context switch and operation IDs | Select the requested lane; a new lane has no old conversation. Duplicate operation IDs do not apply twice. Preserve the core history operation record. |
| Compaction and skills | Keep only trusted durable skill tool results and their matching assistant calls. Reject spoofed user refs, mismatched tool identity and orphan results. |

Existing native facilities already cover effective configuration, committed
Context views and direct history replacement. Extend those facilities instead
of duplicating them. The core snapshot returns only committed Agent plus commit
revision, so the AI inspection view must be composed from those records and the
common Session. The old Strategy can be removed after these features and the
remaining skill/resource links have executable replacements. Root dependency
cutover must still compile all required production modules.


## Native parent inspection and trace prefixes: 2026-09-07

[02_22](../../examples/02_requests/02_22_request_inspection/README.md) adds the common
`Session.snapshot/2` API and 14 integration examples. The envelope distinguishes
the committed Agent/revision/request from a later live Session sample. It keeps
request/run IDs, phase, model counts, reasoning position, usage, output,
text/thinking, tool progress/results, raw failure and retained request selection.
It reuses the existing configuration and committed Context views.

Portable request records now retain bounded trace prefixes. The first 2,000
events are kept; overflow sets the truncation flag. History commits store the
current prefix and metadata. Completion stores the sampled prefix plus the
normal terminal record. State-size pressure can omit trace details. Recovery
retains the last committed prefix and fails interrupted work without replay.
A real durable lost-reply case restores a completed answer and trace.

The simplification pass removed terminal event construction from the pure
outcome Turn. Cancellation can race with later events before commit. A saved
trace therefore declares `scope: :observed_prefix` and its last sampled `seq`.
The canonical stream continues through the existing publisher and emits its
terminal event after commit. This is not a complete durable event journal or
proof of Signal delivery. Events since the last history commit can be lost;
profiles without history save their trace at completion only.

No old Strategy callback, core Snapshot type, new executor, queue or runtime
owner was introduced. Context replace/switch, operation IDs, trusted skill
compaction, skills/resources and active method-specific tree/graph views remain
required before the parent Strategy can retire. Root dependency, old Agent
conversion, full package/consumer/runtime-floor/migration/rollback gates remain
open. The migration goal stays active.


## Native context operations: 2026-09-07

[02_23](../../examples/02_requests/02_23_context_operations/README.md) adds 28 integration
cases and `Session.modify_context/3`. The common lowerer adds context routes
and a pure state Plugin for profiles with history. It stores active lane refs,
one deferred operation, the last 128 applied IDs and a core Thread value per
profile. Request admission/history and terminal completion use the existing
commit paths. No runtime owner, queue or executor was added.

Replacement and switch apply while idle or in the terminal commit after active
work. The current request keeps its admitted context. Success, failure, cancel,
task loss and Session recovery apply the pending operation; later pending input
replaces the previous operation. Nil prompt keeps the configured prompt. New
lanes are empty; switching back restores the selected history and prompt.
Invalid native input fails; the retained legacy Signal keeps invalid no-op
semantics. Direct history changes are reconciled before later lane operations.

Compaction retains accepted skill tool/assistant pairs and removes conflicting
replacement copies. A regression test exposed the old assistant-ID-only check;
v3 now keeps the original call name and arguments with the result. Typed and
string-keyed tool calls work. These are host-imported accepted-history cases;
actual LoadSkill provenance, callbacks, catalog scope and resources remain open.
A real durable lost-reply test proves the request answer, replacement, prompt
and applied ID are in the same saved terminal commit.

Public configuration/Context getters now accept a profile ID, and request
inspection uses it. Private standalone checkpoints exclude the owned context
field from their application domain, with resume checks through a new VM.
The root dependencies remain v2. Local core advanced independently to
`c845eed9` (`3.0.0-beta.1`); this AI slice uses that current checkout. Core was
not edited here, and its full suite was not rerun here. Skill/resource ports,
parent Strategy retirement, old Agent conversion and root package/consumer/
runtime-floor/migration/rollback gates remain required. The goal stays active.


## Native skill runtime and resources: 2026-09-07

[18_01](../../examples/18_skills/18_01_skill_runtime/README.md) adds 27 integration
cases for real `LoadSkill`/`LoadResource`, approved instruction history, context
compaction, closed catalogues, fresh resource reads, image/PDF transport and
owner cleanup/restore. A separate v3 command passes 293 retained skill/resource
checks. `Jido.AI.Skill` now lives in `lib/jido_ai/skill/skill.ex`.

The current path uses an explicit host-prepared catalogue in trusted context.
Request `tool_context` cannot replace reserved catalogue/provider/policy fields.
A native skill session belongs to the Session owner, profile and host binding.
Activation survives requests and model failure; owner exit or explicit cleanup
removes its resource access. Restore retains instructions and requires fresh
activation. Runtime handles stay outside portable state. There is no additional
execution owner, model server or skill compiler.

The legacy `agent_skills` option, automatic prompt/tools setup, declarative skill
source forms and standalone continuation still need their authoring port.
Installed-application resource tests, CLI, complete conversion/recovery and all
root package/consumer/runtime-floor/migration/rollback gates remain open. The
root dependency files still use v2. History statuses remain pending.


## Automatic skill authoring: 2026-09-07

[18_02](../../examples/18_skills/18_02_skill_authoring/README.md) adds 21 integration
cases. Public `agent_skills`, the native `skills` block, source data, Builder
and JSON use one static source and the existing Session/Flow runtime. Live
startup prepares the catalogue; compilation and static construction do not
read skill files. Selected Specs supply the prompt index, loading context and
automatic Actions. File bodies are strictly loaded only on selection.

Cases prove runtime-directory resolution, trust and discovery limits, source
precedence and diagnostics, separate profiles, current-file activation,
restore, and live tool/prompt changes. A refinement fix preserves automatic
tools during live registration. Public timeout/retry defaults apply to the
automatic entries. All 21 cases and 293 retained skill/resource tests pass.

`Session.skill_catalog/2` returns live Specs, index and diagnostics. Pure config
getters show declared values and portable overrides. Automatic skills require
a live ReAct Session; static callbacks use MFA. Native module Plugins stay
explicit Agent declarations. The manual host binding remains available.

The ledger has 787 exact test references and 66 rows with partial evidence;
all 126 row statuses remain pending. Standalone skill continuation, installed
resources/CLI, old parent Strategy retirement, complete Agent conversion and
recovery, root dependency/package, consumer, minimum-runtime and rollback gates
remain open. See the [implementation record](implementation.md) for full checks.


## Persistent tool context: 2026-09-07

[03_02](../../examples/03_tools/03_02_tool_context/README.md) adds the base context
replacement API to the existing Configuration Plugin. Public `tool_context`,
native DSL and source data now store defaults in `Profile.tool_context`.
`set_tool_context/3`, `set_tool_context_direct/3` and the retained
`ai.react.set_tool_context` Signal replace that map. Invalid or nonportable
values leave the committed Agent unchanged. No new runtime owner was added.

The public wrapper no longer inserts old defaults into every request. The
merge order for application fields is host, base, then explicit request values.
Active requests retain their admission context. Request values remain transient.
Native tool projection and protected runtime/skill fields still apply. The
compatibility config view now includes `base_tool_context`. The 11 cases cover
live/direct calls, Signals, callbacks, native Turn/Session profiles, Builder,
both JSON forms, profile isolation and restore.

This completes one remaining parent Strategy behavior. Standalone skill
continuation, parent Strategy retirement, the other uncompiled production files,
complete Agent conversion/recovery and package/consumer/minimum-runtime/migration/
rollback checks remain required. See the [implementation record](implementation.md)
for the current full-suite evidence.
