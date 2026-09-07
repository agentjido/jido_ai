# History review 13: typed signals and catalog setup

Reviewed on 2026-09-06 against `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
This pass completes three more source reviews. The total is 85 of 126.
All v3 port evidence remains pending.

Read all three complete diffs and all discussion attached to PRs 310 and 342.
Inspect final Signal definitions, model setup tests and the local Signal v3
source at `5a09b6bc6d1d192d13f910e5106459e8f0049b29`. No runtime tests were run.

| Commit / PR | Retained behavior | Acceptance mapping |
| --- | --- | --- |
| `6f5a7309` / PR 310 | Typed AI Signal validation and constructors; removal of unused direct dependencies and obsolete warning ignores. | HIST-13: typed signals; HIST-20: signal input/options; RELEASE: direct dependencies, signal metadata, current type checks |
| `01c0f02e` / PR 342 | Model catalog setup does not consume the timed test request budget or depend on test order. | HIST-01: catalog startup; RELEASE: timed model suites |
| `8464b78c` / no merged PR | The public model helper documentation links to the model catalog. | RELEASE: model catalog docs |

## A dependency title hides a Signal contract change

[PR 310](https://github.com/agentjido/jido_ai/pull/310) describes dependency
cleanup. Its merged diff also adds a 233-line `Jido.AI.Signal.Definition` and
moves ten public AI Signal modules to it. This is a behavior change with new
tests. It cannot receive only a dependency disposition.

The description also says that ecosystem lock versions were updated. Those
versions were already present in this commit's parent. The actual lock diff
only removes StreamData. Direct NimbleOptions is removed from `mix.exs`, but
it remains a transitive dependency. Do not require its absence from the entire
dependency tree. Keyword output schemas remain a supported AI input form;
removing a direct package entry does not remove that contract.

The changed Signal modules are EmbedResult, LLMDelta, LLMResponse,
RequestCompleted, RequestError, RequestFailed, RequestStarted, ToolResult,
ToolStarted and Usage. Retain their event types, default sources, required
fields, optional fields and defaults through the shared v3 Signal boundary.

The baseline data validator accepts a map. It converts only known top-level
string keys to their schema atoms and rejects unknown keys. It performs shallow
type checks for any, atom, integer, map and string. It does not recursively
validate an arbitrary result. Nil is valid for `:any`, but is not a string,
integer or map. An omitted optional field differs from an explicit invalid nil.
Default metadata is an empty map; default delta kind is `:content`.

| Variant | Required evidence |
| --- | --- |
| `HIST-13/typed-signals` | Construct every changed Signal with its smallest valid payload, then observe those types in real Agent/model/tool flows. Retain required fields, optional omission, defaults, source and type. Cover missing fields, invalid types and invalid envelope attributes through both `new` and `new!`. |
| `HIST-20/signal-input` | Accept known atom-keyed and string-keyed payloads. Reject unknown keys without creating atoms. Retain nested result keys and arbitrary values where the field is `:any`. Test explicit nil and mixed atom/string duplicates. Define duplicate handling before the common validator replaces the old one. |
| `HIST-20/signal-options` | Apply allowed source, subject, ID and time overrides. Test malformed options, duplicate attribute aliases, and attempts to replace type or validated data. V3 constructors must retain the definition's type and validated data; document that change from the old unrestricted options merge. |
| `RELEASE/signal-metadata` | Check public type/source/content-type/schema accessors and documented metadata helpers. Define the change from keyword schemas to static Zoi schemas. Keep a thin compatibility helper where required; do not build another schema compiler to reproduce metadata. Document constructor error changes or preserve them in an explicit adapter. |
| `RELEASE/direct-dependencies` | Build and test a clean consumer using declared dependencies. Remove unused direct NimbleOptions/StreamData entries without banning valid transitive use. Retain keyword object-schema input through the supported adapter. Keep only current, explained type-check exceptions. |

Reuse `RELEASE/current-type-checks` from review 11 for the two obsolete warning
ignore entries removed here. Do not restore old warnings merely to match the
previous file.

## Use the core Signal implementation where its contract fits

The inspected v3 `use Jido.Signal` accepts a static Zoi data schema and supplies
validation, constructors and basic metadata accessors. It fixes type and data
after option normalization. The old AI helper merges all options after data
validation, so options can replace the validated data or type. The new port
must close that bypass and document the changed behavior.

The old normalizer also overwrites duplicate atom/string data keys during map
iteration. Its default values bypass field validation. These are limits of the
implementation, not reasons to copy it into v3. Test the real public definitions
and select one explicit normalization rule. Do not expose a second general
Signal DSL through AI.

Other differences need deliberate handling. The AI helper adds a timestamp
and derives a module source if no default exists. The v3 core definition leaves
time absent and requires a source when there is no default. All ten changed
AI definitions have explicit sources. Preserve their observed source behavior;
decide timestamp and exception compatibility at the AI boundary. Core errors
can be Zoi errors or envelope strings, while the old AI `new!` raises a
RuntimeError for returned validation failures.

The old helper writes specversion `1.0.2`. The inspected v3 codec accepts that
legacy value and normalizes it to `1.0`. It also retains `from_map/1` and
`ID.generate!/0`. These APIs are not missing. Test the resulting v3 envelope
instead of treating a literal old version string as a required output.

The simplification target is one static Signal schema and the core envelope
implementation. Retain only the AI-specific input/error/metadata compatibility
that the migration contract requires. Link this decision to the DSL and shared
operation gates before deleting the old helper.

## Test catalog setup and request timeouts separately

[PR 342](https://github.com/agentjido/jido_ai/pull/342) explains that the first
model lookup loaded the packaged LLMDB snapshot inside a 750 ms test budget.
The full suite could hide this because an earlier test loaded the catalog.
The change calls `LLMDB.providers()` in `setup_all` for the two affected suites.
It does not add a global preload, change production startup, or raise the
request timeout. This fix was split from PR 341 and has its own acceptance.

| Variant | Required evidence |
| --- | --- |
| `RELEASE/timed-model-suites` | Run the fast strategy file, full strategy file and intended smoke command separately in fresh test processes. Prepare the packaged catalog before each suite's timed request. Retain required tests and avoid dependence on earlier files. Report all excluded cases separately. |
| `HIST-01/catalog-startup` | In a fresh runtime, load the packaged catalog and complete the first real AI request through the mock. Separately hold a provider response beyond the configured request deadline and assert the documented timeout and cleanup. Record whether production catalog preparation occurs before admission or inside the total deadline. |
| `RELEASE/model-catalog-docs` | Build public API documentation and retain a valid link to the model catalog. Verify the destination at the package gate. This documentation change does not require another Agent example or a provider request. |

The full strategy test helper accepts several failure states for some methods.
Passing that matrix alone does not prove every method succeeds. The v3 method
examples must assert their intended success, failure and termination behavior
with the real shared mock. Keep short deadline tests deterministic with barriers;
do not make unrelated timing tests depend on catalog cold-load speed.

The changed [model catalog link](https://llmcatalog.dev/) opened successfully
as the catalog site during this review. Its live model contents are not pinned
acceptance fixtures. Use the packaged catalog and explicit model fixtures for
repeatable examples.

## Baseline evidence

Source: [AI Signal definition](../../../lib/jido_ai/signals/definition.ex),
[Signal modules](../../../lib/jido_ai/signals),
[RunStrategy](../../../lib/jido_ai/operations/run_strategy.ex),
[public model documentation](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai.ex),
[dependencies](../../../mix.exs), and [lockfile](../../../mix.lock).

Tests: [AI Signals](../../../test/jido_ai/signal_test.exs),
[keyword object schemas](../../../test/jido_ai/skills/llm/actions/generate_object_action_test.exs),
[fast strategy suite](../../../test/jido_ai/skills/reasoning/actions/run_strategy_action_fast_test.exs), and
[full strategy suite](../../../test/jido_ai/skills/reasoning/actions/run_strategy_action_test.exs).

V3 comparison: [Signal definition API](../../../../jido_signal/lib/jido_signal.ex),
[codec](../../../../jido_signal/lib/jido_signal/codec.ex),
[definition tests](../../../../jido_signal/test/jido_signal/signal_definition_test.exs), and
[legacy version tests](../../../../jido_signal/test/jido_signal/codec_test.exs).
