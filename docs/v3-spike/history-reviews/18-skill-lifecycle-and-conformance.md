# History review 18: skill lifecycle and conformance

Reviewed on 2026-09-06 against `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
This pass completes two more source reviews. The total is 93 of 126.
All v3 port evidence remains pending.

Read the full 2,918-line and 1,201-line diffs, both PR discussions, issues 323,
348 and 349, and the relevant final source. No runtime tests were run. The later
catalog/resource commits still need their own full source reviews.

| Commit / PR | Retained behavior | Acceptance mapping |
| --- | --- | --- |
| `3a0d8c39` / PR 325 | Explicit Agent Skills integration at instance initialization, session isolation, a closed catalog, actual instruction retention during compaction and strict field checks. | HIST-16: runtime initialization, catalog scope, durable origin and compaction transcript; existing session/diagnostic cases |
| `143099da` / PR 352 | Document/file validation split, valid parser edge cases, namespaced file metadata, diagnostic propagation and explicit-file CLI validation. | HIST-16: file/document rules, conformance boundaries, metadata conversion and diagnostic failure; RELEASE: CLI and reference fixtures |

## Start from the consumer report

[Issue 323](https://github.com/agentjido/jido_ai/issues/323) reports findings from
the ZAQ skill integration. It identifies six gaps: consumers must connect the
lifecycle by hand, activation is global, the model Action bypasses activation,
durability protects only the registry, strict loading changes invalid fields,
and discovery lacks bounds and trust controls.

[PR 325](https://github.com/agentjido/jido_ai/pull/325) implements an explicit
`agent_skills` option. The final accepted decision keeps it disabled by default.
The report's request for automatic integration means automatic wiring after
opt-in. It does not mean that upgrading Jido AI should scan and trust every
project's instructions.

The selected roots produce one catalog, its prompt index and its loading tool.
The [catalog review](https://github.com/agentjido/jido_ai/pull/325#discussion_r3583861197)
found a fallback that could load outside the selected roots. The merged Action
distinguishes an absent catalog from an explicit empty/invalid catalog. A missing
name in a scoped catalog returns `skill_not_found`; it cannot fall through to
unrelated registry or default filesystem entries. Keep that regression with the
same-name and unregistered-Spec cases from [review 16](16-skill-discovery-and-lazy-loading.md).

The [relative-path review](https://github.com/agentjido/jido_ai/pull/325#discussion_r3583861204)
found a valid `SKILL.md` rejected when the caller was inside its directory.
Expand the path before comparing its parent. Test this through both Loader and
the packaged CLI in a separate process. A temporary fixture must not change
the working directory of concurrent tests.

## Runtime initialization and session ownership

The Agent macro stores skill configuration. ReAct prepares the catalog when an
Agent instance initializes. The PR tests compile the module, change a fixture,
then create the Agent. V3 must also test separate build and runtime directories
so the definition cannot capture a build-host path or body.

The initial PR strictly loads every body during instance initialization, though
the prompt contains only metadata. The later `aec0165e` commit changes this to
metadata-only Specs with strict document loading on activation. Use the final
lazy rule. Do not port the first implementation's eager reads or its claim that
every body error must stop Agent initialization.

The final Agent integration accepts false/nil, true, trusted path lists and
explicit options. True selects standard roots; a list trusts only those roots;
keyword discovery options require a trust policy. It preserves a base system
prompt and omits loading tools for an empty catalog. Runtime Specs and resource
providers are later additions and retain separate pending reviews.

Activation uses `{session_id, name}`. Public activation defaults to the caller
process; the Action selects session, Agent, request or caller identity in that
order. Calls across Flow workers need one stable session owner. The source adds
explicit cleanup but contains no automatic Agent-stop call to `Activation.clear`.
The v3 lifecycle must define and test cleanup on completion, failure and owner
exit. Cleanup of one session must not remove another session's activation.

Catalog state, tool context and tool identity can change through existing host
APIs. Initial configuration merges reserved skill context last, but per-request
tool context then overrides base values, and `set_tool_context` replaces the base
map. Dynamic tool registration can also replace a name. These APIs are not proof
of an immutable request scope. Define a trusted host binding for such changes;
ordinary request data must not replace the selected catalog or resource policy.
Record any changed host API rule in the migration guide.

## Preserve instruction content, not just a flag

The runner attaches skill refs only when the executed tool name is `load_skill`,
its Action map points to the concrete `LoadSkill` module, and its successful
payload contains string `name` and `instructions`. An unrelated Action that
uses that name does not receive the refs. The final runner applies the host's
`on_after_tool_call` callback first, so the approved transformed output is what
the model receives and what becomes durable. A failed callback or failed Action
must not create durable instruction content.

The Strategy retains these refs in both live context and thread projection.
It removes skill durability keys from other tools' events. Compaction selects
durable skill tool results with a matching assistant `load_skill` call ID,
preserves those original results, and removes conflicting result copies from
the replacement. It filters mixed assistant batches to the calls it retains.
User entries and unmatched tool results do not become durable merely by carrying
similarly named refs. Ordinary context replacement has a different rule: this
preservation branch runs only for `reason: :compaction`.

The tests prove parts of this path separately. The runner test stubs ReqLLM and
checks refs. The compaction test manually inserts context entries. Neither alone
proves that real loading, event projection, compaction and the next HTTP request
work together. The v3 acceptance case must connect all four stages.

Several source limits need explicit checks:

- Activation reuse returns the same context, but each model call still appends
  its full tool result. Compaction keeps matching call IDs; it does not dedupe
  by skill name. Do not claim that session bookkeeping alone prevents repeated
  instruction text. Preserve call/result pairing when designing content dedupe.
- A replacement assistant call with the same ID suppresses insertion of the
  original assistant call. That comparison does not check its name or arguments.
  Test a conflicting assistant copy as well as a conflicting tool result.
- The compaction helper trusts accepted current entries and does not re-check
  the Action module. The existing test constructs those entries directly. Define
  which runtime path can create trusted provenance and which imported refs are
  only user data. Restored state needs an explicit compatibility rule.
- The Strategy checks the current Action map, while the runner checks the map
  used for execution. A tool change during work must not invalidate genuine
  provenance or grant it to an unrelated result. Test the request's selected
  tool identity and callback output together.
- Appending preserved entries after replacement content can change ordering.
  The next provider request must still have valid call/result order, complete
  pairing, the replacement system prompt and the retained instructions.

These are source findings and acceptance requirements. No new runtime
reproduction is claimed. Registry `mark_durable` remains independent of these
conversation rules; it does not mutate history.

## Conformance and explicit diagnostics

[Issue 348](https://github.com/agentjido/jido_ai/issues/348) separates the remaining
filesystem work from a future provider abstraction. Its thirteen gaps also cover
lazy discovery, arbitrary resources, bounded loads, name collisions and explicit
trust. Do not close the whole parent issue through the parser work alone.
[Issue 349](https://github.com/agentjido/jido_ai/issues/349) and
[PR 352](https://github.com/agentjido/jido_ai/pull/352) deliver the first parser,
diagnostic and CLI slice.

`Loader.parse/3` validates an in-memory document without requiring a real path
or matching directory. `Loader.load/2` additionally requires an exact `SKILL.md`
basename and matching parent in strict mode. Keep these separate public APIs.
Both support empty bodies, a closing delimiter at EOF, LF/CRLF and an optional
UTF-8 BOM. Non-mapping YAML and parser errors return structured errors.

Strict documents permit only name, description, license, compatibility,
metadata and allowed-tools at the top level. Standard field types and length
limits apply. File tags and versions now use `metadata` keys `jido_ai.tags` and
`jido_ai.version`. Module-based Jido skills keep their native fields. Explicit
lenient parsing still accepts legacy fields with warnings; namespaced values
take precedence when both forms exist. This is a file-format conversion, not
the removal of module skill capabilities.

The new internal result carries diagnostics through each stage. The ordinary
load/parse APIs retain their two-element public result, while
`load_with_diagnostics/2` returns the accumulator on success or failure and
accepts an existing accumulator. Filesystem read errors preserve the accumulator
but do not automatically add a validation error to it. Check both the returned
reason and diagnostic content.

The CLI's `validate` command deliberately uses lenient loading to collect
warnings. Recovered parse errors still count as errors. `--strict` fails if any
file has a warning or error; it is not merely an alias for the Loader's strict
parse mode. JSON includes valid/error/warning counts and per-file diagnostics.
Text output prints warnings and summaries before raising in strict mode.

The [PR review](https://github.com/agentjido/jido_ai/pull/352#discussion_r3865422042)
found that explicit files such as `fooSKILL.md` could be removed by discovery
before validation. The [accepted fix](https://github.com/agentjido/jido_ai/pull/352#discussion_r3865828242)
sends explicit regular files to the loader. Directory discovery still filters
for the exact conventional name. Test `list`, `validate` and strict validation;
do not let zero examined files stand in for a successful explicit-file check.

The CLI still has its own wildcard directory scan. `list --json` reports only
valid Specs, unlike `validate --json`, which reports failures too. Missing paths
can still yield no discovered files. Do not describe these as the same bounded
runtime scanner or silently promise identical diagnostic payloads. Keep the
public differences explicit while sharing parsing and diagnostic operations.

The fixture README records exact-case filenames, ASCII names, BOM support and
strict top-level fields as chosen compatibility rules. It cites a review date
for `skills-ref`, but pins no validator revision and runs no external validator.
The ExUnit suite is useful boundary evidence, not proof of complete equivalence
with every version of that reference implementation.

## Required acceptance cases

These cases extend catalog 06, 12, 14 and 18. All remain pending. Reuse the
support Agent from review 16 instead of creating a second skill framework.

| Variant | Required evidence |
| --- | --- |
| `HIST-16/runtime-init` | Compile in one directory and instantiate in another with changed skill metadata/body. Compare DSL, Builder and trusted data forms. Verify final lazy body reads, base prompt composition, disabled/empty catalogs, valid trust forms and no compile-time filesystem work. |
| `HIST-16/closed-catalog` | Configure only one trusted root, register another same-name or unrelated global skill, then request a scoped miss through real model tool calls. Empty/invalid scoped maps cannot fall through. Test trusted host catalog replacement, ordinary context overrides and tool changes at the request boundary. |
| `HIST-16/durable-origin` | Execute the real Action, an unrelated Action named `load_skill`, failed loads and successful/failed result callbacks. Check actual output, runtime refs, committed context and thread projection. Forged user/tool refs cannot grant trusted skill origin. Preserve request and call correlation. |
| `HIST-16/compaction-transcript` | Load a skill through the shared mock, compact, then capture the next provider request. Check original instructions, mixed batches, matching calls, repeated activations, conflicting assistant/result copies, forged/unmatched refs, ordering and the new system prompt. Repeat with supported restored data and ordinary replacement semantics. |
| `HIST-16/session-owner` | Extend the existing case with stable identity across worker processes, two Agents using one skill name, simultaneous activation, explicit session cleanup and owner exit. Separate registry reuse from instruction dedupe and content durability. |
| `HIST-16/file-vs-document` | Parse valid content with an arbitrary source label, then strictly load it from valid and invalid physical layouts. Test `SKILL.md`, `skill.md`, `fooSKILL.md`, mismatched parents and a bare relative `SKILL.md` in a child process. |
| `HIST-16/conformance-boundaries` | Cover empty body/EOF delimiter, LF/CRLF/BOM, scalar/list/malformed YAML, all required and optional field types, name 1/64/65 and invalid forms, description 1/1024/1025, compatibility 1/500/501, unknown fields and explicit lenient repairs. Invalid files must not become accepted runtime skills through a different entry point. |
| `HIST-16/metadata-migration` | Load migrated bundled files with namespaced tags/version and retain native module fields. Verify strict rejection of old top-level keys, lenient warnings, conflict precedence, string metadata and tag-filtered model disclosure. Malformed legacy values give controlled diagnostics. |
| `HIST-16/diagnostic-failure` | Start with prior warnings, then fail filename, YAML, field or directory validation. Retain the accumulator and final error without duplicate or lost records. Include filesystem read failure and JSON/text presentation. Do not treat a lenient Spec with diagnostic errors as strict runtime success. |
| `RELEASE/skill-validation-cli` | Run packaged list/show/validate commands in a fresh consumer with valid, invalid and warning-only files. Verify explicit wrong-name files are examined, JSON counts, text messages and strict exit status. Preserve explicit eager `Prompt.render(..., include_body: true)` in demos after the default becomes false. |
| `RELEASE/skill-reference-fixtures` | Ship the required bundled skills and retain conformance fixtures. Pin the reference revision used for a comparison and document intended differences. Assert those differences and all boundary cases; a fixture's review date or historical green CI is not a passing comparison. |

## Refinement decisions

Keep a single catalog descriptor in the AI profile. Runtime preparation resolves
the trusted binding and gives the same selected set to prompt and Actions.
Do not add a separate skill compiler, permission DSL or execution engine.

Before the runtime port, define session cleanup, trusted provenance, repeated
instruction handling, catalog invalidation and portable state. The same owner
must connect executed Action identity to committed context. During the feature
gate, test compaction with actual transcripts and callbacks, not fabricated
durable flags alone.

Use one parser result with explicit diagnostics. Keep document validation,
filesystem layout and CLI failure policy as separate decisions over that result.
Do not merge their entry points into a helper that silently changes scope.
Review `aec0165e`, `d71a78cc`, `3e391971` and `fc5bc143` next for final catalog,
resource, provider and binary behavior.

Source: [Agent](../../../lib/jido_ai/agent/definition.ex),
[integration](../../../lib/jido_ai/skill/agent_integration.ex),
[loading Action](../../../lib/jido_ai/actions/skill/load_skill.ex),
[runner](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/react/runner.ex),
[context projection/compaction](../../../lib/jido_ai/reasoning/react/strategy.ex),
[activation](../../../lib/jido_ai/skill/activation.ex),
[registry](../../../lib/jido_ai/skill/registry.ex),
[loader](../../../lib/jido_ai/skill/loader.ex), and
[CLI](../../../lib/mix/tasks/jido_ai.skill.ex).
Tests: [runtime](../../../test/jido_ai/react/runtime_runner_test.exs),
[compaction](../../../test/jido_ai/strategy/react_test.exs),
[conformance](../../../test/jido_ai/skill/conformance_test.exs),
[CLI](../../../test/jido_ai/skill/mix_task_test.exs), and
[fixture choices](../../../test/fixtures/agent_skills_conformance/README.md).


## Native context-operation evidence: 2026-09-07

[02_23](../../../examples/02_requests/02_23_context_operations/README.md) adds 28 cases
for real Agent context operations. The linked ledger references cover core
Thread request refs, pending-operation recovery, durable terminal application
and accepted-history compaction. The original skill call and result now replace
conflicting assistant/result copies. Typed ReqLLM calls are supported.
Actual LoadSkill/callback/catalog provenance and resource loading still need
the complete skill port. This evidence does not close those history rows or
the old Agent conversion and root package gates.


## Native runtime evidence: 2026-09-07

[18_01](../../../examples/18_skills/18_01_skill_runtime/README.md) connects real
activation, resource access, callback approval, committed context, compaction
and later HTTP requests in 27 integration cases. The linked ledger entries
are partial evidence for the feature boundaries in this review. A separate
v3 command passes 293 retained skill/resource checks. Automatic Agent Skills
authoring, packaged resources/CLI, standalone continuation, complete recovery
and release gates remain open. These results do not close the history rows.


## Automatic authoring evidence: 2026-09-07

[18_02](../../../examples/18_skills/18_02_skill_authoring/README.md) adds 21 cases
for public/native authoring and static format parity. The live Session prepares
one selected catalogue for prompt disclosure and loading. Cases cover runtime
roots, trust, source precedence, current-file activation, profile isolation,
restore and live tool/prompt changes. Pure construction performs no discovery.
Static providers and trust callbacks use MFA references. Installed resources,
CLI, standalone continuation, complete recovery and package gates remain open.
This evidence does not close a history row.


## Persistent context evidence: 2026-09-07

[03_02](../../../examples/03_tools/03_02_tool_context/README.md) adds base context
replacement through the existing Configuration Plugin. The cases prove live
and direct changes, request precedence, admitted snapshots, callback context,
protected fields, separate profiles, format parity and restore. Base values
are portable; runtime/skill bindings remain host-owned. These results extend
partial history evidence. The complete feature and package gates remain open.
