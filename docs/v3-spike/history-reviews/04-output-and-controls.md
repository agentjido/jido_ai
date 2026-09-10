# History review 04: structured output, request controls and data boundaries

Reviewed on 2026-09-06 against `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
This pass completes ten more source reviews. The total is 41 of 126.
All v3 port checks remain pending. This pass changes documents only.
No tests ran during this pass.

The review read each complete commit diff, its tests and documentation, the
associated PR discussion, and the relevant user reports. Follow-up changes
were traced to the target source. See the [structured ledger](../history-audit.json).

## Commit dispositions

| Commit | Final requirement to retain | Required cases |
| --- | --- | --- |
| `8685b4f8` / PR 260 | Preflight checks the whole proposed tool round before tool start or execution. A block or interrupt stops the run. | HIST-08: preflight batch, pending preflight |
| `354f97bb` / PR 269 | Object output contracts validate before completion, use bounded repair, retain events/metadata and support request-level raw bypass. | HIST-11: output contract, finalization, raw bypass, output events, stream input |
| `a5a2c21a` / PR 279 | Keep simple internal maps only after a proven input conversion. Retain public data, restore, usage, method, retrieval and package behavior. | HIST-20: data boundary matrix; existing usage, error, restore and package cases |
| `2ca198b5` / PR 291 | Positive request-level iteration limits override the configured value. Omitted/invalid values preserve it. Telemetry test isolation also matters. | HIST-08: request limits; HIST-13: correlated telemetry |
| `b0c46f61` / PR 318 | A tool can perform I/O when the current model turn needs the result. Returned effects and final outbound delivery have separate owners. | HIST-08: tool I/O and returned effects |
| `2d6d0df5` / PR 319 | An imported JSON object schema can have string keys. | HIST-11: imported schema; HIST-20: output config |
| `51d4fb03` / PR 331 | A configured per-attempt timeout reaches actual tool execution, including lookup by tool name and direct module execution. | HIST-08: tool timeout, long tool budget |
| `35377529` / PR 337 | Arrays of Zoi objects receive recursive key/enum conversion before validation. | HIST-11: nested arrays |
| `9da84075` / PR 339 | Configured repair callbacks work through the Agent path. Public `repair/5` overrides remain available, and stored callbacks have portable identities. | HIST-11: configured repair, direct override, callback identity |
| `6543a846` / PR 343 | Every repair attempt transforms its exact model request with current runtime context. Errors stop before the provider call; repair keeps tools disabled. | HIST-10: repair binding, transformed request, transform failure, per-attempt refresh |

## One typed Agent exposes the output requirements

Use a support-ticket Agent in catalog 02. Its result has a list of items,
an atom enum for each category, a summary and a default confidence value.
The model first returns invalid output. The next response supplies a valid
object. Use real JSON decoding and schema validation through the production
operations. The final Agent state changes only after validation succeeds.

The same Agent supplies focused variants. Do not make a new Agent module for
each malformed model answer. The mock controls model responses; it does not
return the validated Agent result on behalf of production code.

| Variant | Required evidence |
| --- | --- |
| `HIST-11/output-contract` | Accept an object-shaped Zoi schema and an imported JSON object schema. Validate plain maps, supported response objects, JSON text and fenced JSON. Apply defaults and enum conversion. Reject non-object schemas, non-object final values and invalid configuration before dependent work. |
| `HIST-11/finalization` | Valid initial output completes with a typed map and no repair call. Invalid output either repairs within the configured bound or fails without a final-answer commit. Test `on_validation_error: :error`, zero retries, success on the last permitted retry and exhaustion. |
| `HIST-11/raw-bypass` | An Agent has a default output contract. One request uses `output: :raw` and returns ordinary text without output repair. A later request uses the original typed contract. A request-specific schema also leaves the Agent default intact. |
| `HIST-11/output-events` | Observe output start, repair, validation or failure before terminal completion/failure. Correlate request/run IDs and attempts. Successful request metadata retains `output`; raw bypass has no stale output metadata. Test the public output telemetry families with enabled observability. |
| `HIST-11/stream-input` | A streamed answer split across chunks validates correctly. Thinking stays separate. A later model turn does not reuse a previous turn's text accumulator. Test a valid final answer after a tool round and a limit stop that reaches output finalization. |
| `HIST-11/imported-schema` | Decode the schema from JSON with string keys, then run the Agent and validate its actual result. Repeat with the atom-keyed schema and compare meaning. Merely constructing `Output` is insufficient. |
| `HIST-11/nested-arrays` | Decode a list of objects from model JSON. Convert only schema-declared keys and enum values, apply defaults, and validate every item. Include nested arrays, an invalid item and an unknown enum. Valid output needs no repair. Invalid output must not become valid through unrestricted atom conversion. |

The baseline defaults to one repair and caps configured retries at three.
It accepts non-negative integer values and compatible numeric strings.
It also accepts `schema` and the older `object_schema` option. Preserve these
public input meanings in compatibility conversion. The new DSL can use one
normalized representation for the result schema and repair bound.

The baseline can end a raw run at `max_iterations` with a completion result
that explains the limit. With a configured output contract, that result still
passes through output finalization. Record the termination reason with the
result. A core Flow step limit is not an exact substitute for this public
reasoning-cycle limit. Make any changed terminal contract explicit in the
migration guide.

Output metadata contains bounded previews and error details. Test redaction
of sensitive map keys and long/Unicode previews. The current binary preview
uses `String.slice` with 500 characters; it does not parse an arbitrary JSON
string to redact keys inside that string. Do not claim full secret removal
from this helper. Apply the chosen observability rules at their actual boundary.

[Issue 334](https://github.com/agentjido/jido_ai/issues/334) explains why nested
arrays need a real Agent example: repeated repair could not fix valid JSON
when validation skipped conversion of each array item. The problem was in
the validator path, not the model answer. [PR 337](https://github.com/agentjido/jido_ai/pull/337)
adds that conversion. [PR 319](https://github.com/agentjido/jido_ai/pull/319)
restores acceptance of string-keyed imported schemas.

Baseline evidence: [Output](../../../lib/jido_ai/output.ex),
[ReAct config](../../../lib/jido_ai/reasoning/react/config.ex),
[runner finalization](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/react/runner.ex),
[request metadata](../../../lib/jido_ai/request.ex),
[output tests](../../../test/jido_ai/output_test.exs), and
[runner tests](../../../test/jido_ai/react/runtime_runner_test.exs).

## HIST-10: each repair request uses current runtime bindings

[PR 343](https://github.com/agentjido/jido_ai/pull/343) comes from a deployment
that obtains Bedrock credentials at runtime. Normal turns received the
credentials through `request_transformer`; output repair used static options
and failed. The fix must apply to the real repair request, including every
retry, rather than a discarded copy of the normal conversation request.

Its PR body and first commit message describe fallback after a transformer
error. The final merged code and tests instead propagate the error and prevent
the provider call. Use that final behavior.

| Variant | Required evidence |
| --- | --- |
| `HIST-10/repair-binding` | Use a transient synthetic credential source. Observe credentials on the normal request and a fresh value on repair. Use the local mock endpoint with the actual provider adapter. No real metadata/credential service is needed. |
| `HIST-10/transformed-request` | The transformer receives the repair prompt, selected model, options and empty tool map. Change messages and model; verify those exact values at the provider. Attempts to reintroduce user tools do not enable their execution during repair. |
| `HIST-10/transform-failure` | Return an error or invalid message shape on repair. Observe output failure and request failure, with no repair HTTP request and no successful completion. Preserve the prior committed domain state. |
| `HIST-10/per-attempt-refresh` | First repair fails; second succeeds. Count one preparation call for each model attempt and verify distinct runtime credential values. Valid initial output makes no repair preparation call. |
| `HIST-10/repair-context` | Repair uses the latest user message, including the supported summary of a content-part query. Current runtime state, request IDs and configured options reach the transformer. It must not use the last assistant entry as the user query. |

The default repair call is non-streaming and uses object generation. It strips
user `tools` and `tool_choice` options again after transformation. A provider
may use a schema tool internally to implement object generation; distinguish
that protocol mechanism from the Agent's business tools. Assert that no
business tool is advertised or executed, instead of banning every provider
field named `tools`.

Implement repair as a bounded Flow over the shared model operation. The same
model controls, accounting and transient binding rules must apply to normal,
fallback and repair calls. The old repair helper returns a validated map; its
existence alone does not prove repair usage is charged to the shared budget.
Record actual usage for each attempt and test a budget stop before another call.

## HIST-11: repair callbacks are public behavior

[Issue 335](https://github.com/agentjido/jido_ai/issues/335) reports that a
configured callback could not reach the runner's four-argument call.
[PR 339](https://github.com/agentjido/jido_ai/pull/339) puts the callback on the
output contract. Its [review finding](https://github.com/agentjido/jido_ai/pull/339#discussion_r3683562192)
also preserves public `Output.repair/5` callers. Internal non-use did not make
that public override disposable.

- `HIST-11/configured-repair`: declare a public callback on the Agent's output
  contract. Produce invalid model text and observe that callback through the
  full Agent path. Its result must pass the same schema validator. A helper-only
  call to `Output.repair/4` does not prove Agent wiring.
- `HIST-11/direct-override`: test the existing fifth-argument `repair_fun`
  override, including three- and four-argument functions. It overrides the
  configured callback for that call. Preserve or explicitly migrate this API.
- `HIST-11/callback-identity`: configured external captures normalize to a
  module/function reference; configured local closures and invalid arities
  are rejected. Callback identity changes the output/config fingerprint.
  Restore with the matching callback succeeds; a changed contract follows the
  documented token compatibility rule.

The baseline configured callback accepts a module/function pair with arity
three or four, or an external capture that can become that pair. It prefers
the four-argument export if both exist. Direct `repair/5` overrides can remain
transient functions. A stored profile or checkpoint must use a trusted registry
reference, not a serialized closure. The existing same-runtime term round-trip
test is useful but does not prove JSON or fresh-runtime portability.

## HIST-08: approval and limits act before execution

[PR 260](https://github.com/agentjido/jido_ai/pull/260) came from Moto. Inspecting
an `ai.llm.response` signal was too late because delegated ReAct work could
already start the tool. Preserve the preflight position in the new Flow.

| Variant | Required evidence |
| --- | --- |
| `HIST-08/preflight-batch` | The model requests two real tools. The first preflight check allows; the second blocks or interrupts. Neither Action starts, no tool-start event appears, and no successful request completion occurs. Repeat with all checks allowed. |
| `HIST-08/pending-preflight` | Restore supported pending tool work and rerun the check before execution. Preserve call IDs, arguments and application context. A callback exception is a controlled failure with no tool execution. Specify controlled handling for malformed callback results as well. |
| `HIST-08/request-limits` | Set an Agent limit, override it with a smaller positive value for one request, then omit the override. Count real model/tool rounds and retain the default on the later request. Test nil, zero, negative and invalid-type inputs at their supported public boundaries. |
| `HIST-08/tool-timeout` | Execute tools through both registered-name and direct-module paths. A positive per-attempt limit reaches the actual core execution layer. A task that exceeds it fails and is cleaned up. An omitted limit keeps the documented default. Repeat with retries to separate attempt time from total time. |
| `HIST-08/long-tool-budget` | Include one excluded-by-default integration case that holds a real tool beyond the old 30-second inner default, within a larger explicit budget. It must complete. Use a monitored barrier and record elapsed time. Run this case at the required acceptance gate. |

The older preflight interrupt becomes a failed run with an interrupt reason.
It does not by itself provide durable pause/approval/resume. Keep that behavior
in the compatibility plan. The desired stronger approval design needs its own
portable pending-operation case and explicit ownership in the new runtime.

At the target, the Agent tool interceptor prepares tool calls before preflight.
The callback receives the resulting operation data. Do not reorder these steps
while moving them into Flow. The later
[tool/composition review](05-tools-and-composition.md) completes the full
tool-interceptor source review and adds callback identity, retry and failure cases.

[PR 291](https://github.com/agentjido/jido_ai/pull/291) fixes a nil override that
could replace the configured iteration limit. The high-level Request helper
only forwards positive integers. Direct instruction validation and lower-level
configuration conversion are separate boundaries; do not promise identical
invalid-input handling without testing them. The commit also filters telemetry
tests by tool-call ID. For `HIST-13/correlated-telemetry`, use unique IDs and
per-test event handlers in parallel examples. Another test must not satisfy
the assertion.

[PR 331](https://github.com/agentjido/jido_ai/pull/331) reports a live tool with
a six-minute budget that died at the hidden 30-second inner default. Its old
test checks the option passed to a replaced `Turn.execute_module` function.
Keep that focused check where useful, and add the real execution case above.
A tool that returns immediately cannot expose the original failure.

Baseline evidence: [runner preflight](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/react/runner.ex),
[request option forwarding](../../../lib/jido_ai/request.ex),
[tool execution](../../../lib/jido_ai/directive/tool_exec.ex),
[runtime tests](../../../test/jido_ai/react/runtime_runner_test.exs),
[request tests](../../../test/jido_ai/request_test.exs),
[strategy limit tests](../../../test/jido_ai/strategy/react_test.exs), and
[timeout tests](../../../test/jido_ai/directive/exec_runtime_test.exs).

## HIST-08: tool I/O and returned effects have different owners

[Issue 243](https://github.com/agentjido/jido_ai/issues/243) asks where I/O belongs.
[PR 318](https://github.com/agentjido/jido_ai/pull/318) gives the accepted rule:
a tool can fetch data when the current model turn needs that result. Runtime
delivery handles an outbound effect after the decision is made.

For `HIST-08/tool-io-effects`, use a real Action that reads a test-owned file
and returns data plus allowed and disallowed effects. The next model request
must see the file result. Effect filtering controls the returned effects;
it does not prevent or reverse the completed file read. A final test-only
delivery directive runs at its documented commit boundary, once. A failed
output validation must not deliver that final notification. Use a local event
sink, with no email or external message.

Port this distinction to ordinary v3 Actions/Flows and typed directives.
Remove the old StateOp representation through explicit state assembly. Keep
the domain behavior and the distinction between tool data and Agent state.
The migration guide must include the concrete I/O decision rule, not only tests.

## HIST-20: simplify input conversion only after proving the boundary

[PR 279](https://github.com/agentjido/jido_ai/pull/279) removes repeated atom/string
key access and makes several small code changes. Some affected maps are external
data. The later schema fix in PR 319 is direct evidence that one removed fallback
was needed. Treat this as a required simplification check across the port.

| Variant | Input boundary and required check |
| --- | --- |
| `HIST-20/output-config` | Test the string-keyed schema separately from the outer output option map. Compare DSL, Builder, direct data and JSON profile input after one conversion of known fields. Conflicting key forms have a defined result. |
| `HIST-20/method-input` | GoT/TRM/Adaptive public request inputs retain prompt, IDs, result data and phase metadata after supported decoding. Test an unknown key beside valid known fields. Do not silently lose the known fields. |
| `HIST-20/retrieval-input` | Upsert decoded retrieval data with ID, text and metadata. Read it back in the correct namespace. An unknown extra key cannot silently cause a new ID or empty text. Apply an explicit accepted/rejected-extra-field rule. |
| `HIST-20/restored-data` | The explicit old-to-new conversion accepts the documented stored-data formats and preserves Agent ID/state. Ordinary current core restore is tested separately. Do not assume a JSON map and an Erlang checkpoint are the same format. |
| `HIST-20/provider-data` | Actual ReqLLM decoding supplies usage, response IDs and tool calls to AI. Cross-check the existing usage and Responses continuation cases. Normalization is verified at the boundary before internal atom-only reads are used. |
| `HIST-20/package-helpers` | A packaged consumer finds bundled skill files through application paths. Invalid tokens still return controlled decode errors. Plugin state projection, independent runtime supervisors, planning text extraction and mock text assembly retain their behavior. |

The target accepts string keys inside imported JSON schemas. Its outer
`Output.new` options currently read atom keys. The original PR 269 accepted
both outer forms; PR 279 removed the outer fallbacks as well. Record this
source-level difference. The desired JSON authoring frontend must convert
approved profile fields before constructing the shared contract. Preserve the
earlier public outer-map form in compatibility conversion or obtain an explicit
migration decision before removing it.

The new GoT/TRM/retrieval helpers in PR 279 call `String.to_existing_atom` for
each key and return the original map if any conversion raises. The next code
then reads atom keys. Source inspection therefore exposes a risk: one unknown
string key can prevent conversion of all known keys. This pass did not run a
dynamic reproduction. The v3 case must prove either correct known-field handling
or an explicit validation error, with no invented atoms or silent data loss.

Later error and usage changes restore broader normalized input handling.
Use their final contract, including the error cases in
[review 03](03-media-and-errors.md). Those later usage commits still need their
own full reviews. Simplification can remove repeated conversions after the
boundary tests pass; a lint result alone is not behavior evidence.

Baseline evidence: [Output options](../../../lib/jido_ai/output.ex),
[retrieval input](../../../lib/jido_ai/retrieval/store.ex),
[GoT input](../../../lib/jido_ai/reasoning/graph_of_thoughts/strategy.ex),
[TRM input](../../../lib/jido_ai/reasoning/trm/strategy.ex),
[Agent restore](../../../lib/jido_ai/agent/definition.ex),
[usage helper](../../../lib/jido_ai/actions/helpers.ex), and
[packaged skill test](../../../test/jido_ai/skill/runtime_contracts_test.exs).

## Refined implementation order

First, keep pure output parsing and schema validation independent of the DSL.
Add one conversion of trusted profile fields before common lowering. Preserve
callback identity in the profile fingerprint and keep transient bindings out.

Then build output repair from the shared model operation, with the same controls,
usage accounting and request preparation. Run preflight over the whole tool
batch before Exec starts any Action. Give Exec the effective attempt limit.

At the authoring simplification pass, rerun input-format, schema and callback
tests. At the live-runtime pass, rerun preflight, timeout, repair-binding and
budget cases. At recovery and package checks, rerun callback identity, old-data
conversion and packaged-resource cases. Each retained feature still needs an
enabled integration test against production v3 code before the port gate closes.

## Partial Planning helper evidence — 2026-09-07

[08_01](../../../examples/08_planning/08_01_planning/README.md) adds actual HTTP cases
for the three Planning Actions. Direct, Exec and live capability calls retain
the full text and parsed result maps. A raw multi-block provider response goes
through the common Turn extractor and keeps token usage. Known string input
keys are normalized before schema defaults, and a caller cannot forge the
supplied-key marker used by the pre-validation callback. Planning defaults also
work when `context.agent` contains a current core Agent struct.

These cases add partial evidence for PR 279's Planning/input helper changes.
They do not prove skill packaging, every legacy input map, restored v2 Agent
conversion, or standalone token recovery. Those required cases remain open.
The full AI acceptance run passes 678 tests. All history statuses remain pending.

## Chat port evidence: 2026-09-07

[Example 16_02](../../../examples/16_capabilities/16_02_chat/README.md) supplies the
new execution evidence. Known nested Zoi keys and enum labels are now validated in the callable GenerateObject path through the shared Output validator. The public result retains decoded forms. Invalid output fails without an added repair request and preserves available usage in error telemetry.

## Failure position evidence: 2026-09-07

[14_10](../../../examples/14_resume/14_10_failure_position/README.md) adds partial
PR 269 evidence for failed repair calls, validation failure, repair after tools
and successful repair. Reasoning position stays separate from model calls.
The repair-transform rejection case extends PR 343; the real configured local
callback failure extends PR 339. These cases run through the native standalone
Agent, common output path and shared MockLLM. Remaining provider, Agent recovery
and root package gates stay open.
