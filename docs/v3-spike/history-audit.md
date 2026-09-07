# Release history and PR feedback audit

Status: all 126 commits and all 103 associated merged PRs have completed
source review. All 126 v3 port checks remain pending.
Updated: 2026-09-06.

This is a required part of the migration goal. Every commit after the initial
2.0 release must have a disposition. Each retained behavior must have passing
v3 evidence. A feature name in the broad port map is not sufficient.

## Scope and current evidence

- Base: `v2.0.0`, release commit `c7843534fe035a5ca3a2237635de136c8ae8e2cd`,
  dated March 14, 2026 in the project timezone. Release candidates are not the base.
- Current target: `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`, the migration
  branch baseline from September 4.
- All 126 reachable commits in that range are indexed. The enumeration includes
  merged branch history; it is not restricted to first-parent commits.
- 81 commits have behavior, refactor, test or documentation acceptance
  groups. The other 45 have only a release/maintenance gate. These are commit counts,
  not counts of distinct features or completed reviews.
- GitHub returned 103 associated merged PR records. Their descriptions, issue
  comments, reviews and inline comments were captured for review: 35 issue
  comments, 32 reviews and 28 inline comments. Another 42 selected local issue
  or original-PR references are indexed: 40 reviewed and two read as pre-release
  context. Ten upstream records were read as context. Associated PR review is
  complete; upstream source histories are outside the pinned AI commit range.

Use the [readable commit ledger](history-commits.md) and
[structured ledger](history-audit.json). The structured ledger retains full SHAs,
changed paths, added test titles, PR links, feedback links, candidate acceptance
groups and explicit pending evidence fields. All 126 rows have
`source_review: reviewed`; none retains `pending_full_review`. All rows retain
`v3_status: pending`. No historical feature is marked ported by this work.

## Completed source reviews

The detailed reviews retain source paths, PR decisions and named acceptance
cases. Their opening totals record progress at the time of each review. The
current total is 126 reviewed commits. No review result is runtime port proof.

| Review | Required behavior | Commits |
| --- | --- | --- |
| [01](history-reviews/01-authoring-and-cli.md) | Models, prompts, unloaded tools and CLI | 12 |
| [02](history-reviews/02-content-and-references.md) | Content parts, refs, live worker requests and restore | 9 |
| [03](history-reviews/03-media-and-errors.md) | Generated media, structured errors and completed results | 10 |
| [04](history-reviews/04-output-and-controls.md) | Schemas, repair, limits, callbacks and data conversion | 10 |
| [05](history-reviews/05-tools-and-composition.md) | Tool registration, aliases, schemas, ordinary routes and Plugins | 7 |
| [06](history-reviews/06-release-and-documentation.md) | Release workflow, runtime, docs and package checks | 14 |
| [07](history-reviews/07-streams-and-checkpoints.md) | Partial responses, failed streams, cleanup and checkpoints | 5 |
| [08](history-reviews/08-request-stream-contract.md) | Public streams, sequence, keepalive and traversal checks | 3 |
| [09](history-reviews/09-steering-and-queued-input.md) | Bounded input, consumption, closure and wrapper compatibility | 2 |
| [10](history-reviews/10-lifecycle-and-execution-policy.md) | Lifecycle parity, test setup and logging policy | 3 |
| [11](history-reviews/11-telemetry-usage-and-payloads.md) | Correlation, nested payloads, usage merging and action policy | 5 |
| [12](history-reviews/12-observation-and-token-reporting.md) | Public tool events, token counts, embeddings and CLI traces | 2 |
| [13](history-reviews/13-signals-and-catalog-setup.md) | Signal constructors, catalog setup and package metadata | 3 |
| [14](history-reviews/14-model-routing-and-websocket-sessions.md) | Effective models, Responses sessions and ownership | 2 |
| [15](history-reviews/15-public-test-helpers.md) | Consumer helpers, script ownership and repeat requests | 1 |
| [16](history-reviews/16-skill-discovery-and-lazy-loading.md) | Trusted catalogs, lazy activation and diagnostics | 2 |
| [17](history-reviews/17-runtime-compatibility.md) | Clause order, errors, literal checks and tool state | 1 |
| [18](history-reviews/18-skill-lifecycle-and-conformance.md) | Sessions, compaction, parser boundaries and CLI diagnostics | 2 |
| [19](history-reviews/19-trusted-catalog-and-resource-bounds.md) | Current-file validation, registry failures and exact resource limits | 2 |
| [20](history-reviews/20-runtime-providers-and-binary-resources.md) | Opaque IDs, host callbacks, tenant context and binary transport | 2 |
| [21](history-reviews/21-dependencies-and-consumer-compatibility.md) | All remaining dependency deltas, stream headers and runtime floor | 29 |

Review 21 reclassifies two candidate maintenance rows as mixed feature/release
work. One closes the custom-stream-header report; another changes the default
Plugin test. The empty dependency commit is retained in the ledger with its
shared package check. Titles alone did not determine these decisions.

Associated PRs provide evidence. Their association does not add code outside
the pinned Git range. Bare issue numbers in dependency release notes can refer
to another repository. Resolve their repository before treating them as local
user feedback. Follow original and superseded PRs when they explain the use
case, but do not adopt unmerged proposals as released behavior.

The existing [feature map](feature-map.md) still covers the initial 2.0 feature
set. This audit adds the subsequent features, fixes, and compatibility details.
Before final release validation, refresh the upstream comparison. Record and
review any new commits accepted into the migration scope instead of silently
changing the original range.

## Required audit procedure

1. Read each commit's complete message, changed files, production diff, tests,
   and relevant documentation. Do not classify a change only from its title:
   some dependency/runtime maintenance commits also change code behavior.
2. Read the associated PR description, discussion, inline review and linked
   user report. Follow an original PR when the merged change replaced it.
   Record the actual user problem, constraints, and final maintainer decision.
3. Trace follow-up commits through the target revision. Consolidate repeated
   changes into a behavior record while keeping every contributing SHA linked.
   Preserve the final accepted behavior, not an earlier defect or abandoned API.
4. Assign each behavior to an existing integration example or a new focused
   case. Record input, expected result, failure behavior, state/side-effect
   boundary, runtime owner, and the original regression that the case detects.
5. During the port, link the actual v3 source and test name. Run the case with
   the unified mock and real production operations. Record the command, source
   revision and result. An excluded or expected-failing test is still pending.
6. At each simplification checkpoint, recheck the linked historical cases.
   Shared code must preserve the user-facing behavior that caused the original
   fix. Review unresolved rows before starting the next feature group.
7. At the package gate, require zero unreviewed commits and zero retained
   behaviors without passing v3 evidence. Maintenance-only rows need their
   named package/runtime/docs check. Removed or replaced behavior needs a named
   migration decision, a reason and a migration-guide entry. Removing a public
   behavior requires an explicit user decision; it cannot close a missing port
   by default. Replacing an internal API must preserve its supported behavior.

Track source review and port evidence separately. Several commits may map to
one case; one commit may require several cases. Add cases within the existing
catalog families where possible. Review notes alone cannot close a behavior row.

## Acceptance groups from the first history pass

These groups connect the 126 ledger rows to the existing example catalog.
They specify work; they do not describe tests already implemented.

| Group | Required behavior | Catalog |
| --- | --- | --- |
| H01 | Rich ReqLLM model inputs and aliases, provider options, effective per-turn model, labels and token fingerprints | 01, 13, 14 |
| H02 | Module-attribute prompts, method-specific omitted/default prompt behavior, useful validation without multiline code false positives | 01, 09, 13 |
| H03 | User/tool/assistant content parts, references, uploaded files and MIME, generated media, thinking, JSON round trips, no raw binary in tool JSON | 02, 03, 05, 06, 12 |
| H04 | Loadable tool modules, open/strict schemas, direct registration, synchronized catalogs, canonical tool results and completed outputs | 03, 04, 16 |
| H05 | Structured error terms, model-facing error envelopes, printable CLI compatibility, completed request metadata and stable public result shapes | 01–05, 09–11, 18 |
| H06 | Request/call/tool correlation, ordered deltas, provider usage normalization, nested tool payloads, redaction/bounds and observability options | 05, 09–11, 13, 18 |
| H07 | Busy rejection, steering consumption/sealing, request streams, terminal errors, tool-call progress, keepalive, lifecycle parity and cleanup | 04, 05, 09–11 |
| H08 | Preflight block/interrupt, per-request limits, actual per-attempt tool timeout, Agent-only before/after tool transforms and effect filtering | 03, 04, 13, 15 |
| H09 | Structured finalization, raw bypass, imported JSON schemas, nested array normalization, configured repair callbacks and per-attempt request transformation | 02, 09–11, 13 |
| H10 | Ordinary Signal routes, Plugin configuration/overrides and compiled-but-unloaded routed Actions | 01, 16, 18 |
| H11 | Skill specification, diagnostics, trusted lazy catalogs, activation lifecycle, bounded files, runtime resource providers and binary attachments | 06, 12 |
| H12 | Portable checkpoints, stream sink cleanup, interrupted restore, stable external references and token/repair callback compatibility | 06, 14 |
| H13 | Non-interactive CLI, installer formatting, deterministic test helpers, timed-test catalog setup, docs and direct-call usage | 18 and package gate |
| H14 | OpenAI Responses continuation and WebSocket reuse, effective model routing, caller-owned versus runner-owned session cleanup | 01, 04, 05, 13 |
| H15 | Cross-method prompt, result, error, media and lifecycle parity without losing method-specific reasoning behavior | 09–11 |
| RELEASE | Dependency/runtime/security compatibility, build/lint/type/docs checks, workflow and package release requirements | Package gate |

## Examples from real use

Add these cases during their feature ports. Use stable `history_case` IDs in
test metadata and link the full test names back into the ledger. A history case
can be a variation within an existing Agent example.

| Case | User problem and concrete acceptance scenario | Evidence and destination |
| --- | --- | --- |
| HIST-01 | A gateway needs rich model settings and request headers. Inspect base and per-request headers on normal and SSE requests. Configure an alias as a map, tuple and model struct; verify the selected endpoint/options, effective per-turn provider, label and portable fingerprint. | [issue 212](https://github.com/agentjido/jido_ai/issues/212), [PR 206](https://github.com/agentjido/jido_ai/pull/206), [PR 248](https://github.com/agentjido/jido_ai/pull/248), [original PR 289](https://github.com/agentjido/jido_ai/pull/289), [PR 295](https://github.com/agentjido/jido_ai/pull/295); H01 |
| HIST-02 | A module-attribute prompt must compile to text. Test the same authoring inputs across methods, including each method's accepted nil/false behavior. Feed an ordinary multiline Elixir diff through validation without a false rejection. | [PR 217](https://github.com/agentjido/jido_ai/pull/217), [PR 218](https://github.com/agentjido/jido_ai/pull/218), [PR 290](https://github.com/agentjido/jido_ai/pull/290); H02 |
| HIST-03 | A tool returns a PDF with non-UTF-8 bytes and structured data. The next model request gets both, while JSON contains no raw binary. Preserve uploaded file MIME and user/tool refs through history and restore. | [PR 209](https://github.com/agentjido/jido_ai/pull/209), [PR 250](https://github.com/agentjido/jido_ai/pull/250), [PR 211](https://github.com/agentjido/jido_ai/pull/211), [PR 213](https://github.com/agentjido/jido_ai/pull/213), [PR 306](https://github.com/agentjido/jido_ai/pull/306); H03/H12 |
| HIST-04 | An assistant message stored as JSON must retain text and thinking when read back. Model-generated images must survive stream delivery, final results and the next tool round. Keep text-only results as strings. | [issue 328](https://github.com/agentjido/jido_ai/issues/328), [PR 329](https://github.com/agentjido/jido_ai/pull/329), [issue 336](https://github.com/agentjido/jido_ai/issues/336), [PR 340](https://github.com/agentjido/jido_ai/pull/340); H03/H07/H15 |
| HIST-05 | Generated tool modules must work before incidental loading occurs. A non-strict tool with dynamic nested parameters retains an open nested schema; strict mode closes it. Verify the actual model payload and real tool input. | [PR 226](https://github.com/agentjido/jido_ai/pull/226), [PR 268](https://github.com/agentjido/jido_ai/pull/268), [PR 341](https://github.com/agentjido/jido_ai/pull/341), which reports Fireworks behavior; H04/H10 |
| HIST-06 | A provider failure must not become a successful empty greeting. Cover blank terminal errors and truncated/failed streams. The direct and Agent calls return errors, preserve prior state, and emit no completion event. | [PR 239](https://github.com/agentjido/jido_ai/pull/239), reported from the getting-started Greeter; H07 |
| HIST-07 | A model can spend a long time producing tool arguments. Deliver tool-call deltas before execution, optional keepalive while tools run, and ordered/correlated events that a consumer can reconstruct. | [PR 247](https://github.com/agentjido/jido_ai/pull/247), [PR 271](https://github.com/agentjido/jido_ai/pull/271), commit `aae99061`; H06/H07 |
| HIST-08 | Approval/preflight must run before tool execution. A rejected or interrupted batch starts no tool. A configured tool timeout reaches the actual inner execution layer; its shorter hidden default cannot terminate permitted work. | [PR 260](https://github.com/agentjido/jido_ai/pull/260), motivated by Moto, and [PR 331](https://github.com/agentjido/jido_ai/pull/331); H08 |
| HIST-09 | A model miscopies long action keys. One tool exposes a short alias; the Agent's next tool call restores the original key before validation/execution. A normal workflow calls the same Action with the original key and no AI transform. Test ReAct and ToT, immutable IDs, callback errors and effect filtering. | [PR 347 user report](https://github.com/agentjido/jido_ai/pull/347#issuecomment-5345440818), [maintainer boundary decision](https://github.com/agentjido/jido_ai/pull/347#issuecomment-5428496166); H08 |
| HIST-10 | A normal model turn can receive fresh credentials while output repair fails without them. Transform every repair request with fresh runtime bindings, honor model/message changes, keep tools disabled, and reject transformer failure before a provider call. Valid initial output makes no repair call. | [PR 343](https://github.com/agentjido/jido_ai/pull/343) and merged runtime-runner tests; H01/H08/H09 |
| HIST-11 | A typed result contains arrays of objects with enums. Accept string-keyed JSON, apply defaults, and invoke the configured repair callback through the actual Agent path. Cover imported schemas and explicit raw-output bypass. | [issue 334](https://github.com/agentjido/jido_ai/issues/334), [PR 337](https://github.com/agentjido/jido_ai/pull/337), [issue 335](https://github.com/agentjido/jido_ai/issues/335), [PR 339](https://github.com/agentjido/jido_ai/pull/339); H09 |
| HIST-12 | A streamed Agent checkpoint becomes unreadable after a node-name change. Store completed and active requests without live handles, decode in a fresh runtime, restore active streams as interrupted, and accept a later request with new resources. | [issue 327](https://github.com/agentjido/jido_ai/issues/327), [PR 332](https://github.com/agentjido/jido_ai/pull/332); H12 |
| HIST-13 | Monitoring lost token counts and nested tool outputs after an update. Preserve provider usage forms and actual permitted nested tool payloads, correlate every tool ID, retain redaction/bounds, and honor global/instance/explicit log options. | [PR 276 user confirmation](https://github.com/agentjido/jido_ai/pull/276#issuecomment-4364469431), [PR 297](https://github.com/agentjido/jido_ai/pull/297), [PR 309 review outcome](https://github.com/agentjido/jido_ai/pull/309#pullrequestreview-4468978518), [PR 338](https://github.com/agentjido/jido_ai/pull/338); H06 |
| HIST-14 | A caller needs structured failure terms and richer completed-request metadata. Preserve errors, usage, reasoning details and available thinking metadata in their intended public locations. Keep CLI display conversion at the display boundary. | [PR 223](https://github.com/agentjido/jido_ai/pull/223), [PR 233](https://github.com/agentjido/jido_ai/pull/233), [PR 234](https://github.com/agentjido/jido_ai/pull/234); H05/H15 |
| HIST-15 | A tool loop reuses one Responses WebSocket. Verify continuation IDs and session reuse; close only the runner-owned session, preserve caller ownership, and use the effective model when the provider changes. | [PR 272](https://github.com/agentjido/jido_ai/pull/272), [PR 295](https://github.com/agentjido/jido_ai/pull/295); H14 |
| HIST-16 | Skill content comes from trusted files or a host provider. Prove lazy activation, duplicate precedence, strict/lenient diagnostics, session isolation and bounded loading. Repeat image/PDF cases through both sources with MIME/size checks. | [PR 286 review feedback](https://github.com/agentjido/jido_ai/pull/286#pullrequestreview-4332191615), [PR 352](https://github.com/agentjido/jido_ai/pull/352), [PR 353](https://github.com/agentjido/jido_ai/pull/353), [PR 354](https://github.com/agentjido/jido_ai/pull/354), [PR 358](https://github.com/agentjido/jido_ai/pull/358), [PR 360](https://github.com/agentjido/jido_ai/pull/360); H11 |
| HIST-17 | An Agent needs ordinary routes and dynamic tool registration from executing work. Verify live and direct catalog changes, declared Plugin choices, static route parameters and module-attribute routes without self-call deadlock. | [PR 263](https://github.com/agentjido/jido_ai/pull/263), [PR 267](https://github.com/agentjido/jido_ai/pull/267), [PR 281](https://github.com/agentjido/jido_ai/pull/281); H04/H10 |
| HIST-18 | Installing Jido AI must preserve Phoenix/Ecto formatter behavior and user configuration. Test the packaged installer in a fresh consumer. Any new v3 DSL formatter import must have a shipped export and compose with the host rules. | [issue 236](https://github.com/agentjido/jido_ai/issues/236), [PR 237](https://github.com/agentjido/jido_ai/pull/237); H13 and package gate |
| HIST-19 | Keep the accepted non-interactive CLI: one-shot prompts and standard-input batches. Empty input without `--stdin` must give useful guidance and make no model call. The unmerged legacy TUI proposal is outside retained scope. | [PR 205](https://github.com/agentjido/jido_ai/pull/205), [maintainer decision on PR 122](https://github.com/agentjido/jido_ai/pull/122#issuecomment-4067288457); H13 |
| HIST-20 | A key-conversion cleanup must preserve imported schemas, known request fields, retrieval records, provider data and supported stored formats. Test unknown keys beside known keys and define conflicts explicitly. Keep the input conversion shared across authoring formats. | [PR 279](https://github.com/agentjido/jido_ai/pull/279), [PR 319](https://github.com/agentjido/jido_ai/pull/319), [detailed cases](history-reviews/04-output-and-controls.md); H01/H03/H05/H15 and related data/package gates |
| HIST-21 | A person or peer needs to correct a running task. Keep one request, visible user input and bounded FIFO order. Prove when input enters history/model context, atomic closure, hard limits, queue loss, public helpers and cleanup. | [issue 224 final scope](https://github.com/agentjido/jido_ai/issues/224#issuecomment-4137695363), [PR 225](https://github.com/agentjido/jido_ai/pull/225), [PR 235](https://github.com/agentjido/jido_ai/pull/235), [detailed cases](history-reviews/09-steering-and-queued-input.md); H07, catalog 05 |
| HIST-22 | Consumers need readable deterministic Agent tests with real tools. Preserve the public helper API over one mock server. A second request must start its own script despite old tool history. Prove async isolation, explicit binding, strict diagnostics and actual Action output. | [issue 315](https://github.com/agentjido/jido_ai/issues/315), [PR 317 unresolved review](https://github.com/agentjido/jido_ai/pull/317#discussion_r3448986957), [detailed cases](history-reviews/15-public-test-helpers.md); H13, catalog 03/05/18 |

These scenario families summarize the full ledger. The detailed source reviews
define their required variants; this selected table is not the complete test list.
Preserve the stable test coverage required by PR review, including the AoT
lifecycle test discussed in PR 309. The new integration examples can remain
excluded by default, but do not weaken existing default test coverage to make
a migration gate pass.

## Decisions exposed by the history

PR descriptions can describe an early revision. For example, PR 343 mentions
fallback on a request-transformer error. Its merged tests require that the
error propagates and that no repair provider call occurs. Use the merged source
and final tests to settle that contract, with the discussion explaining why.

The tool effect guidance in [PR 318](https://github.com/agentjido/jido_ai/pull/318)
also matters: a tool Action can perform I/O when the model needs its result
immediately. Filtering returned effects does not reverse that I/O. Preserve
this distinction when simplifying Action, Flow and post-commit work.

The current mock uses Chat Completions/SSE and embeddings. That alone cannot
prove Responses continuation, WebSocket reuse, or all generated-media behavior.
Extend the same mock server with the required wire support during these ports.
Keep one script/report contract and real ReqLLM transport. Use synthetic fresh
credentials and local endpoints; no real cloud credential service is required.

The content review also requires Anthropic uploaded-file requests, OpenAI
Responses `input_file` encoding, and Bedrock Converse tool-image encoding.
Verify actual HTTP content and the AI context at their respective boundaries.
Application refs need not appear as arbitrary provider fields. Old tests that
conditionally avoid file assertions when ReqLLM lacks support cannot close the
v3 gate. The supported dependency set must run the positive file cases.

The media/error review requires OpenRouter image fields in real HTTP/SSE
responses, including an image beside empty text. Test media before stream end,
after policy, in the final result and on replay. Use one AI error adapter for
the new core runtime. Preserve raw failure terms and stable answer shapes,
with separate model JSON, display strings and completed-result inspection.
Resolve the discovered malformed-binary serialization gap before closing that
gate. These cases supplement the original fixtures; none is port evidence yet.

The output/control review requires every repair attempt to use the actual
transformed request and current runtime bindings. Business tools remain disabled
during repair. A failed transformation makes no provider call. Preserve the
public repair override and callback identity. Preflight checks the full batch
before any tool starts. Include a real tool that exceeds the old hidden timeout
inside its larger explicit budget. Repeat data-format checks after each
simplification; source-level assumptions about atom keys are not sufficient.

The public deterministic test helpers are also a retained feature. Implement
their supported behavior over the unified mock where suitable; do not silently
delete them when transferring the temporary examples into the root suite.

## Audit validation record

Validated on 2026-09-06:

- The ledger matches the exact ordered Git range: 126 unique commits, including
  the empty dependency commit. The target is still the branch HEAD.
- All 126 rows have a decision, source-review document and required case IDs.
  All 103 associated PRs are reviewed. All v3 evidence fields remain pending.
- The final 29 reviews preserve the earlier 97 commit records. Their source
  and test paths exist. New case IDs resolve to their detailed review.
- Local documentation links resolve. The documentation has no trailing
  whitespace. Tracked production files and dependencies have no changes.

No runtime tests were run for the final documentation pass. The isolated
foundation results remain in its [run record](../../examples/v3/README.md).

## First implementation evidence: 2026-09-06

The shared model-helper tests now inspect actual headers on normal and SSE
requests. The ledger links this partial `HIST-01/stream-headers` evidence to
`8f669705` and `26bb4106`. Both cases pass in the 60-test acceptance run.
All 126 row-level port statuses remain pending. The ReAct option path, Finch
hook order, isolation and row-specific package checks still need proof.
See the [implementation record](implementation.md).

## Session implementation evidence: 2026-09-06

The 86-test acceptance run adds partial evidence for generated tool loading
(PR 226), blank/partial/failed responses (PR 239), public request streams
(PR 262), canonical events (PR 314), portable runtime resources (PR 332),
and headers through the public Request path. Each affected ledger row names
the exact tests and remaining limits. All 126 row-level statuses remain pending.
The session example does not establish standalone, durable or full facade parity.

## Steering implementation evidence: 2026-09-06

The 99-test acceptance run adds 13 steering/history cases. Partial HIST-21
evidence is linked to `ef176f67` / PR 225 and `45157844` / PR 235. The tests
preserve the accepted best-effort queue semantics, consumed history, closure,
timeouts and limits. Legacy helper parity and the remaining failure/restore
cases stay open. All 126 row-level statuses remain pending.

## Public Agent implementation evidence: 2026-09-06

The 110-test acceptance run adds 11 cases through the actual public Agent
macro. The history ledger adds partial evidence for PR 217 prompt attributes,
PRs 225/235 steering helper results, PR 262 event streams, PR 314 event order,
PR 332 portable completed state, and the actual HTTP header path. The complete
ReAct facade, remaining options and failure/recovery cases stay open. All 126
row-level statuses remain pending. See
[02_03](../../examples/v3/profiles/02_03_public_agent.md) for the exact scope.

## Request policy implementation evidence: 2026-09-06

The 120-test acceptance run adds ten request-policy cases. The ledger adds
partial evidence for PR 291 iteration overrides, PR 269 raw/custom output,
PR 319 imported JSON schemas, and PR 341 open tool schemas. The 32 existing
ToolAdapter assertions also pass against v3 test Actions. Fourteen history rows
now have partial execution evidence. All 126 row-level statuses remain pending.
See [02_04](../../examples/v3/profiles/02_04_request_scope.md) for the exact scope.

## Request transformation implementation evidence: 2026-09-06

The 134-test acceptance run adds 14 transformation and repair cases. PR 343 now
has partial evidence for exact repair requests, fresh options, model changes,
failure before HTTP, content-part query summaries and shared limits/accounting.
PR 339 has partial evidence for configured callbacks, direct overrides, source
formats and callback identity. The existing Output tests also pass on v3.
Sixteen history rows now have partial execution evidence. All 126 row-level
statuses remain pending. Full events, standalone execution, fresh-runtime
restore and token compatibility remain required. See
[02_05](../../examples/v3/profiles/02_05_request_transform.md) for the scope.

## Output implementation evidence: 2026-09-06

The 151-test acceptance run adds 17 output cases. PR 269 gains output events,
stored metadata, failure rules and schema-tool dispatch evidence. PR 337 now
has a live nested-array/default/enum case. PR 300 gains the retained Observe
helper checks and the actual output telemetry boundary. PR 339 gains held
callback cancellation and deadline evidence. Eighteen rows have partial
execution evidence. All 126 row-level statuses remain pending. See
[02_06](../../examples/v3/profiles/02_06_output_contract.md) for the limits.

## Response metadata implementation evidence: 2026-09-06

The 162-test acceptance run adds 11 response metadata cases. PR 233 now has
partial evidence for decoded thinking/reasoning data, stable result tuples,
later-request isolation and snapshot source order. Tool rounds, output repair,
later provider failure and cancellation retain completed-call metadata.
The shared helper suite has 117 passing tests, including 21 existing error-model
tests. Nineteen rows have partial execution evidence. All 126 row-level statuses
remain pending. See [02_07](../../examples/v3/profiles/02_07_response_metadata.md)
for the remaining method, failure and recovery checks.

## Error implementation evidence: 2026-09-06

The 177-test acceptance run adds 15 error cases. PRs 214, 223, 258, 275 and
299 gain partial evidence for real constructor details, raw error preservation,
portable failure storage, provider status/cause data and shared normalization.
PR 300 gains a finite null-error summary and valid transport-key checks.
Twenty-four rows have partial execution evidence. All 126 row-level statuses
remain pending. See [02_08](../../examples/v3/profiles/02_08_error_contract.md)
for the exact boundary and remaining tool, method and recovery checks.

## Tool result execution checkpoint

The [02_09 example](../../examples/v3/profiles/02_09_tool_results.md) raises
the enabled acceptance result to 196 passed. The retained shared helper suite
has 117 passed. PRs 230, 250, 296 and 306 gain first partial evidence for tool
envelopes, binary content and completed tool inspection. PRs 258, 299 and 300
gain live tool/Flow error and transport evidence. Twenty-eight rows now have
partial execution evidence. All 126 row-level statuses remain pending.

The selected chat provider rejects PDF/text files before HTTP; the tests
retain this boundary and inspect stored completed values. Supported image
bytes reach the mock through the provider encoder. These are not file restore
or model interpretation tests. Effects, all input-error and retry variants,
standalone APIs, method parity and package checks remain required.

## Tool effect execution checkpoint

The [02_10 example](../../examples/v3/profiles/02_10_tool_effects.md) raises
the enabled acceptance result to 220 passed. The retained shared suite now has
128 passed, including 11 Policy/Applier cases updated for current core types.
PR 318 gains local-file I/O, effect filtering and final-delivery evidence.
PRs 230 and 296 gain nonempty-result, retry and effect-inspection evidence.
Twenty-nine rows have partial execution evidence; all 126 statuses remain
pending. Tool callbacks, all methods/standalone APIs, post-commit failure
reporting, pending-work recovery and package validation remain required.

## Completion execution checkpoint

The [02_11 example](../../examples/v3/profiles/02_11_completion.md) raises
the enabled acceptance result to 231 passed. PR 262 gains terminal-failure
evidence after a rejected completion. PR 318 gains the post-commit Directive
failure boundary. PR 332 gains actual storage-conflict and lost-write-reply
checks with portable stored requests. These use real core commits and storage
callbacks. Twenty-nine rows have partial evidence; all 126 statuses remain
pending. Sink recovery, v2 conversion, fresh-process and durable work recovery,
all methods/facades and package validation remain required.

## Tool callback execution checkpoint

The [02_12 example](../../examples/v3/profiles/02_12_tool_callbacks.md) raises
the enabled acceptance result to 263 passed. The retained shared suite adds
11 ToolInterceptor tests. PR 347 gains its first partial execution evidence:
the alias workflow uses real tools and explicit candidate state; callbacks
retain identity, order, retries, failures, policy and runtime context. PR 296
also gains completed-tool inspection through the next request transform.
Thirty rows have partial evidence; all 126 statuses remain pending. ToT,
standalone APIs, pending-work replay, full recovery and package checks remain
required.

## Preflight and time-limit execution checkpoint

The [02_13 example](../../examples/v3/profiles/02_13_tool_limits.md) raises
the enabled acceptance result to 282 passed, including 19 new cases. The
retained shared suite has 139 passed. PR 260 gains batch preflight, prepared
arguments, interruption, failure events, request isolation and real callback
cleanup evidence. PR 331 gains actual Action/Flow attempt timeouts, total
request deadlines, retry budgets and monitored tool runs beyond 31 seconds.
DSL, data, Builder and source JSON execute the same declared retry settings.

Core timeouts now explicitly prohibit retry; AI retains that v3 decision and
records the v2 behavior change in the migration plan. Permitted retries use
typed Action errors. Legacy error-map input forms still need a compatibility
case. Thirty-two rows have partial evidence; all 126 statuses remain pending.
The ledger has 211 concrete test references. Pending-work preflight, durable
approval/resume, legacy direct AI execution facades, keepalives and idle limits,
recovery and package validation remain required.

## Session stream activity execution checkpoint

The [02_14 example](../../examples/v3/profiles/02_14_stream_activity.md) raises
the enabled acceptance result to 298 passed, including 16 new cases. The
retained shared suite has 139 passed. PR 308 gains its first partial evidence:
public keepalives preserve runtime and enumerable idle limits around real
held tools. One owner retains sequence order through parallel tools, retries,
multiple rounds and injection. Actual provider chunks reset internal activity.
Both idle option names, automatic limits, explicit zero, invalid overrides,
source-format parity and timer cleanup have execution evidence.

Owner failure stops timers and tool work; recovery interrupts the stored
request without replaying the old sink. Standalone ReAct and Start/Continue/
Collect, token compatibility, durable sink/sequence recovery, early tool-call
Signals and package checks remain required. Thirty-three rows have partial
evidence, with 227 concrete test references. All 126 row statuses remain pending.

## Early tool activity execution checkpoint

The [02_15 example](../../examples/v3/profiles/02_15_early_tool_activity.md)
raises the enabled acceptance result to 311 passed, including 13 new cases.
PR 247 gains its first partial evidence. The real decoder emits tool-name
activity before argument completion and document execution. Empty names are
suppressed; blocked, unknown, cancelled and disconnected calls do not execute.
Unnamed fragments keep runtime activity with capture enabled or disabled.
Native and public Agents share the existing capture flag and retain complete
results. Four source formats and a quiet JSON variant execute the same tool.

An empty declared tool round now fails before history and model completion,
with usage counted. This named v3 behavior change is in the migration plan;
blank successful stops and provider object validation remain separate.
Thirty-four rows have partial evidence, with 240 concrete test references.
All 126 statuses remain pending. Typed Signal projection/delivery, standalone
and other methods, durable recovery and full package checks remain required.

## Typed Signal execution checkpoint

The [02_16 example](../../examples/v3/profiles/02_16_typed_signals.md) raises
the enabled acceptance result to 329 passed, including 18 new cases. The
retained shared suite now has 227 passed, including 88 Turn and Signal cases.
PR 310 gains static core schemas, constructors, duplicate/nil/type/options
checks and actual outbound delivery. PR 271 gains ordered typed delta
projection and delivery from actual model events. PR 247 gains delivery of an
early name-only Signal before the real tool executes.

The example records schema metadata, error class and timestamp changes.
Explicit projection feeds a publisher Agent; automatic session-owner Signal
delivery is still required. Other methods, standalone APIs, full legacy
execution options, durable recovery, root dependencies and package checks
remain open. Thirty-six rows have partial evidence, with 261 concrete test
references. All 126 row statuses remain pending.

## Automatic session Signal checkpoint

The [02_17 example](../../examples/v3/profiles/02_17_signal_delivery.md) adds
26 executed cases for automatic ReAct session delivery through core Agent
commits, outbound Plugins and dispatch adapters. PR 310 gains the complete
new example references. PRs 247 and 271 gain automatic early/ordered delta
evidence. PR 229 gains its first partial evidence for actual public tool
Signals and failure/cancellation identity.

There are 37 rows with partial evidence and 292 concrete test references.
All 126 row statuses remain pending. The delivery report is transient; core
dispatch success does not prove receiver handling. Owner recovery does not
replay batches. Other methods, standalone Action observations, CLI behavior,
all legacy envelopes and package gates still require their own evidence.
The [implementation record](implementation.md) records final suite checks.

## CoT and CoD execution evidence

The [09_01 example](../../examples/v3/profiles/09_01_linear.md) adds 33 cases.
The full integration run has 388 passed. PR 218 gains first partial evidence
for real prompt attributes, default normalization and invalid authoring in both
public linear wrappers. PR 217 gains the corresponding method scope. PRs 223
and 233 gain linear error, result and metadata evidence. PRs 271 and 310 gain
actual method-aware SSE and typed Signal delivery.

PR 340 gains first partial evidence for non-streamed rich provider results:
ReAct, CoT and CoD retain ordered text/image/text; public linear helpers retain
media queries and image-only results. This does **not** prove the historical
streaming fix. Generated media streaming and all capture modes remain required.

There are 39 partial history rows and 311 concrete test references. All 126
statuses remain pending. Old Strategy/Machine/worker APIs, CLI, capability
Plugins, direct CoD empty-prompt behavior, state conversion and package gates
remain open. The example records parser corrections, the new 60-second total
linear request default and CoD's actual observation label.


## Retained linear API execution evidence

The [09_02 example](../../examples/v3/profiles/09_02_method_api.md) adds seven
cases; the full acceptance run has 395 passed. The retained CoT Machine tests
run unchanged on v3. Its finite transitions replace Fsmx, and its data API,
raw failures and legacy telemetry remain. PR 297 gains first partial evidence
for nested usage through the common merge helper. PRs 223 and 233 gain raw
Machine errors and committed method-specific result inspection.

There are 40 partial history rows and 315 concrete test references. All 126
statuses remain pending. Method selection now uses namespace `method/0`.
Old Strategy module names retain deprecated result getters only. The example
maps old execution callbacks and direct CoD empty-prompt behavior explicitly.
CLI, worker APIs, capability Plugins, other methods and package gates remain
required.


## AoT execution evidence

The [09_03 example](../../examples/v3/profiles/09_03_aot.md) adds 24 integration
cases and one default lifecycle case. The full acceptance run has 420 passed.
AoT retains its single-generation search prompt and complete result through
actual Agent/Flow execution. Seven retained Machine cases also remain usable
on v3. Method options, typed final-answer repair, raw causes, usage, busy input,
cancellation, recovery and typed observation have live execution evidence.

PR 231 gains first partial evidence for the AoT lifecycle. PR 309 gains first
partial evidence because the migrated AoT lifecycle case stays in the default
suite, with actual Signal/telemetry identity and measured usage and duration.
The old root mixed-method file remains unported until suite transfer. It is not
counted as passing. PRs 233, 239, 299 and 310 gain related method evidence.

There are 42 partial history rows and 332 concrete test references. All 126
statuses remain pending. Other methods, CLI and capability paths, generated
media output, complete partial-transport capture, v2 conversion and package
checks remain required. Source inventory paths and hashes remain pinned to
the original target commit.

## Native ToT execution evidence

The [09_04 example](../../examples/v3/profiles/09_04_tot.md) adds 23 native
integration cases. The full acceptance run has 443 passed. Search order,
ranked results, node/branch/beam limits, parser repair, tools in both phases,
callback order, usage, cancellation and owner interruption use actual core
Agent/Flow and mock HTTP/SSE execution. All 18 retained Machine/Result tests
also pass against v3 dependencies.

PRs 231, 297, 299, 309, 310 and 347 gain partial native ToT evidence. There are
42 partial history rows and 349 concrete test references. All 126 statuses
remain pending. The exact PR 347 alias-and-state case, public ToT APIs, typed
results, rich input, full failure/recovery matrices and root package gates
remain open. Native phase observation does not replace the required default
AoT lifecycle case; that case remains enabled.

## Public ToT and alias execution evidence

The [09_05 example](../../examples/v3/profiles/09_05_tot_api.md) adds 28 public
and callback integration cases. The full acceptance run has 471 passed. The
public macro, result helpers, failed-tree getters, cancellation, search budget
and provider-timeout mapping use actual Agent/Flow and mock HTTP/SSE execution.

PR 347 now has its exact alias/state workflow under ToT, including ordinary
Agent turns. Before callbacks restore original keys before validation. After
callbacks receive raw final retry results and transform canonical/model output.
Denied effects and a later callback failure retain real tool evidence without
committing proposed state. Direct Exec retains original Action behavior.
PRs 231, 297 and 299 gain related lifecycle, usage and error evidence.

There are 42 partial history rows and 380 concrete test references. All 126
statuses remain pending. No new claim is made for full ReqLLM model-input parity
from an alias-only example. Live frontier inspection, runtime state overrides,
typed ToT output, rich input, full provider variants, standalone/capability/CLI
paths, durable recovery and root package gates remain required.

## Method response refinement evidence

PR 239 gains three ToT cases for decoded objects under a provider length limit,
method validation/repair of an invalid object, and failure on an empty
evaluation. Actual usage and later-request recovery remain correct. PR 343
gains an AoT case with refreshed request headers through typed-answer repair.
The transformer preserves the method's text framing and provider schema rule.

The full acceptance run has 475 passed. There are 42 partial history rows and
384 concrete test references. All 126 statuses remain pending. These bounded
cases do not close full finish-reason, generated-media, standalone, durable
recovery or package acceptance requirements.

## Native GoT execution evidence

The [09_06 example](../../examples/v3/profiles/09_06_got.md) adds 22 integration
cases. Native generation, connection discovery and synthesis use the existing
Agent/Flow/Session. All 41 retained Machine tests pass unchanged on v3. A real
model connection and separate diamond/cycle cases cover the graph change in
PR 314. Other cases add method lifecycle, usage, phase observation and failure
evidence for PRs 223, 231, 239, 297, 299 and 310.

The full acceptance run has 498 passed. There are 42 partial history rows and
400 concrete test references. All 126 statuses remain pending. Aggregation-mode
settings do not prove voting or weighted algorithms. General branching,
aggregation across several leaves, public GoT APIs, typed/rich contracts,
complete provider variants, durable recovery and package gates remain required.

## Public GoT execution evidence

The [09_07 example](../../examples/v3/profiles/09_07_got_api.md) adds 11 cases
for public authoring, retained graph inspection, failed causes, larger call
budgets, cancellation and method filtering. A bounded path test fixes infinite
parent-cycle traversal. Busy admission now has the same request/stream result
before and after a model call. PRs 223, 231, 297, 299 and 314 gain partial
evidence from actual request work and retained Machine APIs.

The full acceptance run has 509 passed. There are 42 partial history rows and
412 concrete test references. All 126 statuses remain pending. Admission-failure
method identity, distinct aggregation algorithms, broader graph construction,
runtime state overrides, typed/rich contracts, CLI/capability APIs, complete
provider variants, durable recovery and root package gates remain required.

## Native TRM implementation evidence: 2026-09-07

The [09_08 profile](../../examples/v3/profiles/09_08_trm.md) adds 24 integration
cases for the existing TRM method. The five retained support modules also pass
204 tests on v3 dependencies. PRs 223, 231, 233, 239, 297, 299 and 314 gain
partial evidence for scored-answer selection, method and phase identity, request
metadata, blank terminal failure, nested usage, canonical causes and observation.
Cancellation, a deadline, owner loss and a later request use the common Session.
The legacy Machine keeps its printable error and direct telemetry behavior.

Public TRMAgent and namespace/Strategy APIs, old phase-input/state conversion,
runtime overrides, CLI/capability paths, complete provider/media support, active
inspection and durable recovery remain required. The native method rejects
typed results, rich input, tools and steering. All 126 history statuses remain
pending; there are still 42 rows with partial evidence. The root package and
release checks remain open.

## Public TRM implementation evidence: 2026-09-07

The [09_09 profile](../../examples/v3/profiles/09_09_trm_api.md) adds 12 public
TRM integration cases. They preserve reason/sync/await, declared options, default
model resolution, all five cycles, retained review data, printable failures,
streaming and cancellation through the common Agent and native Flow. PRs 223,
231, 233, 297, 299 and 314 gain partial evidence. There are still 42 partial
rows and all 126 history statuses remain pending. Active inspection, legacy
phase-input/state conversion, custom hooks, runtime overrides, CLI/capability
APIs, full provider/media behavior, durable recovery and package gates remain
required. The pinned source inventory is unchanged.

## Native Adaptive evidence: 2026-09-07

The [09_10 profile](../../examples/v3/profiles/09_10_adaptive.md) adds 28
integration cases. All seven methods use actual model calls through the shared
Flow. ReAct and ToT execute real tools. Selection repeats for each request and
retains its method, result, usage and failure data. Invalid settings fail before
model work. Typed repair keeps the chosen method. Cancellation, owner loss and
a deadline use the common Session. Sixteen retained selection tests also pass.

Commit `e2b2d275` gains partial method-dispatch evidence. PRs 231, 233, 297,
299 and 314 gain related evidence. There are now 43 partial rows and 477 test
references; all 126 history statuses remain pending. The public Adaptive API,
printable failure state, command and state conversion, runtime overrides, live
inspection, CLI/capability paths, complete provider variants, durable recovery
and root package gates remain required. The pinned API inventory is unchanged.

## Public Adaptive evidence: 2026-09-07

The [09_11 profile](../../examples/v3/profiles/09_11_adaptive_api.md) adds 22
public integration cases. All seven methods run through the common Agent and
Flow. The cases retain public selection, typed results, printable failures,
tool callbacks, streams, cancellation and actual method usage. PR 234 gains
partial evidence from actual HTTP/provider failures and non-text results.
Commit e2b2d275 and PRs 231, 233, 297, 299 and 314 gain related evidence.

The full acceptance run has 595 passed. There are 44 partial rows and
500 concrete test references. All 126 statuses remain pending. CLI output,
active inspection, old state/command conversion, runtime overrides, per-method
default control parity, capability/skill paths, durable recovery and root
package/release gates remain open. The baseline API inventory is unchanged.

## Selected method control refinement: 2026-09-07

The [09_12 cases](../../examples/v3/profiles/09_12_method_controls.md) fix
the initial combined Adaptive budget. Actual ReAct and TRM requests preserve
their respective counts on one Agent. Explicit Agent/request limits, whole-batch
tool limits, typed repair and source-format parity have focused evidence.
Commit e2b2d275 and PRs 269, 291 and 299 gain partial references. All 126
statuses remain pending; 44 rows have partial evidence and 515 test references
resolve. The full feature, recovery, API and package gates remain required.

## Active Adaptive selection: 2026-09-07

The [09_13 cases](../../examples/v3/profiles/09_13_active_selection.md)
restore active method and score inspection. Core commits prepared selection
before model work. Input controls, one-use owner grants, host policy rejection,
unrelated domain changes, cancellation and owner loss have focused evidence.
The owner retains already committed metadata when it recovers. It does not
replay the method.

Commit e2b2d275 and PRs 231, 233 and 299 gain partial evidence. There are
44 partial rows and 525 test references. All 126 statuses remain pending.
Active method phase data, full state conversion, interrupted-stream delivery,
CLI/capability/skill paths, durable recovery and root package gates stay open.

## Callable reasoning evidence: 2026-09-07

The [09_14 cases](../../examples/v3/profiles/09_14_callable_reasoning.md) add
partial evidence for commit e2b2d275 and PRs 231, 233 and 297. Twenty cases
execute all seven RunStrategy methods through direct Exec and an Agent. They
check defaults, full method outputs, failure usage, cancellation, timeouts and
separate concurrent ownership on one host runtime. The implicit global runner
instance and seven internal wrappers are replaced by one validated profile
factory. There are 544 test references and 44 partial rows; all 126 history
statuses remain pending. PR 342 cold-catalog timing remains unproved.

## Reasoning capability evidence — 2026-09-07

[Example 16_01](../../examples/v3/profiles/16_01_reasoning_capabilities.md)
adds 17 integration cases and 21 native Plugin contract cases. The full AI
acceptance suite now passes 659 cases. This adds partial evidence for PR 263
(Plugin choices), PR 281 (ordinary routes), callable reasoning dispatch and
timeout cleanup. The ledger now has 557 exact test references across 46 rows
with partial evidence. All 126 migration statuses remain pending. The example
lists the unproved legacy conversion, other capabilities and release gates.

## Planning helper evidence — 2026-09-07

[08_01](../../examples/v3/profiles/08_01_planning.md) adds 18 integration cases
for the three Planning Actions and Plugin, plus 12 native API/Plugin checks.
The full AI acceptance suite passes 678 cases. Six exact test references add
partial PR 279 evidence for text extraction, parser results, string inputs and
current Agent state defaults. The ledger now has 563 references across 47 rows
with partial evidence. All 126 statuses remain pending. The root package and
remaining feature/release gates are not complete.

## Chat Action evidence: 2026-09-07

[Example 16_02](../../examples/v3/profiles/16_02_chat.md) adds 32 integration
cases for the seven Chat Actions and the native Plugin. Actual HTTP tests
cover schema/input conversion, model inputs, empty embeddings, returned usage,
canonical telemetry, nested usage, invalid structured output and the PR 290
multiline validation reports. There are now 580 exact test references and 50
rows with partial evidence. All 126 migration statuses remain pending.
The root dependency, consumer, CLI, state conversion and recovery gates remain
required. No baseline inventory or history range was changed.

## Routing and Policy evidence: 2026-09-07

[Example 16_03](../../examples/v3/profiles/16_03_routing_policy.md) adds 21
integration cases and 11 native Plugin checks. The full acceptance suite passes
732 tests. Ten new exact references add partial evidence for canonical errors,
PR 279 input conversion, PR 340 typed content in Policy, and PR 295 request model
selection. The PR 295 evidence is limited to direct core calls and two OpenAI
models. Within-loop provider changes, WebSockets, continuation and all public
request option forms remain required.

The ledger now has 590 exact references and 51 rows with partial evidence.
All 126 statuses remain pending. The API baseline, reviewed commit range and
complete package, consumer, conversion and recovery requirements are unchanged.

## Retrieval boundary evidence: 2026-09-07

[Example 07_01](../../examples/v3/profiles/07_01_memory.md) adds actual Store,
Action, Agent and model-tool checks. Three references add partial PR 279 evidence
for memory input conversion, ranking and current Agent context. The reproduced
unknown-key defect is fixed without creating atoms. Supervised ownership,
concurrent writes and failure-after-write behavior have separate examples.

The ledger now has 593 exact references and 51 rows with partial evidence.
All 126 statuses remain pending. Memory import with original timestamps,
durable backup/restore, all provider/data paths and full package/consumer gates
remain required. The reviewed commit range and baseline inventory are unchanged.

## Quota accounting evidence: 2026-09-07

[13_01](../../examples/v3/profiles/13_01_quota.md) adds partial evidence for
PR 297 and PR 312. The user reports in issues 294 and 311 require correct usage
beyond a successful answer. The new cases keep call cost outside Agent commit,
distinguish cumulative stream snapshots from separate calls, preserve partial
usage on cancellation/disconnect and prevent duplicate charging. A response
whose usage source is absent is not presented as known zero cost.

The Quota modules have no direct changes in the pinned post-v2.0.0 range; they
are also covered by the API baseline requirement. This port does not invent a
new historical Quota commit. There are now 601 exact test references and 51
partial rows. All 126 statuses remain pending. Full telemetry/API parity,
provider provenance, durable recovery, default PluginStack and root package
checks remain open. Immutable baseline paths and hashes are unchanged.

## Default Plugin integration evidence: 2026-09-07

[16_04](../../examples/v3/profiles/16_04_plugin_stack.md) adds six exact
references for PR 263 Plugin choices and PR 281 ordinary routes. The examples
retain explicit configuration, static route input and a caller module-attribute
route table through real Agent calls. One Session owns work; optional stores
survive Agent stop. The private reasoning factory retains default Policy.

Core default-map conversion remains open. The new helper does not interpret
old Memory/Thread choices as AI policy switches. This is partial execution
evidence, not completion of all composition or recovery requirements. Immutable
baseline paths and commit scope are unchanged. All 126 statuses remain pending.

## Request admission and options evidence: 2026-09-07

[02_18](../../examples/v3/profiles/02_18_admission.md) adds actual rejection
events for PR 262 and canonical method identity for PR 314. The tests preserve
the original stream after a duplicate ID. Custom routes use the declared
profile instead of a method inferred from the Signal name.

[02_19](../../examples/v3/profiles/02_19_model_options.md) adds public model
forms and option evidence for PRs 206, 238, 248 and 295. Request headers use
actual HTTP/SSE and retain the issue 212 cases. The shared mock now serves
buffered Responses, including a real Action round and a typed object.

The ledger adds 23 exact test references. It now has 630 references and 53 rows
with partial evidence. All 126 statuses remain pending. These cases do not
complete the whole model/method matrix, within-loop provider changes, streaming
Responses, WebSocket ownership, durable recovery or package/consumer gates.
The immutable baseline paths, hashes and reviewed commit range are unchanged.

## Failed-call counts and prompt evidence: 2026-09-07

[02_20](../../examples/v3/profiles/02_20_call_counts.md) checks terminal
failure/cancellation counts and preserved usage for PRs 262, 314, 297 and 312.
These counts describe started v3 model operations; they do not replace HTTP
or Quota accounting. Recovery does not invent an uncommitted count.

[09_15](../../examples/v3/profiles/09_15_prompt_policy.md) extends related
PR 217 and 218 prompt-attribute and default evidence to Adaptive. Actual model
messages retain the documented differences between public and native inputs.

The ledger adds 19 exact references, for 649 in total. Its 53 partial rows and
126 pending statuses remain. Baseline paths, hashes and commit scope are
unchanged. Full feature, recovery, package and consumer checks remain required.

## Raw reasoning-tool evidence: 2026-09-07

[09_16](../../examples/v3/profiles/09_16_reasoning_tool.md) closes the raw
RunStrategy schema-export gap and adds five exact references. They cover
PR 341 schema conversion, the runtime-maintenance method-dispatch requirement,
and related PR 332 portable-state and cancellation boundaries. All seven
methods run through actual model-selected Actions. No wrapper Flow replaces
the raw Action proof.

The ledger has 654 references and 53 rows with partial evidence. All 126
statuses remain pending. These tests do not establish legacy checkpoint
conversion or durable recovery. Immutable baseline paths and hashes remain.

## Dynamic catalog and facade evidence: 2026-09-07

[03_01](../../examples/v3/profiles/03_01_dynamic_catalog.md) adds ten exact
references for PR 267 dynamic/direct tools, PR 281 ordinary routes and related
PR 332 portable reconstruction. The real Action and held-tool cases preserve
request identity, next-request visibility and protected Plugin state. Repeated
registration preserves a native alias instead of adding a duplicate target.

The ledger has 664 references and 54 rows with partial evidence. All 126
statuses remain pending. Reconstruction does not prove durable recovery or
legacy checkpoint conversion. Baseline paths and hashes remain unchanged.


## Native checkpoint resume: 2026-09-07

[14_03](../../examples/v3/profiles/14_03_checkpoint_resume.md) adds 17 integration cases through the actual public ReAct API.
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

[14_04](../../examples/v3/profiles/14_04_standalone_actions.md) adds 13 integration
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

[14_05](../../examples/v3/profiles/14_05_worker_lifecycle.md) adds nine integration
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

## Trace and repeated-call evidence: 2026-09-07

[14_06](../../examples/v3/profiles/14_06_trace_and_cycles.md) adds 13 cases using
the real Flow and the shared model mock. Three exact tool-start redaction
references extend PR 300's partial sanitizer evidence. The other cases retain
baseline stream and repeated-call behavior. The repeated-call code entered in
`eb2279fa` (PR 188), before v2.0.0; it does not create a post-release ledger row.

The ledger has 693 exact references and 59 rows with partial evidence. All
126 statuses remain pending. Original source paths and hashes stay unchanged.
The focused set passes 82 checks. Full results and remaining gates are in the
[implementation record](implementation.md).

## Standalone queue evidence: 2026-09-07

[14_07](../../examples/v3/profiles/14_07_standalone_input.md) adds 13 integration
cases for caller queues through the native runtime. Twelve exact references
extend PR 225's input and lifecycle evidence; one shared-control reference
extends PR 235. The ledger now has 706 references and 59 rows with partial
evidence. All 126 statuses remain pending. Baseline source paths and hashes
are unchanged.

The focused set passes 57 checks, including retained queue tests. Queued input
remains volatile, and query append and old State conversion remain open. Full
validation is recorded in [implementation](implementation.md).

## Native query append evidence: 2026-09-07

[14_08](../../examples/v3/profiles/14_08_query_append.md) adds 15 native
continuation cases. One exact rich-input reference extends PR 278. Query append
already existed before v2.0.0; the canonical Runner relocation is visible in
`eeadb632`, an ancestor of the baseline. No post-release row is invented for it.

The ledger now has 707 exact references and 59 rows with partial evidence.
All 126 statuses remain pending. Baseline paths and hashes are unchanged.
Native checkpoint version-1 compatibility is distinct from old v2 State
conversion. The focused set passes 58 checks. Full validation and remaining
conversion gates are in [implementation](implementation.md).

## Standalone State conversion evidence: 2026-09-07

[14_09](../../examples/v3/profiles/14_09_state_migration.md) adds 22 conversion
and recovery examples. Its rich-input case extends PR 278 with an uploaded PDF
file ID and retained refs. The ledger now has 708 exact references and 59 rows
with partial evidence; all 126 statuses remain pending. The other conversion
cases cover the baseline standalone token contract. They do not close PR 332's
Agent persistence and sink conversion requirements. Immutable baseline paths
and hashes are unchanged.

## Failure-position evidence: 2026-09-07

[14_10](../../examples/v3/profiles/14_10_failure_position.md) adds 18 integration
cases. Eight exact references extend PRs 269, 343, 339 and 225. The ledger now
has 716 exact references and 59 rows with partial evidence. All 126 history
statuses stay pending. Baseline source/test paths and hashes are unchanged.
The new checks cover reasoning position and retain separate model-call meaning;
they do not close Agent persistence, lost-owner recovery or package acceptance.


## Parent inspection evidence: 2026-09-07

[02_22](../../examples/v3/profiles/02_22_request_inspection.md) adds 14 integration
cases. Eight exact references extend PRs 223, 233, 296, 332 and 262. The ledger
now has 724 references and 59 rows with partial evidence. All 126 statuses stay
pending. Immutable baseline paths and hashes are unchanged. The prefix/commit
boundary, state-size elision and remaining recovery limits are explicit in the
profile. Root package acceptance remains open.


## Context-operation evidence: 2026-09-07

[02_23](../../examples/v3/profiles/02_23_context_operations.md) adds 28 integration
cases. Seven references extend PRs 325, 332 and 211. The ledger now has 731 exact
references and 60 rows with partial evidence. All 126 statuses remain pending.
Immutable baseline paths and hashes are unchanged. Context operations that
predate the release remain baseline requirements; no new post-release row was
invented for them. Skill provenance, full recovery and root package gates remain.


## Skill runtime evidence: 2026-09-07

[18_01](../../examples/v3/profiles/18_01_skill_runtime.md) adds 27 integration
cases. Thirty-one exact references extend PRs 286, 316, 325, 353, 354, 358
and 360. The ledger now has 762 references and 66 rows with partial
evidence. All 126 statuses remain pending. Immutable baseline paths, hashes
and source-review records are unchanged. Automatic skills authoring, installed
resources, CLI, complete conversion/recovery and root package gates remain open.


## Automatic skill authoring evidence: 2026-09-07

[18_02](../../examples/v3/profiles/18_02_skill_authoring.md) adds 21 integration
cases and 25 exact references for PRs 286, 316, 325, 353, 354 and 358.
The ledger has 787 references and 66 rows with partial evidence. All 126
row statuses remain pending. Baseline paths, source-review details and the API
inventory are unchanged. Installed resources, CLI, standalone continuation,
complete conversion/recovery and root package gates still need acceptance.


## Persistent tool context evidence: 2026-09-07

[03_02](../../examples/v3/profiles/03_02_tool_context.md) adds 11 cases and
10 exact references for PRs 325 and 347. The ledger has 797 references and
66 rows with partial evidence. All 126 row statuses remain pending. Source
review and baseline fields are unchanged. Remaining feature, conversion,
recovery and package gates still apply.
