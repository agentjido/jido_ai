# History review 16: skill discovery and lazy loading

Reviewed on 2026-09-06 against `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
This pass completes two more source reviews. The total is 90 of 126.
All v3 port evidence remains pending.

Read the complete 2,642-line and 713-line diffs, all PR 286 and PR 316 feedback,
issues 207 and 313, and the relevant final source. Later skill commits remain
pending full review. No runtime tests were run in this pass.

| Commit / PR | Retained behavior | Acceptance mapping |
| --- | --- | --- |
| `678684ff` / PR 286 | Discovery, strict and lenient loading, diagnostics, activation context, registry bookkeeping and relative resources. | HIST-16: discovery, diagnostics, activation, session owner, resource paths and retire/reset |
| `68569d76` / PR 316 | Compact skill indexes, tag filters and the public `LoadSkill` Action. | HIST-16: lazy loop, index resolution and Action inputs; RELEASE: skill API/package |

## Use the real requests as the example

[Issue 207](https://github.com/agentjido/jido_ai/issues/207) asks for Agent Skills
support inside Jido AI. Its scope includes discovery, activation, lazy resource
access, diagnostics and retained session instructions. It explicitly leaves out
Markdown-to-Elixir compilation, a separate signal runtime, hook machinery and
standalone skill CLIs. Preserve that boundary in the AI DSL.

[Issue 313](https://github.com/agentjido/jido_ai/issues/313) supplies a concrete
consumer workflow. A host puts skill names and descriptions in the system prompt,
filters them by an agent tag, and gives the model a `load_skill` Action. The model
requests the full instructions only when needed. The new Action replaces the
consumer's custom wrapper around `Skill.resolve/1`.

The current [Agent Skills specification](https://agentskills.io/specification)
describes separate metadata, instruction and resource loading stages. The
[client guide](https://agentskills.io/client-implementation/adding-skills-support)
also describes catalog filtering and activation context. These pages were checked
on 2026-09-06. They are current design context, not proof of what an earlier PR
implemented. In particular, the final Jido loader still has explicit lenient
fallbacks that differ from the client guide's advice to skip unusable metadata.

Use one support Agent in catalog 12. Give it two valid skills with different
tags, one long instruction body and one small reference file. Define this flow:

1. Build the Agent from trusted configuration. Its model request has the selected
   name/description index and a real `load_skill` tool. It has no full skill body.
2. The shared mock asks for `load_skill` with the selected name. The real Action
   loads and activates that skill.
3. The next captured model request has the actual instruction text and correct
   tool-call/result ID. It does not contain the other skill's body.
4. The mock requests the reference through the real resource Action. Check the
   actual file content in the next model request before the final answer.
5. Repeat activation in the same session and inspect the conversation. Repeated
   calls must not add repeated durable instruction blocks. Each tool call still
   needs its matching result.
6. Start a second Agent with the same skill name and different content. It must
   receive its own instructions. Clear one session and check the other.
7. Repeat after compaction and restore. Check the next provider request, portable
   state and rebuilt runtime bindings. A registry flag alone is insufficient.

The core skill Action, Agent integration and provider transcript need evidence.
Do not stub `LoadSkill.run/2` or return a scripted tool result from the mock.

## Preserve the review fixes and the later contract

[PR 286](https://github.com/agentjido/jido_ai/pull/286) added useful APIs, but its
first implementation did not complete the full lifecycle from issue 207.
The merged review fixes matter:

- Repeated activation returns the same direct context map. The earlier nested
  tuple defect is identified in [the inline review](https://github.com/agentjido/jido_ai/pull/286#discussion_r3234365127).
- Resource access rejects path escape, including absolute paths and symlink
  targets outside the root. Search results must not include an escaped target.
  [The resource review](https://github.com/agentjido/jido_ai/pull/286#discussion_r3234365133)
  explains the failure case.
- Diagnostics accumulated during parsing must reach the caller. They live in
  `Spec.diagnostics`, separate from user metadata. See [the diagnostics review](https://github.com/agentjido/jido_ai/pull/286#discussion_r3234365147).
- A numeric YAML name must return a validation result, not crash during directory
  comparison. Strict mode rejects it. Lenient mode supplies a valid fallback and
  a warning. See [the blocking review](https://github.com/agentjido/jido_ai/pull/286#pullrequestreview-4330838815)
  and [the fix report](https://github.com/agentjido/jido_ai/pull/286#issuecomment-4501145677).
- Empty name normalization also needs a valid fallback. User-home discovery is
  computed at runtime. Registry clear removes activation records. Durable flags
  must not leak into the returned activation context. These requirements appear
  in [the final review](https://github.com/agentjido/jido_ai/pull/286#pullrequestreview-4332191615).

PR 286's body also claims changes to four LLM Actions. Those files are absent
from the complete merged diff. Do not assign that body claim to this commit.
Historical reports of passing tests and CI are review context, not new v3 proof.

The initial activation table used only the skill name. The final table uses
`{session_id, name}` and still belongs to the global Registry process. The public
activation API defaults to the caller process. Skill Actions choose the first
available session, Agent or request ID, then the caller process. V3 must keep a
stable session identity across Flow workers. Do not let each worker become a
new session or copy the old global-name key.

Activation returns the canonical stored context and reports failed body reads.
The final context also holds resource policy, provider bindings and allowed
provider resource IDs. These runtime bindings must not be copied as portable
Agent state. Preserve instruction data and rebuild host bindings on restore.

Sequential reuse does not prove atomic activation. The source checks for an
existing entry, reads the body/resources, then writes the entry. Concurrent
calls can both pass the first check. Define one owner and test simultaneous
activation, failed loading and cleanup. Also test a changed catalog under the
same session/name: a cached context must not cross an Agent or tenant boundary.

`mark_durable` is registry bookkeeping. It does not itself change conversation
content. `clear_activations` removes one session, including durable entries;
`Registry.clear` clears both tables. `unregister` removes a catalog entry but
does not remove an existing activation. Preserve or explicitly migrate these
distinct operations. The lazy Registry startup is linked to its first caller;
test supervised ownership and caller exit rather than assume persistence.

## Make the index and loader agree

[PR 316's inline review](https://github.com/agentjido/jido_ai/pull/316#discussion_r3448947356)
found that `render_index/2` could advertise an unregistered module or Spec, while
the first loading Action resolved names only through the Registry. The model
could see a skill it could not load.

The final `AgentIntegration` builds an index and reserved tool context from the
same selected Specs. `LoadSkill` uses that scoped map and does not fall through
to the global Registry when a name is absent. However, `Prompt.render_index/2`
still only renders text. It does not register a module/Spec or bind it to a
later Action call. A manual index requires a matching catalog or registry setup.
Do not claim the generic helper makes an unregistered skill loadable.

The common AI lowerer should describe one catalog binding. Runtime preparation
must derive both disclosure and loading from it. Apply tag selection once to
that selected set when it defines Agent scope. The standalone prompt helper's
tag filter only controls rendered text; it is not a permission check.

Keep `:any` and `:all` tag matching, deterministic registry index ordering,
optional header/loading instructions, optional allowed-tool labels and the empty
index result. The final automatic Agent integration omits skill tools when its
catalog is empty. `allowed-tools` remains advisory metadata. The explicit
`filter_tools/2` helper is host policy; automatic activation must neither grant
permission nor silently remove unrelated Agent tools.

The Action accepts atom or string parameter keys, trims names, validates name
format and returns structured failures. Preserve `include_metadata` defaults
and validation. Its final minimal payload includes `root_dir` and `resources`
as well as `name`, `description` and `instructions`. The first three-field
payload is not the target contract. Error `available_skills` must use the
selected catalog and must not disclose another Agent's registry entries.

## Required acceptance variants

All cases remain pending. Add these variants to catalog 12, with history and
restore checks in catalog 06 and 14. No new top-level example family is needed.

| Variant | Required evidence |
| --- | --- |
| `HIST-16/discovery` | Use temporary project/user roots and duplicate names. Prove final precedence, stable order, source paths and collision diagnostics. Runtime configuration selects trusted roots. Discovery does not retain full bodies. Invalid metadata and scan limits give the final documented results. |
| `HIST-16/diagnostics` | Cover numeric, missing and empty-normalized names; blank descriptions; malformed YAML; wrong filename/directory; invalid optional fields; strict and explicit lenient modes. Check returned errors, warnings, counts and presentation on both success and failure. Preserve user metadata separately. |
| `HIST-16/activation` | Activate by name, Spec and trusted module; test a compiled but unloaded module. Check canonical context equality, missing body errors, no activation after failure, empty inline body and ordered batch results. Test the final resource context, not the initial smaller map. |
| `HIST-16/lazy-loop` | Run the seven-step support workflow through Agent/Flow, ReqLLM and the shared mock. Capture catalog-only input, real loaded instructions, relative reference content, paired tool results, final answer and committed state. Full bodies must appear only after selection. |
| `HIST-16/index-resolution` | Advertise modules, runtime Specs and discovered files through the same selected catalog used by the loader. Exercise the original unregistered-Spec failure and the documented manual setup. Check tag `:any`/`:all`, empty catalogs, ordering and unknown-name errors. Missing scoped names cannot fall through to global entries. A removed or changed file has an explicit activation result. |
| `HIST-16/action-inputs` | Use real tool calls and direct Exec for atom/string inputs, trimmed names, metadata true/false/nil, invalid names and invalid types. Verify final payload keys, structured errors and provider-visible tool schemas/results. Advisory tool labels do not change actual tool permission. |
| `HIST-16/session-owner` | Use concurrent Agents with equal names and distinct content. Reuse a session across workers and requests; activate twice at once; fail a load; end an owner. Check instruction deduplication, tool pairing, compaction, restored state and tenant/catalog identity. Runtime provider handles remain outside portable state. |
| `HIST-16/resource-paths` | Read relative resources from the activated root. Reject traversal, absolute paths, escaped symlinks and missing escaped targets; test search as well as direct reads. Apply the final listing/read bounds and final symlink policy. No rejected path or content reaches the model. |
| `HIST-16/retire-reset` | Distinguish unregister, deactivate, durable/unmark, one-session clear and full registry clear. Existing activations follow the documented invalidation rule. No stale state appears in a new session. Run normal supervised startup and first-caller exit cases. |
| `RELEASE/skill-api-package` | Compile a fresh consumer using the skill Actions, prompt helpers and activation APIs. Check the published Action schemas, Skill documentation group, guides and Mix-task diagnostics. Keep schema setup reliable after removal of compile-time `require` calls. |

## Follow-up review and simplification

Trace these commits before closing HIST-16: lifecycle `3a0d8c39`, conformance
`143099da`, trusted catalog `aec0165e`, bounded resources `d71a78cc`, runtime
providers `3e391971` and binary resources `fc5bc143`. Each still needs its own
complete diff and PR review. Their final source constrains this plan but does
not make their ledger rows reviewed.

Examples must use the final strict loader rules. The first PR warned on directory
mismatch in strict mode and truncated long descriptions; final strict loading
rejects both. Final `load_with_diagnostics` also carries diagnostics through
failure. Final discovery requires explicit trust and reads bounded frontmatter.
Final resource loading has stronger limits than the first wildcard-based scan.
Do not reintroduce the earlier behavior during a mechanical port.

Keep the authoring model small: one skill catalog reference in the AI profile,
runtime catalog preparation, normal Actions for loading, and session-owned
activation state. No separate skill compiler, execution engine or mock server.
In the runtime refinement pass, decide invalidation and restore behavior before
porting the global tables. In the feature gate, require the captured provider
transcript and failure cases before marking this feature complete.

Source: [activation](../../../lib/jido_ai/skill/activation.ex),
[registry](../../../lib/jido_ai/skill/registry.ex),
[discovery](../../../lib/jido_ai/skill/discovery.ex),
[loader](../../../lib/jido_ai/skill/loader.ex),
[diagnostics](../../../lib/jido_ai/skill/diagnostics.ex),
[resources](../../../lib/jido_ai/skill/resources.ex),
[prompt](../../../lib/jido_ai/skill/prompt.ex),
[Agent integration](../../../lib/jido_ai/skill/agent_integration.ex), and
[loading Action](../../../lib/jido_ai/actions/skill/load_skill.ex).
Tests: [activation](../../../test/jido_ai/skill/activation_test.exs),
[discovery](../../../test/jido_ai/skill/discovery_test.exs),
[loader](../../../test/jido_ai/skill/loader_test.exs),
[diagnostics](../../../test/jido_ai/skill/diagnostics_test.exs),
[registry](../../../test/jido_ai/skill/registry_test.exs),
[resources](../../../test/jido_ai/skill/resources_test.exs),
[prompt](../../../test/jido_ai/skill/prompt_test.exs), and
[Action](../../../test/jido_ai/skills/skill/actions/load_skill_test.exs).
Guide: [Skills System](../../../guides/developer/skills_system.md).


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
