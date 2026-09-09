# History review 19: trusted catalog and resource bounds

Reviewed on 2026-09-06 against `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
This pass completes two more source reviews. The total is 95 of 126.
All v3 port evidence remains pending.

Read the complete 1,151-line and 1,966-line merged diffs, both PR discussions,
issues 350 and 351, and relevant final source. Issue 348 supplies the parent
scope from [review 18](18-skill-lifecycle-and-conformance.md). No runtime tests
were run. Provider and binary commits retain separate pending source reviews.

| Commit / PR | Retained behavior | Acceptance mapping |
| --- | --- | --- |
| `aec0165e` / PR 353 | Catalog metadata without bodies, deterministic root precedence, strict current-file activation, explicit discovery trust and visible registry load errors. | HIST-16: precedence, validation, current files, read bounds and install failure |
| `d71a78cc` / PR 354 | General resource listing, explicit incomplete state, validated limits, scoped loading, structured errors and file identity checks. | HIST-16: listing, read policy, session scope, open races and Action errors; RELEASE: packaged APIs and dependency runtime |

## Use the accepted PR corrections

[Issue 350](https://github.com/agentjido/jido_ai/issues/350) requests lazy catalog
construction with one duplicate policy, current-file validation and explicit
filesystem trust. [PR 353](https://github.com/agentjido/jido_ai/pull/353) contains
three review corrections:

- [Unusable catalog names](https://github.com/agentjido/jido_ai/pull/353#discussion_r3865539856):
  matching directory and YAML names were insufficient. Spaces, uppercase and
  names over 64 characters could enter the prompt but fail in `LoadSkill`.
  The merged catalog constructor applies the runtime name rule.
- [Registered catalog activation](https://github.com/agentjido/jido_ai/pull/353#discussion_r3865539860):
  activation by name bypassed the strict catalog resolver. It could return the
  whole file, including frontmatter. Both name and direct Spec activation now
  resolve file catalog Specs before loading their instructions.
- [Malformed registry files](https://github.com/agentjido/jido_ai/pull/353#discussion_r3865539869):
  metadata discovery could silently drop malformed candidates. Registry path
  loading now sends every discovered file through strict loading. Keep this
  distinct from discovery's permissive omission behavior.

The author records all three fixes and adds regression tests. Historical green
CI is evidence of the original change, not proof that v3 implements it.

[Issue 351](https://github.com/agentjido/jido_ai/issues/351) requests arbitrary
bundled files and bounded resource access after activation.
[PR 354](https://github.com/agentjido/jido_ai/pull/354) also contains two accepted
corrections. [Valid UTF-8 with NUL bytes](https://github.com/agentjido/jido_ai/pull/354#discussion_r3865660520)
must still fail text loading. A [failed file inspection](https://github.com/agentjido/jido_ai/pull/354#discussion_r3865660532)
must set `:unreadable_entry` and make the listing incomplete. The diff tests NUL
rejection through both the resource API and Action. It adds the inspection-error
branch without a corresponding named regression test. Add that missing case.

## One selected catalog, with explicit lifecycle rules

Discovery preserves configured root order, sorts files within each root and
removes repeated paths. Earlier roots win duplicate names. Standard discovery
selects project entries before user entries. Collision warnings name both files;
discovery metadata also records shadowed locations. The Agent stores diagnostics
with its prepared configuration and derives its index and scoped lookup from
the same selected Specs.

`to_catalog_spec/1` keeps name, description, source/body file references and
discovery scope. It does not keep the full body or all manifest fields. The
selected file is strictly loaded on first activation. That load obtains current
instructions and manifest data, then merges the catalog metadata. `to_spec/2`
also changes to strict loading by default; lenient loading stays explicit.

Name activation checks the registry first. Filesystem fallback requires both
`:paths` and `:trust`; a supplied false policy still rejects the root. A registry
hit is not restricted by fallback paths. This is different from the model
Action's closed scoped catalog. Keep these APIs and their precedence explicit.

The final provider commit adds validated inline runtime Specs, with precedence
over discovered files. It does not remove these filesystem rules. Its full
review remains pending.

The source exposes limits that need decisions before the v3 runtime port:

- Discovery reads lines until the closing delimiter and retains at most 64 KiB
  of YAML. `IO.read(..., :line)` can allocate a larger line before this check.
  The opening line is also read before a size check. Prove actual bounded reads
  for oversized single lines; the retained-byte counter is not sufficient.
- Malformed or missing/non-string names are omitted by metadata discovery.
  Catalog validation rejects other invalid names, but does not apply every
  strict manifest rule, such as the description length limit. Document which
  errors appear during discovery, preparation and activation. Do not describe
  a catalog Spec as a fully validated file.
- A leniently loaded file Spec has an inline body. The strict resolver matches
  file body references with discovery metadata. Direct activation of an inline
  file Spec can bypass that resolver. Define the accepted boundary for trusted
  module/runtime Specs and explicitly repaired file Specs. Add a test instead
  of claiming the issue's full strict-activation requirement already passes.
- Activation reuse is keyed by session and name. A different root, changed
  policy or changed Spec under that key can reuse old content. Define catalog
  revision, invalidation and cleanup rules with the existing session case.
- Registry loading writes each accepted file before reading the next one. A
  later error can leave earlier changes installed. Its duplicate map is local
  to one load call; a later call can replace an existing name. It also strictly
  validates shadowed files before skipping them. Test these public effects and
  define atomic installation for the v3 selected catalog, with an explicit
  compatibility rule for the old Registry API.

The current catalog reader skips malformed files without diagnostic records.
Registry loading instead fails, and collision reporting uses logs there rather
than the discovery result's diagnostics. A shared implementation must preserve
or explicitly migrate these differences.

## General resource listing and loading

The resource list includes root files such as `LICENSE`, custom directories and
the conventional `scripts`, `references` and `assets` groups. Those three groups
are views of the general list. Entries contain relative paths, names, byte sizes
and modification times. Root `SKILL.md` and its hard-link aliases are excluded.
The enclosing `LoadSkill` result still has `root_dir`; relative listing entries
do not mean that the entire result contains no absolute path.

The original policy defaults are 256 resources, depth 8, 1,024 directories,
64 KiB for the encoded general list, 1 MiB per file and 256 KiB of text.
Policy input accepts validated structs, keyword lists or atom-keyed maps.
Unknown keys and invalid limits return structured errors. Depth can be zero;
the other numeric limits must be positive. The later binary commit adds explicit
`:allow` to the default `:reject`. Text-only APIs still reject binary content.

Count, depth, directory and listing-byte limits produce incomplete results with
named reasons. Unreadable directories and entries also make results incomplete.
Symlinks and other non-resource file types are skipped. No-root/module skills
get an empty complete list. A missing or non-directory filesystem root also
currently yields an empty complete list; that is not proof the root was scanned.

Preserve the distinction between a listing bound and read authorization.
Filesystem resource loading checks the active skill's root and saved policy;
it does not require the path to have appeared in the activation listing. The
original Action test creates a resource after activation and loads it. Later
provider resource IDs have a different, explicit listed-ID rule.

Loading rejects absolute and escaped paths, symlink components below the root,
non-regular files, root instructions and hard-link aliases of those instructions.
Safe relative normalization such as `references/../references/guide.md` is valid.
The resource API checks size before opening, compares the opened descriptor's
device/inode/type with the inspected file, reads at most the selected limit plus
one byte, and closes the descriptor. Text loading rejects invalid UTF-8 and NUL
content. Other control characters are not excluded by that test alone.

`LoadResource` uses the same session identity as `LoadSkill` and the policy saved
at activation. Caller context does not replace that saved policy on each load.
The new Action exposes structured invalid-input, not-activated, missing-path,
oversized, binary and general-load errors. Both Actions are installed when the
selected catalog is nonempty. Later code adds resource IDs, a path alias and
binary results; keep those additions for their own source review.

Further acceptance limits from source inspection:

- The listing byte limit measures only `resources`, not duplicated compatibility
  groups, the wrapper or the complete model result. An empty JSON list itself
  uses two bytes, while policy validation permits a one-byte limit. Define this
  boundary and separately bound total model input.
- The scan reads and sorts all names in a directory before count limits stop
  collection. It also walks in sorted depth-first order, which is not always
  global relative-path order. Test `a.txt` next to `a/z.txt`, wide directories
  and exact limit boundaries before claiming order and memory guarantees.
- File identity checks detect replacement between inspection and open. They
  are not a content version or an activation-time root binding. Test root/file
  replacement, growth, unchanged-inode writes, symlink races and cleanup with
  controlled barriers. No new runtime reproduction is claimed here.
- `search/2` now filters a bounded listing with a small glob translator. It
  returns no completeness metadata. `resource_info/2` folds load-path failures
  into `:not_found`. Preserve these compatibility contracts explicitly; do not
  silently claim the old wildcard grammar or full unbounded search.

## Required acceptance cases

Extend HIST-16 and catalog 12. Keep one support Agent with real loading Actions
and the unified mock. Direct filesystem/API tests supply precise boundaries;
the Agent flow proves that accepted instructions and resources reach the model.
Every case below remains pending.

| Variant | Required evidence |
| --- | --- |
| `HIST-16/catalog-precedence` | Use reversed lexical root names, project/user roots, repeated paths and multiple collisions. Compare selected prompt entries, scoped lookup, activation content and warnings naming both locations. Include the final runtime-Spec precedence in the provider slice. |
| `HIST-16/catalog-validation` | Reject advertised names the Action cannot use. Cover missing/non-string names, malformed YAML, long descriptions, strict versus explicit lenient Specs, and direct/name/module activation. Each stage returns its documented error or omission without unexpected filesystem fallback. |
| `HIST-16/catalog-current-file` | Change valid instructions after preparation. Direct catalog and registry-name activation load the new body without frontmatter. A newly invalid file fails without activation. Repeat after session reuse, catalog replacement and restore under the documented invalidation rule. |
| `HIST-16/catalog-read-bounds` | Prove no body read during discovery, including a non-UTF-8 body. Exercise frontmatter delimiter/BOM/EOF, 64 KiB boundaries, oversized single/opening lines, unreadable entries, depth and directory limits. Record actual read bounds rather than only retained state size. |
| `HIST-16/catalog-install-failure` | Load a valid file followed by a malformed or invalid file, an invalid shadowed file, and a later load call with an existing name. Check returned errors and installed state. Prove atomic v3 catalog replacement or document the separate legacy Registry contract. |
| `HIST-16/resource-listing` | Include root/custom/conventional paths, no-root skills, missing roots, instruction hard links and symlinks. Cover exact/over count, depth, directory and encoded-byte limits, empty-list bytes, unreadable-entry PR regression, sorting and compatibility views. Capture complete/truncated state in the actual tool result. |
| `HIST-16/resource-read-policy` | Check file/text byte boundaries, empty/multibyte text, invalid UTF-8, NUL and the final explicit binary policy. Keep raw-byte APIs separate from text APIs. Prove default and custom policies through Agent setup, real activation and subsequent resource calls. |
| `HIST-16/resource-session-scope` | Load before activation, from another session, after cleanup and across Flow workers. Read a new allowed filesystem file after activation; do not treat a truncated list as a filesystem allowlist. Changed catalog/policy bindings follow the chosen invalidation rule. |
| `HIST-16/resource-open-race` | Reject escaped/absolute paths, root instructions and aliases, internal/escaped symlinks, missing escaped targets, changed descriptors and invalid roots. Test root/file changes and growth with deterministic barriers. Rejected bytes never reach the model and open handles are closed. |
| `HIST-16/resource-action-errors` | Compare direct Exec and real model tool calls for atom/string inputs, normalized paths, invalid name/path types, not-activated, missing, oversized, binary and general load failures. Preserve error details, call correlation and public compatibility helpers/search behavior. |
| `RELEASE/skill-api-package` | Extend the existing package case with `ResourcePolicy`, all resource APIs, both Actions, provider schemas and updated documentation. Define source-profile/JSON policy conversion without accepting arbitrary atom creation. |
| `RELEASE/dependency-runtime` | Include the commit's Mint 1.9.3 to 1.10.0 lock update. Validate the final resolved graph and HTTP/stream behavior with the package's audit checks. The historical lock change is not a current audit result. |

## Refinement decisions

Keep one prepared catalog and one resource policy shared by ordinary Actions.
Use explicit source kinds to distinguish trusted runtime/module Specs from file
catalogs and lenient inspection results. Keep the selected runtime owner in the
Agent/Flow contract; do not create another skill execution loop.

Before the runtime port, settle catalog replacement, session reuse, saved policy,
portable source identity and failure atomicity. During the feature gate, compare
direct resource results with the next captured provider request. During package
validation, check compatibility APIs, documented bounds and the resolved graph.

Source: [discovery](../../../lib/jido_ai/skill/discovery.ex),
[integration](../../../lib/jido_ai/skill/agent_integration.ex),
[activation](../../../lib/jido_ai/skill/activation.ex),
[registry](../../../lib/jido_ai/skill/registry.ex),
[resource policy](../../../lib/jido_ai/skill/resource_policy.ex),
[resources](../../../lib/jido_ai/skill/resources.ex),
[LoadSkill](../../../lib/jido_ai/actions/skill/load_skill.ex),
[LoadResource](../../../lib/jido_ai/actions/skill/load_resource.ex), and
[session helper](../../../lib/jido_ai/actions/skill/runtime_context.ex).
Tests: [discovery](../../../test/jido_ai/skill/discovery_test.exs),
[activation](../../../test/jido_ai/skill/activation_test.exs),
[registry](../../../test/jido_ai/skill/registry_test.exs),
[resources](../../../test/jido_ai/skill/resources_test.exs), and
[resource Action](../../../test/jido_ai/skills/skill/actions/load_resource_test.exs).


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
