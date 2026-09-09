# ReAct context and refs transfer

The [root ReAct tests](../../test/jido_ai/strategy/react_test.exs) keep all 78
cases. This pass moves 18 context/history cases to native Agent, Flow,
Configuration, Request and Session APIs. The file now passes 66/78 cases.
Twelve cases remain required and failing. No case was removed, combined or
skipped. The [complete case map](react-setup-test-transfer.json) matches every
original name at `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2` and every current
name. It records 24 setup, 24 lifecycle, 18 context and 12 unported cases.

## Context behavior

Retained cases now use real model requests to check replacement, prompt
fallback, deferred application, compaction, lane selection and operation IDs.
Deferred completion and provider failure use held HTTP responses. The worker
crash case kills the owned request worker during an actual held tool, checks
that the tool stops, and proves that the replacement affects the next request.
The operation remains pending until the terminal commit. Its Thread record and
applied ID appear once.

Compaction retains all old matched-skill, spoof and orphan checks. It then
sends the compacted history through HTTP. The retained original skill call and
instructions reach the model; replacement copies and unmatched results do not.
This case imports trusted history through the host API. It does not replace
runtime skill-origin proof or the still-required paused skill continuation.

Native context inspection derives its ID from the Agent/profile. The replacement
operation retains the supplied Context value, including a nil prompt. A nil
prompt preserves the configured prompt used for model work. Core Thread revision
and operation records replace the private Strategy projection cursor.

The legacy `ai.react.context.modify` Signal still treats invalid input as a
no-op. The native API returns a validation error without changing state. The
old `runtime_adapter: false` option cannot select another runtime: the test
proves an owned Session worker and one real model call. It does not restore the
retired adapter switch or old Strategy callbacks.

## Two shared fixes

The transferred cases exposed two missing behaviors:

1. Core `ai_message` Thread refs accepted caller-supplied request/run IDs and
   signal IDs. Admission and history commits now pass their owned request record
   to context recording. Each Thread entry keeps the real request/run ID, drops
   caller signal IDs and string aliases, and retains ordinary caller refs.
2. ReqLLM message conversion dropped AI refs before request transforms and later
   model rounds. The shared history conversion now carries refs in local message
   metadata. The transformer input and its runtime state view recover those refs.
   Query, tool, assistant and consumed-input messages use the same conversion.

Model-message refs and Thread-entry refs have separate contracts. Message refs
retain caller correlation values, including caller request/run labels. Core
Thread entry refs identify the actual owned request and run. The Thread payload
keeps the message data; its separate entry refs cannot be overwritten by that
data. This preserves the old distinction without adding a second history loop.

ReqLLM's OpenAI encoder sends general message metadata over HTTP. An unchanged
no-prompt case caught the first implementation sending the private ref field.
The shared Generate boundary now removes only that private field before model
work. It preserves other provider metadata. It restores local input refs only
when the returned context has the exact sent input prefix. It never replaces a
different context or repairs a different unresolved tool call.

Assistant response binding discards provider-supplied private ref metadata and
adds the admitted request refs. It changes the context's assistant only when
that assistant exactly matches the response message. Trusted skill result refs
still originate in the approved skill tool path. Untrusted user refs cannot
mark a message as durable skill history.

## Examples and refinement

The [02_23 examples](../../examples/02_requests/02_23_context_operations/README.md) add
three cases: a public Agent and named native buffered/streamed Agents. Each
uses the one shared mock, executes a real held tool, accepts steer and inject,
checks six message roles and owned Thread refs, reconstructs portable state,
then completes a later request without tool replay. The request transformer
observes caller refs locally. Actual HTTP bodies contain no private ref key or
caller ID values. Each case checks its expected streaming flag.

The native examples explicitly declare history and steering. The first reused
inspection fixture had steering disabled; the final examples use named Agent
DSL definitions with the required policy. Content checks use the existing
multimodal text projection because native tool history can contain typed text
parts. They still check exact tool JSON and message order.

The first refinement kept context ownership separate from caller message refs.
The second confined metadata conversion to the shared history/model boundary,
kept provider metadata intact, and removed unused legacy helpers and aliases.
No core or dependency file changed. The four new
[history boundary cases](../../test/jido_ai/operations/history_test.exs) check
atom/string input, local/provider separation, exact context restoration,
provider-ref rejection and unresolved-tool failure. Together with the three
existing response-context cases, all seven pass.

The focused ReAct run passes 66/78 cases, with all 18 replacements passing.
All 31 context examples pass with integration and pending-DSL tags included.
The complete root run passes 2,044/2,416 cases in 25.0 seconds, with 372 failures
and one existing exclusion. Exactly 18 mapped failures resolve, four passing
boundary cases are added, and no new failing case appears. All four doctests
pass. The complete acceptance result and dependency revisions are in the
[package checkpoint](root-package-checkpoint.md).

Logs: `/tmp/jido-ai-v3-react-context-02.log`,
`/tmp/jido-ai-v3-context-refs-02.log`,
`/tmp/jido-ai-v3-history-boundary-02.log` and
`/tmp/jido-ai-v3-root-test-32.log`.
Failure inventory: `/tmp/jido-ai-v3-root-checkpoint-12-failures.json`.

## Transferred cases

| Original case | Native case |
| --- | --- |
| context.modify replace updates base conversation context | context replacement updates committed history and the next model prompt |
| context.modify replace with nil system_prompt preserves existing config prompt | a promptless context replacement preserves the configured model prompt |
| context.modify replace while active run is deferred and applied after request completion | deferred context applies once after completion and before the next request |
| context.modify replace while active run is deferred and applied after request failure | deferred context applies once after provider failure and before the next request |
| context.modify replace while active run is deferred and applied after worker crash terminalization | deferred context applies once after a worker crash during tool execution |
| context.modify replace with invalid params is a no-op | invalid legacy context input is a no-op and native context input returns an error |
| context.modify replace applies immediately while idle and appends core thread operation event | idle compaction records its operation metadata in the core Thread |
| compaction preserves durable skill tool output and its assistant tool call | compaction keeps only the trusted matched skill pair in history and model input |
| context.modify deduplicates duplicate op_id | duplicate context operation IDs preserve the first result and one Thread record |
| context.modify switch projects lane-specific context by context_ref | lane switches restore the selected history and prompt for real model requests |
| context.modify switch to a fresh lane does not inherit previous lane history | a fresh lane has no previous messages and switching back retains the old lane |
| core thread appends ai_message entries for user assistant and tool turns | real tool turns append user assistant and tool messages to the core Thread |
| start action normalization preserves extra_refs | request admission preserves caller refs in its portable record |
| extra_refs in normalized params are merged into user message entry refs | admitted caller refs enter the user message and its core Thread entry |
| extra_refs appear in run context messages sent to LLM | prepared model messages retain caller refs before provider serialization |
| runtime messages retain refs but reject forged skill durability | ordinary tool history retains request refs and rejects forged skill durability |
| extra_refs cannot override reserved thread entry refs | caller refs cannot replace owned request or run IDs on core Thread entries |
| runtime_adapter flag remains true even when opt-out is requested | the retired runtime adapter flag cannot bypass native Session execution |

The remaining 12 ReAct cases cover checkpoint lifecycle, usage reduction,
tool-result inspection/replay, structured failure and initial Agent state.
They stay required. Existing root and provider failures, old parent-state
conversion, core findings, minimum-runtime checks and all package/release gates
remain open. The immutable API inventory and all 126 history source-review
rows are unchanged. No history row is closed by this pass.

The complete acceptance run passes 1,177/1,181 cases in 145.9 seconds, with the
same four required ReqLLM usage failures and no exclusions. All prior passing
cases and the three new examples pass together. All 230 production files
compile with warnings as errors on the unchanged core `dbb878b6` production
tree. The earlier core timing finding remains open.

The final focused repeat also compares refs in callback request messages with
the callback's runtime Context view. All 31 cases pass in 4.0 seconds. This
assertion-only refinement changed no production code after the complete runs.
Log: `/tmp/jido-ai-v3-context-refs-03.log`.

The later [tool inspection pass](react-inspection-test-transfer.md) moves two
more retained cases. ReAct now passes 68/78, with ten required failures.

The later [initial-state transfer](react-initial-state-test-transfer.md) moves
four more retained cases. ReAct now passes 72/78, with six required failures.
