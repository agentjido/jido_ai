# History review 01: authoring, model inputs, tools and CLI

Execution update, 2026-09-07:
[02_19](../../../examples/02_requests/02_19_model_options/README.md) adds actual public
request model forms and alias checks for PRs 206, 238 and 248. Strings, aliases,
both tuples, inline maps and model structs use the existing resolver and reach
the shared HTTP mock. Declared defaults remain after each request. The complete
method/source-format matrix, rich gateway credentials, fingerprints and CLI
cases below remain required.

Reviewed on 2026-09-06 against `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
This pass completes source review for 12 commits. All v3 port evidence remains
pending. The review read the complete commit diffs, messages, tests, related
PR discussions and linked user reports. Relevant code was traced to the target
revision. No production code changed and no tests ran during this pass.

The [structured ledger](../history-audit.json) records each SHA and its required
cases. Later commits have their own review status. A reference to a later fix
below does not mark that whole commit reviewed.

## Commit dispositions

| Commit | Finding and retained requirement | Required evidence |
| --- | --- | --- |
| `6ddead0f` | Only reformats a documentation group in `mix.exs`. | FORMAT gate |
| `164d629d` / PR 203 | Only updates the Zoi lock entry. The quoted dependency notes cover nil in generated types. | SCHEMA-TYPES gate |
| `108fbfc9` / PR 204 | Only updates the Igniter lock entry. The quoted dependency notes cover compilation and queued task execution. | INSTALL gate |
| `2ab0b15f` / PR 205 | Makes the existing one-shot/standard-input CLI contract explicit. Empty input without `--stdin` returns an actionable error. | HIST-19 |
| `835756d6` / PR 206 | Adds rich model inputs to all eight Agent macros and reasoning configuration. Adds labels, provider-option keys and token fingerprints. | HIST-01: forms, transport, fingerprints |
| `69934a2d` / PR 217 | Resolves prompt attributes in the caller's compile context. Distinguishes Agent defaults from direct ReAct prompt disabling. | HIST-02: attributes, defaults, invalid values |
| `d6c5b4fc` / PR 218 | Extends prompt handling to CoT/CoD and validates direct CoT prompts. | HIST-02: CoT/CoD defaults |
| `0ba6785d` / PR 221 | Only updates the Zoi lock entry. Dependency notes cover duplicate nil types and nested custom type overrides. | SCHEMA-TYPES gate |
| `22e415e8` / PR 226 | Loads tool modules before checking their callbacks. Keeps a distinct error for modules that cannot load. | HIST-05: unloaded Action |
| `4392827e` / PR 237 | Preserves consumer formatter imports. Also adjusts model helper types and label formatting for Dialyzer. | HIST-18; HIST-01 labels; MODEL-TYPES gate |
| `d2c211f0` / PR 238 | Moves model helpers into `Jido.AI`, removes the internal `ModelInput` module, broadens Action inputs, and serializes tests that change application configuration. | HIST-01: public helpers, Action parity; CONFIG-ISOLATION gate |
| `97f78e79` / PR 248 | Accepts rich aliases, validates their shapes, and resolves labels/fingerprints through aliases. Adds `:llm_db` to the Dialyzer PLT. | HIST-01: aliases, invalid configuration; MODEL-TYPES gate |

These dependency versions are historical evidence, not proposed v3 pins. The
target already uses newer versions. Select compatible v3 dependencies and prove
the required behavior with the package checks.

## HIST-01: a model alias carries gateway settings

[Issue 202](https://github.com/agentjido/jido_ai/issues/202) reports the original
string-only restriction. [PR 206](https://github.com/agentjido/jido_ai/pull/206)
adds direct rich inputs. [PR 248](https://github.com/agentjido/jido_ai/pull/248)
explains the later use case: an OpenAI-compatible gateway needs `base_url` and
provider options in an application alias.

Retain strings, alias atoms, inline maps, both ReqLLM tuple forms, and
`LLMDB.Model` values at the supported entry points. Pass the selected rich value
to ReqLLM without reducing it to a label. Use a label only for display and
metadata. Alias resolution must preserve endpoint and provider settings.

The final public helper owner is `Jido.AI`. PR 238 removed the internal
`Jido.AI.ModelInput` module. Do not restore it as a parallel normalization path.
`Actions.Helpers.resolve_model/2` returns `{:error, :invalid_model_format}` for
an invalid explicit input. `Jido.AI.resolve_model/1` raises `ArgumentError`.
Keep these public result conventions at their respective boundaries.

Alias validation has a specific scope. Unknown aliases fail. Unsupported rich
values fail with the alias name in the error. Rich values also pass ReqLLM model
validation. String values still pass through; this change did not add eager
validation of every string or permit alias-to-alias chains.

| Variant | Example input and observation | Failure and ownership rule |
| --- | --- | --- |
| `forms` | Define a gateway Agent with each supported direct input. Cover ReAct, CoD, CoT, AoT, ToT, GoT, TRM and Adaptive with their real method calls. Use the same input through direct AI operations. | Invalid explicit inputs fail at the documented boundary. Shared AI operations own resolution; the mock only receives requests. |
| `aliases` | Configure `:capable` with a map, tuple and model value pointing to the local mock. Assert the requested path, model ID and a provider option on the wire. | Unknown aliases, invalid shapes and invalid rich specs make no provider/tool call. Restore application configuration after each case. |
| `labels-and-fingerprints` | Compare an alias with its resolved value. Labels remain strings. Fingerprints are deterministic, and a material model/endpoint change changes the fingerprint. | Token restore must check the selected configuration. No raw map can reach a string-only label field. |
| `effective-model` | Change the model for a later turn through a request transformer. Check transport selection, label and continuation handling. | PR 295 supplies the later effective-model rules. Its full review and HIST-15 WebSocket proof remain separate work. |

Use catalog 01 for the small example, 09–11 for method cases, 13 for overrides
and 14 for token compatibility. Extend one model fixture and the shared mock.
Do not build separate adapters in each example.

Baseline evidence: [public model helpers](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai.ex),
[alias validation](../../../lib/jido_ai/model_aliases.ex),
[Action helper](../../../lib/jido_ai/actions/helpers.ex),
[core helper tests](../../../test/jido_ai/jido_ai_core_test.exs),
[Action helper tests](../../../test/jido_ai/actions/helpers_test.exs),
[Agent tests](../../../test/jido_ai/agent_test.exs),
[direct ReAct tests](../../../test/jido_ai/react/public_api_test.exs),
[runtime forwarding test](../../../test/jido_ai/react/runtime_runner_test.exs),
and [token tests](../../../test/jido_ai/react/token_test.exs).

## HIST-02: an attribute prompt reaches the model as text

[Issue 216](https://github.com/agentjido/jido_ai/issues/216) reports a snapshot
crash caused by stored prompt AST. The first proposal in PR 217 evaluated the
attribute too early. [The review](https://github.com/agentjido/jido_ai/pull/217#discussion_r2968231505)
found that this could silently drop the prompt. The merged patch defers the
bare attribute into the caller's compile context, then validates its value.

The new example must compile an Agent with `@prompt`, run a real model operation,
and inspect its exact system message. Compilation alone cannot detect silent
prompt loss. Compare that Agent with one using the same literal string. Check
the lowered definition and stored history for resolved values, not AST tuples.

Preserve the following existing rules at compatibility entry points. Disable
skills in these cases; active skills can append their own system content.

| Entry point | Omitted prompt | `nil`, `false` or `""` | Nonempty text |
| --- | --- | --- | --- |
| `use Jido.AI.Agent` | ReAct default | ReAct default | Exact supplied text |
| Direct ReAct Strategy configuration | ReAct default | No base system prompt | Exact supplied text |
| `use Jido.AI.CoTAgent` | CoT default | CoT default; omit the option before method defaults | Exact supplied text |
| Direct CoT Strategy configuration | CoT default | CoT default | Exact supplied text |
| `use Jido.AI.CoDAgent` | CoD default | CoD default | Exact supplied text |

This table does not assert that every direct CoD call has the CoDAgent rule.
Its Strategy delegates to CoT and uses `Keyword.put_new/3` for the CoD default.
An explicitly empty value can therefore reach CoT normalization. Include that
direct/Agent difference in the method migration decision; do not silently
invent uniform old behavior.

For v3 authoring, keep default, disabled and explicit-text meanings distinct
until normalization finishes. Apply legacy defaults in the compatibility
frontend. All four new source forms must then use the same normalized policy
and common lowerer. This avoids copying the old prompt branches into each
reasoning method.

Add variants for a literal string, a bare attribute, omitted input, `nil`,
`false`, empty text and an invalid numeric attribute. Invalid authoring must
give a source-located compile error before provider/tool work. Direct invalid
configuration retains its argument error. Arbitrary function expressions were
not added as supported prompt inputs by these fixes. The report's wider claim
about model/description attributes is not evidence that those options were fixed.

Catalog 01 owns the authoring cases. Catalog 09 owns CoT/CoD behavior. The later
multiline-code validation case from PR 290 remains part of HIST-02 and needs
its own source review.

Baseline evidence: [Agent normalization](../../../lib/jido_ai/authoring/agent.ex),
[ReAct normalization](../../../lib/jido_ai/reasoning/react/strategy.ex),
[CoT normalization](../../../lib/jido_ai/reasoning/chain_of_thought/strategy.ex),
[CoD delegation](../../../lib/jido_ai/reasoning/chain_of_draft/strategy.ex),
[Agent tests](../../../test/jido_ai/agent_test.exs),
[CoT Agent tests](../../../test/jido_ai/cot_agent_test.exs),
[CoD Agent tests](../../../test/jido_ai/cod_agent_test.exs),
[direct ReAct tests](../../../test/jido_ai/strategy/react_test.exs), and
[direct CoT tests](../../../test/jido_ai/strategy/chain_of_thought_test.exs).

## HIST-05: a generated Action loads before tool validation

[PR 226](https://github.com/agentjido/jido_ai/pull/226) reports generated AshJido
Actions failing with `:missing_name`. Checking exported functions before loading
a compiled module caused that error. The merged test checks a missing module;
the new example must also reproduce the valid, unloaded-module case.

Compile a small real Action to a temporary BEAM file. Run the case in an
isolated runtime with that file on its code path and the module still unloaded.
Register it as a tool, let the mock request it, and verify its actual result in
the next model request. Tool validation owns loading. The mock must not return
the tool's result on its behalf.

Also register a nonexistent module and a loadable module with missing callbacks.
Preserve distinct errors and verify zero model/tool work for rejected setup.
Do not purge a shared application module to construct this case.

Use catalog 03 and 16. The later Plugin-route loading fix and strict/open schema
fix are separate HIST-05 variants. Baseline evidence:
[ToolAdapter](../../../lib/jido_ai/tool_adapter.ex) and
[its tests](../../../test/jido_ai/tool_adapter_test.exs).

## HIST-18: installation preserves the host formatter

[Issue 236](https://github.com/agentjido/jido_ai/issues/236) reports Phoenix and
LiveView macros gaining unwanted parentheses after installation. The installer
added a formatter dependency with no exported rules. The merged
[PR 237](https://github.com/agentjido/jido_ai/pull/237) removes that import and
keeps model alias configuration.

Start a temporary consumer with Phoenix/Ecto formatter imports and representative
`plug` and `attr` calls. Run the packaged installer, then format the consumer.
Existing imports and macro formatting must remain valid. Model configuration
must be present and the install notice must remain useful. Repeat installation
and check that user configuration and imports remain intact.

The v3 DSL may need exported formatter rules. This history does not forbid
adding valid rules. If the new installer adds an import, include the export in
the actual package and prove composition with the existing imports. A source
checkout containing an unshipped formatter file is insufficient evidence.

Use catalog 18 and the fresh-consumer package gate. No LLM response is needed;
assert zero provider calls. Baseline evidence:
[installer](../../../lib/mix/tasks/jido_ai.install.ex) and
[installer regression](../../../test/jido_ai/install_task_test.exs).

## HIST-19: CLI calls remain non-interactive

[PR 205](https://github.com/agentjido/jido_ai/pull/205) and the
[maintainer response on PR 122](https://github.com/agentjido/jido_ai/pull/122#issuecomment-4067288457)
settle the contract. The old `mix jido_ai.agent --tui` proposal was not retained.
It is not a missing v3 feature.

Use catalog 18 to run a one-shot prompt and two standard-input lines through
the packaged CLI and real AI operations. Script their responses in the shared
mock. Check documented text/JSON output, exit behavior and request count.
An empty invocation without `--stdin` must fail with the prompt/standard-input
guidance and make no provider call. No case may start an interactive loop.

Do not claim the current task explicitly rejects every unknown option. It
discards the parser's invalid-option list. PR 205 adds invocation validation;
it does not implement general option-error handling.

Baseline evidence: [Mix task](../../../lib/mix/tasks/jido_ai.ex) and
[CLI contract tests](../../../test/jido_ai/cli/adapters/mix_task_contract_test.exs).
CLI error display and trace metadata have later changes with separate audit rows.

## Package checks and simplification rules

| Gate | Required v3 check |
| --- | --- |
| FORMAT | Root formatting and documentation configuration checks pass. No semantic feature needs a separate LLM example for `6ddead0f`. |
| SCHEMA-TYPES | Compile and type-check representative generated schemas with optional/default-nil fields and nested custom type overrides on the selected Zoi version. Check both the oldest supported runtime and the current runtime. |
| INSTALL | Run the installed Mix task in a fresh consumer, including queued compilation/task execution. Pair this with HIST-18. |
| MODEL-TYPES | Type-check public rich model inputs, string labels and call sites using the actual ReqLLM/LLMDB dependency versions. Keep the required PLT applications. |
| CONFIG-ISOLATION | Tests that change global aliases/defaults run serially and restore prior configuration. Ordinary tests retain safe concurrency. The shared mock has per-test scripts and records. |

The dependency bot's missing-label comments concern repository maintenance.
They do not define an Agent feature. Upstream issue numbers in dependency notes
belong to their named upstream repository.

At the first simplification checkpoint, check three things: one model resolver,
one prompt normalization contract after frontend defaults, and one tool adapter
that loads modules before validation. At the package checkpoint, run HIST-18
against packaged files. Keep these cases when fixture operations are replaced
with production operations. Source review alone cannot close their v3 rows.
