# 14_02: Public standalone runtime

[Example](agent.ex) and
[tests](../../../test/examples/14_resume/14_02_standalone_runtime/14_02_standalone_runtime_test.exs) call the
actual public `Jido.AI.Reasoning.ReAct` module. They use the same mocked HTTP
model server as the other v3 examples.

## Execution and ownership

The public module now compiles from `lib/jido_ai/reasoning/react.ex`. The Runner
now compiles from `lib/jido_ai/operations/react_runner.ex`. Its old model/tool
loop is removed. The new adapter starts a private Agent at enumeration time,
submits one Session request, forwards canonical events, and stops the Agent.
The optional Task supervisor owns the adapter task. Core Flow and Exec own all
model and tool work. No second executor or mock model was added.

`start/3` keeps its map with request ID, run ID, events and a nil initial token.
`stream`, `run` and `collect_stream` keep their public return shapes. A custom
run ID now reaches Session admission and the portable request record. It is
not a rewrite applied only to outgoing events. IDs must be nonempty strings.

Stopping enumeration cancels work. Consumer death stops the private Agent and
its blocked tool. Successful completion also stops that Agent. Normal loss of
the Agent produces a failed terminal event and token instead of an indefinite
wait. Abnormal owner failure still raises through the stream monitor; a wider
owner/restart fault matrix remains required.

## Controls and state

Runner options accept `limits: %{timeout: milliseconds, max_tool_calls: count}`.
When omitted, the total tool-call bound uses the native Profile default of 16.
The total timeout is the larger of the native default and
`Config.stream_timeout(config) * config.max_iterations`. This gives the
configured tool timeout room beyond the old native 60-second default.
The example inspects this budget with a 90-second configured tool timeout;
it releases the tool through a barrier and does not wait 90 seconds.

These are finite v3 bounds. The old standalone Config had no total tool-call
bound or overall deadline. Callers with larger batches or longer workloads
must supply explicit limits. Native concurrency remains 1 through 64.
The old iteration-limit answer and `:max_iterations` reason remain available
after the last permitted tool round.

`context.state` supplies portable domain fields for the private Agent. Keys
must be atoms and cannot replace the result, history or Plugin-owned fields.
Core validates state effects; the next request transformer sees the proposed
domain state. Runtime provider options and caller resources remain separate.
Quota context is carried into the private request. This example does not prove
the complete standalone Quota matrix or arbitrary old Agent-state conversion.

The Config lowerer no longer builds discarded provider tool definitions. The
native ToolCatalog owns them. This also permits an Action with no description
through the native catalog's fallback. The retained direct ToolAdapter still
needs its separate optional-description compatibility check.

## Tokens and remaining resume work

The terminal event is followed by a signed terminal checkpoint. It contains
committed message history, result/error, usage, output metadata, identity and
sequence. State now has an optional `termination_reason` field. Earlier tokens
without that field still decode. Prefix `rt2` and token version 2 are unchanged.
The saved sequence includes the checkpoint event, so terminal replay advances
it. Failed and cancelled collections retain terminal usage.

Terminal `continue` and `collect` return saved results without another model
call. `collect(..., run_until_terminal?: false)` remains a data-only view.
Cancellation returns a replacement cancelled token. An untouched initial
token can start through the native runtime.

[14_03](../14_03_checkpoint_resume/README.md) now proves native model and complete-tool-round
checkpoints. Progressed legacy state, query append on resume and an external
pending-input queue remain refused before provider work. Partial tool batches,
durable replay control, old-state conversion and Agent persistence remain open.
No Exec value goes into a token.

Further work must map all trace and redaction flags, queued-input rebinding,
cycle handling, interceptor/worker configuration, WebSocket ownership,
Scripts/TestCase, standalone Actions and the remaining provider/content cases.
The full root package now uses the local v3 dependencies. It compiles all
production sources; the complete root suite still has required failures.

## Validation

The initial eighteen example cases cover lazy start; identity; real aliased tools;
usage; terminal replay and cancellation; stream deltas; consumer and Agent
lifetimes; state effects; typed repair; iteration and tool bounds; incomplete
provider responses; long-tool budgets; Task supervision; invalid IDs; initial
tokens; and refusal of unsupported intermediate state.

The first run had no compiled public module and passed 0 of 12 cases. After
the adapter was added, 10 passed. The state-effect fixture used the wrong policy
shape. The held-tool case found the redundant tool conversion described above.
The refinement run passed 14 of 18 and exposed lost failure usage, lost saved
iteration reason, normal Agent-stop hangs and empty-ID acceptance. Those faults
were fixed. The focused run then passed all 41 cases, including the 12 prior
authoring cases and 11 retained root Token cases.

Run from the repository root:

```sh
mix test test/examples/14_resume/14_02_standalone_runtime/14_02_standalone_runtime_test.exs --include example
```

## Later native continuation work

[14_07](../14_07_standalone_input/README.md) adds caller-supplied input queues.
[14_08](../14_08_query_append/README.md) adds query append for initial State and native
checkpoints, including new terminal continuation data. Native checkpoint
version 2 keeps reasoning iteration separate from model-call count; version 1
native tokens still resume. Released v2 progressed State and restart from
failure/cancellation remain separate conversion work.

## Callback and repair transfer

Six added cases bring this file to 24 example cases. Standalone callers
can supply `context.agent_module` with before and after tool callbacks. The
adapter binds those callbacks to the shared native profile interceptor.
Tests prove the exact Action input, guardrail input and model tool-result JSON
for before-only, after-only and combined callbacks.

Transform failures and invalid repair messages report `:request_transform`
without a second provider call. A 503 during repair can use the next permitted
attempt. The terminal token keeps call counts, output attempts and available
usage. Stored errors are portable, and the token omits the test API key.
The full [runner transfer](../../../docs/v3-spike/runner-test-transfer.md)
records retained root cases and the still-open numeric-string usage and AWS
credential requirements.
