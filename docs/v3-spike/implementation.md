# Jido AI v3 implementation record

## Root package cutover: 2026-09-07

The user changed the immediate order: build the complete package, obtain a
complete root test result, then fix shared failure causes. The root now uses
local v3 dependencies. All 231 production files compile with warnings as
errors. The acceptance project depends on this same full root package. Its latest
complete run passes 1,192/1,196 examples in 159.1 seconds, with four required
ReqLLM numeric-string failures and no exclusions. An earlier run also hit a
core shutdown timing error. It did not repeat, but remains in the dependency
record. All six new terminal-state examples pass with all prior 1,186 passing
cases. A skill regression found in the first run is fixed; nested exception
fields now use Map lookup during retry-hint checks. Integration and pending-DSL tags are included.

The first complete root result was 1,763/2,418 passed, with 655 failures and
one existing exclusion. After the first fixes, the result was 1,814/2,425 passed,
with 611 failures and one exclusion. The CoT/CoD/AoT pass reached 1,867/2,425,
with 558 failures and one exclusion. It transferred 70 cases and resolved 53
failures without changing the count. The StateOp pass reached 1,906/2,388 passed,
with 482 failures and one exclusion. Two StateOp test files now have 39 native
behavior cases in place of 76 repeated constructor/Strategy checks. Their
[case map](state-test-transfer.md) accounts for each old check and the reduced
root count. No additional failing case appeared. A real metadata gap was fixed:
ReAct completion now stores `:final_answer` when no specific reason is present.
Four additional HTTP/SSE examples check that reason through the request,
terminal event and Session view.
The tool input root result was 1,934/2,396 passed, with 462 failures and one exclusion.
The [tool input repair](tool-input-repair.md) fixes 20 existing failures and adds
eight root cases. All 32 original direct tool cases remain. Numeric conversion
now serves direct Turn calls and Session tools. Strict non-tool validation is
unchanged. Four new mocked-LLM examples prove Action and Flow numeric inputs,
stored results and complete-batch validation. Core-caught Action exceptions
again produce a server log without exposing a stacktrace in the public error.
The shared stream callback now forwards complete image parts. Two added examples
check image bytes in live events, typed Signals and stored results. See the
[CoT/CoD](linear-test-transfer.md) and [AoT](aot-test-transfer.md) case maps.
The runner transfer root result was 1,948/2,397 passed, with 449 failures and one exclusion.
The [runner transfer](runner-test-transfer.md) retains all 58 original runner
cases and adds one HTTP credential case. Fourteen retained cases now use the
shared HTTP mock. The full comparison resolves 13 failures with no new failure.
Shared fixes bind standalone tool callbacks, classify transform errors and
continue bounded output repair after provider errors. Eight added integration
cases check native Agent and standalone execution, saved errors and tokens.
Numeric-string usage and AWS credential options remain required failing cases;
the separate HTTP API-key case does not replace either requirement.
The stream usage root result was 1,961/2,409 passed, with 448 failures and one exclusion.
The [stream usage port](stream-usage-port.md) fixes the retained decoded-chunk
fallback case and adds 12 passing boundary tests. Source priority and explicit
zero remain intact. Eight new native/standalone HTTP examples add stronger
provider evidence; four fail inside ReqLLM before AI receives the usage chunk.
The integer zero and cumulative two-call cases pass. No dependency code changed,
no tests were hidden, and no history row was closed.
The provider root result was 1,973/2,412 passed, with 439 failures and one exclusion.
The [provider transfer](provider-test-transfer.md) moves four retained runner
cases to real HTTP. The shared response-context fix also resolves six unchanged
state, checkpoint and heartbeat cases. Three new response-boundary cases, two
mock contracts and four provider-change integration cases pass. The full root
comparison resolves nine failures and has no new failing case.
The incomplete-response root result was 1,974/2,412 passed, with 438 failures and one exclusion.
The [incomplete response port](incomplete-response-port.md) fixes the retained
blank-response failure type and accepts partial images through the existing
Turn result projection. The unchanged root case now passes. All 16 new native
Agent and standalone response examples pass. Five old wrapper-envelope cases
remain failing and were not changed.
The setup root result was 1,998/2,412 passed, with 414 failures and one exclusion.
The [ReAct setup transfer](react-setup-test-transfer.md) replaces 24 private
worker-payload checks with native validation, controls, routes and HTTP cases.
Its complete 78-case map leaves 54 cases required and unported. Shared fixes
accept option maps, defer alias/provider lookup and preserve declared HTTP
options through context and request overrides. Six new Session/Turn HTTP
examples pass. No root case was removed, combined or skipped in this pass.
The lifecycle root result was 2,022/2,412 passed, with 390 failures and one exclusion.
The [ReAct lifecycle transfer](react-lifecycle-test-transfer.md) moves 24 more
retained cases to native APIs. Its full comparison adds no new failing case.
At that checkpoint, all 78 ReAct cases remained: 48 passed and 30 stayed required failures. Three new
real-tool examples prove host state and identity through named native Session,
native Turn and public Agents. The 14-case tool-context group passes. This pass
changes tests, examples and migration records; it does not change production AI
code. Complete checks use the independently updated core `dbb878b6`, whose
constructor/codec fix changed the production tree. Earlier core failures still
need a separate check.
The latest root result is 2,070/2,430 passed, with 360 failures and one exclusion.
The [context transfer](react-context-test-transfer.md) moves 18 more retained
ReAct cases and adds four passing history boundary cases. It fixes owned Thread
identity and local model refs, while keeping private ref metadata out of HTTP.
That comparison adds no failing case. At the context checkpoint, 66/78 ReAct
cases passed and 12 remained required failures. Three new buffered/streamed/public examples
cover tools, input, reconstruction and later history. The 31-case context group
passes. All other provider, dependency, initial-state and release gates remain.
The later [inspection transfer](react-inspection-test-transfer.md) moves two
more cases and adds five passing error-boundary cases. All 78 ReAct cases
remain, with 68 passing and ten required failures. It fixes missing nil results,
phase changes from duplicate completions and loss of typed Action errors.
Two new buffered/streamed examples pass in the 16-case inspection group. The
full root comparison has no added failing case.
The [initial-state transfer](react-initial-state-test-transfer.md) adds
`Agent.from_initial_state/3` for conversation-only startup data. Four retained
ReAct cases now pass through that API, and nine boundary cases cover validation.
Seven new examples prove public/native buffered/streamed input, saved tools and
images, prompt/profile selection and later native reconstruction. The 60-case
focused conversion/context group passes. Full old Agent checkpoint and Plugin
state conversion remain required. At that checkpoint, ReAct passed 72/78 cases.
The [terminal-state transfer](react-terminal-test-transfer.md) moves the final
six retained cases to native Agent checkpoints, standalone signed tokens and
public request/collector APIs. All 78 ReAct cases now pass. Six buffered/SSE
examples check terminal success/error restore, saved usage and tool history,
and a later request. No production file changed in this pass. Exact raw errors
and nested usage have explicit collection-boundary tests; provider decoding
limits and the old wrapper-envelope failures remain open.
Main remaining groups call removed Strategy and Plugin APIs. None of these
failures is counted as feature proof.

The shared HTTP/SSE mock now lives in the root package test helpers. Acceptance
keeps a compatibility entry for the same server. Public scripts bind before
runtime startup and retain real ReqLLM execution. Cases prove concurrent caller
isolation, usage, checkpoint fingerprints and server cleanup. Task-list state
updates use tool-result effects; weather uses request transforms. Native example
checks and request/helper checks pass. The retained Directive and three
reasoning Action group also has 87 passes.

See the [root package checkpoint](root-package-checkpoint.md) for full results,
limits, failure inventory and logs. This section replaces earlier current-status
claims that root Mix files use v2 or source directories remain outside the build.
Earlier sections record prior work. The immutable API inventory and history
source-review fields are unchanged. No history row was closed. The goal is active.


## Persistent tool context: 2026-09-07

[03_02](../../examples/v3/profiles/03_02_tool_context.md) adds 11 integration
cases and ports the old base-context replacement behavior to the existing
Configuration Plugin. Public `tool_context` defaults, the native DSL and source
data use `Profile.tool_context`. Live `set_tool_context/3`, direct
`set_tool_context_direct/3` and `ai.react.set_tool_context` use the same validated
configuration directive. The compatibility view exposes `base_tool_context`.

The public `ask` wrapper previously merged compile-time defaults into every
request. That would overwrite a new live base map and omitted those defaults
for raw Signals. Defaults now bind at the profile admission boundary. A live
change replaces the whole map. Application fields merge in host, base, request
order. Active requests retain their snapshot. Request-only values stay transient.
Tool projection and owned runtime identity still apply.

One shared helper validates static base maps and filters protected request
fields. Base maps cannot contain runtime/skill bindings or live handles. The
manual host binding and automatic skill source remain the ways to supply those
resources. Restore keeps the portable replacement and receives new runtime
bindings. No extra process, global state store, compiler or executor was added.

The refinement checks cover real tool/callback context, HTTP tool results,
separate profiles, native Turn/Session use, Builder, both JSON forms and restore.
Explicit false/nil DSL maps now fail like source maps. Empty maps clear defaults.
The final boundary review found that actual skill keys use `__jido_ai_*__`.
Base validation now checks the canonical reserved-key list in addition to private
runtime fields. Tests use every actual skill key in both atom and string form.
The new route required an explicit trusted Registry atom and updated route-list
expectations. Validation was kept strict; the affected fixtures now declare the
new command. The first four feature checks failed before the port and pass now.

| Check | Result |
| --- | --- |
| Final context integration cases | 11 passed |
| Authoring and dynamic tool checks | 69 passed |
| First wider boundary run | 242/243 passed; old route expectation corrected |
| First full acceptance run | 1,119/1,121 passed; old Registry/route expectations corrected |
| Full acceptance after route/Registry fixes | 1,121 passed in 143.9 seconds |
| Final context/skill boundary checks | 59 passed |
| Full acceptance after reserved-key refinement | 1,121 passed in 144.5 seconds |
| Default acceptance | 17 passed; 1,104 integration cases excluded |
| Forced compile with warnings as errors | Passed; 261 application files |
| Selected format checks | Passed |
| Evidence links, exact references and whitespace | Passed; 1,222 links and 797 references |

Logs use `/tmp/jido-ai-v3-tool-context-*`. The initial command was issued from
the root project and stopped on dependency lock mismatches; it did not run
these cases. All stated v3 test counts come from `examples/v3`. Root Mix files
are unchanged and still use v2. Expected failure-path logs and existing deliberate
type-mismatch warnings remain in test output.

Ten exact references extend PRs 325 and 347. The ledger has 797 references and
66 rows with partial evidence; all 126 statuses remain pending. Baseline and
source-review fields are unchanged, and the immutable API inventory hash was
verified. Core documentation advanced independently from `448c1455` to
`0c4c6568` during this work. Its `lib` tree is
`b34b22ab7bedd936adf5711202425bf3ad9944d2`. The inspected changes affect guides,
module documentation, package description and one schema description. Execution
logic and dependency requirements are unchanged. The acceptance compile and
final tests use this source. Core files were not edited here, and the full
core suite was not rerun.

This resolves the remaining persistent tool-context command in the old parent
Strategy. Standalone skills still need a complete continuation example. The
Runner filters private `jido_ai_` fields before starting its internal Session.
Actual skill bindings use `__jido_ai_*__` keys and pass that filter. Verify those
bindings, fresh ownership and resource access across continuation. Prove actual LoadSkill/LoadResource execution, checkpoint continuation,
current resource authorization and cleanup before retiring the old Strategy.
The 34 files outside the acceptance paths remain a compile-boundary inventory,
not a list of proven dead code. Complete their ports/dispositions, root package,
consumer, minimum-runtime, old Agent conversion, recovery, migration and rollback
checks. The full migration goal stays active.


## Automatic skill authoring: 2026-09-07

[18_02](../../examples/v3/profiles/18_02_skill_authoring.md) adds 21 integration
cases. `Profile.skills` stores one validated source. The public `agent_skills`
option and native `skills` block lower to that source. Source maps, Builder,
Agent JSON and AI-source JSON retain the same behavior. JSON uses the existing
host Registry for code and static value references.

The existing Session child prepares each profile's catalogue at live startup.
No extra child, compiler, executor or model server was added. Static construction
does not call skill manifests, trust callbacks or discovery. Relative paths use
the runtime directory. Selected Specs supply prompt disclosure and loading
context; strict activation reads the current file body. Runtime Specs win over
module Specs, then discovered files; diagnostics report shadowed entries.

Automatic tools include the loading Actions and selected module Actions.
Explicit tool declarations win by public name. Request tools/allowed-tools
still apply after defaults. A declared source owns the reserved catalogue,
provider and policy fields. Module Plugins remain explicit Agent declarations.
Live catalogues are runtime resources; restore rebuilds them from current sources.

The refinement pass found a real defect: live tool registration started from
the declared tools and dropped automatic entries. Configuration now commits the
full effective catalogue before applying register/unregister. Exact prompt
replacement remains an override. Public timeout/retry defaults also reach the
automatic tools. The new cases prove both corrections. A fixture initially
lacked trusted atoms for AI-source JSON; the test now supplies the host Registry
entries instead of weakening decode validation. Invalid module validation was
corrected to retain native metadata without applying file manifest restrictions.

| Check | Result |
| --- | --- |
| Skill runtime and authoring cases before final refinements | 48 passed |
| Final authoring cases, including timeout/retry assertions | 21 passed |
| Dynamic tools and authoring boundary checks | 81 passed |
| Retained root skill/resource tests against v3 | 293 passed |
| First full acceptance run, integration enabled, seed 0 | 1,110 passed in 143.1 seconds |
| Final full acceptance run, integration enabled, seed 0 | 1,110 passed in 140.0 seconds |
| Default acceptance | 17 passed; 1,093 integration cases excluded |
| Forced compile with warnings as errors | Passed; 259 application files |
| Selected format checks in root and acceptance projects | Passed |
| Evidence links, exact references and whitespace | Passed; 1,202 links and 787 references |

Logs use `/tmp/jido-ai-v3-skill-authoring-*`. Test output contains expected
failure-path logs and existing deliberate type-mismatch warnings. Excluded
tests are not counted as passed. The 293 retained tests do not include the
four installed-application tests or the skill CLI suite; those remain package
work. Root `mix.exs` and `mix.lock` are unchanged and still use v2.

Twenty-five exact references extend PRs 286, 316, 325, 353, 354 and 358. The
ledger has 787 references and 66 rows with partial evidence. All 126 statuses
remain pending. Baseline/source-review fields and the API inventory are unchanged.
Core guide work advanced independently from `dd6bc231` to `448c1455` during
the final suite. The diff changes guides, Mix documentation configuration and
one `Jido` module-doc sentence. Runtime code and dependency requirements are
unchanged. The final observed `lib` tree is
`0edc405c893b325be5413a9a98f90d35ec0f8c5d`. A compile check with warnings as
errors also passes on that final checkout. This work did not edit core or
rerun its full suite.

The live `Session.skill_catalog/2` API exposes Specs, index and diagnostics.
Pure config getters do not prepare a catalogue. Automatic skills require a
ReAct Session; stored callbacks use MFA. The manual preparation API retains
runtime function callbacks. These limits are documented in the example.

The next parent Strategy boundary includes `ai.react.set_tool_context`, which
still replaces the persistent base tool context only in the old Strategy.
Other old public action identifiers, `action_spec/1`, `signal_routes/1`,
`snapshot/2`, `init/2`, `cmd/3`, and `list_tools/1` need a final disposition.
Legacy result/delta/runtime-event commands were already no-ops in delegated
mode; native request records and Session events must replace their old routing.
Raw Action fallback must use core command execution. Do not retain the old
worker or Strategy executor to keep these helper names.

The current source-path check leaves 34 production files outside acceptance.
They include CLI/install/quality commands, public test helpers, checkpoint and
request helpers, the old Strategy and directives, and three reasoning Actions.
This is the remaining compile boundary, not a list of proven dead files.

For the tool-context replacement, move static defaults into the profile/runtime
configuration before adding the live override. The public `ask` wrapper currently
merges its compile-time defaults into every request. If that remains, it can
replace a new live base value with the old default. Tests must prove replacement
removes old keys, explicit per-request values win, active requests retain their
admission context, and reserved skill/runtime bindings cannot be replaced.

Standalone skill continuation, installed resources/CLI, complete Agent state
conversion/recovery, parent Strategy retirement, active method-specific views,
root package and consumer checks, the minimum runtime, migration guide and
rollback remain required. The full migration goal stays active.


## Native skill runtime and resources: 2026-09-07

[18_01](../../examples/v3/profiles/18_01_skill_runtime.md) adds 27 integration
cases. Real skill activation, host result callbacks, committed context, core
Thread history, compaction and the next HTTP request now work together. Resource
cases cover fresh provider reads, opaque IDs, filesystem bounds, provider errors
and actual image/PDF attachment bytes. The public Agent and native DSL share
the existing Session/Flow path and the one shared mock.

The existing Skill modules and loading Actions compile against v3. Actions keep
their category/tags/version functions and normalize known string input fields
before schema validation. Two retained tests now use `Jido.Exec` in place of
the removed `Jido.Action.Tool` API. Their input and resource assertions remain.

The refinement pass scopes activation to the live Session owner, profile and
host catalogue/provider/policy binding. Request tool context cannot replace
those reserved host fields. Registry cleanup follows owner exit and explicit
cleanup; model failure preserves activation. Restore keeps saved instructions
and requires fresh activation for resources. Lazy Registry startup no longer
links its lifetime to the first caller. Concurrent registration keeps the first
context, but concurrent provider work is not guaranteed to run only once.

Durable refs require the concrete loading Action and successful original and
approved payloads with the same skill name. Approved instructions become the
stored tool content. Failed callbacks, renamed results, invented success after
failed activation, a different same-name Action and forged user refs cannot
grant runtime skill provenance. Direct host imports keep their documented
accepted-history trust boundary.

| Check | Result |
| --- | --- |
| New skill integration cases after refinement | 27 passed |
| Retained root skill/resource tests against v3 | 293 passed |
| Full acceptance, integration enabled, seed 0 | 1,089 passed in 140.0 seconds |
| Default acceptance | 17 passed; 1,072 integration cases excluded |
| Forced compile with warnings as errors | Passed; 257 files |
| Selected format checks in both projects | Passed |
| Evidence links, exact references and whitespace | Passed; 1,183 links |

The first PDF example failed because the Chat provider rejects PDF attachments.
It now uses the same mock's Responses endpoint and proves transmitted bytes.
The retained suite first exposed the removed core tool API, then string-key
schema admission; the migrated Action hook and direct Exec checks resolve both.
An earlier retained-suite command could not load four tests that require an
installed `:jido_ai` application. Those tests and the skill CLI tests remain
package work; they are absent from the 293 count and have not been marked passed.
Generated ExUnit fixtures under `examples/v3/tmp` are now ignored. They include
intentional invalid/binary Markdown and are not documentation evidence.

Logs use `/tmp/jido-ai-v3-skills-*`. Dependency compilation emits existing
`yamerl` OTP 29 deprecation warnings; forced application compilation passes
with warnings as errors. Tests retain expected failure-path logs and existing
deliberate type-mismatch warnings.

Thirty-one exact references extend PRs 286, 316, 325, 353, 354, 358 and 360.
The ledger has 762 references and 66 rows with partial evidence. All 126 statuses
remain pending. Only acceptance evidence changed in the ledger; immutable
baseline paths and source-review records are unchanged.

Core documentation advanced independently from `c845eed9` to `dd6bc231`.
Both revisions have the same `lib` tree, `24039c4736371ba96e50779a9b6b572fa4c0fe31`.
The later commit changes documentation and Mix documentation configuration.
The final forced compile uses the later checkout. This slice did not change
core or run its full suite. Active core guide work remains untouched.

The current skill example uses an explicit host-prepared catalogue. The legacy
`agent_skills` option, automatic index/tools, declarative source forms, standalone
skill continuation and old parent Strategy retirement remain required. Root
dependency files still use v2. Installed resources, CLI, full Agent conversion,
complete recovery, root package/consumer/minimum-runtime/migration/rollback
checks remain open. The migration goal stays active.


## Native context operations: 2026-09-07

[02_23](../../examples/v3/profiles/02_23_context_operations.md) adds 28 integration
cases for context replace, switch, deferred changes, operation IDs and durable
skill-pair compaction. A pure Plugin owns portable per-profile context journals.
Session remains the only AI runtime owner. A pending context change commits with
the request outcome on success, failure, cancellation or interrupted recovery.
Inspection selects the request profile. Profiles without history gain no context
routes. Standalone checkpoints exclude the private context journal.

The refinement pass found a defect in the old compaction rule: a replacement
could retain a skill call ID while changing its name or arguments. Compaction
now preserves the original call and result as a pair. Actual skill activation,
resource access and runtime provenance remain the next feature port.

| Check | Result |
| --- | --- |
| New context integration cases | 28 passed |
| Authoring, checkpoint and Plugin boundary checks after fixes | 218 passed |
| First full acceptance run | 1,022 passed; 35 failed |
| Final full acceptance, integration enabled, seed 0 | 1,062 passed in 137.0 seconds |
| Default acceptance | 17 passed; 1,045 integration cases excluded |
| Forced compile with warnings as errors | Passed; 239 files |

The first full run found context routes on profiles without history, a private
journal in checkpoint domain data, and an old expected Plugin list. All three
causes were fixed. No existing test was excluded to obtain the passing result.
Logs use `/tmp/jido-ai-v3-context-*`.

Seven exact references extend PRs 325, 332 and 211. The ledger has 731 references
and 60 rows with partial evidence; all 126 statuses remain pending. Immutable
baseline paths and hashes remain unchanged. Root dependencies still use v2.

Core advanced independently to `c845eed9` (`3.0.0-beta.1`). These example results
use that checkout. This slice did not change core or run its full test suite;
earlier core results apply to earlier revisions. Skill/resource behavior, parent
Strategy retirement, complete saved-Agent conversion, root package and consumer
checks, the minimum runtime, migration and rollback gates remain open.

## Native parent request inspection: 2026-09-07

[02_22](../../examples/v3/profiles/02_22_request_inspection.md) adds 14 integration
cases and `Jido.AI.Session.snapshot/2`. The API combines the committed Agent,
revision and selected request with a separate live sample from the matching
Session run. It exposes phase, model label/counts, reasoning position, IDs,
usage, output, stream text/thinking, tool progress/results and raw terminal
failure. Older retained requests remain selectable. Live worker identifiers
stay outside portable Agent state.

Request records now store bounded observed trace prefixes. The first 2,000
events are retained; overflow and state-size elision are explicit. Existing
history commits save active prefixes and metadata. Terminal commits save the
sampled prefix alongside the outcome. Recovery keeps the last committed prefix
and fails interrupted work without replay. A real durable lost-reply example
loads a completed answer and trace in a new Agent Server.

The refinement pass removed terminal stream event construction from the pure
outcome Turn. Cancellation can race with more live events before commit. The
trace now declares its sampled sequence and `scope: :observed_prefix`; the
existing publisher owns canonical terminal events after commit. The race has
an integration test. No new executor, runtime owner, queue or DSL term was added.

| Check | Result |
| --- | --- |
| New inspection integration cases | 14 passed |
| Initial inspection/completion checks after refinement | 20 passed |
| Mock, Session and inspection checks after cleanup fix | 56 passed |
| First full acceptance run | 1,032 of 1,033 passed; mock shutdown race |
| Final full acceptance, integration enabled, seed 0 | 1,034 passed in 131.0 seconds |
| Default acceptance | 17 passed; 1,017 integration cases excluded |
| Forced compile with warnings as errors | Passed; 237 files |
| Selected formatting | Passed |
| Evidence links, exact references and whitespace | Passed |

The first full run exposed an existing shared-mock shutdown race in the
fresh-runtime generated-tool case. An owned acceptor could propagate its
shutdown exit through the mock to the linked caller. A new default mock test
reproduced that failure, then passed after cleanup unlinked owned processes
before it stopped them. It checks caller survival and resource cleanup over
20 independent starts. The original generated-tool test remains unchanged.

Logs use `/tmp/jido-ai-v3-inspection-*`. The final quality results are in
`/tmp/jido-ai-v3-inspection-final-quality.json`. Full/default checks still show
existing deliberate type-mismatch warnings and expected failure-path logs;
forced production compilation passes with warnings as errors.

Eight references extend PRs 223, 233, 296, 332 and 262. The ledger has 724 exact
references and 59 rows with partial evidence; all 126 statuses remain pending.
Immutable baseline paths and hashes are unchanged. Core source and its last
results remain unchanged: 1,268 passes, 11 known research failures and one
approved exclusion. Root dependencies still use v2.

A trace is not a complete durable journal or a Signal delivery receipt. Events
since the last history commit can be lost, and profiles without history save
their trace at completion only. Configuration/history inspection still uses
the current default-profile getters; selecting context for each request profile
belongs in the next context port. The parent Strategy still needs context
replace/switch, deferred operations, operation IDs, trusted skill compaction
and skills/resources before retirement. Method-specific active tree/graph
views, old Agent conversion, complete recovery and root package/consumer/
runtime-floor/migration/rollback gates remain open. The migration goal is active.

## Reasoning position on failure and cancellation: 2026-09-07

[14_10](../../examples/v3/profiles/14_10_failure_position.md) adds 18 integration
cases. Session now keeps `reasoning_iteration` separate from started model calls.
The model step reports its position before controls and request transformation;
checkpoints report their saved position. The standalone State reads this value
on failure, cancellation and parent loss. Output repair adds model calls while
keeping its current reasoning position. Transformer State and the model step
share the position calculation.

Request, model-start and checkpoint events carry the position. Terminal request
metadata carries it on success and failure. Stream chunks keep their existing
fields. Wrong-run position updates cannot change active work. No executor,
checkpoint format or runtime owner was added. Failed tokens still need explicit
State conversion where continuation data or reconciled tool outcomes are absent.

| Check | Result |
| --- | --- |
| New failure-position integration cases | 18 passed |
| Broad focused position, conversion, resume and call-count checks | 83 passed |
| Refined position, worker and call-count checks | 40 passed |
| Position and existing early-tool-activity checks | 31 passed |
| Retained root token tests against v3 | 11 passed |
| Full acceptance, integration enabled, seed 0 | 1,019 passed in 124.7 seconds |
| Default acceptance | 16 passed; 1,003 integration cases excluded |
| Forced compile with warnings as errors | Passed; 235 files |
| Selected formatting after final correction | Passed |
| Evidence links, exact references and whitespace | Passed |

After fixture fixes, all 16 initial cases failed before the port. The first
implementation passed 15; its missing success metadata field was then fixed.
Two refinement cases cover queued input and append after a repair checkpoint.
The first full run passed 1,018 of 1,019 checks. The remaining check required
the small early-tool-activity payload to stay unchanged. Position data was
limited to boundary events, and the original test passed without modification.
The final formatter required one further line-wrap pass; the selected-format
rerun passed. No test or build rerun was needed for that whitespace-only change.
Logs use `/tmp/jido-ai-v3-failure-position-*`; final acceptance logs use
`/tmp/jido-ai-v3-failure-position-final-*`, and the last formatting result is in
`/tmp/jido-ai-v3-failure-position-format-correction-quality.json`.

The ledger now has 716 exact references and 59 rows with partial evidence.
Eight new references extend PRs 269, 343, 339 and 225. All 126 statuses remain
pending; immutable baseline paths and hashes are unchanged. Core checks remain
unchanged at 1,268 passes, 11 known research failures and one approved exclusion.
Root dependencies still use v2. The next work is the parent Agent feature port:
active/terminal inspection, bounded traces, context lanes/operation IDs,
compaction and skills/resources. Old Agent persistence, lost-owner recovery,
provider variants and root package/consumer/runtime-floor/migration/rollback
checks remain required. The migration goal is active.

## Explicit standalone State conversion: 2026-09-07

[14_09](../../examples/v3/profiles/14_09_state_migration.md) adds 22 integration
cases and the public `ReAct.State.migrate/3` function. It converts the released
State-v3 field shape from Jido AI v2 into the existing native checkpoint format.
The caller supplies phase, separate counters, reconciled domain and remaining
time. Old tokens do not contain enough data to derive these values.

The old model checkpoint precedes the pending-tool update. The converter reads
that saved assistant message and restores pending tools without another model
call. Complete tool exchanges retain results without repeating effects. Saved
text and typed answers use the normal output path. Complete terminal history
can accept new input after failure or cancellation. A real failure-after-tools
case uses observed model/tool counts and proves the completed tool is not run
again. Unknown tool outcomes require reconciliation before restart.

The refinement pass shares native tool defaults and checkpoint validation.
Terminal checkpoints now accept failed/cancelled status and zero completed
reasoning calls. There is no new execution loop, storage record or mock.
Malformed history, inconsistent counters/position/reasons, changed catalogs,
missing evidence, live data and repeated native import are rejected. Conversion
leaves the source unchanged. One fixture signs the exact old field map; the test
does not run the full old package or claim automatic Agent persistence conversion.

| Check | Result |
| --- | --- |
| New State conversion integration cases | 22 passed |
| Focused conversion, append, checkpoint and standalone checks | 72 passed |
| Retained root token tests against v3 | 11 passed |
| Full acceptance, integration enabled, seed 0 | 1,001 passed in 123.3 seconds |
| Default acceptance | 16 passed; 985 integration cases excluded |
| Forced compile with warnings as errors | Passed; 234 files |
| Selected formatting | Passed |
| Evidence links, exact references and whitespace | Passed |

The initial 18 cases all failed before the port, then passed. Four refinement
cases added real failure recovery, model/iteration bounds and malformed history.
The full run includes the final system-message assertion. Logs use
`/tmp/jido-ai-v3-state-migration-*`. The ledger has 708 exact references, 59 rows
with partial evidence and 126 pending statuses. The added rich-input conversion
reference extends PR 278. Immutable baseline source/test paths and hashes remain
unchanged. These standalone cases do not close PR 332's old Agent persistence,
sink fields or custom restore requirements.

Automatic native failure counter projection and the full failure-phase matrix
remain next. Parent inspection/context lanes/compaction, skills/resources, old
Agent state and persistence, provider variants and core recovery remain open.
Root dependencies still use v2. Full package, consumer, minimum-runtime,
migration and rollback checks are required before the goal can complete.

## Native query append and State counters: 2026-09-07

[14_08](../../examples/v3/profiles/14_08_query_append.md) adds 15 integration
cases. The standalone API can append input to initial State, a native pause,
or a successful terminal State. It uses the same Agent and Flow. History,
identity, sequence, usage, committed domain state and remaining limits survive.
Saved pending tools finish before the added input reaches the model.

New native checkpoint data uses version 2. It adds next-model and terminal
positions to the existing model/tool positions. Terminal data has no pending
effects and uses committed domain state. Public events do not expose the
internal transfer field. Existing native data version 1 still resumes.
The State iteration now follows reasoning position, with a separate native
model-call count for output repair. No second execution loop was added.

| Check | Result |
| --- | --- |
| New integration cases | 15 passed |
| Focused append, resume, trace and input checks | 58 passed |
| Full acceptance, integration enabled, seed 0 | 979 passed in 122.1 seconds |
| Default acceptance | 16 passed; 963 integration cases excluded |
| Forced compile with warnings as errors | Passed; 232 files |
| Selected formatting | Passed |

The first 14 examples all failed before the port. The refined set adds saved
time limits, private-field removal and system-message checks. The rich PDF
fixture uses buffered Responses; buffered Chat rejects this file type in
ReqLLM. All model calls use the common local mock. Logs use
`/tmp/jido-ai-v3-query-append-*`.

The history ledger has 707 exact references and 59 rows with partial evidence.
The added rich-input check extends PR 278. All 126 history statuses remain
pending. Baseline paths and hashes are unchanged. Old v2 progressed State,
failure/cancellation restart, parent inspection, context lanes/compaction,
skills/resources, provider/recovery variants and all root package gates remain
open. Root dependencies still use v2. See the plan for the next conversion step.

## Standalone caller queues on native Sessions: 2026-09-07

[14_07](../../examples/v3/profiles/14_07_standalone_input.md) adds 13 integration
cases for Config's existing `pending_input_server` option. The native Session
uses the supplied queue directly. Real standalone tools and public steering
reach the same queue. FIFO input, source markers, refs and lower-level size
limits reach the actual provider request and saved history.

The port records whether Session created the queue. Terminal cleanup seals
borrowed queues and stops internally created queues. Standalone stream cleanup
also seals borrowed input after consumer loss or an admission/runtime failure.
The caller keeps its process and undrained data. The existing owner monitor
still controls queue lifetime. An unused lazy stream has no queue side effects.

Queue failure before a model step or at final closure retains
`{:pending_input_server, :unavailable}` and `error_type: :runtime`. Known usage
survives. Final-answer input forces another model call, but cannot bypass the
iteration limit. An empty queue seals before local output repair. A pending-tool
checkpoint can bind a new queue without saving a process handle or repeating
a completed model request.

The refinement uses the existing queue module and common Flow. There is no
new queue process layer, executor or mock. The public return formats remain
separate: ReAct steering returns an Agent, while Session steering returns an
acknowledgement. The first runtime run exposed a fixture that confused those
formats; only the fixture needed correction.

| Check | Result |
| --- | --- |
| New standalone input integration cases | 13 passed |
| Focused steering, checkpoint, worker and retained queue tests | 57 passed |
| Full acceptance, integration enabled, seed 0 | 964 passed in 121.9 seconds |
| Default acceptance | 16 passed; 948 integration cases excluded |
| Forced compile with warnings as errors | Passed; 231 files |
| Selected production, example and ported-test formatting | Passed |
| Evidence links, exact references and whitespace | Passed |

The initial 11 examples passed 1 of 11 before the port and 10 of 11 after it.
After the return-format fixture correction, 55 focused checks passed. Two
refinement cases added iteration limits and closure before repair; the expanded
focused set passed 57. Logs and quality results use
`/tmp/jido-ai-v3-standalone-input-*`.

The history ledger has 706 exact references and 59 rows with partial evidence.
Twelve cases extend PR 225; one shared-control case extends PR 235. All 126
history statuses remain pending. Baseline paths and hashes are unchanged.

Query append still needs its State continuation adapter. Source review found
that old State iteration advances after tools and consumed final-answer input,
while the current adapter projects model-call count. State conversion must
separate those counters and retain next-step position before query append is
enabled. Parent trace/inspection, context lanes and compaction, skills/resources,
provider variants and durable recovery are also open. Root dependencies still
use v2; full package, consumer, minimum-runtime, migration and rollback gates
remain open. Core, Action and Signal are unchanged. No commit, push or
publication was made.

## Native trace controls and repeated tool calls: 2026-09-07

[14_06](../../examples/v3/profiles/14_06_trace_and_cycles.md) adds 13 integration
cases. Native and standalone Agents now expose prepared tool arguments in
`tool_started`, with optional nested sensitive-key redaction. The real tool
receives complete inputs. Captured standalone text and thinking accumulate
from deltas, reset at model start and survive model checkpoint resume.

The shared Flow checks completed tool rounds. Public names and complete model
arguments determine the signature; IDs and order do not. Repeated calls still
execute, then add one warning before the next model call. Tool metadata keeps
the signature for normal completion, a later model failure and checkpoint
resume. Wrong-run observations cannot change it.

The refinement pass made four decisions:

- Keep `capture_thinking?` and `capture_messages?` as accepted legacy no-op
  options. The old Runner did not use them to filter data.
- Use the existing Agent observation map and Session event boundary for
  tool-start redaction. Do not add another capture system.
- Hash complete arguments instead of truncated inspection text. Remove the
  unsupported claim that repeated tools returned equal results.
- Save the warning and signature before the after-tools checkpoint. Rebuild
  completed checkpoint stream fields from the decoded response, without a
  second live accumulator in Session.

The new tests first passed 2 of 12 before the runtime changes. The initial
fixture had used nested Config options, then was corrected to flat public
options before that run. The first runtime run passed 6 of 12. It found that
events used schema-normalized arguments, and warning history used content
parts where the old API used text. The implementation now keeps prepared
arguments and text warning entries. A fixture also checked a nonexistent
standalone `thinking_trace` field; it now checks retained Context thinking.
The 12 cases passed, then one alias case and wrong-run checks were added.

| Check | Result |
| --- | --- |
| New trace and repeated-call integration cases | 13 passed |
| Focused checkpoint, worker, response and tool checks | 82 passed |
| Full acceptance, integration enabled, seed 0 | 951 passed in 121.6 seconds |
| Default acceptance | 16 passed; 935 integration cases excluded |
| Forced compile with warnings as errors | Passed; 230 files |
| Selected production, example and ported-test formatting | Passed |
| Evidence links, exact references and whitespace | Passed |

Logs and quality results use `/tmp/jido-ai-v3-trace-cycles-*`. The history ledger
has 693 exact test references and 59 rows with partial evidence. Three cases
extend PR 300's sanitizer evidence. The repeated-call feature predates v2.0.0
(PR 188), so it does not add a post-release audit row. All 126 history statuses
remain pending. Immutable baseline paths and hashes are unchanged.

Tool-start redaction does not filter full model-completion calls or checkpoint
execution data. Parent trace retention and inspection, context lanes and
compaction, query append, old state conversion, skills/resources, provider
variants and durable recovery remain open. Root dependencies still use v2;
full package, consumer, minimum-runtime, migration and rollback gates are open.
Core, Action and Signal are unchanged, including the 11 known core research
failures. No commit, push or publication was made.

## Native worker lifetime and error detail: 2026-09-07

[14_05](../../examples/v3/profiles/14_05_worker_lifecycle.md) adds nine integration
cases through the public ReAct and CoT Agents. A killed request task stops held
work, commits one failure and permits a later request. Old task results, exit
messages and runtime events cannot finish that later request. Session-owner
loss interrupts stored work and creates fresh resources. Parent shutdown stops
the complete owned process tree. Wrong-run observations cannot change a request.

ReAct uses a real held tool with the current tenant context. CoT uses a real
held model connection. Another ReAct case carries an uploaded file ID through
the public Agent into the actual model request. All model responses use the
shared MockLLM implementation.

Refinement found that native task failure discarded its process exit reason.
Session now keeps `error_type: :worker_task` and a portable `worker_exit_reason`
in metadata, while preserving the public `:worker_crash` result and known usage.
The focused tests failed on the missing detail before this change.

The four internal ReAct/CoT Worker Agent and Worker Strategy modules are removed.
Native Session tasks and core Exec replace their separate execution loops.
The old callback-only ReAct worker test is replaced by these real HTTP and
lifetime examples. The old parent ReAct Strategy and other root callback tests
still need their remaining feature and API mappings; they are not compiled in
the acceptance project.

| Check | Result |
| --- | --- |
| New public worker lifetime and file cases | 9 passed |
| Focused Session, activity, delivery and linear-method checks | 84 passed |
| Full acceptance, integration enabled, seed 0 | 938 passed in 121.0 seconds |
| Default acceptance | 16 passed; 922 integration cases excluded |
| Forced compile with warnings as errors | Passed; 228 files |
| Selected production, example and ported-test formatting | Passed |
| Evidence links, exact references and whitespace | Passed |

The first fixture used a function call in an authoring option that requires a
literal, then gave CoT an unsupported tool declaration. It now uses a literal
chat model and holds each method's supported work. Nine baseline lifetime
cases then passed. The exit-reason refinement passed 7 of 9 before the metadata
fix, then the complete focused set passed. Logs and quality results use
`/tmp/jido-ai-v3-worker-lifecycle-*`.

The history ledger has 690 exact references and 59 rows with partial evidence.
PR 304 has a real uploaded-file request case; PR 231 has ReAct and CoT task
failure cases. All 126 history statuses remain pending. Historical links for
removed sources point to the pinned baseline. Baseline JSON paths and hashes
are unchanged.

Session-owner recovery does not restore its lost volatile stream sink. No
terminal-delivery claim is made for that sink. Parent Strategy trace retention,
active inspection, context lanes and compaction, skills/resources, old-state
conversion and remaining standalone behavior stay open. Root dependencies still
select v2. Full package, consumer, minimum-runtime, migration and rollback gates
remain open. Core, Action and Signal revisions are unchanged; the 11 known core
research failures remain visible. No commit, push or publication was made.

## Standalone Actions through Exec and Flow: 2026-09-07

[14_04](../../examples/v3/profiles/14_04_standalone_actions.md) adds 13 integration
cases for the actual Start, Continue, Collect and Cancel Actions. They now
compile from `operations/react_actions`. A portable Flow connects Start and
Collect; an Agent route executes that Flow and commits aggregate data. Live
streams stay in execution. Real tools, streamed model replies and multimodal
input use the same MockLLM server as the other examples.

Start delegates to `ReAct.start/3` instead of duplicating its envelope and IDs.
Collect now uses the shared runner option builder, which preserves runtime
context and Task supervisor on token resume. Start, Continue and Collect accept
explicit native limits. The helper no longer depends on the removed core
AgentServer State struct. Transient nested legacy maps still resolve a
supervisor; portable Agent state still rejects live resources.

The old Action category, tags and version fields are explicit public functions.
Known string keys use the existing schema input normalizer. Refinement proves
that a reduced tool bound stops a saved two-tool batch and that Exec cancellation
stops its held tool, private Agent and supervised stream owner.

| Check | Result |
| --- | --- |
| New standalone Action integration cases | 13 passed |
| Focused integration and retained root helper checks | 28 passed |
| Retained root wrapper tests, separate run | 7 passed |
| Full acceptance, integration enabled, seed 0 | 929 passed in 120.2 seconds |
| Default acceptance | 16 passed; 913 integration cases excluded |
| Forced compile with warnings as errors | Passed; 227 files |
| Selected production, example and ported-test formatting | Passed |
| Evidence links, exact references and whitespace | Passed |

The first example could not compile because the Actions were not in the v3
build. Moving them exposed unsupported v2 metadata options. The first running
cases passed 6 of 10; fixtures had retained a query during checkpoint resume and
passed an unwrapped Agent constructor result. After those corrections, one
assertion expected the wrong native limit error. Refinement passed 11 of 13;
string-key input needed normalization, and the held-tool fixture expected the
wrong message name. The final focused run passed all 28 checks.

The retained wrapper tests use Mimic and are counted separately from the live
integration proof. The isolated Mix project had pruned the Erlang `tools` code
path. The test harness loaded the installed tools, Mimic and Ham paths, then all
seven tests passed. No acceptance dependency or production mock was added.
Logs, harness and quality results use `/tmp/jido-ai-v3-standalone-actions-*`.

The history ledger now has 687 exact references and 58 rows with partial
evidence. A real multimodal Start request is linked to PR 278. All 126 history
statuses remain pending. Immutable baseline JSON paths and hashes are unchanged.
The separate old worker branch from PR 304 still needs its v3 mapping.

Complete query append, old-state conversion, Runner flags and cycles, provider
forms, workers and skills/resources remain required. Root Mix files still
select v2. Root package, consumer, minimum-runtime, migration and rollback gates
remain open. Core source did not change; the 11 known research failures remain
visible. No commit, push or publication was made.

## Native model and tool checkpoint resume: 2026-09-07

[14_03](../../examples/v3/profiles/14_03_checkpoint_resume.md) adds 17 integration
cases for the public ReAct API. The shared Flow now pauses after a model
response or a complete tool round. Session emits a signed checkpoint and waits
for the next stream pull. Stopping at that event cancels the private Agent
before the next operation starts. Resume uses a fresh Agent and the existing
decision or model step. No second executor or mock model was added.

Checkpoints retain conversation, completed history, pending tools, proposed
domain state, directives, usage, counts, output repair state, identity, sequence
and remaining execution time. Provider credentials and transport options are
supplied again. Code and contract checks reject changed tools; current tool
permission and native limits apply again. A new operating-system VM resumes
completed tool data and confirms that the tool does not run again.

Refinement removed provider callback handles from saved response Context and
made pending-call duration accept nil. Token signing errors now return to the
Flow instead of crashing the Session owner. A resumed repair response exposed
missing validation input; it is now saved and checked. Runner no longer decodes
its own emitted tokens. Token expiry prevents later continuation and does not
stop execution that is already active. Saved execution time excludes offline
storage time. Core Exec values are never serialized.

| Check | Result |
| --- | --- |
| New checkpoint integration cases | 17 passed |
| Focused standalone and retained root Token/PendingToolCall checks | 60 passed |
| Full acceptance, integration enabled, seed 0 | 916 passed in 119.1 seconds |
| Default acceptance | 16 passed; 900 integration cases excluded |
| Forced compile with warnings as errors | Passed; 221 files |
| Selected production, example and ported-test formatting | Passed |
| Evidence links, exact references and whitespace | Passed |
| Immutable API source hashes | All 175 match the pinned Git source |

The first run passed 0 of 7 before checkpoint support. Later failures exposed
the callback, duration and output-repair faults above. The fresh-VM fixture
loads known application modules before safe token decoding. Logs and quality
results use `/tmp/jido-ai-v3-checkpoint-*`.

The history ledger has 686 exact references and 57 rows with partial evidence.
New references cover PR 260 pending-tool preflight, PR 314 event identity and
PR 339 configured repair. All 126 history statuses remain pending. The new-VM
token test is not attributed to the separate Agent persistence feature.

Tokens remain caller-owned and replayable. Partial tool batches, durable
single-consumer records, old progressed-state conversion, query append and
external queue binding remain required. Complete trace/redaction, cycle,
provider/media, standalone Action, worker and skill/resource ports remain open.
Root Mix files still select v2. Root package, consumer, minimum-runtime,
migration and rollback gates remain open. Core source did not change; its 11
known research failures remain at the package gate. No commit or push was made.

## Public standalone Agent and Session runtime: 2026-09-07

[14_02](../../examples/v3/profiles/14_02_standalone_runtime.md) adds 18 integration
cases through the actual public ReAct module. The old Runner model/tool loop
is removed. A lazy stream adapter now owns a private v3 Agent and submits one
request to its Session. All model and tool work uses the common Flow and Exec.
The public module and Runner now compile in the acceptance project.

The examples prove real aliased tools, typed repair, state effects, streamed
deltas, usage, custom request/run identity, iteration and tool limits, terminal
tokens, initial-token execution and consumer ownership. Terminal continuation
does no model replay. Successful completion, consumer halt and consumer death
stop owned work. Normal loss of the Agent terminates the stream with an error.

Refinement found and fixed lost failure usage, lost iteration-limit meaning in
terminal tokens, a stream wait after normal Agent shutdown and empty run IDs.
State now carries an optional termination reason. Older tokens without that
field still decode. Saved sequence includes the checkpoint event. Session
admission stores an optional validated run ID instead of rewriting event IDs.

The lowerer also stopped building provider tools that it immediately discarded.
The native ToolCatalog now supplies the only provider tool definitions for this
path. An Action with no description uses that catalog's fallback. A separate
direct ToolAdapter optional-description check remains required.

| Check | Result |
| --- | --- |
| New standalone runtime integration cases | 18 passed |
| Focused runtime, authoring and retained root Token checks | 41 passed |
| Full acceptance, integration enabled, seed 0 | 899 passed in 114.6 seconds |
| Default acceptance | 16 passed; 883 integration cases excluded |
| Forced compile with warnings as errors | Passed; 219 files |
| Selected production, example and ported-test formatting | Passed |
| Evidence links, exact test references and whitespace | Passed |

The initial runtime example run passed 0 of 12 because the public module was
not compiled in the v3 project. The first adapter run passed 10 of 12. One
fixture used the wrong effect-policy shape; the other exposed the discarded
tool conversion. Refinement then passed 14 of 18 before the four fixes above.
Logs and quality results use `/tmp/jido-ai-v3-standalone-runtime-*`.

The history ledger has 683 exact references and 57 rows with partial evidence.
All 126 history statuses remain pending. Historical source links use the pinned
baseline; current API links use the moved source. Baseline JSON paths and hashes
are unchanged. Root Mix files still select v2. Core source did not change, so
its prior 11 known research failures remain visible at the package gate.

This is a partial standalone port. No intermediate model/tool checkpoints are
emitted yet. Progressed state, query append on resume and external queue binding
are refused before provider work. Pending/completed tool continuation, replay
control, trace/redaction/cycle/provider mappings, standalone Actions, workers,
skills/resources, old-state conversion and durable recovery remain required.
The profile records finite native default limits and explicit overrides.
Dependency cutover, full package/consumer and minimum-runtime checks, migration
instructions and rollback remain open. The migration goal is active. No commit,
push or publication was made.

## Standalone authoring and token data: 2026-09-07

[14_01](../../examples/v3/profiles/14_01_standalone_authoring.md) adds twelve
integration cases. The internal Config conversion uses the existing AI Profile,
ToolCatalog and Agent lowerer. Real v3 work proves aliased tools, generation
options, typed repair, state effects, model deltas and cancellation. Runtime
credentials and transport callbacks stay outside the portable definition.
Two public aliases for one Action now retain their distinct provider names.

The retained Token and Event modules now compile in the acceptance project.
Token issue and decode reject live state. Decode also rejects disagreement
between the outer identity and saved State. Valid signed tokens retain their
format and work in another process. This does not prove fresh-runtime recovery.

Core Exec values are live execution data and cannot be saved in tokens. The
public standalone Runner still needs replacement. Its adapter must rebuild
execution from AI state at tested model and tool boundaries. Explicit native
timeout and total tool-call limits are required by the new internal conversion;
the public Runner limit policy is still open.

| Check | Result |
| --- | --- |
| New standalone integration cases | 12 passed |
| Focused authoring, tokens, output and transformation checks | 58 passed |
| Full acceptance, integration enabled, seed 0 | 881 passed in 113.9 seconds |
| Default acceptance | 16 passed; 865 integration cases excluded |
| Forced compile with warnings as errors | Passed; 216 files |
| Selected production, example and ported-test formatting | Passed |

Logs use `/tmp/jido-ai-v3-standalone-authoring-*`. The profile records the
initial fixture faults and their corrections. One fixture lost its mock URL
and sent a synthetic request with a dummy key to the provider, which returned
401. The fixture now merges local mock options and checks the loopback host.

The history ledger has 676 exact references and 57 rows with partial evidence.
All 126 history statuses remain pending. The root Mix files still select v2.
Core source did not change. The full runtime, dependency, package, consumer,
minimum-runtime, state migration and rollback checks remain open. The migration
goal is active. No commit, push or publication was made.

## Public context and history data: 2026-09-07

[02_21](../../examples/v3/profiles/02_21_context_views.md) adds nine integration
cases. The public context view now retains stored timestamps and thinking.
A later HTTP model request receives the saved thinking, tool IDs and content.
New assistant and tool history entries receive message references for their
request. Existing references remain intact across later requests.

History replacement validates portable input and ReqLLM messages before the
core Agent update. Invalid roles, missing tool IDs, invalid tool calls, live
values and non-map entries cannot commit. A neutral Agent definition returns
an absent context instead of raising on its uninitialized state.

The active-history case runs an ordinary host Action while the model call is
held. The active call keeps its admitted history; completion appends to the
new committed history; the next request uses the updated history. Portable
v3 reconstruction retains entries and fails interrupted work without replay.
This is an in-memory state test, not offline v2 conversion or durable recovery.

The first six cases exposed reset timestamps, lost thinking, a neutral-state
crash and invalid-role acceptance. The first fixture also used the provider's
catalog wire default; it was corrected to the existing mock's explicit chat
model. After that correction, one of six cases passed before the production
fix. All six then passed. Real tool refs, string-keyed entries and malformed
thinking added three more cases.

The simplification uses the existing Context entry conversion for both message
import and Context coercion. It removes a duplicate converter. Invalid explicit
thinking values cannot break valid visible content. The change adds no DSL term,
generated history route, process, executor or model mock.

| Check | Result |
| --- | --- |
| New context integration cases | 9 passed |
| Focused request/history/configuration and root refs run | 51 passed |
| Refined context run, including 70 retained root Context cases | 79 passed |
| Full acceptance, integration enabled, seed 0 | 869 passed in 113.6 seconds |
| Default acceptance | 16 passed; 853 integration cases excluded |
| Forced compile with warnings as errors | Passed; 212 files |
| Selected production, example and ported-test formatting | Passed |
| Evidence links, exact test references and whitespace | Passed |

Quality logs and results use `/tmp/jido-ai-v3-context-*`. The ledger now has
673 exact test references and 57 rows with partial evidence. All 126 history
statuses remain pending. Immutable baseline paths and hashes are unchanged.
Root Mix files still select v2. No core source changed; its prior 11 known
research failures remain visible in the package acceptance plan.

The migration map now states the context behavior change directly. The old
helper updated active private `run_context`. The v3 helper changes committed
domain history; use Session steering/injection for active input. Remaining
configuration/option views, standalone execution and workers, skills/resources,
old-state conversion, durable recovery, root dependency/package, consumer,
minimum-runtime, migration and rollback checks remain open. The full migration
goal is active. No commit, push or publication was made.

## Dynamic tools, prompts and the public facade: 2026-09-07

[03_01](../../examples/v3/profiles/03_01_dynamic_catalog.md) adds 11 integration
cases. The existing AI Runtime Plugin now owns portable `jido_ai_config`
overrides for tools and instructions. It combines them with the static
profile before request admission. Core directives validate and commit live
changes. Direct helpers validate complete Agent values without Server calls.
Ordinary Actions must use configuration directives for the protected key.

The public `Jido.AI` module moved from `lib/jido_ai.ex` to
`lib/jido_ai/shared/facade.ex`, so the actual facade now compiles with the
v3 acceptance project. Its generation delegates stay shared with Models.
Tool/prompt APIs no longer use Strategy state or the old Server-state call.
Configuration and history getters provide the documented effective-profile
and committed-history views. The active private worker buffer and full old
config structure still need explicit consumer/state migration; these views
do not claim to reproduce those internal structures.

Real work proves live/direct registration, removal and prompt changes, an
ordinary Action using the direct API, protected-state rejection, native profile
isolation, retained legacy configuration Signals, source-format equality,
portable reconstruction and public text/object/stream generation. A held tool
finishes with its original target and prompt after a configuration change;
the next request uses the replacement. Completion retains the newer config.

The first getter check found that ReAct has no mandatory `reasoning.options`
field; the compatibility view now handles it. Three foundation assertions
needed the new configuration routes and trusted codec identifiers. The
refinement removed an unnecessary direct Agent transition from the live
Action; the Plugin applies the intent at the core commit boundary.

A later alias check exposed a duplicate target: registering a module already
present under a native alias added its canonical name. The check failed with
both names present. Registration now finds an existing target first and keeps
its declared name and settings. Conflicting different targets still fail.
The original Action schema and one shared catalog remain authoritative.

| Check | Result |
| --- | --- |
| New dynamic/facade integration cases | 11 passed |
| Focused authoring, steering, completion and configuration run | 62 passed |
| Final full acceptance, integration enabled, seed 0 | 860 passed in 113.2 seconds |
| Default acceptance | 16 passed; 844 integration cases excluded |
| Forced compile with warnings as errors | Passed; 211 files |
| Selected production, example and ported-test formatting | Passed |
| Evidence links, exact test references and whitespace | Passed |

The first full run also passed 860 tests. Its format check found one call
layout after forced compilation; this was formatted before the final checks.
The alias refinement then passed its focused check and all four final quality
checks. Final logs use `/tmp/jido-ai-v3-dynamic-final-*`.

The history ledger now has 664 references and 54 rows with partial evidence;
all 126 statuses remain pending. The immutable API inventory and history
baseline paths/hashes remain unchanged. Historical facade links now point at
the pinned baseline; current links point at the moved production source.
Root Mix files still select v2. Core source did not change, so the prior core
results remain applicable, including its 11 known research failures.

Next: complete remaining public configuration/context and option mappings,
then standalone/worker and skill/resource APIs, old state conversion and
durable recovery. Root dependency cutover, full package and consumer tests,
the supported runtime floor, migration instructions and rollback remain open.
The full migration goal is active. No commit, push or publication was made.

## Raw reasoning tool and atom schemas: 2026-09-07

[09_16](../../examples/v3/profiles/09_16_reasoning_tool.md) adds ten integration
cases for direct model use of `Jido.AI.Actions.Reasoning.RunStrategy`. The
native DSL, public Agent macro, data, Builder and trusted source JSON now
support the raw Action. All seven methods retain their result envelopes.
Nested calls use the outer Quota scope. Cancellation stops the private Agent
and held provider, and a later outer request succeeds. An inner provider
failure becomes the canonical tool error sent to the outer model.

The initial export and three initial tests failed on the `Zoi.atom` request
policy. The fix keeps that direct Action schema. For provider JSON only,
the ToolAdapter uses Zoi's existing traversal to represent atom nodes as
strings, with their metadata. The shared input normalizer resolves strings
only to existing atoms. Unknown names fail Action validation without atom
creation. Nested atom fields, defaults, open data and explicit strict export
have live provider evidence. Finite enums keep their existing label map.

The refinement adds no DSL term, schema enum restriction, public execution
wrapper, external protocol implementation or second model server. It uses
one schema exporter and normalizer. The expanded tests corrected three
fixture assumptions: Session tool metadata uses `result`, source JSON needs
the normal route atom in its trusted registry, and a ToolAdapter fixture
must supply the required description. No production contract changed for
those assertions.

| Check | Result |
| --- | --- |
| New integration cases | 10 passed |
| Focused tools, callable reasoning, Quota, Chat and public ToolAdapter tests | 142 passed |
| Full acceptance, integration enabled, seed 0 | 849 passed in 105.3 seconds |
| Default acceptance | 16 passed; 833 integration cases excluded |
| Forced compile with warnings as errors | Passed; 208 files |
| Selected production, examples and ported-test formatting | Passed |
| Evidence links, exact test references and whitespace | Passed |

Logs use `/tmp/jido-ai-v3-reasoning-tool-*`. All four quality-driver checks
passed. The ledger now has 654 exact references and 53 rows with partial
evidence; all 126 statuses remain pending. Root dependency files and immutable
API/history baseline paths are unchanged. No core source changed, so its
previous full and quality results still apply.

Next: replace dynamic tool and prompt access through v2 Strategy state with
validated v3 state and Action contracts. Complete the remaining facade,
standalone/worker, skill/resource and state-conversion/recovery work. Root
dependency cutover, full package, consumer, minimum-runtime, migration and
rollback checks remain required. The full migration goal remains active.

## Call counts and Adaptive prompts: 2026-09-07

Examples [02_20](../../examples/v3/profiles/02_20_call_counts.md) and
[09_15](../../examples/v3/profiles/09_15_prompt_policy.md) add 21 integration
cases through the production runtime and the shared mock model server.

Session metadata now retains the number of started model operations after
failure and cancellation. It uses the existing canonical event sequence and
keeps a known zero before model work. HTTP retries and Quota charges remain
separate. Completed usage remains intact. Owner recovery retains committed
metadata and does not invent a zero for an uncommitted counter.

Adaptive now resolves the shared ReAct default after method selection. Public
empty prompt options use their default in both macros and direct adapters.
Native empty or custom instructions keep their existing meaning. DSL, data,
Builder and trusted source JSON agree, as do direct Flow and ordinary Turn
execution. The declared profile stays intact. Typed output retains its own
instructions beside the selected default.

The first cases exposed missing failed-call counts and an absent selected
ReAct prompt. The refinement reused the existing event count, moved duplicate
prompt text to one source, and removed duplicate public prompt normalization.
The added direct-option example then found the remaining empty-string case;
the common adapter now resolves it. No new DSL term, model server or execution
owner was added.

The public iteration-limit test initially expected failure, but the retained
API returns its documented limit result. The final example exercises the
native shared model-call bound instead. The owner-loss case explicitly expects
an unknown uncommitted count. These distinctions preserve the actual contracts.

| Check | Result |
| --- | --- |
| New integration cases | 21 passed |
| Request and Adaptive regression run | 412 passed |
| Full acceptance, integration enabled, seed 0 | 839 passed in 105.2 seconds |
| Default acceptance | 16 passed; 823 integration cases excluded |
| Forced compile with warnings as errors | Passed; 207 files |
| Selected production, example and ported-test formatting | Passed |
| Evidence links, exact test references and whitespace | Passed |

The focused regression command included two incorrect directory names for
Quota and capability tests. Those directories contributed no tests to that
412-case result. Both actual directories were included in the successful full
suite. Logs use `/tmp/jido-ai-v3-counts-prompts-*`; all four quality-driver
checks passed.

The ledger has 649 exact references across 53 rows with partial evidence.
All 126 statuses remain pending. Immutable API/history baseline paths and
root Mix files are unchanged. Core source did not change. Its prior result
remains 1,268 passing tests, the same 11 known research failures, one approved
exclusion and 93.9% coverage, with required core quality checks passed.

The next work includes raw RunStrategy tool-schema export, dynamic catalogs
and prompts, remaining facade/worker/skill/resource APIs, old state conversion
and recovery. Root dependency cutover, full package, fresh consumer, supported
runtime floor, migration and rollback gates remain open. This is acceptance
project progress. The full migration goal remains active.

## Request admission and options progress: 2026-09-07

Examples [02_18](../../examples/v3/profiles/02_18_admission.md) and
[02_19](../../examples/v3/profiles/02_19_model_options.md) add 19 integration
cases. Rejected requests use the canonical method from the declared route.
They retain raw errors and correlation; duplicate IDs keep the original
stream open. Unknown bindings report `unknown`. The read uses the core Agent
API and replaces the previous Session Plugin-state read.

Public `model` overrides now enter the existing runtime profile binding.
ModelRouting respects that choice. Later requests retain the declared model.
Request model/options/callbacks remain outside portable Signal and Agent data.
The Session and transformer paths share the selected-model option normalizer.
Known string option names work. Invalid outer option containers fail admission
instead of disappearing. Existing Config merge functions keep their behavior.

The common mock now supports buffered Responses text, function calls and
objects, including a forced structured-output function. The tests inspect
actual HTTP and SSE requests, execute a real Action between Responses calls,
validate object output, and observe headers, model labels and usage. Responses
streaming is still explicitly unsupported by the mock. WebSocket work remains.

The first focused run passed 99 checks. The first full run passed 816 of 818.
Its two failures compared snapshots during independent observation commits.
Waiting for the publication receipt was insufficient: it confirms publication,
not later delivery back to the same Agent. The refinement removes that wait.
Tests compare all domain data and request records; only the observation Audit
counter and core revision are outside the rejected-command assertion. The new
Agent without Audit is compared in full. No production behavior was changed to
satisfy the timing assumption.

Final verification:

| Check | Result |
| --- | --- |
| Full acceptance suite, integration enabled, seed 0 | 818 passed in 102.6 seconds |
| Default acceptance suite | 16 passed; 802 integration tests excluded |
| Focused request/routing/Config checks | 99 passed; 45 affected request cases passed again after the assertion refinement |
| Forced acceptance compile with warnings as errors | 205 files compiled successfully |
| Selected-source and example formatting | Passed |
| Evidence links, exact test references and whitespace | Passed |
| Root dependency files | Unchanged; still v2 |

The successful forced compile used the final production source. Only test
assertions and documents changed after that build. Core source did not change
in this slice, so its earlier full checks were not repeated. This is acceptance
project evidence, not a successful build of the full root package.

The ledger now has 630 exact references and 53 rows with partial evidence.
All 126 statuses remain pending. Failed-call metadata, Adaptive prompt defaults,
all remaining API/skill/resource/runtime ports, state conversion, root dependency,
consumer, runtime-floor, migration and rollback checks remain required.

The user authorized the migration on 2026-09-06 with “start the migration”.
Work runs on `jido_ai/v3-spike`, based on `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
The full migration goal is active. This record is a progress checkpoint, not a
package release result.

## First production slice

- Added the generic `Jido.Agent.Extension` contract in local core at
  `b48e089c6660ee836c4bd8e06540e692e3e9a868`. Core forwards Spark extensions,
  processes foreign entities in declared order, checks callback results, and
  validates generated helpers against the lowered target. Normal Agent and
  Plugin validation still applies.
- Added `Jido.AI.Profile`, `Jido.AI.DSL`, and `Jido.AI.Authoring`. One profile
  normalizer serves the DSL, direct source attributes and source-profile JSON.
  The lowerer produces ordinary Agent definitions and core Flow targets.
  The core Builder can consume those lowered attributes.
- Added source-profile JSON through the core tagged-data format and a trusted
  Registry. Tests assign explicit host IDs to schemas, model records, atoms,
  profiles and generated Flow artifacts. They execute the restored definition.
- Added a core Plugin that binds static profiles into command context. It owns
  no Agent state. Provider options enter through trusted caller context under
  `ai: %{profile_id => %{options: keyword()}}`. Signal data cannot replace the
  profile, model role, tool catalog or controls.
- Added shared model requests and bounded ReAct Flows. Core Dispatch selects
  the next Flow. Core Map executes real Action and Flow tools. Full-batch
  validation and operation controls run before the first tool. Tool batches
  enforce the profile concurrency bound, subject to the core execution limit.
- Added input, model, operation and output controls; iteration, model, tool and
  elapsed-time limits; typed output with bounded repair; complete candidate
  assembly; and cancellation tests with process monitors. Rejection preserves
  committed Agent state. Completed external tool work remains an external effect.

These are production files under `lib/jido_ai/authoring` and
`lib/jido_ai/operations`. The temporary example project compiles those exact
files. It does not contain a copy of the AI runtime.

## Source moves and first simplification pass

Six existing helpers moved into `lib/jido_ai/shared`: ModelAliases, Output,
Error, Error.Sanitize, Observe.Sanitize and Usage. Their module names remain
unchanged. This lets the acceptance project compile the shared code against v3
before the full root dependency change. The root still compiles all of `lib`.

Output now calls the pure sanitizer directly. A new regression test found that
the sanitizer tried to enumerate provider structs; it now converts structs to
maps before redaction. The existing output key/enum conversion moved into
`Jido.AI.SchemaInput`, which also prepares model tool arguments. Profile source
normalization is shared by the lowerer and source Codec. The first foundation
model example now uses the production generation operation.

The public model-helper bodies in `Jido.AI` now delegate to the shared
`Jido.AI.Models` implementation. Alias resolution, labels, fingerprints,
provider option names, generation defaults and option precedence retain their
existing code. Text, object and stream calls use one provider boundary, also
used by the v3 model Action. Six additional cases test that shared boundary.
The complete public facade still contains v2 request/tool/state functions, so
this does not establish a passing root package or complete public API parity.

The mock now records actual HTTP headers. Normal and SSE requests are checked
for the header-loss report from issue 212. Partial evidence is linked to
`8f669705` and `26bb4106` in the history ledger under `HIST-01/stream-headers`.
The legacy ReAct option path, Finch hook order and release/installer checks
remain pending for those rows.

This is the first implementation refinement pass. It does not close milestones
2–3. Further public API and historical cases remain required before those
milestones can be complete.

## Checks at this checkpoint

Runtime: Elixir 1.20.3, OTP 29. ReqLLM: 1.22.0. Local Action is beta.7 and
Signal is beta.4. The declared Elixir 1.18 / OTP 27 floor remains a release check.

| Check | Result |
| --- | --- |
| AI acceptance project, `mix test --include integration` | 60 passed; no pending AI test excluded |
| AI acceptance build, `MIX_ENV=test mix compile --warnings-as-errors` | Passed |
| Default acceptance run | 13 mock tests passed; 47 integration tests excluded as intended |
| Changed-file formatting and whitespace checks | Passed |
| Existing root Usage and Error.Sanitize tests, executed against the v3 acceptance build | 16 passed |
| Full core suite, examples and flaky tests enabled, seed 0 | 1,262 passed; 11 failed; one approved test excluded |
| Core coverage selection | 982 passed; one approved test excluded; 93.7% total core coverage |
| New core extension coverage | 100% |
| Core compile with warnings as errors | Passed |
| Core required warning checks, `mix credo --strict --only warning` | Passed |
| Core Dialyzer | Passed; zero errors |
| Core docs and local Hex package build | Passed |

The broader strict Credo pass reports existing style/refactoring suggestions;
the repository's required warning-only check passes. No broad style rewrite was
made as part of this migration. Core check logs are in `/tmp/jido-ai-v3-core-*`.

The 11 core failures match the pre-existing missing-feature assertions in
[`jido/examples/99_research/README.md`](../../../jido/examples/99_research/README.md).
They cover route precedence, Plugin isolation, stable references, definition
revision, durable deletion, runtime reconstruction and live upgrades. The full
suite was run without hiding those failures. The core extension introduced no
additional failure in that run. Revisit any such contract if an AI feature
depends on it; this result does not establish a fully passing core release.

## Request/session slice

The second production slice adds `lib/jido_ai/session`. Profiles now accept
`requests` with `mode: :turn | :session`, `on_busy: :reject`, `max_requests`,
and `streaming`. One-Turn remains the default. Source profiles, the DSL and
source JSON still use the same lowerer. Core Builder consumes its output.

Admission uses a direct core Action. A test showed that the current Flow
adapter does not carry step extras into the final Agent result. Starting work
from that Flow would lose the admission directive. The lowerer therefore binds
the session Action with a static profile default. The session Plugin reads the
actual declared route through the public Router API, so Signal input cannot
replace that profile. The post-commit task executes the existing reasoning Flow.
There is no second AI scheduler or reasoning interpreter.

The session Plugin owns the portable `:requests` state field. Its process owns
Tasks, sinks, provider options, usage and event sequence. Admission commits
before task dispatch. A correlated completion Signal gets its result from the
Plugin process, not caller data. The final Action changes only the declared
result field and returns the full current candidate. It preserves unrelated
changes committed while the model task was running. An invalid domain result
becomes a committed request failure instead of leaving a request pending.

`Request.create_and_send/3` now returns after confirmed admission. `await/2`
reads committed records with the public Plugin state API. Its bounded polling
runs in the waiting caller; it does not add a scheduler process. `await_many/2`
keeps input order and now accepts an infinite wait. `Session.cancel/2` commits
cancellation before stopping its task. Busy requests fail before provider work.
A rejected duplicate ID cannot send a false terminal event to the first stream.

The shared provider operation now handles SSE text and objects. Real tool-call
fragments are collected by ReqLLM, then executed through the existing catalog
and core Map/Dispatch path. One emitter assigns ordered canonical events.
Disconnects after visible text fail. Blank terminal responses with failed
finish reasons fail before `llm_completed`; non-empty incomplete content keeps
its accepted baseline behavior. Available usage is retained on normal failure
and cancellation after completed model calls. Crash-time accounting remains
part of the recovery work.

Query, Request, Request.Stream and Runtime.Event moved into `shared` with their
module names preserved. Query and Event keep their original implementation.
Request retains its old state helpers for the later facade conversion; those
helpers are not the new Plugin reducer. The acceptance project compiles these
production files and the session directory. The root still compiles all `lib`.

The session case exposed a fresh-runtime loading defect in tool schema lookup.
Schema lookup now loads a compiled tool before checking callbacks. A separate
OS runtime loads a newly compiled Action from a temporary BEAM path, executes
it and checks the real result in the next model request.

These are partial migration results. The example contains local `ask` and
`ask_stream` wrappers over the production Request API; the old `Jido.AI.Agent`
macro and all its generated helpers still need conversion. Unsupported request
options fail explicitly instead of being ignored. The supplied Signal path
must identify a session route. Custom Agent routing overrides and overlapping
routes need separate checks against the known core routing limitations.

The process-restart case reads committed state through `Jido.Plugin.state/1`,
marks pending work interrupted and accepts a later request with fresh resources.
It does not replay the old stream. A crashed Plugin loses its old sink; terminal
failure delivery to that sink remains open, though `await` sees the failure.
Durable restore, old-state conversion and cross-runtime persistence remain open.

See [02_01](../../examples/v3/profiles/02_01_session.md) for the executable scope.
This does not close milestone 4 or its later simplification gate.

## Session checkpoint checks

| Check | Result |
| --- | --- |
| Full acceptance project, integration enabled, seed 0 | 86 passed; no pending case excluded |
| New session example alone | 26 passed, including a separate OS runtime for a generated Action |
| Acceptance compile with warnings as errors | Passed |
| Production and acceptance formatting | Passed |
| Tracked whitespace checks | Passed |
| Existing root Query, Usage and Error.Sanitize tests against the v3 build | 25 passed |
| Default acceptance run | 13 mock tests passed; 73 integration cases excluded as intended |

No core runtime code changed in this slice. The earlier core release checks
remain the recorded core results. Local Action and Signal trees remain clean.
The user file `jido/DIARY_V3_UPGRADE.md` remains untouched. No commit or push
was made. The full migration goal remains active.

## Steering and history slice

Profiles now accept `requests.steering` and `memory.history`. Steering requires
session mode. History must use a declared domain field separate from the result.
The default keeps steering off and does not select a history field. The DSL,
source profile validation and lowerer use these same fields.

The session owner now owns one existing `PendingInputServer` queue per enabled
request. The queue retains the baseline 64-item limit, trimming, FIFO order,
closed/unavailable errors and atomic empty-queue seal. Both steer and inject
add visible user input. `Session.steer/3` and `inject/3` return explicit control
results with control/input/request IDs. A Handle supplies its expected request
ID. Queuing remains best effort. A timeout does not prove rejection, and no
control is retried automatically.

The control Action calls the live queue, then records its correlated queued
result through the Plugin reducer. Queue acceptance is an effect before that
control Turn commits; it is not a durable input receipt. Rejected controls
preserve committed state. This replaces private Strategy state lookup for the
new API. The old ReAct, facade and generated helper wrappers remain to be ported.

Session admission records the initial query in the selected history field.
Successful model messages, tool results and consumed input use separate core
history Turns. Runtime batches hold the actual entries; incoming Signals carry
only batch IDs. Plugin admission supplies trusted entries and a post-commit
acknowledgement removes the runtime batch. The worker waits for the history
commit before continuing. History commits do not replace unrelated domain data.
One-Turn mode instead accumulates its history in local Flow data and commits it
with the final candidate. Output rejection leaves that history unchanged.

The existing Context and PendingInputServer modules moved into `shared` without
changing their module names or implementation. Model history goes through
Context projection and ReqLLM normalization. The first test exposed invalid
mixed map/Message values in an already constructed ReqLLM Context; the shared
projection now normalizes history before constructing that context. A later
request retains the actual tool-call/result pair and one system instruction.

The input drain initially made one history Turn per item. A refinement reduced
this to one history batch per drain, with separate ordered input events. This
keeps the same queue and core commit owner and avoids 64 separate history Turns
for a full queue. It does not change queued-versus-consumed semantics or add a
durable queue. Process failure can still lose queued input or staged history.

The [02_02 example](../../examples/v3/profiles/02_02_steering.md) has 13 tests.
They cover the two closure orders, held model/tool input, guards, capacity,
queue loss, cancellation, hard limits, timeout uncertainty, repair closure,
history reuse and one-Turn state preservation. The latest full acceptance run
passes 99 tests with integration enabled, seed 0. Compiler warnings-as-errors
passes. The 38 existing Context refs, PendingInputServer, Query, Usage and
Error.Sanitize tests also pass against the v3 build. The default run passes
13 mock tests and excludes 86 integration tests as intended. Production and
example formatting and whitespace checks pass. This remains a partial milestone 4 result. It does not close the live
runtime simplification gate or establish full history/recovery/API parity.

## Public Agent slice and refinement

`Jido.AI.Agent` moved to `lib/jido_ai/authoring/agent.ex`. The basic option
macro now builds one profile through the common lowerer and then uses the
ordinary core Agent macro. It no longer starts a v2 ReAct Strategy. The
production generated helpers supply ask, ask_stream, await, ask_sync, cancel,
steer and inject with their existing result shapes. The
[02_03 example](../../examples/v3/profiles/02_03_public_agent.md) tests the
actual generated functions.

One small option adapter maps the public model, prompt, tool, output and
request configuration. A pure state projection supplies last_request_id,
last_query, last_answer and completed while Session Actions build complete
domain candidates. The session Plugin still owns the only request store.
Typed results use last_result and the existing Request.compat_text projection
for last_answer. The runtime Plugin binds the compatibility profile as static
host policy; caller data cannot select it. Native AI profiles keep their own
declared domain fields.

The shared control path can return either the explicit Session acknowledgement
or the committed Agent required by the old helpers. Both use one Signal and
one queue operation. ReAct's steering functions now delegate to this path, but
the complete ReAct module and facade still depend on unported code and have
not passed v3 package tests. Generated Agent controls are tested directly.
Advisory cancel keeps reason and optional request ID. Its committed failure
record drives the matching cancellation event and stops only that request.

Tool retries use core Exec continuations. The macro retains its default one
retry and fixed backoff; native catalog entries default to zero retries.
The Map adapter rejects a continuation returned directly from a Map target.
The tool wrapper therefore uses a nested Exec call to consume its bounded
attempts. It does not add an AI scheduler. Each attempt has the tool timeout,
and the outer request deadline bounds all work. Tool context retains base and
request values, but reserved Agent and AI runtime keys are protected. The
v3 `state` tool snapshot is explicitly before admission, rather than a view of
later state. The current query is available in request context.

A fresh compile of the public macro exposed a Plugin load-order defect. The
common lowerer now waits for its AI binding Plugin to compile before core
validation. A concurrent stale cancellation also exposed the core monitor-graph
reentry check rejecting an independent history task. The history path retries
only explicit pre-execution reentry rejections within five seconds. It does
not retry timeouts, model work or queued controls. The underlying core guard
remains a follow-up; this narrow rule depends on history running outside the
active core Turn.

The public example has 11 passing cases: definitions and exports, prompt
attributes, handle/state results, typed output, streaming, steering defaults,
cancellation correlation, context and retries, retry exhaustion, headers, and
a completed streaming Agent checkpoint round trip. The full acceptance run
passes 110 tests with integration enabled, seed 0. All 126 history statuses
remain pending; 10 rows now have partial execution evidence.

Unsupported authoring options and legacy command/tool callbacks fail explicitly.
They remain required work. The old quoted compatibility helper is retained only
for the unported strategy macros; the new Agent uses core checkpoint/restore.
The checkpoint example does not prove legacy conversion or durable recovery.
This refinement keeps one lowerer, one session owner and one mock. It does not
close the public API or live runtime milestone.

## Request policy and tool schema slice

The [02_04 example](../../examples/v3/profiles/02_04_request_scope.md) adds ten
cases through the public Agent helpers. Session preparation derives a profile
for one request and validates it through the existing Profile and ToolCatalog.
Tool overrides accept module, list and named-map input. The selected catalog
supplies both advertised names and actual tool lookup. Allowlists filter that
catalog, including an empty selection. Invalid tools, unknown allowed names
and invalid output schemas fail before an admission commit or model work.

Raw output, a request-specific Zoi schema, and an imported JSON object schema
leave the default output contract intact for later requests. Positive iteration
overrides can increase or decrease the legacy Agent limit; invalid values keep
the default. A legacy limit produces the existing raw completion message with
an explicit termination reason. A typed limit result still validates and can
use bounded repair. This result is a policy outcome, not a fabricated provider
response. Native profiles retain their explicit model-call limit and limit
failure rules. The outer deadline still bounds each path.

ToolAdapter and ReAct.ToolSelection moved to `lib/jido_ai/shared` with module
names preserved. ToolAdapter uses Zoi's public export and ReqLLM JSON schemas
instead of the removed `Jido.Action.Schema`. Tests showed that ReqLLM's direct
Zoi conversion closes every object. The adapter therefore exports Zoi first
to preserve non-strict open fields. Strict conversion closes them explicitly.
The native ToolCatalog uses this same converter and honors a tool's strict?
callback. Fresh compile validation waits for tool modules instead of checking
only modules that are already loaded.

The root ToolAdapter test fixtures now provide `run/2` and use Zoi schemas as
required by v3. All 32 existing assertions remain. A new integration case
advertises an open tool, executes a dynamic field, and checks that field in the
next provider request. Tool construction alone is not the only proof.

Latest checks: 120 acceptance tests pass with integration enabled and seed 0;
70 existing helper tests pass against the v3 build. The default run passes
13 mock tests and excludes 107 integration tests. Compiler warnings-as-errors,
changed-file formatting and whitespace checks pass. The root package is still
not a passing v3 build. No core code changed in this slice.

The history ledger now has 14 rows with partial execution evidence. All 126
statuses remain pending. This slice adds evidence for request limits (PR 291),
raw/custom output (PR 269), imported schemas (PR 319), and open tools (PR 341).
Remaining work includes every-model-call request transformers, repair callbacks,
full output/event metadata, tool effects and callbacks, keepalives/timeouts,
durable recovery and the full ReAct/facade port. Retry and context options also
need full native DSL/data/source-JSON examples before the authoring gate closes.

## Request transformation and repair callback slice

The [02_05 example](../../examples/v3/profiles/02_05_request_transform.md) adds
14 cases. Normal and repair calls now use the same request transformer before
model controls and provider work. The prepared model determines option merging.
The returned tool catalog supplies both provider definitions and real execution.
Errors stop the next call. Each repair gets fresh transient request resources.

Repair keeps the public prompt format: original user message, failed answer,
and validation error. Content-part queries use the existing query summary.
Repairs use the shared object generation Action with streaming and business
tools disabled after transformation. A provider schema tool is still permitted.
Model-call and time limits remain in force, and actual provider repair usage
is included in the request account.

Configured repair callbacks now run from the public Agent and native profile
paths. Callback results use the same validator. Direct fifth-argument overrides
remain supported. External captures normalize to module/function references;
DSL, data, Builder and source JSON execute them. Invalid stored closures and
arities fail before runtime work. Callback identity remains in the output
fingerprint. A local callback consumes no model call. Callback-owned external
I/O is not automatically included in provider usage accounting.

ReAct Config, State, PendingToolCall and RequestTransformer moved into `shared`
with their public module names retained. The callback state adapter includes
actual call IDs, usage, original repair context and the session owner's current
event sequence. It does not establish full standalone State/checkpoint parity.
Cycle state, thinking accumulators and pending-tool recovery remain open.

This refinement keeps one request preparation path, one profile normalizer,
one tool catalog and one event sequence owner. It introduces no separate repair
scheduler. The root package still requires the complete production port.

| Check | Result |
| --- | --- |
| Full acceptance project, integration enabled, seed 0 | 134 passed; no pending case excluded |
| Existing ToolAdapter, Context refs, queue, Query, Usage, sanitizer and Output tests against v3 | 82 passed |
| Acceptance compile with warnings as errors | Passed |
| Default acceptance run | 13 mock tests passed; 121 integration cases excluded as intended |
| Changed production and example formatting; whitespace | Passed |

The history ledger adds partial execution evidence for PR 343 and PR 339.
Sixteen rows now have partial evidence. All 126 row-level statuses remain
pending. Full output events and metadata, cross-provider routing, callback
cancellation, standalone execution, fresh-runtime restore and package checks
remain required. No core code changed in this slice. No commit or push was made.

## Output events and metadata slice

The [02_06 example](../../examples/v3/profiles/02_06_output_contract.md) adds
17 cases. Output start, repair, validation and failure now share one transition
helper and the existing session event owner. Each transition carries attempt
and schema data. Metadata and event updates reach the owner in one operation.
Completed and failed request records retain output metadata. Terminal stream
events retain those fields while preserving the existing result tuple.

The example found a dispatch error: object generation through a provider schema
tool entered business-tool lookup. Model results now retain whether the request
was for an object. Those responses go to output validation. No business Action
executes for the provider's schema tool. Invalid output without business tools
also repairs through the normal bounded Flow. No extra model loop was added.

Repair cancellation and deadline tests hold an actual callback process and
monitor its exit. The runtime retains the last output attempt and available
usage. One output failure precedes the terminal event. A domain-schema failure
now retains metadata from the successful AI validation, marked as failed for
the rejected commit. An output control can also reject after schema validation.

The existing Observe module moved to `shared` without changing its module name
or implementation. One event adapter now calls the public AI telemetry API.
Output telemetry has actual request/run/call IDs and no model payload. The
Agent ID comes from Plugin initialization. The core rejects attempts to insert
reserved Agent context keys during prepare; the inline path therefore carries
its trusted ID under a separate AI context key.

Profiles, native DSL and the public macro accept two boolean observation flags:
`emit_telemetry?` and `emit_llm_deltas?`. The same validator and JSON lowerer
handle both. Stream delivery remains active when telemetry is disabled. Other
observation options and lifecycle Signal delivery remain open.

The later early-tool-activity slice makes the delta flag control capture as
well as telemetry, matching v2. The telemetry master flag alone still permits
request events. See that slice for the corrected source-format assertions.

The refinement keeps output repair in the existing core Flow, one event sequence
owner, one metadata update path and the existing telemetry sanitizer. It also
reduces final request metadata assembly to one field selection and the optional
output field. It does not add another request process or output interpreter.

| Check | Result |
| --- | --- |
| Full acceptance project, integration enabled, seed 0 | 151 passed; no pending case excluded |
| Existing helper tests, including Output and Observe, against v3 | 96 passed |
| Default acceptance run | 13 mock tests passed; 138 integration cases excluded as intended |
| Production compile with warnings as errors | Passed |
| Production/example formatting and whitespace | Passed |

The existing Observe tests emit two Elixir 1.20 type warnings for redundant
tuple assertions after map assertions. All 14 Observe tests pass. The production
warnings-as-errors compile passes. No test warning was hidden.

Eighteen history rows now have partial execution evidence. All 126 statuses
remain pending. PR 337 has its first live nested-array example. PR 269 gains
output event/finalization evidence; PR 300 gains the shared Observe checks;
PR 339 gains callback cancellation/deadline checks. Full thinking/reasoning
metadata, arbitrary error terms, tool payloads, lifecycle Signals, standalone
execution, recovery and root package checks remain required. Core code did
not change in this slice. No commit or push was made.

## Model response metadata slice

The [02_07 example](../../examples/v3/profiles/02_07_response_metadata.md) adds
11 cases. Buffered and streamed model responses retain synthetic reasoning
details and thinking text in their request metadata. Each trace entry has its
actual model-call ID and number. Tool rounds and typed-output repair retain
separate entries. A later request cannot inherit optional fields from an
earlier request. Public result tuples remain unchanged.

Model completion events now carry text, content parts, normalized tool-call
maps, reasoning details, usage and response IDs. The tests found that exposing
ReqLLM tool-call structs would change the AI event shape. The event adapter
now uses the provider library's map conversion, which the tool catalog also
uses. Execution still validates the full tool batch before any Action starts.

The existing snapshot metadata extraction moved into one shared helper.
It retains field-specific source order, explicit empty-value behavior,
assistant-conversation fallback and explicit override precedence. The same
helper has one model-turn reducer for Flow results and the session owner.
Failure and cancellation retain data from completed model calls through the
existing event owner. A final call without thinking clears `last_thinking`
but keeps earlier trace entries and the latest non-empty reasoning details.

This refinement keeps one metadata reducer and one session event owner.
It adds no scheduler or separate request process. Snapshot helper tests use
an actual completed Agent record but do not establish live snapshot ownership
or recovery parity.

| Check | Result |
| --- | --- |
| Full acceptance project, integration enabled, seed 0 | 162 passed; no pending case excluded |
| Existing shared helper tests, including the error model, against v3 | 117 passed |
| Default acceptance run | 13 mock tests passed; 149 integration cases excluded as intended |
| Production compile with warnings as errors | Passed |
| Production/example formatting and whitespace | Passed |

The 21 existing error-model tests pass without changes. They check the public
AI error adapter against v3 upstream errors and arbitrary error details. They
do not prove the live model/tool/output failure paths. The same two existing
Observe test type warnings remain visible. Production compilation passes with
warnings treated as errors.

Nineteen history rows now have partial execution evidence. PR 233 gains live
request metadata and snapshot source-order evidence. All 126 statuses remain
pending. Other methods, standalone execution, partial interrupted thinking,
transformer thinking-state parity, completed tool outputs and durable recovery
remain required. The next error slice must test arbitrary terms through real
failure paths: output error metadata still uses the redaction-only sanitizer,
and a nonportable worker result currently becomes a generic failure. Core
code did not change in this slice. No commit or push was made.

## Error boundary slice

The [02_08 example](../../examples/v3/profiles/02_08_error_contract.md) adds
15 cases. The initial four tests found three failures: core Flow conversion
changed raw error terms and removed provider status fields; a nonportable
worker error became a generic error; and live values in output error metadata
prevented the final failure commit. These paths now complete through the same
request owner and core execution path.

The shared AI error adapter carries the original cause in a supported Action
error while core Flow executes. Generation, controls, request preparation and
model decisions use that adapter. The session owner extracts the original
cause before storage. Portable errors retain their structure. Nonportable
causes use the existing AI normalizer. Outer failure tuples remain present.
Successful values still require the normal portability check; they are not
silently converted into display data.

Output error metadata now uses the AI normalizer and transport sanitizer.
This removes live resources, redacts sensitive keys and bounds error summaries.
The sanitizer now terminates when a depth-limited error map has only null
type/message fields. It also converts invalid binary keys into valid text.
The canonical JSON error normalizer uses `base64:` strings for malformed UTF-8
messages, keys and values. Raw portable request errors remain separate from
that JSON representation.

The examples preserve source errors from native DSL controls and actual
Action/core constructors. Retry checks for supported upstream error structs
now agree with the shared normalizer. Callback raise, exit and kill cases
retain a cause, available usage and one output-failure event. Later requests
can run after a rejected output. No second executor or retry loop was added.

| Check | Result |
| --- | --- |
| Full acceptance project, integration enabled, seed 0 | 177 passed; no pending case excluded |
| Existing shared helper tests against v3 | 117 passed |
| Default acceptance run | 13 mock tests passed; 164 integration cases excluded as intended |
| Production compile with warnings as errors | Passed |
| Production/example formatting and whitespace | Passed |

The two existing Observe test type warnings remain visible. Production
compilation passes with warnings treated as errors. No core source changed.

Twenty-four history rows now have partial execution evidence. PRs 214, 223,
258, 275 and 299 gain their first live error cases. PR 300 gains error-summary
termination and transport-key evidence. All 126 row-level statuses remain
pending. Model-facing tool envelopes, completed tool outputs, effects, full
retry policy, Flow-specific error adapters, standalone execution, other
methods, durable recovery and package checks remain required. No commit or
push was made.

## Tool result slice

The [02_09 example](../../examples/v3/profiles/02_09_tool_results.md) adds
19 cases. A real directory failure now returns a canonical error message to
the model. Successful tools use the same success envelope as the existing
Turn API. Core raw/batch wrappers expose the value. Content parts remain
separate from JSON. A supported Flow error uses the Flow package's public
map adapter. Unsupported output kinds require an explicit consumer.

The existing Turn formatter moved into `Jido.AI.Turn.Content`; the public Turn
function delegates to it. A small core-output adapter reuses `PendingToolCall`
and one ordered metadata reducer. Completed records contain IDs, arguments,
status, native result tuples, attempts and duration. The same reducer runs in
the Flow and request owner, so later model failure and cancellation retain
completed tools. Repeated completion data replaces the same call record.
Reversed parallel completion does not change model-message or stored order.

The public retry example now supplies a final model reply after tool failure.
It verifies exact attempts, explicit retry hints and stored attempt counts.
No returned effects are retried. Nonempty effects still stop continuation with
an explicit error until the typed-effect and candidate-state port is complete.

File tests found and retain a provider boundary: ReqLLM's selected chat path
rejects PDF and text-file attachments before HTTP. The failed request keeps
the completed tool value and file metadata. Supported image file bytes reach
the shared mock in a separate data URI through the real encoder. These small
binary fixtures prove transport and JSON safety, not rendered-file validity
or provider interpretation. File restore and other provider formats remain open.

| Check | Result |
| --- | --- |
| Full acceptance project, integration enabled, seed 0 | 196 passed; no pending case excluded |
| Existing shared helper tests against v3 | 117 passed |
| Default acceptance run | 13 mock tests passed; 183 integration cases excluded as intended |
| Production compile with warnings as errors | Passed |
| Production/example formatting and whitespace | Passed |

The two existing Observe test type warnings remain visible. No core source
changed. Twenty-eight history rows now have partial execution evidence.
PRs 230, 250, 296 and 306 gain their first evidence. All 126 row-level statuses
remain pending. The full Turn/ReAct APIs, effects, complete retry/input-error
policy, source-format equality, other methods, recovery and package acceptance
remain required. The root dependencies still select v2. No commit or push
was made.

## Tool effect and candidate-state slice

The [02_10 example](../../examples/v3/profiles/02_10_tool_effects.md) adds
24 cases. Effects, Policy and Applier moved into the shared production source
set with their public module names retained. The existing policy filter and
intersection code now accept the new complete-state proposal and current core
Emit, Dispatch and Scheduler Directives. No StateOps interpreter was restored.

`Jido.AI.Effects.state/1` creates a complete proposed state. One candidate
assembler uses core Plugin protection and `Jido.Agent.transition/2` to validate
it. Parallel proposals combine different top-level fields in call order and
reject conflicting writes. Later model tool rounds receive the candidate.
Final assembly applies its changes to the latest committed state, preserving
unrelated fields and rejecting intervening writes to the same changed field.

The reasoning Flow carries the result, candidate and pending Directives as
data. One-Turn routes now bind a terminal Action that runs that Flow and returns
the complete candidate plus Directives. This replaces the earlier direct Flow
route because the Flow adapter discards step extras. Session completion uses
the same assembler. It commits accepted output before core dispatches effects.
Source-profile JSON, stored Agent entry Actions, Builder and DSL tests pass.

The Agent-level `effect_policy` and reasoning-level policy share one normalizer.
The public `strategy_effect_policy` option maps to reasoning policy. A narrower
policy cannot be widened by caller context. Filtered completion data includes
received, allowed and dropped counts. A retryable error with returned effects
is not retried; allowed effects can commit with the later accepted model answer.

Live Directive targets stay in the request runtime owner. They are excluded
from the portable-result check and validated by core before dispatch. Portable
tool values keep their native form even when an effect has a live target.
Stored state-effect inspection records only changed values and deleted keys;
it does not copy previous request records into each new state proposal.
Inspection data is marked and is not an effect replay format.

The examples run real Dispatch and Scheduler Plugins, and a stateless observer
that reads committed Agent state. Cancellation, output rejection, invalid
proposals and later model failure prevent candidate/directive commit. A real
local file write remains after policy filtering or output rejection, as PR 318
requires. No external model or outbound application was called.

A new defaulted enum in the tool schema found a conversion gap. The shared
schema-input normalizer now unwraps a Zoi Default before converting its known
enum labels. A public Agent with a declared Plugin found a compile-time loading
gap. Its option adapter now ensures declared Plugin modules are compiled before
core validation. A forced production/example recompile passes.

This is the effect refinement pass: one policy filter, one candidate assembler,
one provider boundary and one core Flow continue to serve both request modes.
The existing 11 Policy/Applier tests now use complete-state proposals and current
core constructors. They retain tuple/filter/constraint/application assertions.

| Check | Result |
| --- | --- |
| Full acceptance project, integration enabled, seed 0 | 220 passed; no pending case excluded |
| Existing shared helpers, including Policy and Applier, against v3 | 128 passed |
| Default acceptance run | 13 mock tests passed; 207 integration cases excluded as intended |
| Forced production/example compile with warnings as errors | Passed |
| Production/example formatting, whitespace and document references | Passed |

The two existing Observe test type warnings remain visible. Core source did
not change in this slice. Twenty-nine history rows now have partial execution
evidence, including PR 318. All 126 row-level statuses remain pending.

Tool interceptor ordering and failure behavior still need their port. The
request-transformer Config/state view must expose the effective effect policy
and staged state/results. Other methods and standalone APIs, default Plugin
choices, complete post-commit failure reporting, pending-work recovery and the
root dependency/package checks remain open. The root still selects v2. No
commit or push was made.

## Completion commit and failure slice

The [02_11 example](../../examples/v3/profiles/02_11_completion.md) adds
11 integration cases. A failed Plugin reduction or final state-size check
previously left an accepted request pending: completion used a best-effort
cast, whose error had no owner. The session owner now starts a monitored core
call and observes its commit reply. It stays free to answer Plugin admission
and dispatch callbacks while that call runs.

Core call success proves the commit. It does not prove later Directive success.
The existing first completion Directive ends the request stream after commit.
A later effect failure keeps the answer and stops the rest of core's batch.
The example verifies one completion event and no repeated tool or Directive.

A definite completion rejection causes a failure-only settlement. AI never
submits the original tool or effect batch again. If full failure metadata does
not fit, one final attempt uses a small error and an explicit details-elided
marker. New pending records reserve 512 string bytes for that record. The
reserve is real Plugin state, so another Turn cannot consume those bytes while
staying within the same state limit. Completion and cancellation release it.
Tests fill state to its exact limit and reject admission before model work when
the reserve cannot fit. Earlier v3 records default the field to nil; activation
can still mark them interrupted. This does not prove v2 conversion.

If all settlement forms fail, the owner reports `completion_uncommitted` and
one terminal event with `committed?: false`. The stored record remains pending.
Await reads that owner status through public core child lookup. A later manual
cancellation does not send a second terminal event. A storage conflict stops
completion attempts immediately. Unknown writes, call exits and settlement
task loss are not retried. Their observed error is `completion_uncertain`.

The storage fixture uses the real persistence protocol. A second write can be
refused, or stored before its reply is lost or raises. In the unknown cases,
core stops the Agent; loading the stored checkpoint finds the answer, while
no pending Directive was dispatched. Await on the stopped PID returns
`agent_server_unavailable`. Delivery from a stopping owner is not guaranteed.
Durable sink and work recovery remain open.

This is the completion refinement pass: one request owner observes one core
commit boundary. Model Tasks and settlement Tasks have separate monitor keys.
Only the core's explicit pre-execution reentry refusals are retried briefly;
an unknown call result is never treated as a refusal. Failure settlement uses
the same terminal Action and Plugin reducer as normal completion. It does not
add a second state store or invoke a tool Plugin reducer speculatively.

| Check | Result |
| --- | --- |
| Full acceptance project, integration enabled, seed 0 | 231 passed; no pending case excluded |
| Default acceptance run | 13 mock tests passed; 218 integration cases excluded as intended |
| Forced production/example compile with warnings as errors | 67 files compiled; passed |
| Shared helper baseline | 128 passed in the preceding effect slice; those sources did not change here |
| Production/example formatting, whitespace and document references | Passed |

The storage-conflict fixture causes an expected shutdown persistence error log.
Core source did not change. PRs 262, 318 and 332 gain partial completion/storage
evidence. Twenty-nine history rows have partial evidence; all 126 row statuses
remain pending. No commit or push was made. Request transformer state/policy
views, tool interceptors, all methods and facades, full cancellation/recovery
contracts and root dependency/package checks remain open.

## Tool callback and request-view slice

The [02_12 example](../../examples/v3/profiles/02_12_tool_callbacks.md) adds
32 integration cases. `ToolInterceptor` moved into the shared production
source set with its module and public helper results retained. The public
Agent wrapper now permits its optional tool callbacks. Native profiles add
one `tool_interceptor` module reference; DSL, data, Builder and source JSON
execute the same definition. Unused nil callback fields are omitted from
encoded source documents so existing registries need no new atom entry.

The PR 347 alias workflow now runs with real Actions. A result callback maps
a long key to an alias and proposes explicit candidate state. The next model
round selects the alias; argument preparation restores the exact original key
before validation. Direct Exec still accepts the original key without AI hooks.
The original before-callback rejection test now checks an unported command
hook; positive callback tests prove the newly supported path.

Catalog admission now resolves the whole batch before argument preparation.
It validates all prepared calls before operation controls and execution. One
shared core Action invokes callbacks within the remaining request deadline.
The existing ToolInterceptor checks identity and canonical result tuples and
catches callback errors, exceptions, throws and exits. Its internal result
form also returns filter counts, while the public helper keeps its old tuple.

Before callbacks run once before retries. With callbacks, tool attempts return
raw results to the Flow. All concurrency chunks finish before result callbacks
run in model call order. A monitored reversed completion test checks the order
directly. The final canonical error also reaches its result callback once.
The shared result completion path applies policy after transformation, emits
completion evidence and stages permitted state. A later callback failure does
not undo completed Action I/O or earlier completion evidence; it prevents final
candidate commit. Without callbacks, existing immediate tool completion
behavior remains available, including partial results on cancellation.

Request transforms now see the effective effect policy, candidate state and
completed tools in their ReAct State view. Callbacks and tools receive trusted
request/run IDs and Agent identity. These replace caller-supplied context
values. A literal Flow can keep its full executable identity in the callback
call. Both native one-Turn and session execution pass the same callback path.

This is the callback refinement pass: one catalog prepares calls, one callback
contract normalizes results and filters effects, and one candidate assembler
handles state. Core Exec owns all execution and callback lifetime. The port
does not attach AI hooks to ordinary Actions or add an alternate executor.

| Check | Result |
| --- | --- |
| Full acceptance project, integration enabled, seed 0 | 263 passed; no pending case excluded |
| Callback integration examples | 32 passed within the full acceptance run |
| Forced production/example compile with warnings as errors | 70 files compiled; passed |
| Shared helper suite including ToolInterceptor | 139 passed |
| Default acceptance run | 13 mock tests passed; 250 integration cases excluded as intended |
| Formatting, whitespace and document/test references | Passed |

The existing two Observe test type warnings and expected storage-conflict
shutdown log remain visible. Core source did not change. PR 347 gains first
partial evidence, and PR 296 gains request-transform inspection evidence.
Thirty history rows have partial evidence; all 126 row statuses remain pending.

ToT must still preserve its raw inbound tool-result Signal and apply callbacks
at its own result boundary. Standalone AI tool APIs, pending-work validation,
non-idempotent callback replay, durable pause/resume and sink recovery remain
open. A cancelled batch that has not reached result callbacks has no approved
transformed result for those tools; durable recovery must represent that fact.
Remaining request options, early tool activity, keepalives, method/facade ports,
root dependency cutover and package/consumer/runtime-floor/rollback checks are
still required. No commit, push or publication was made.

## Tool preflight and time-limit slice

The [02_13 example](../../examples/v3/profiles/02_13_tool_limits.md) adds
19 integration cases. Native Action and Flow declarations now expose optional
`max_retries` and `retry_backoff` fields. They use the existing catalog and
Flow attempt loop. Omitted fields retain catalog defaults and do not add atom
requirements to existing source registries. DSL, data, Builder and source JSON
produce the same definition and execute its retries.

One shared preflight boundary checks all native operation controls, then the
transient legacy `__tool_guardrail_callback__`, before any tool starts. The
catalog retains prepared arguments beside the schema-validated map. The old
callback receives its original argument shape plus `validated_arguments`.
Its trusted context has the request/run identity and current candidate state.
No callback closure enters portable Agent state or a later request.

Explicit errors and interrupts retain their reasons. Native operation controls
can also interrupt; other stages keep the existing result contract. Malformed
legacy results, exceptions, throws and exits become controlled failures.
Non-functions and wrong-arity callback values retain the old no-op behavior.
The session owner stores the `tool_guardrail` failure type, correlated by
request and run, for the final failed event. No separate tool executor or event
owner was added. Core Exec stops held callbacks on cancellation and deadline.

The PR 331 test holds real named Action and Flow tools and direct core Exec
for more than 31 seconds with a 45-second budget. Monitors and elapsed times
prove execution and completion beyond the old inner limit. Short cases prove
that an attempt timeout kills real Action/Flow workers and that a smaller
request deadline stops work with a larger tool budget. An explicitly retryable
typed error gets a fresh attempt budget and configured backoff. Its total
elapsed duration exceeds one attempt budget.

The timeout test exposed a v3 compatibility change. Core now sets `retry: false`
on its own timeouts; the old execution layer did not set that flag. AI retains
the explicit core decision, even with unused retry attempts. The migration
plan records this change. A tool can use a typed Action error with `retry: true`
when another attempt is permitted. Raw legacy error-map forms still need
their compatibility decision and tests. A stopped tool does not imply that
its completed I/O was reversed.

This refinement keeps one catalog, one batch preflight, one Flow retry loop
and core execution ownership. Legacy callbacks remain transient input; the
static DSL uses module controls. Interruption still means request failure with
an interrupt reason. It does not claim durable approval or resume.

| Check | Result |
| --- | --- |
| Full acceptance project, integration enabled, seed 0 | 282 passed; no pending case excluded |
| Preflight and time-limit examples | 19 passed within the full acceptance run |
| Forced production/example compile with warnings as errors | 72 files compiled; passed |
| Shared helper suite | 139 passed |
| Default acceptance run | 13 mock tests passed; 269 integration cases excluded as intended |
| Formatting, whitespace and document/test references | Passed |

The two existing Observe test type warnings and expected storage-conflict
shutdown log remain visible. Core source did not change. PRs 260 and 331 gain
first partial evidence. Thirty-two history rows now have partial evidence;
all 126 statuses remain pending. The ledger has 211 concrete test references.

Pending-work preflight, durable approval/resume, standalone ReAct, legacy
`Turn.execute_module` and Directive entry points, old retry input forms,
keepalives/idle limits and recovery remain open. Direct core Exec proves its
own path only. Root dependency cutover and full package, consumer, runtime-floor
and rollback checks are still required. No commit, push or publication was made.

## Session stream activity and keepalive slice

The [02_14 example](../../examples/v3/profiles/02_14_stream_activity.md) adds
16 integration cases. Native session requests can declare `idle_timeout`
and `tool_heartbeat` in milliseconds. Optional fields stay omitted from older
source documents. The public Agent accepts `stream_timeout_ms`, its older
`stream_receive_timeout_ms` alias, and `tool_heartbeat_ms`. One request-option
conversion serves the macro and per-request resources. Explicit zero and
invalid high-level overrides retain their documented meanings. Static native
values are validated, and one-Turn activity declarations fail before activation.

The existing session owner now owns idle and heartbeat timers. Activity keeps
live references in its private job data. Each timer message carries request/run
identity and a fresh token. Provider chunks reset runtime idle time through
ReqLLM's actual `on_chunk` callback. Tool-argument fragments count as activity
even when there is no visible text; they do not emit a public keepalive.

Tool start opens an activity window. Parallel tools share one heartbeat timer.
Retries and backoff remain inside that window. Completion closes the tool's
window before the completion event. A work-finished notification also closes
it when result callbacks are deferred until the complete batch returns. The
same owner emits canonical keepalives and assigns every sequence, so no second
heartbeat process or sequence handoff is needed.

Runtime idle expiry stops the core-owned work and uses the existing observed
failure commit, with reason and failed-event type `:stream_timeout`. A finite
enumerable receive timeout still ends only that enumeration. The request can
finish later. Tool and total request deadlines remain effective while heartbeat
events arrive. Completion, failure and cancellation stop timers. Owner death
also stops real tool work and timer references. Recovery interrupts the stored
request; the lost transient sink does not gain terminal-event replay.

The tests hold a real tool for 650 ms across a 300 ms runtime idle limit and a
150 ms public consumer limit. Other cases exercise order through parallel
tools, retries, multiple rounds and injection; both option names, explicit
zero and automatic idle calculation; silent providers; failure and timeout
cleanup; and owner failure. Real provider argument fragments arrive over more
than 700 ms without a public keepalive before tool execution. DSL, data,
Builder and source JSON execute the same held-tool policy.

This is the stream-owner simplification pass: one event owner, one sequence,
one bounded set of activity timers, and core execution cleanup. The old
negative heartbeat-option test now checks an unported skill option; positive
heartbeat behavior is covered by the new integration cases. The plan and
README now describe the actual source layout: acceptance compiles ported
production modules from the root tree, while root dependency cutover remains
open. The pinned v2 Git commit remains the comparison baseline.

| Check | Result |
| --- | --- |
| Full acceptance project, integration enabled, seed 0 | 298 passed; no pending case excluded |
| Stream activity examples | 16 passed within the full acceptance run |
| Forced production/example compile with warnings as errors | 74 files compiled; passed |
| Shared helper suite | 139 passed |
| Default acceptance run | 13 mock tests passed; 285 integration cases excluded as intended |
| Formatting, whitespace and document/test references | Passed |

The two existing Observe test type warnings and expected storage-conflict
shutdown log remain visible. Core source did not change in this slice. PR 308
gains first partial evidence. Thirty-three history rows now have partial
evidence; all 126 row statuses remain pending. There are 227 concrete test
references in the ledger.

Standalone ReAct, Start/Continue/Collect, token compatibility, early tool-call
Signals, other methods and full durable sink/sequence recovery still need
their port. Root dependencies, the full package and consumer, the declared
runtime floor, migration instructions and rollback checks remain required.
No commit, push or publication was made.

## Early tool activity and delta capture slice

The [02_15 example](../../examples/v3/profiles/02_15_early_tool_activity.md)
adds 13 integration cases based on PR 247 and its document-tool use case.
ReqLLM's real `on_tool_call` callback emits a canonical `:llm_delta` for a
nonempty tool name. A mock barrier holds the remaining document arguments.
The test receives early activity before admission or file creation, then
releases the stream and checks the written bytes and next model tool result.

Early activity retains the v2 name-only payload. It has model-call, request,
run, iteration and sequence correlation, but no executable tool-call ID.
Unknown or blocked tools can emit early activity and still fail admission.
Cancellation and a disconnected argument stream stop the provider without
writing the document. Empty names produce no public delta.

The simplification pass uses `observability.emit_llm_deltas?` for both native
and public Agent delta capture. The existing session owner filters disabled
deltas before sequence assignment. `emit_telemetry?` remains the master
telemetry flag; disabling it alone leaves enabled public deltas available.
There is no new capture option in the DSL, data or Builder. The earlier native
output example now checks the same capture policy while retaining output
telemetry and complete request events.

Internal activity remains separate from public capture. Actual unnamed
argument fragments arrive over more than 700 ms with a 300 ms idle limit,
with capture enabled and disabled. The same real document Action executes in
DSL, data, Builder and source JSON forms, including a quiet JSON variant.
Invalid static observation flags fail before activation. Enabled events keep
one sequence and distinct model-call IDs through early activity, tool work
and final text.

The empty-name test found that the provider decoder can remove an unusable
call and return an empty declared tool round. V3 now fails that response with
`{:incomplete_response, :tool_calls}` before history or model completion.
Usage remains counted. This changes the v2 behavior, which could continue an
empty round until a limit applied. A blank successful stop is still valid.
Object requests continue through their existing validation and repair path.
The 17 output cases pass with this change.

| Check | Result |
| --- | --- |
| Full acceptance project, integration enabled, seed 0 | 311 passed; no pending case excluded |
| Early tool activity examples | 13 passed within the full acceptance run |
| Forced production/example compile with warnings as errors | 75 files compiled; passed |
| Shared helper suite | 139 passed |
| Default acceptance run | 13 mock tests passed; 298 integration cases excluded as intended |
| Formatting, whitespace and document/test references | Passed |

The two existing Observe test type warnings and expected storage-conflict
shutdown log remain visible. Core source did not change. PR 247 gains its first
partial execution evidence. Thirty-four history rows now have partial evidence,
with 240 concrete test references. All 126 row statuses remain pending.

The separate typed Signal boundary and actual Signal delivery still need a
port. Do not count canonical public request events as that proof. Standalone
ReAct, other methods, complete content-part deltas, durable sink/sequence
recovery and all root package gates remain required. No commit, push or
publication was made.

## Typed Signal and shared Turn slice

The [02_16 example](../../examples/v3/profiles/02_16_typed_signals.md) adds
18 integration cases. All ten public typed Signal definitions now use core
`Jido.Signal` and static Zoi schemas. The old internal AI Signal DSL is gone.
The remaining Definition helper handles known top-level keys, duplicate
rejection, explicit nil and metadata accessors. Zoi validates field values;
core Signal owns the envelope and constructors.

The tests caught two schema boundary differences. Unknown tuple keys can fail
inside Zoi's error renderer, so the input adapter rejects non-atom/non-string
keys first. Zoi defaults also replace explicit nil. AI defaults previously
applied only to missing fields. For a present nil the adapter uses the declared
inner schema: metadata remains invalid, while atom/any fields retain their nil
meaning. Nested result data and shallow map structs remain unchanged.

Constructor options cannot replace the declared Signal type or validated
data. Mixed key aliases fail, including equal duplicate data values. Identical
repeated keyword option keys retain the core last-value rule. The example
records the intentional v3 schema metadata, error class and timestamp changes.
`new!` now uses Zoi parse errors or ArgumentError. Standalone constructors
leave time absent; canonical event projection uses actual event time.

`Jido.AI.Signal.from_event/2` projects the existing ReAct request events.
`emit/1` returns core Emit Directives for a normal Agent Action. The test
publisher commits its complete state, runs an outbound Plugin and dispatches
to a real receiver. A rejected outbound Signal does not reach the receiver and
does not undo the publisher state commit.

A live mock barrier holds incomplete tool arguments. The example receives,
projects and delivers an early tool-name Signal before the Echo Action can
execute. Request, run, model-call, iteration and sequence fields survive.
The next model round has a distinct call ID. Reversed text deltas reconstruct
by sequence. Model/tool results, usage and final results reach the receiver.
Actual provider failure and cancellation have matching failed Signals. The
request-start event now includes its query, and lifecycle projection uses the
actual run ID. Model-response helper conversion and real embedding vectors
also pass through typed delivery.

Pure projection keeps complete image parts, reasoning details and message
metadata. This does not claim that arbitrary local data is JSON-serializable:
the example checks the core rejection of non-JSON content-part data. Events
without an existing typed AI Signal produce no new type. DSL, data, Builder
and source JSON execute the same request and produce the same payloads.

The shared `Jido.AI.Turn` module is now compiled on v3. Its response, content,
tool-message and direct execution APIs remain. Direct tools use core Exec,
shared declared-key/enum input conversion and the shared ToolResult envelope.
Real validation and timeout cleanup are checked. Core's no-retry timeout
meaning is retained. Registry and observation options do not go to Exec. The
old per-run log_level option is accepted at the AI boundary; core v3 does not
provide the old input logging. Suppression-only tests do not prove all old
logging precedence or execution-option behavior.

| Check | Result |
| --- | --- |
| Full acceptance project, integration enabled, seed 0 | 329 passed; no pending case excluded |
| Typed Signal examples | 18 passed within the full acceptance run |
| Forced production/example compile with warnings as errors | 91 files compiled; passed |
| Retained shared suite, now including Turn and Signals | 227 passed |
| Default acceptance run | 13 mock tests passed; 316 integration cases excluded as intended |
| Formatting, whitespace and document/test references | Passed |

The retained suite adds 88 Turn, Signal and Signal.Helpers cases; only three
Signal error assertions change to the new core contract. The existing two
Observe type warnings and expected storage-conflict shutdown log remain
visible. Core source did not change. PRs 310 and 271 gain first partial
evidence; PR 247 gains explicit early Signal delivery evidence. Thirty-six
history rows have partial evidence and 261 concrete test references. All 126
statuses remain pending.

This is an explicit event-to-publisher example. It does not install automatic
Signal delivery in the session owner. Complete that integration with bounded
queue, authority and post-commit failure rules. CoT and all other methods,
standalone APIs, public embedding Actions, provider content-part streaming,
durable delivery/replay, all legacy execution options and root package gates
remain required. No commit, push or publication was made.

## Automatic session Signal delivery slice

The [02_17 example](../../examples/v3/profiles/02_17_signal_delivery.md) adds
26 integration cases. `Session.Runtime` remains the only canonical event and
sequence owner. A linked and monitored `Session.Delivery` process holds a
bounded transient queue and one active submission. It projects existing typed
Signals, then submits a batch through the owning Agent with a one-use ticket.
The admission Plugin replaces untrusted grants. The publication Action
consumes the actual ticket and returns the complete current state, core Emit
Directives and one final receipt. Core source did not change.

The receipt runs only after all Emits pass outbound Plugin preparation and
adapter dispatch. `Request.await` still confirms the answer commit. The new
`Session.delivery_status/2` confirms only the observation stage. It does not
confirm receiver handling. Normal core revisions, Plugin reductions and
persistence writes apply to publication. Default self dispatch retains host
exact and wildcard routes; unhandled known AI observations use a no-op Action.

One existing observation option, `emit_signals?`, defaults to true. It can be
false while canonical deltas and telemetry keep their own policy. Delta
capture still uses `emit_llm_deltas?` before sequence assignment. Native DSL,
data, Builder and source JSON run the same flag settings. The public Agent
facade uses the same delivery path. The request-start Signal now accepts the
public query schema, including actual multimodal content-part lists.

Count and encoded-term byte limits include queued and active events. Defaults
are 256 events, 8 MiB, 16 events per batch and a 15-second receipt deadline.
The application setting is checked at Agent activation. Unknown keys and
out-of-range values cause defined startup errors. Reports retain at most 100
finished requests plus active work. The profile documents each counter and
its event unit; one event can produce more than one typed Signal.

Overflow closes observation for the affected request and drops its queued
tail. The canonical stream and model/tool result remain separate. Confirmed
admission/commit rejection is failed; missing receipts and unknown outcomes
are unconfirmed. A batch is never replayed after commit. Only explicit core
reentry refusal permits bounded retry before admission. Core's Directive
limit also applies to each batch and its receipt.

This is the observation refinement pass. A receipt uses the core Directive
path. Core serializes turns: slow dispatch can delay history, completion and cancellation commits.
The AI receipt timeout stops its submission task and closes its batch; it
cannot retract a committed Emit. A real held Emit can finish after that
timeout without changing the report. Core's Directive timeout can stop the
outbound worker. A partial batch remains unconfirmed. These limits are tested
with the shared mock and real outbound Plugins/adapters.

Owner or server loss stops the transient delivery owner, submission work and
timers. Restart rejects old tickets. Pending requests use the existing
interruption path, with no recovered Signal replay or old report. An Emit
already committed by core can still finish after session-owner loss. There is
no durable delivery claim.

The completion storage fixture now selects terminal request state in the
actual checkpoint instead of assuming the second write is completion. It
counts one completion attempt separately from observation writes. The
refusal and indeterminate-write tests still check their original behavior.
The ordinary session test accounts for the extra core observation commits
while it verifies admission and preservation of intervening domain state.

| Check | Result |
| --- | --- |
| Full acceptance project, integration enabled, seed 0 | 355 passed; no pending case excluded |
| New automatic delivery example | 26 passed |
| Retained shared helper suite | 227 passed |
| Default acceptance run | 13 passed; 342 integration cases excluded as intended |
| Forced production/example compile with warnings as errors | 93 files compiled; passed |
| Production/example formatting and whitespace | Passed |
| Local document links and historical test references | Passed |

The retained Observe tests still emit their two known type warnings. Failure
and shutdown cases can log stopped dispatch or Plugin runtime errors; the
full acceptance run passed. Root package compilation was not claimed.

PRs 310, 247 and 271 gain automatic delivery evidence. PR 229 gains first
partial evidence. There are 37 partial history rows and 292 concrete test
references; all 126 statuses remain pending. Other methods, standalone
observations, durable delivery, all legacy options, and root dependency,
consumer, runtime-floor and package checks remain required. No commit, push
or publication was made.

## CoT and CoD shared Flow slice

The [09_01 example](../../examples/v3/profiles/09_01_linear.md) adds 33
integration cases. The existing `reasoning` field now accepts CoT and CoD.
Both use the same Prepare, model-call and Decide Flow, output validation,
controls and session owner as ReAct. DSL, data, Builder, source JSON, direct
Flow and ordinary Agent paths have execution evidence. No new executor or
request owner was added.

The simplification pass places prompts and plain-text result parsing in
`Reasoning.Linear`. Native profiles select their method prompt for omitted or
empty instructions. Public macros retain historical prompt-attribute and
nil/false/empty defaults. Linear methods reject tools and steering, including
request tool injection before admission. An unsolicited provider tool call
fails without tool execution or a second call. Structured object repair uses
the shared bounded path and keeps the validated result.

CoT and CoD public modules now live in `authoring` and delegate their think/
draft helpers to the common Agent. They retain await, Signal namespaces,
model/prompt inspection, fresh per-request context, last_prompt and printable
last_result fields. Omitted linear max_tokens retains the provider default.
`llm_timeout_ms` maps to provider receive_timeout with common option precedence.
`request_timeout_ms` sets a separate total budget with a new 60-second default.
The profile documents this source migration. Actual transport and total
request deadlines stop held provider work.

The shared namespace helpers moved into `shared`. Their prompts, parsers and
ID prefixes run on v3. The old CoT Machine now delegates parser code; it is
still outside the acceptance compile. Old Strategy identifiers, executors,
worker interfaces, CLI and capability entry points remain unported. The final
method selection/introspection API remains an explicit open item.

Plain-text results keep raw text, parsed steps, conclusion, method and usage
metadata. Conclusion projection occurs before output controls. Byte-safe
parser slices fix Unicode and adjacent markers; boundary and indentation
checks fix false conclusion matches. Non-streamed rich content uses the shared
Turn result projection for ReAct, CoT and CoD. Real provider text/image/text
and image-only replies retain their content order. Generated media streaming
is not proved by these cases.

Portable records and canonical events now store method identity. Typed Signals
and telemetry use :cot and :cod; CoD no longer inherits the CoT label. Ordinary
Agent output telemetry carries the same identity. An initial full run exposed
ordinary event maps without the new field; those now carry it, and the old map
fallback remains ReAct. Known structured error types also survive telemetry.
Cancellation retains its reason and closes provider work. Busy admission,
failed output, method recovery and fresh requests have real Agent evidence.

A repeated run exposed a recovery race: the new owner could submit its
interrupted result before core published its ready state. The shared completion
path now retries core's exact session-owner :restarting refusal within its
existing five-second pre-admission deadline. Core rejects that case before
execution. Other Plugin errors and unknown commit outcomes keep their failure
rules. No committed model/tool work is replayed. Core source did not change.

| Check | Result |
| --- | --- |
| Full acceptance project, integration enabled, seed 0 | 388 passed; no pending case excluded |
| New linear example | 33 passed within the full run |
| Retained shared helper suite | 227 passed |
| Default acceptance run | 13 passed; 375 integration cases excluded as intended |
| Forced production/example compile with warnings as errors | 99 files compiled; passed |
| Production/example formatting, whitespace, links and test references | Passed; 761 local links and 311 history test references |

The history ledger adds first partial evidence for PRs 218 and 340 and expands
PRs 217, 223, 233, 271 and 310. There are 39 partial history rows and 311 concrete
test references; all 126 statuses remain pending. Root dependencies and the
pinned baseline inventory are unchanged. No commit, push or publication was
made.

## Linear method and retained Machine API slice

The [09_02 example](../../examples/v3/profiles/09_02_method_api.md) adds seven
integration cases. CoT and CoD namespaces now expose `method/0` for the existing
AI profile and result getters with optional request IDs. One actual Agent runs
both profiles and reads their separate committed metadata. A new pending or
cancelled request cannot expose an earlier answer as current; a retained older
ID remains readable. No inspection helper calls a runtime or converts v2 state.

The old CoT/CoD Strategy module names moved into `shared` as deprecated
read-only getter adapters. `strategy_module/0` still returns a loadable module,
but that module is not an executor. Its old core callbacks, snapshots, action
atoms and worker channels now have an explicit source mapping to native
Agent/Flow/Session APIs. The example profile records direct CoD's former
empty-prompt fallback: supply the CoT default explicitly when that behavior is
needed. Public CoD Agent defaults remain CoD.

The retained CoT Machine also moved into `shared`. Direct finite transitions
replace its Fsmx dependency. New/update/map conversion, status shapes, parser,
prompt/ID helpers, busy errors, stale-call checks, terminal closure, raw errors
and content accumulation remain. It owns no process and never executes its
returned model-work tuples. Its legacy clocks and telemetry remain; the docs
now state those side effects. The 27 retained Machine tests pass unchanged.
A new case feeds an actual ReqLLM result through its explicit legacy result
projection. Other cases check raw errors, telemetry and nested usage.

This simplification pass reuses the shared Usage merger and Linear parser.
Nested usage no longer attempts arithmetic on metadata maps or strings.
Known numeric keys normalize; arbitrary provider keys remain strings when
supplied as strings. The shared merge preserves those metadata values without
creating atoms. No new dependency or execution owner was added. Core source
and root dependencies did not change.

| Check | Result |
| --- | --- |
| Full acceptance project, integration enabled, seed 0 | 395 passed; no pending case excluded |
| New method API example | 7 passed within the full run |
| Retained shared suite, including 27 unchanged Machine cases | 254 passed |
| Default acceptance run | 13 passed; 382 integration cases excluded as intended |
| Forced production/example compile with warnings as errors | 103 files compiled; passed |
| Formatting, whitespace, document links and historical test references | Passed; 771 local links and 315 history test references |

PR 297 gains first partial evidence for common nested Machine usage. PRs 223
and 233 gain raw-error and stored-inspection evidence. There are 40 partial
history rows and 315 concrete test references; all 126 statuses remain pending.
CLI adapters, direct worker APIs, capability Plugins, other methods, generated
media streaming, state conversion and root package gates remain open. No
commit, push or publication was made.

## AoT shared Flow and result slice

The [09_03 example](../../examples/v3/profiles/09_03_aot.md) adds 24 integration
cases and a port of one default lifecycle case. AoT keeps its current algorithm:
one model generation with in-context search examples and a structured parser
result. There is no host-side DFS/BFS search loop. Native DSL/data/Builder/source
JSON, direct Flow and ordinary Agent paths use the same existing Flow.

`reasoning.options` holds the AoT prompt profile, search preference, examples
and explicit-answer rule. The common profile validates those settings before
execution. Model temperature and token settings remain generation options,
with AoT defaults 0.0 and 2048. The public wrapper keeps its legacy example
string conversion and invalid-temperature fallback. An initial full run exposed
an empty-options source-JSON regression; normalization now omits that empty key,
so existing registries do not need a new atom identifier.

The simplification pass adds a small shared method adapter for prompt framing,
result projection and method labels. It adds no execution owner. AoT's Machine
and Result moved into shared code. Finite transitions replace Fsmx. The seven
retained Machine tests run unchanged. Missing map status now becomes idle;
usage uses the common projection and retains provider metadata. The old Strategy
module is a deprecated get_result adapter. Method selection and stored result
inspection use the namespace, with an optional request ID.

The public AoTAgent now delegates explore/explore_sync/await to the common Agent.
It retains result extraction, declared-option inspection, last_prompt,
last_result, completion fields and Signal namespaces. Request contexts are
fresh by default. The native result retains answer, found-solution flag, search
counts, raw response, measured usage, termination and diagnostics. Output
controls and successful Agent commits receive that complete map.

A declared result schema validates the AoT answer field. The model keeps its
search-text prompt and puts JSON on the final answer line. Shared Output
validation and bounded repair retain the AoT envelope. A configured callback
can supply the typed answer without another model call; its diagnostics do not
invent model search steps. Exhaustion, missing answers and rejected output
preserve domain state. The example documents this schema-to-field mapping.

Provider and control failures keep the AoT failure result, display text and
structured cause. The existing session accounting supplies measured usage in
the error result. Empty ordinary text is no solution; empty truncated text keeps
an incomplete-response error. Nonempty partial text with a valid answer can
complete after a token limit, as required by the accepted partial-content rule.
Actual transport failure does not imply a successful partial answer. Complete
transport-error delta retention remains an open case.

The same canonical events, typed Signals and telemetry now carry :aot identity.
Telemetry and Signal policy flags stay independent. Known cause types survive
method failure wrapping. Live request terminal duration is now measured by the
Session owner's monotonic clock. Ordinary output telemetry has agent_turn
origin; actual session work keeps worker_runtime origin. No core source changed.

The migrated historical AoT lifecycle case is in the default temporary suite,
as required by PRs 231 and 309. It retains the number-puzzle answer and the
start/completion Signal and telemetry contract, now over real HTTP/SSE and
Agent/Flow execution. Measured provider usage replaces injected counters, and
a held response checks nonzero duration. The original root mixed-method file
still awaits suite transfer; it has not passed a v3 run.

| Check | Result |
| --- | --- |
| Full acceptance project, integration enabled, seed 0 | 420 passed; no pending case excluded |
| New AoT cases | 24 integration cases and 1 default lifecycle case passed |
| Retained shared suite, including seven unchanged AoT Machine tests | 261 passed |
| Default acceptance run | 14 passed; 406 integration cases excluded as intended |
| Forced production/example compile with warnings as errors | 110 files compiled; passed |
| Formatting, whitespace, links and history test references | Passed; 780 local links and 332 history test references |

PRs 231 and 309 gain first partial evidence. PRs 233, 239, 299 and 310 gain AoT
result, partial-content, error and observation evidence. There are 42 partial
history rows and 332 concrete test references; all 126 statuses remain pending.
CLI/capability entry points, full old callback coverage, generated media output,
complete partial-transport retention, state conversion and root package gates
remain open. No commit, push or publication was made.

## Native Tree of Thoughts search through shared Flow

The [09_04 profile](../../examples/v3/profiles/09_04_tot.md) adds 23 excluded-by-default
integration cases for the native ToT method. The
[Agent example](../../examples/v3/lib/examples/09_reasoning/09_04_tot/agent.ex)
uses the same model, tool, control and request declarations as other methods.
The public ToT facade is still a separate pending port.

The refinement pass kept one execution owner. A small method adapter prepares
search data, advances generation/evaluation and supplies the next model context.
The existing ReasonFlow and ToolsFlow run all work. Tool follow-ups stay within
the phase and use the common preflight, callbacks, ordering, effects and usage
path. No new runtime process or execution loop was added. DSL, data, Builder
and source JSON produce the same definition; direct Flow returns the same
ranked result contract.

Machine and Result moved to shared code with unchanged module names. Explicit
finite transitions replace Fsmx. The legacy transition callback remains callable.
The Machine retains its legacy telemetry by default, but native execution uses
only common request observation. Nested usage uses the shared merger. The
18 retained Machine/Result tests pass unchanged against v3 dependencies.

The real provider test found that streamed JSON can become a ReqLLM object with
an empty text field. The adapter now consumes that object. Numbered thought
parsing and default score fallback remain available. Parser repair is bounded,
uses a real model call and does not advertise tools. The common request policy
removes tools after a request transformer, so a transform cannot enable repair
tools again. An unsolicited repair tool
call fails before execution. Generation and evaluation have separate tool-round
limits; all actual provider calls have distinct call IDs and shared request IDs.
Phase identity reaches canonical events, typed Signal metadata and telemetry.

Search tests cover BFS, DFS, best-first, minimum depth, threshold, convergence,
beam width, top-k, node count, branch count and duration. A limit review found
that the old node budget could be exceeded by the last batch. Accepted thoughts
are now limited before evaluation and node creation. A root-only node budget
fails before a provider call. Search duration is checked after evaluation; the
common total deadline stops an active transport. These remain separate controls.

Ranked results retain candidates, paths, topology, termination, usage and
parser/tool diagnostics. Output controls receive the complete map before a
state write. Failure keeps structured causes and common measured usage.
Cancellation and owner loss terminate old work and allow a later request.
A reverse-completion tool test waits for the second Action to finish before
releasing the first; the provider still receives results in declared call order.

The simplification check keeps method state local to the shared Flow and retains
complete result maps. Unsupported native contracts fail explicitly: text queries
work, while steering and declared typed ToT results remain pending. Old public
ToTAgent, namespace helpers, Strategy callbacks, CLI and capability Plugin remain
v2 code. Do not infer their acceptance from native Flow examples. The exact
PR 347 alias/state case and full provider/control/callback failure matrix remain
for the next ToT slice.

| Check | Result |
| --- | --- |
| Full acceptance project, integration enabled, seed 0 | 443 passed; no pending case excluded |
| Native ToT integration cases | 23 passed |
| Retained shared suite, including 18 unchanged ToT Machine/Result tests | 279 passed |
| Default acceptance run | 14 passed; 429 integration cases excluded as intended |
| Forced production/example compile with warnings as errors | 114 files compiled; passed |
| Formatting, whitespace, links and history test references | Passed; 792 local links and 349 history test references |

PRs 231, 297, 299, 309, 310 and 347 gain partial native ToT evidence. There are
42 partial history rows; all 126 statuses remain pending. Root mix files are
unchanged and the root package is not yet on v3. No core source changed in this
slice. No commit, push or publication was made.

## Public Tree of Thoughts API and PR 347 callbacks

The [09_05 profile](../../examples/v3/profiles/09_05_tot_api.md) adds 28
integration cases. The public ToT macro now lowers through `Jido.AI.Agent`.
Explore helpers, search defaults, custom generation settings, retained results,
failed nodes, cancellation reasons and the old inspection helpers use the
existing Flow and Session. Old Strategy names keep deprecated getters only.
The source inventory stays pinned to the original commit.

The PR 347 example now runs the long-key alias workflow in a ToT session and an
ordinary Agent turn. Real Actions supply the list and consume the restored key.
Core Exec delivers each raw final retry result to the after callback. The
shared path then filters effects and creates canonical/model results. Direct
Exec still uses original Action keys without AI interception. The profile maps
old inbound tool-result Signals to core execution and observations.

Callback tests cover all specified before/after failure modes, trusted identity,
context precedence, denied alias effects and partial batch failure. A later
callback error keeps completed tool evidence without committing earlier staged
effects. The test exposed a missing error boundary in `Runtime.NextBatch`.
The operation now captures the known AI cause before core Flow wraps it, so
Session retains the failed tree envelope. No general core-error unwrapping was
added. Actual tool I/O remains outside state rollback.

The simplification pass kept one lowerer, request owner and tool executor.
Tool context retains the authoritative snapshot from before admission, plus
staged effects. Public state projections remain separate. Search getters read
retained records; active frontier inspection remains a named gap.

The option review found that the generic ten-call limit could stop a valid ToT
search. The public wrapper now derives a finite model-call budget from node,
tool-round and parser limits. A 16-call search with 12 tools verifies it. The
public tool-call default is also explicit. The old `max_duration_ms` provider
timeout mapping is retained, with an explicit override. A held SSE response
proves connection cleanup and failed-result retention. Native search duration
and the hard whole-request deadline remain separate controls.

| Check | Result |
| --- | --- |
| Full acceptance project, integration enabled, seed 0 | 471 passed; no pending case excluded |
| Public ToT integration cases | 28 passed |
| Retained shared suite | 279 passed |
| Default acceptance run | 14 passed; 457 integration cases excluded as intended |
| Forced production/example compile with warnings as errors | 118 files compiled; passed |
| Formatting | Passed |
| Whitespace, local links and history test references | Passed; 806 links and 380 references |

PRs 231, 297, 299 and 347 gain partial public evidence. There are 42 partial
history rows and 380 concrete test references. All 126 statuses remain pending.
Full model-input/state override parity, typed ToT output, rich input, live tree
inspection, provider variants, old command hooks, CLI/capability paths and
durable recovery remain open. Root mix files remain unchanged. The root package
has not passed a v3 compile. No commit, push or publication was made.

## Method response and transform refinement

Three additional native ToT cases test actual provider length limits. The first
failed before the fix: ReqLLM had decoded complete JSON into an object with no
text, so the common terminal check rejected it. The check now accepts a decoded
object before method validation. Valid thoughts and scores complete; an invalid
object still needs bounded parser repair. An empty length-limited evaluation
fails with measured usage and no domain result write. A later request succeeds.

One additional AoT case exposed a separate request-transform defect. The
transform path added the answer schema to the provider request, despite the
method's text-and-final-answer contract. It now uses the existing method schema
function. Initial and repair requests retain AoT framing, refresh actual HTTP
headers and commit the complete validated result. This reuses the common method
rule; it adds no provider-specific logic or separate repair path.

The focused AoT, ToT and request-transform suite has 65 passed. The full
acceptance run has 475 passed. The native ToT profile now has 26 integration
cases; AoT has 25 plus its retained default lifecycle case. The public ToT
profile still has 28. PRs 239 and 343 gain partial evidence. There are 42 partial
history rows and 384 concrete test references; all 126 statuses remain pending.
Complete provider variants, generated media, other methods, recovery and root
package gates remain required.

Final checks for this refinement pass: the default run has 14 passed and 461
integration cases excluded. The forced build compiles 118 files with warnings
as errors. Formatting and whitespace checks pass. All 806 local links and 384
history test references resolve. Root mix files remain unchanged.

## Native Graph of Thoughts through shared Flow

The [09_06 profile](../../examples/v3/profiles/09_06_got.md) adds 22 integration
cases for native graph generation, connection discovery and synthesis. One
method adapter prepares phase messages and advances the retained Machine.
Core Agent/Flow/Exec and the existing Session still own execution. The Agent
result remains text; completed request metadata retains graph data and usage.
DSL/data/Builder/source-JSON, direct Flow and ordinary Agent turns all execute.

The Machine moved to shared code under the same module name. Finite transitions
replace Fsmx. All 41 original Machine tests pass unchanged. Those tests found
that the initial usage port omitted totals when only input/output counts were
present. Each incoming call now derives a missing total before the common
nested-metadata merge. Native observation uses common phase identity; the
compatibility Machine retains its legacy telemetry by default.

The PR 314 case returns a connection using actual node IDs from the model
request. Later generation sees each ancestor once. Separate graph data cases
cover a diamond, disconnected node, root/leaf and bounded cycle. The unified
mock gained one request-based reply form, with its own default contract test.
It runs in the connection worker and cannot replace Agent state or tool work.

The refinement pass found that the old aggregation-mode option was stored but
did not select voting/weighted execution. Default search usually synthesized
one leaf. Distinct mode behavior, general branching and aggregation across
several leaves remain explicit requirements. Setting retention is not proof
of those algorithms. Native method options now expose the existing aggregation
threshold, and explicit phase prompts override Machine defaults. The profile
records both decisions and the old prompt-precedence defect.

Tests also cover native generation options, root/node/depth limits, the common
call budget, output rejection, unsolicited tools, empty failed responses,
cancellation, deadline and owner interruption. Tools remain disabled even after
a request transformer. Failed searches retain graph evidence without domain
result writes. Busy native calls retain the core typed error; public GoT mapping
is still pending.

| Check | Result |
| --- | --- |
| Full acceptance run, integration enabled, seed 0 | 498 passed; no pending case excluded |
| Native GoT cases | 22 passed |
| Retained shared suite, including 41 unchanged GoT Machine cases | 320 passed |
| Default run | 15 passed; 483 integration cases excluded |
| Forced production/example compile with warnings as errors | 121 files compiled; passed |
| Formatting and whitespace | Passed |
| Local links and history test references | 816 links and 400 references resolve |

PRs 223, 231, 239, 297, 299, 310 and 314 gain partial evidence. There are still
42 partial history rows; all 126 statuses remain pending. Public GoT macros and
namespace/Strategy mapping, runtime state overrides, CLI/capability paths,
typed/rich contracts, complete provider variants, active graph inspection and
durable resume remain required. Root dependencies remain on v2. No core source,
commit, push or publication changed in this slice.

## Public GoT API and bounded graph inspection

The [09_07 profile](../../examples/v3/profiles/09_07_got_api.md) adds 11 public
API integration cases. GoTAgent now supplies method settings to the common
Agent lowerer. The common Agent can also select GoT directly. Both use the same
Flow, Session, model controls and result commit. The old namespace prompt and
call-ID helpers remain, and five deprecated Strategy getters inspect retained
records. Old Strategy execution callbacks are removed.

The examples prove separate completed graphs, empty inspection for a pending
request, explicit earlier-request reads, custom model/prompt settings, raw
failure causes and printable public state. Failed `last_result` text does not
duplicate the complete graph. A 14-call search retains all 210 tokens within
its node budget. The public call limit is derived from that budget.

The refinement pass found two defects. The old solution-path helper could loop
through its first-parent chain. A bounded test now proves that it can skip a
cycle, use another valid parent path and return no path when all chains cycle.
The retained acyclic Machine tests still pass. Busy admission also had two
error forms, depending on whether core or the Start Action refused the call.
The request helper now returns `{:error, :busy}` for both and sends the same
reason to the rejected stream. Existing session and linear examples verify
that this change preserves the original request and duplicate-ID protection.
Direct core errors and other typed admission errors are not broadly unwrapped.

The rejected-stream test exposed another gap: before a job exists, its event
constructor still uses a legacy default method. The next observation case must
derive authoritative method identity, including custom routes, without claiming
that rejected work ran. This remains open.

| Check | Result |
| --- | --- |
| Full acceptance run, integration enabled, seed 0 | 509 passed; no pending case excluded |
| Public GoT cases | 11 passed |
| Focused GoT, retained Machine, linear and session run | 133 passed |
| Retained shared suite | 320 passed |
| Default run | 15 passed; 494 integration cases excluded |
| Forced production/example compile with warnings as errors | 125 files compiled; passed |
| Formatting and whitespace | Passed |
| Local links and history test references | 829 links and 412 references resolve |

PRs 223, 231, 297, 299 and 314 gain partial evidence. There are still 42 partial
history rows; all 126 statuses remain pending. Distinct graph aggregation
algorithms, general branching, runtime state overrides, typed/rich contracts,
CLI/capability paths, complete provider variants, active graph inspection,
durable recovery and root package checks remain required. No root dependency,
core source, commit, push or publication changed in this slice.

## Native TRM checkpoint: 2026-09-07

The [09_08 Agent example](../../examples/v3/profiles/09_08_trm.md) adds 24
integration cases. Its first compile failed because the v3 profile did not
accept TRM. The port now admits the method and uses a small phase-data adapter
inside the existing Flow. Model calls, output control, failure, cancellation,
request settlement and domain commit stay in the common runtime.

Machine, ACT, Reasoning, Supervision and Helpers retain their module names.
They moved into the shared production compilation set. Finite transitions
replace Fsmx. The Machine uses the shared nested usage merge and adds a missing
total when both counters are present. It keeps legacy events for direct callers;
native requests use only the common event path. All 204 retained tests for
these five modules pass unchanged. Their existing underscored-variable warnings
in Supervision tests remain test-source warnings; the forced production compile
passes with warnings as errors.

The examples verify all five review cycles with 15 actual model calls, the
highest scored answer, the zero-score fallback, bounded latent trace, previous
feedback, ACT threshold/convergence and maximum-step precedence. The existing
near-maximum quality stop retains its legacy threshold termination label even
when the configured threshold is higher. Each phase failure retains its actual
cause and usage. An output rejection prevents the domain write. Cancellation,
a deadline, owner loss and a later request use the common Session. DSL, source
data, Builder, registered source JSON, direct Flow and ordinary Agent turns
execute the same method.

The refinement pass kept two TRM settings and the shared model/control fields.
Optional native instructions precede the required phase prompt. No private
executor or extra owner was added. The first mock script used QUALITY instead
of the existing SCORE marker; it was corrected rather than changing the parser.
The support-module text filters remain compatibility behavior and do not claim
a general security boundary. The original namespace/Strategy, public macro,
runner and capability code still need their separate port.

| Check | Result |
| --- | --- |
| Full acceptance run, integration enabled, seed 0 | 533 passed; no pending case excluded |
| Native TRM integration cases | 24 passed |
| Retained TRM support-module tests | 204 passed |
| Retained shared suite | 320 passed |
| Default run | 15 passed; 518 integration cases excluded |
| Forced production/example compile with warnings as errors | 132 files compiled; passed |
| Formatting and whitespace | Passed |
| Local links and history test references | 846 links and 441 references resolve |

PRs 223, 231, 233, 239, 297, 299 and 314 gain partial evidence. There are still
42 partial rows; all 126 history statuses remain pending. Public TRM helpers,
old command/phase-input conversion, runtime overrides, CLI/capability APIs,
complete provider/media contracts, active state inspection and durable recovery
remain required. Typed results, rich input, tools and steering are rejected in
this native slice. The shared admission-failure method-identity gap remains
open. No root dependency, core source, commit, push or publication changed.

## Public TRM checkpoint: 2026-09-07

The [09_09 Agent example](../../examples/v3/profiles/09_09_trm_api.md) adds 12
public API cases. Its first compile failed because the old TRMAgent module was
outside the v3 compilation set. The new wrapper now supplies settings and
reason/sync aliases to the common Agent. The common Agent can also select TRM
directly. Both use the same native profile, Flow and request owner.

The wrapper retains its default alias and description, two method settings,
text-only reason guards, declared options, string convenience fields and
await contract. Its default budget allows three calls per supervision cycle,
capped at the common limit. A real five-cycle request now proves 15 calls and
225 tokens through the public API. Explicit limits stop at the expected phase.
Generation options and the default model alias are tested at the provider.

Six namespace getters read retained request data with an optional request ID.
They keep the selected scored answer distinct from the latest improvement.
Failed improvement keeps prior review data and the canonical cause; printable
legacy result text remains a separate field. Pending requests clear convenience
state while older completed records remain inspectable. The old Strategy name
has only deprecated getter and prompt delegates. Its execution callbacks and
action atoms are removed. Call-ID and prompt helpers retain their names.

The refinement pass keeps the wrapper to authoring settings and public aliases.
It adds no command loop, request store or phase executor. Public streams and
cancellation use the inherited common APIs. The stream has ordered phase events
and one selected-answer terminal event. Cancellation closes active improvement
transport, retains prior usage, rejects busy input and permits a later request.

| Check | Result |
| --- | --- |
| Full acceptance run, integration enabled, seed 0 | 545 passed; no pending case excluded |
| Public TRM integration cases | 12 passed |
| Focused public/native TRM, public GoT and common Agent run | 58 passed |
| Retained shared and TRM support-module suite | 524 passed |
| Default run | 15 passed; 530 integration cases excluded |
| Forced production/example compile with warnings as errors | 136 files compiled; passed |
| Formatting and whitespace | Passed |
| Local links and history test references | 858 links and 451 references resolve |

PRs 223, 231, 233, 297, 299 and 314 gain partial evidence. All 126 history
statuses remain pending; 42 rows have partial evidence. Active phase inspection,
custom command hooks, old phase-input/state conversion, runtime model/state
overrides, CLI/capability APIs, complete provider/media contracts and durable
recovery remain open. The shared rejected-admission method-identity gap also
remains open. Root dependency, package, consumer, minimum-runtime, migration and
rollback gates are unchanged. No commit, push or publication was made.

## Native Adaptive checkpoint: 2026-09-07

The [09_10 Agent example](../../examples/v3/profiles/09_10_adaptive.md) adds
28 integration cases. Its first compile failed because the profile did not
accept Adaptive. The port extracts the existing pure selection rules, checks
configuration and selects a method profile before the shared model Flow starts.
Selection makes no model call and repeats for each request. The old Strategy
now delegates its pure analysis helper to the same selector.

Actual requests prove all seven methods, tools under ReAct and ToT, custom
thresholds, an explicit override, per-method settings and ordinary core Actions
during AI work. Non-tool methods keep an empty provider catalog, including after
a request transformer. Typed output is checked against the chosen method and
bounded AoT repair keeps that method. The original empty-list analysis fallback
remains available to direct helper callers; native runtime configuration rejects
an empty list. The unused legacy default_strategy option is not a native setting.

Selection data stays in canonical result and error metadata. The outer request
still identifies Adaptive; model Signals and telemetry also identify the chosen
method. Cancellation, owner loss, a deadline, output rejection and call limits
use the existing Session and preserve known selection and usage. No separate
method executor, model selector process or request store was added.

| Check | Result |
| --- | --- |
| Full acceptance run, integration enabled, seed 0 | 573 passed; no pending case excluded |
| Native Adaptive integration cases | 28 passed |
| Focused Adaptive, retained selection, linear and AoT run | 102 passed |
| Retained shared, TRM and selection suite | 540 passed |
| Default run | 15 passed; 558 integration cases excluded |
| Forced production/example compile with warnings as errors | 138 files compiled; passed |
| Formatting and whitespace | Passed |
| History test references | 477 references resolve |

Commit e2b2d275 gains partial dispatch evidence. PRs 231, 233, 297, 299 and
314 gain related evidence. There are now 43 partial rows; all 126 history
statuses remain pending. Public Adaptive authoring and inspection, printable
public failure state, custom hooks, old command and state conversion, runtime
overrides, live inspection, CLI/capability paths, full provider/media behavior
and durable recovery remain required. The rejected-admission method-identity
gap and all root package/release gates remain open. No root dependencies, core
source, commit, push or publication changed.

## Public Adaptive checkpoint: 2026-09-07

The [09_11 Agent examples](../../examples/v3/profiles/09_11_adaptive_api.md)
add 22 integration cases. The initial compile failed because the old public
AdaptiveAgent was outside the v3 compilation set. The new wrapper lowers into
the common Agent. The namespace retains analysis and adds retained-request forms
of the old Strategy getters. Strategy execution callbacks and action atoms are
removed. Deprecated analysis and one-argument getters remain loadable.

The examples execute all seven methods. They prove default and custom aliases,
declared settings, binary prompt guards, typed results, printable public state,
retained selection, real tool callbacks, actual HTTP failures, bounded repair,
streams and cancellation with a different later choice. A pending request clears
its convenience fields while older completed selections stay available by ID.
The canonical request retains the structured result or actual error cause.
PR 234 gains partial evidence from these display and failure boundaries.

The refinement pass found a quoted-data error for nested method settings. The
wrapper now escapes evaluated option data before it calls the common macro.
The pass also put ToT, GoT and TRM call-limit formulas into one shared helper.
Adaptive derives its outer default budget from the available methods. A complete
TRM run makes 15 actual calls and retains 225 tokens. Explicit controls win.
The larger outer budget also applies to ReAct, so exact per-method default
control preservation remains an explicit follow-up before package cutover.
The old default_strategy field remains an unused compatibility inspection value;
strategy_override is the explicit native control for a fixed choice.

Three initial test failures assumed the wrong existing contract: an atom for
a shared control error, an unwrapped tool result and a boolean repair flag.
The cases now assert the actual validation error, model-facing result envelope
and repaired status. They did not require a runtime behavior change. Selected
ReAct generation now uses the shared 4096-token and 0.2-temperature defaults;
explicit provider options retain precedence. Production and example compilation
passes with warnings as errors.

| Check | Result |
| --- | --- |
| Full acceptance run, integration enabled, seed 0 | 595 passed; no pending case excluded |
| Public Adaptive integration cases | 22 passed |
| Focused public/native Adaptive and public ToT/GoT/TRM run | 101 passed |
| Retained pure-selection suite | 16 passed |
| Default run | 15 passed; 580 integration cases excluded |
| Forced production/example compile with warnings as errors | 142 files compiled; passed |
| Formatting and whitespace | Passed |
| History test references | 500 references resolve |

Commit e2b2d275 and PRs 231, 233, 234, 297, 299 and 314 gain partial evidence.
There are now 44 partial rows; all 126 history statuses remain pending. Active
selection inspection, custom command hooks, old worker/phase-input and state
conversion, runtime overrides, per-method default controls, CLI/capability and
skill/resource paths, complete provider/media behavior and durable recovery
remain required. The shared rejected-admission method-identity gap and all root
package/release gates remain open. No root dependencies, core source, commit,
push or publication changed in this slice.

## Selected method controls: 2026-09-07

The [09_12 example](../../examples/v3/profiles/09_12_method_controls.md) adds
19 cases. Existing count controls accept `:method_default`. Static profiles
retain that policy. The common Prepare path resolves counts after method and
request output selection. This fixes the initial Adaptive combined-budget bug:
ReAct stops at ten calls while the same Agent can complete fifteen TRM calls.
Explicit Agent, request and native integer limits remain effective.

The refinement pass moved resolution from profile construction to runtime.
A fixed native method can then accept a per-request output schema and keep its
repair allowance. Actual Actions verify whole-batch tool bounds. DSL, data,
Builder, registered source JSON, direct Flow and ordinary turns each complete
a full TRM run. No second executor or new Adaptive option was added.

The full suite passes 614 tests; the focused method-control and Adaptive run
passes 69. The default run has 15 passed and 599 excluded integration cases.
Production/example compilation passes with warnings as errors for 143 files.
Formatting, whitespace and 515 history references pass. All 126 history
statuses stay pending; 44 rows have partial evidence. Active selection,
state/command conversion, runtime state overrides, capability/CLI/skill paths,
durable recovery and root package/release gates remain open. Failed-record
model-call counts need further work; actual HTTP counts and usage prove the
failure paths in this slice. Root dependencies are unchanged.

## Active Adaptive selection: 2026-09-07

The [09_13 Agent example](../../examples/v3/profiles/09_13_active_selection.md)
adds eight integration cases. Selection commits after input controls and method
preparation, before the first provider call. Public getters and the compatibility
state field can inspect that committed selection while the request is pending.
Older request IDs retain their selection. A three-phase request commits it once.

The existing Session owner grants each update with a request ID, run ID and
one-use ticket. The progress Action reads the owner's grant, not selection data
from the Signal. Host Plugins still control admission. A fresh core Turn supplies
current Agent state; the worker's old state and private AI bindings are removed
from caller context. This preserves an unrelated domain change made during input
control. Invalid grants, consumed grants and updates after cancellation fail.
Only known pre-execution busy/reentry errors are retried within the deadline.
An unknown commit outcome is not replayed. No second AI executor or owner was
added. Recovery now keeps metadata from the committed request record.

The full AI run exposed a core restart deadlock: the replacement Session owner
waited for Agent state while the lifecycle wrapper waited for Session readiness.
An Agent runtime lookup then waited for that wrapper. The generic core
[Plugin child](../../../jido/lib/jido/agent_server/plugin_child.ex) now runs the
restart readiness callback in an owned task. Runtime lookup stays responsive
and reports unavailable until readiness succeeds. Owner shutdown stops the task;
readiness failure stops the owner. The deterministic
[Agent-state regression](../../../jido/test/jido/agent_server_runtime_test.exs)
failed before the fix. The
[lifecycle cases](../../../jido/test/jido/agent/plugin_lifecycle_test.exs) also
check task loss and shutdown while readiness is pending. The focused core run
passes 57 tests. The full AI run now passes all 622 cases, including the restart
case that failed before the core fix.

| Check | Result |
| --- | --- |
| Full AI acceptance run, integration enabled, seed 0 | 622 passed; no pending case excluded |
| Default AI run | 15 passed; 607 integration cases excluded as intended |
| Forced AI production/example build with warnings as errors | 145 files compiled; passed |
| AI production/example formatting and changed-file whitespace | Passed |
| History references | 525 references resolve; 44 partial rows; all 126 statuses pending |
| Focused active-selection, method-control, Adaptive and Session run | 103 passed |
| Focused core runtime and lifecycle cases | 57 passed |
| Full core suite with coverage, examples and flaky tests, seed 0 | 1,265 passed; the same 11 research failures; one approved exclusion |
| Total core coverage | 93.9% |
| Core compile with warnings as errors, warning lint and Dialyzer | Passed; zero Dialyzer errors |
| Core formatting, docs with warnings as errors and local Hex build | Passed |

Core logs are `/tmp/jido-ai-v3-readiness-core-*`. The 11 research failures match
the earlier baseline; the fix adds no new failure. This is not a passing core
release claim. The declared Elixir 1.18 / OTP 27 floor remains untested here.

Active ToT/GoT/TRM phase data, command and state conversion, runtime overrides,
capability/CLI/skill paths, full provider behavior, durable recovery and the
rejected-admission method-identity gap remain open. The root AI dependencies
remain unchanged. No history row is marked fully ported from these cases.

The next usage refinement should reuse the Session's existing model-start
counter. It must distinguish started logical model calls from HTTP retries,
completed responses and token usage. Failure before model work can prove zero;
owner loss without a committed counter cannot. Add cases for control rejection,
provider failure, cancellation, repair and repeated terminal observation before
changing that metadata contract. This review adds no counter implementation.

## Callable reasoning: 2026-09-07

The [09_14 Agent example](../../examples/v3/profiles/09_14_callable_reasoning.md)
adds 20 cases for the production RunStrategy Action. All seven methods now use
one source-profile factory, the common Authoring lowerer and the existing
Agent/Session/Flow implementation. The first seven cases failed because the old
Action was outside the v3 compilation set. The port then exposed removed core
Action metadata options and a linked-Server shutdown that discarded its caller's
result. Explicit catalog accessors and normal Server shutdown fixed those paths.

The runtime review found that an implicit global Jido instance could be owned by
its first short-lived caller. The port removes that lifetime dependency. A call
can use `context.jido` to select an existing host, or run a standalone core Agent.
The caller owns the linked Agent and its Session. Concurrent calls have separate
request/run IDs; one call's cleanup leaves the other and their host alive.
Exec cancellation and timeout close the actual provider connection. The seven
unused internal Runner macro modules are removed; the public Action remains.

The result keeps strategy, status, output, usage and diagnostics. AoT and ToT
retain structured method results on success and failure. Committed records
supply the compatibility snapshot fields. Failed later phases retain prior usage
and method diagnostics. A full default TRM request makes 15 calls and reports
225 mock tokens. Existing defaults and explicit parameter precedence reach the
actual HTTP request. Parent Agent state and private AI bindings are removed from
new admission context by the same helper used for progress commits.

The simplification pass removed the old runner dispatch table, seven wrappers,
private state-override construction and dead snapshot fallbacks. One mock server
supplies every test, including two concurrent request barriers. A ToT assertion
was corrected after source inspection: generated thoughts remain pending until
scored, so evaluation failure does not install them as tree nodes. The test
retains the actual method result and completed usage without inventing nodes.

| Check | Result |
| --- | --- |
| Full AI acceptance run, integration enabled, seed 0 | 642 passed; no pending case excluded |
| Callable reasoning cases | 20 passed |
| Default run | 15 passed; 627 integration cases excluded as intended |
| Forced production/example build with warnings as errors | 147 files compiled; passed |
| Production/example formatting and changed-file whitespace | Passed |
| History references | 544 references resolve; 44 partial rows; all 126 statuses pending |

Logs are `/tmp/jido-ai-v3-callable-*`. Core source did not change in this slice;
its previous 1,265 passing tests, 11 research failures and 93.9% coverage remain
the recorded core results. Local Action and Signal trees stay clean. The root AI
`mix.exs` and lockfile remain unchanged; this is not a passing root package.
Capability Plugin declarations, CLI dispatch, complete legacy option/metadata
parity, nested AI-tool budget aggregation, cold catalog timing, state conversion,
durable recovery, minimum-runtime and package/consumer gates remain required.
No commit, push or publication was made. The full migration goal stays active.

## Reasoning capability Plugins: 2026-09-07

[Example 16_01](../../examples/v3/profiles/16_01_reasoning_capabilities.md)
ports all seven `Jido.AI.Plugins.Reasoning.*` modules. The modules moved into
`authoring/plugins/reasoning`; their public names and Signal namespaces remain.
One shared adapter now owns the repeated declaration/schema/preparation code.
The explicit `RunCapability` route calls `RunStrategy` through Exec and returns
the complete Agent candidate. The domain result field is explicit. No new DSL
keyword, execution loop or Plugin runtime was added.

The example combines two capabilities and an ordinary route, and combines a
capability with a native AI profile. All seven methods execute against the same
mock server implementation. Tests check fixed identity, defaults, explicit
model/timeout/options, Plugin order, forged private context, domain result
selection, failure isolation and timeout cleanup. The old callback unit tests
now check v3 initialization, restored defaults and protected state. The example
contains the public API replacement table.

The first seven integration tests failed because the v2 Plugins were absent
from the v3 build. The expanded tests then found a real configured-default loss
on empty restored state. A second real failure was in core: `state_spec/1`
exceptions were mistaken for `{state_key, schema}`. Core now preserves an error
tuple before that clause. Two core tests cover raise/throw/exit and a returned
structured error through `Jido.Agent.new/1`. This does not add callbacks or
change Plugin ownership.

| Check | Result |
| --- | --- |
| New capability integration + native Plugin contracts | 38 passed: 17 integration and 21 focused cases |
| Full AI acceptance suite, integration enabled, seed 0 | 659 passed in 92.4 seconds; no required pending case excluded |
| Default acceptance suite | 15 passed; 644 integration cases excluded |
| Forced acceptance build with warnings as errors | Passed; 157 files compiled |
| Selected production, examples and changed contract-test formatting | Passed |
| Core Plugin validation and Agent Plugin tests | 32 passed on the final exception guard |
| Full core before the final exception guard | 1,267 passed, 11 known research failures, one approved exclusion; 93.9% coverage |
| Final core full run, coverage and repeated checks | 1,268 passed, the same 11 research failures, one approved exclusion; 93.9% coverage; all quality/package checks passed |
| Core formatting, compile, lint, Dialyzer, docs and package after the initial full run | Passed |
| History references and document links | 557 references and 928 local links valid at this check |
| Whitespace and root dependency/lockfile checks | Passed; root dependencies unchanged |

Partial evidence was added for the Plugin-choice and ordinary-route reports
(PR 263 and PR 281), callable dispatch and cancellation. Forty-six history rows
now have partial evidence. All 126 statuses remain pending. Do not count the
native capability examples as proof of legacy default-Plugin conversion or all
old route source forms.

The last core refinement permits `:error` as a valid Plugin state key. The
error clause now matches exception structs only. A direct constructor probe
failed with the broad clause and passed with the guard. The 38 capability and
Plugin contract cases passed again on the guard. A third core regression test
covers the valid field name. The initial full core run used the broader clause;
the final focused run passed all 32 cases. The final full run completed in
549.4 seconds with the same 11 known research failures. Formatting, compilation,
required lint, Dialyzer, docs and package checks all passed. Results are in the
separate `capability-final-core` logs.

This is a simplification checkpoint for milestone 5. Other capability families,
complete method options and metadata, active phase inspection, CLI, nested
AI-tool budgets, state conversion and durable recovery remain required. The
root package is still on its v2 dependency baseline. Final dependency, consumer,
minimum-runtime, migration and rollback gates remain open. Nothing was committed,
pushed or published.

## Planning Actions and capability: 2026-09-07

[Example 08_01](../../examples/v3/profiles/08_01_planning.md) ports Plan,
Decompose, Prioritize and the Planning Plugin. Their sources moved into the
selected production directories. Names, catalog metadata, prompts and public
result maps remain. The shared request helper replaces repeated preparation of
defaults, model input and provider options. All three Actions use the common
model boundary. Core pre-validation records supplied keys before Zoi adds
defaults; explicit default-valued parameters retain precedence.

Eighteen integration cases use the one HTTP mock for direct, Exec and live
capability calls. They check prompts, parsed results, depth limits, score forms,
empty parser fallback, model/default precedence, string input, raw content blocks,
usage, headers, bad input, failure and cancellation. A held connection proves the
request timeout ends work before the outer Exec deadline. Twelve native
schema/catalog/Plugin tests replace the old manifest/callback and provider-stub
tests. The DSL example combines Planning, reasoning and an ordinary route.

The shared `Capability` helper now validates the result field and assembles the
complete candidate for both capability families. It uses core Exec and adds no
new execution loop, DSL keyword, or runtime process. Plugin defaults remain
protected. Explicit caller action/result-field data cannot replace the binding.
A failed provider call preserves prior committed state.

The first three cases failed because the v2 Actions were unavailable. The first
port exposed an alias-order compile error, which was fixed. Expanded tests then
found three real boundary defects: a current Agent struct did not support the
old Access call, false defaults were skipped, and trailing empty score captures
lost parenthesized/range scores. The fixes retain the original prompts and parser
shapes. A failing RunStrategy test exposed the same Agent-struct access issue;
it now uses map-safe access and passes. This is a shared-operation and
capability simplification checkpoint.

| Check | Result |
| --- | --- |
| Focused Planning, reasoning, callable and native API/Plugin cases | 89 passed |
| Full AI acceptance suite, integration enabled, seed 0 | 678 passed in 92.2 seconds; no required pending test excluded |
| Default acceptance suite | 15 passed; 663 integration cases excluded |
| Forced acceptance compile with warnings as errors | Passed; 165 files |
| Selected production/example/changed contract-test formatting | Passed |
| Final core checks from the preceding capability guard | 1,268 passed; same 11 research failures; one approved exclusion; 93.9% coverage |
| Core formatting, compile, required lint, Dialyzer, docs and package | Passed |
| History ledger | 563 references; 47 rows with partial evidence; all 126 statuses pending |
| Whitespace, local links and root dependency/lockfile checks | Passed; root dependencies unchanged |

Logs use `/tmp/jido-ai-v3-planning-*`; final core logs use
`/tmp/jido-ai-v3-capability-final-core-*`. No core source changed in the Planning
port. Action and Signal remain clean. Partial PR 279 evidence now covers the
Planning text/input helpers, without claiming skill packaging or full state
conversion. Baseline API inventory paths and hashes were not changed.

Validated plan execution and repair remain open. Next are Chat and its Action
families, other capability Plugins, remaining facades/CLI/skill/resource paths,
complete legacy conversion and durable recovery. The root package is still on
v2 dependencies and is not release-ready. Package, consumer, minimum-runtime,
migration and rollback gates remain required. The full migration goal stays
active. No commit, push or publication was made.

## Chat Actions and capability: 2026-09-07

[Example 16_02](../../examples/v3/profiles/16_02_chat.md) ports Chat, Complete,
Embed, GenerateObject, CallWithTools, ExecuteTool, ListTools and the Chat Plugin.
Public names, catalog functions and result fields remain. The seven routes use
core Plugin state, the shared capability binding and a declared result field.
The Agent DSL example includes an ordinary domain route. Both Action modules
and a core Flow can supply a named tool.

The refinement pass merged repeated default/model/provider-option preparation
into `ActionInput`; Planning now shares it. All four LLM Actions use one request
implementation. The automatic tool algorithm now uses core Flow dispatch and
shared Turn/Usage/ToolAdapter/Models/Exec. There is no additional runtime owner
or interpreter. Default callback execution uses core Exec; an explicit caller
Task supervisor remains supported.

The 32 integration cases use the existing HTTP mock. They test direct, Exec and
live capability calls, actual schemas/options, alias lookup, tool filters,
multiple rounds, limits, first and later model failures, timeout and cancellation.
Actual next HTTP requests retain reasoning details and Responses identity.
Completed provider usage survives nested merging and later failure. Four native
Chat API/configuration cases and 50 retained Helper/Validation cases also pass.

The initial seven cases failed before the port. Tests then found unsafe map
access on embedding vectors and an untyped-map key conversion error. Both are
fixed. Embed now requests available usage from ReqLLM internally. Empty vectors
remain a valid zero-dimension result; empty or ambiguous input is rejected.
Later tool rounds no longer duplicate assistant messages. GenerateObject now
checks returned schemas with shared validation, preserves decoded forms and
makes no extra AI repair request. Invalid output preserves the completed model's
usage in error telemetry without committing a result. Default callback tests
prove arbitrary return values, failures, timeouts and worker cleanup.

The final focused run passes 104 cases: 32 Chat, 18 Planning, 50 retained
Helper/Validation and four Chat contracts. No core, Action or Signal source changed in
this slice. The previously checked core still has the same 11 research failures;
this slice does not claim they are fixed. All 126 history statuses remain pending,
with 580 references and 50 partially proved rows. Baseline inventory JSON remains
unchanged. Root dependencies still select v2. Full package, CLI, consumer,
minimum-runtime, migration and rollback gates remain required.

| Final Chat check | Result |
| --- | --- |
| Focused integration and native contracts | 104 passed |
| Full acceptance with integration, seed 0 | 710 passed in 93.1 seconds; no required pending test excluded |
| Default acceptance | 15 passed; 695 integration cases excluded |
| Forced acceptance compile with warnings as errors | Passed; 181 files |
| Selected production, example and changed contract-test format | Passed |
| Exact history references and local links | 580 references; 951 links; all resolve |
| History state | 50 partial rows; all 126 statuses remain pending |
| Tracked/untracked whitespace and root dependency checks | Passed; root `mix.exs` and `mix.lock` unchanged |

Logs use `/tmp/jido-ai-v3-chat-*`. The first full check found two format changes;
formatting was corrected. Two further failure-accounting examples justified the
final full run. The existing TRM invalid-type test emits its known compile-time
warning during test loading; the forced production compile has no warnings.
The core results remain 1,268 passing, the same 11 research failures, one approved
exclusion and 93.9% coverage. Core quality checks passed at the preceding
checkpoint; no new core change required a repeat here.

Next: port ModelRouting and Policy through core preparation, with examples that
prove model precedence, Signal normalization and blocked provider work. Then
port Retrieval and Quota with explicit state/runtime ownership and observed
usage. Continue the remaining full-migration gates below. No commit, push,
publication, skill or sub-agent was used.

## ModelRouting and Policy: 2026-09-07

[Example 16_03](../../examples/v3/profiles/16_03_routing_policy.md) ports both
Plugins through core `state_spec/1` and `prepare/2`. Public module names and
catalog helpers remain. Committed Plugin state supplies model routes and policy
options. Caller context cannot replace that state. Empty restored state keeps
declared defaults. Keyword options replace v2 map configuration.

The 21 integration cases cover actual provider model selection, explicit
overrides, exact/wildcard precedence, both Plugin orders, custom native AI
routes, query defaults, multimodal input, observation normalization and typed
content. Enforce mode returns the structured non-retryable policy error in the
plan. It preserves correlation, makes no HTTP call and commits no state. It
does not rewrite the request to an error route. Monitor mode and disabled
blocking retain observation normalization. Eleven root Plugin tests now exercise
native Commands in place of removed callbacks.

The refinement pass shares declared route lookup across Runtime, Session and
Policy. One keyword option validator serves all ported capability families.
Native request model overrides change only the selected profile's primary model
for that request. The following request uses the declared choice again. This
adds no router, executor, process or DSL syntax.

The first tests failed because both v2 Plugins were unavailable. Later tests
found that native requests ignored the routed model and that mixed string/atom
keys could replace a prepared model with an empty value. Native preparation now
applies the request model; schema key conversion gives the canonical atom key
precedence. Actual structured requests also exposed a mock protocol gap: a
forced output tool needs tool-call data. The unified mock now supplies it through
its existing tool and SSE paths. A default contract test proves both forms and
their decoded usage through ReqLLM.

| Routing and Policy check | Result |
| --- | --- |
| Focused capability, Planning, native Plugin and mock checks | 151 passed |
| Updated forced-tool object mock, including SSE | 15 mock tests passed |
| Full acceptance with integration, seed 0 | 732 passed in 91.9 seconds |
| Default acceptance | 16 passed; 716 integration cases excluded |
| Forced acceptance compile with warnings as errors | Passed; 185 files |
| Selected source and test format | Passed after one test format correction |
| History ledger | 590 references; 51 partial rows; all 126 statuses pending |

Logs use `/tmp/jido-ai-v3-routing-policy-*`. The full run includes all integration
cases; default exclusions are not counted as passing evidence. The prior core
result remains 1,268 passing, 11 known research failures, one approved exclusion
and 93.9% coverage. Core format, compile, required lint, Dialyzer, docs and package
checks passed at that checkpoint. No core, Action or Signal source changed here.

PR 295 has narrow per-request evidence through direct core calls. Within-loop
provider switching, Fireworks/xAI, WebSocket reuse, continuation and all public
ask/submit options remain open. PR 340 gains an actual typed Policy preparation
case; full generated-image streaming remains required. Root dependencies and the
immutable API inventory stay unchanged. Full state conversion, recovery,
package, consumer, minimum-runtime and migration/rollback gates remain open.

Next: Retrieval and Quota with explicit state/runtime ownership, then default
PluginStack integration and the remaining full-migration gates. No commit, push,
publication, skill or sub-agent was used. The full migration goal stays active.

## Retrieval Actions, Store and Plugin: 2026-09-07

[Example 07_01](../../examples/v3/profiles/07_01_memory.md) ports UpsertMemory,
RecallMemory, ClearMemory, the public Store and Retrieval Plugin. The Store is
now an explicit application-supervised service. It owns a private ETS table and
does not create an implicit process or heir. Named stores retain namespace
sharing across Agents. Direct Actions can select an unnamed owner through
transient context. Store data survives caller and Agent stops; a replacement
store starts empty.

The Plugin uses portable configuration, live admission for memory reads and pure
preparation for capability binding. Explicit routes use the common candidate
helper. Direct Actions retain their public result envelopes. The DSL example
combines native AI, CRUD routes and a real RecallMemory model tool. Both native
Turn and session requests use their actual query binding for enrichment.

The refinement combines namespace and input handling across the three Actions.
It retains token-overlap ranking, namespace overrides, insertion/update fields,
metadata, snippet limits and opt-out rules. An unknown string key no longer
discards valid memory fields, and no new atom is created. Conversion errors stay
with the caller and cannot stop the shared store. Updates and clear operations
run through one owner. A failed Agent result commit cannot undo a completed
memory write. The checkpoint example proves that restoring an Agent does not
restore cleared external memory.

The first four cases failed because the v2 Store and Plugin were unavailable.
After the port they passed. Expanded tests verify direct and Exec input errors,
current Agent context, declared namespace/store bindings, restart behavior,
store absence, configured defaults and actual provider prompts. One session
test was corrected to match the existing `await` record contract. The final
tool example proves that the model receives the real recalled entry in its next
request, with the original tool call ID and namespace.

| Retrieval check | Result |
| --- | --- |
| Integration examples | 21 passed |
| Focused examples plus retained Store/Action and native Plugin tests | 44 passed |
| Full acceptance with integration, seed 0 | 753 passed in 93.8 seconds |
| Default acceptance | 16 passed; 737 integration cases excluded |
| Forced acceptance compile with warnings as errors | Passed; 193 files |
| Selected source/test formatting | Passed after one test format correction |
| History ledger | 593 references; 51 partial rows; all 126 statuses pending |

Logs use `/tmp/jido-ai-v3-retrieval-*`. A first full run passed 752 tests; the
added real memory-tool case justified the final full run. No core, Action or
Signal source changed. Core retains its previously checked 1,268 passing tests,
11 known research failures, one approved exclusion and 93.9% coverage. Its
required quality checks passed at that checkpoint. Action and Signal are clean.

Consumers must supervise the Store before use. `ensure_table!/0` now checks
readiness. Pure Agent commands require an explicit retrieval Action for memory
enrichment. These are documented migration rules. Full source-format parity,
old memory import with timestamp preservation, durable backup/restore and
application deployment setup remain required. Root dependencies and immutable
API inventory data are unchanged. No historical row is marked fully ported.

Next: port Quota using observed usage, explicit ownership and duplicate-event
checks; integrate default PluginStack behavior. Continue all remaining API,
skill/resource, recovery, CLI, root package, consumer, minimum-runtime and
migration/rollback requirements. The full goal remains active. No commit, push,
publication, skill or sub-agent was used.

## Quota Actions, Store and Plugin: 2026-09-07

[Example 13_01](../../examples/v3/profiles/13_01_quota.md) ports Quota Store,
GetStatus, Reset and the Plugin to the shared v3 execution paths. It uses an
explicit application-supervised GenServer. One atomic operation checks the
budget and reserves a model invocation. Call records and known tokens remain
outside the Agent commit. The Store monitors unfinished work and retains
partial usage when a stream or owner stops.

The shared model boundary covers generation Actions, Chat tool rounds, native
reasoning, repair and nested built-in reasoning. The new nested example is a
core Flow tool with an explicit prompt schema. It forwards the private budget
through the existing tool/session path. No second executor or model server was
added. Streaming uses the one mock's intermediate usage events and the actual
ReqLLM decoder. Two physical HTTP attempts can remain one guarded invocation.

The refinement keeps one accounting owner and the common capability result
helper. Pure Plugin preparation binds configuration; live admission checks the
existing ledger. Every guarded model invocation checks it again atomically.
This also protects pure Agent commands and the last request slot shared by two
Agents. Declared configuration overrides forged caller state. Status/reset
retain direct result envelopes and use a declared domain result field through
Agent routes. Keyword options and core callbacks replace v2 mount and Signal
rewriting. The Store has no implicit ETS owner or heir.

The tests cover repeated and changed duplicate reports, separate call IDs in one
request, failed model/typed output, cancellation, disconnect, owner termination,
repair and nested limits, disabled enforcement, embeddings, actual retry
transport, scope/store selection and the Agent DSL. Reset and expiry use window
generations so old active call results cannot charge the replacement window.
Validated v2 tuple/map import preserves timestamps and aggregate counters and
rejects invalid batches without partial writes. Imported calls without IDs are
reported as unattributed. Store restart starts empty.

A source check found that ReqLLM marks an empty-choice usage event terminal.
The mock's intermediate event was corrected to carry a nonterminal choice.
Its final usage event remains terminal. This made partial-usage cancellation
exercise an active model call. A later full run found a race in an older
response-metadata test: cancellation can close the provider before the test
releases its barrier. That test now accepts the already-closed state, monitors
worker termination and verifies the old request metadata after the next call.
The result and metadata assertions remain intact.

| Quota check | Result |
| --- | --- |
| Quota integration examples | 28 passed |
| Quota plus retained root Store/Action/Plugin tests | 43 passed |
| Final focused run, including response-metadata regressions | 54 passed |
| Full acceptance with integration, seed 0 | 781 passed in 95.9 seconds |
| Default acceptance | 16 passed; 765 integration cases excluded |
| Forced acceptance compile with warnings as errors | Passed; 201 files |
| Selected source/test formatting | Passed |
| History ledger | 601 references; 51 partial rows; all 126 statuses pending |

Logs use `/tmp/jido-ai-v3-quota-*`. The first full run passed 780 of 781;
the cancellation test correction justified the final full run. Formatting
needed one further pass after compilation loaded remote macro metadata.
Action and Signal remain clean. Core did not change; its last checks retain
1,268 passing tests, the same 11 research failures, one approved exclusion and
93.9% coverage. Its required quality checks passed at that checkpoint.

Usage provenance remains a specific limitation. ReqLLM normalizes missing usage
to zero, so a zero-only model response remains unknown at the ledger boundary.
The public Usage helper and explicit external zero reports retain their own
zero semantics. The ledger is local to its Store and window; it does not prove
durable replay or a hard cap on provider spend. A non-expiring window retains
its call records until reset; deployment retention must account for this.
Raw RunStrategy as a model tool has an unresolved generic-atom JSON Schema
export gap. The Flow example does not claim to fix that public Action surface.

Next: integrate the default PluginStack with Policy, ModelRouting and optional
Retrieval/Quota. Core Session already owns request work, so the old default
TaskSupervisor must be replaced through that existing owner. The public AI
option adapter currently omits default Plugin insertion and rejects retrieval
and quota options. Add actual facade examples for that change. Preserve the
difference between the old core `default_plugins` override and AI's own defaults.
Then continue all remaining API, skill/resource, recovery, CLI, root package,
consumer, minimum-runtime and migration/rollback requirements. The root Mix
files and immutable API/history baselines are unchanged. The full goal remains
active. No commit, push, publication, skill or sub-agent was used.

## Default Plugin integration: 2026-09-07

[Example 16_04](../../examples/v3/profiles/16_04_plugin_stack.md) integrates
PluginStack with the public AI option adapter. Policy and ModelRouting are
inserted before the common profile and Session Plugins. Optional Retrieval and
Quota accept map or keyword configuration. Explicit Plugin configuration merges
over its default once; repeated explicit modules fail. The private RunStrategy
factory also uses the default list, as its old public wrappers did.

The refinement keeps one composition helper and the existing core lowerer.
Eleven supported AI capability Plugins supply their route helpers. The public
adapter declares `capability_result` for their result maps, preserving typed
answers and request records. Custom Plugins retain their state. Explicit routes
replace generated routes with the same path, match and priority, while other
routes remain available. Native Agent DSL definitions retain explicit Plugin
choices; no additional AI DSL was introduced.

The Session Plugin owns request work. No old TaskSupervisor is inserted, and an
explicit old TaskSupervisor declaration gets a conversion error. The actual
stop example monitors a held tool, stops the public Agent, then uses the same
Quota and Retrieval stores from a new Agent. Portable state contains no task
supervisor PID. Store startup remains an application responsibility.

The examples cover default validation and actual model routing, explicit model
precedence, configuration merging, optional routes, forged state, disabled
stores, mixed capability execution, CoT answer preservation and all eight
reasoning adapter declarations. Public macro, direct data, Builder and JSON
codec definitions are equal and run real enriched model calls with separate
Agent scopes. The combined-capability Agent executes Planning, CoT and Chat
and records their three model calls in one quota ledger.

The first three tests failed because defaults and optional options were absent.
The expanded callable test then found that the private factory lacked Policy.
That factory now rejects the blocked prompt before provider work for all seven
supported RunStrategy methods. Core Exec keeps the original policy error under
`details.reason`; the test checks that boundary instead of expecting a top-level
Policy error from Exec.

PR 281 also requires caller module-attribute route tables. The macro now defers
that attribute to the caller's compile context, as it already does for a prompt
attribute. The new route example exposed a first-use Action loading failure.
The public option adapter now ensures referenced executable modules are compiled
before core route validation. The final example invokes the actual Action with
its static route input and then completes an AI request on the same Agent.

| PluginStack check | Result |
| --- | --- |
| New integration cases | 18 passed |
| Retained public PluginStack helper tests | 3 passed |
| Focused run with callable reasoning and Quota regressions | 70 passed |
| Full acceptance with integration, seed 0 | 799 passed in 99.9 seconds |
| Default acceptance | 16 passed; 783 integration cases excluded |
| Forced acceptance compile with warnings as errors | Passed; 203 files |
| Selected source/test formatting | Passed |
| History ledger | 607 references; 51 partial rows; all 126 statuses pending |

Logs use `/tmp/jido-ai-v3-plugin-stack-*`. All four quality-driver checks passed.
Core, Action and Signal did not change. The prior core result remains 1,268
passing tests, the same 11 known research failures, one approved exclusion and
93.9% coverage, with required quality checks passed. Root Mix files and immutable
API/history baselines are unchanged. The root package has not passed a v3 build.

The old core `default_plugins: false` setting remains accepted and does not
disable AI defaults. Map overrides for old Memory/Thread/Identity choices still
require explicit v3 capability and state conversion. Do not reinterpret those
keys as AI policy settings. The old TaskSupervisor source/tests remain outside
this acceptance compile until the rest of the v2 runtime is retired.

Next: fix non-ReAct admission-failure event identity through the actual declared
profile binding. Complete remaining public request option and metadata paths,
then mutable tool catalogs, raw RunStrategy tool-schema export, standalone and
skill/resource APIs, old state conversion and durable recovery. Continue root
dependency cutover, full package tests, consumer and minimum-runtime checks,
migration instructions and rollback. No full history row is marked ported.
The full migration goal remains active. No commit, push, publication, skill or
sub-agent was used.

## Remaining work

The complete root package builds on local v3 dependencies. Continue by fixing
the shared root failure groups and running retained behavior against the same
package as the acceptance examples. Transfer checks of removed internals to
their native behavior before deleting or replacing those checks.

Then complete the open feature, CLI, state conversion, recovery, supported
runtime, fresh consumer, quality, migration-guide and rollback gates. Standalone
skill continuation and complete ToT/GoT/TRM inspection remain required. The
126-commit ledger and API map define the required coverage. No history row is
fully ported from the package build alone. No commit, push or publication was
made here.
