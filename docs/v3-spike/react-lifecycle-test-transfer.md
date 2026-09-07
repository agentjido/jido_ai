# ReAct lifecycle test transfer

The [root ReAct tests](../../test/jido_ai/strategy/react_test.exs) keep all 78
cases. This pass moves 24 more cases to native Agent, Flow, Configuration,
Request and Session APIs. Together with the 24 setup cases, 48 passed at that checkpoint.
The later [context transfer](react-context-test-transfer.md) moves 18 more.
The current ReAct result is 66 passed and 12 required failures. No case was removed, combined or
skipped. The [complete source-to-v3 map](react-setup-test-transfer.json) matches
all original names at `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2` and all current
names. It records setup, lifecycle and required-unported cases separately.

## Preserved behavior

The shared HTTP/SSE mock holds real model responses for admission, rejection,
steering, cancellation and worker failure. A queued input enters history only
when consumed. A provider failure discards input before the next request.
Idle, blank and stale controls add no message or model call. Cancellation keeps
its reason and closes the provider connection. A killed worker fails its own
request and permits later work. Busy admission reports only the refused ID.

Live events retain request, run, call and sequence identities. Image parts
reach both streams and the saved multimodal result without entering text
state. Model telemetry uses the effective request model. Inspection shows the
committed conversation and the observed trace prefix. The trace-cap case sends
2,010 deterministic events to the owned Session while a real HTTP response is
held. It proves the 2,000-event limit, overflow flag and terminal retention;
it does not claim that these injected events came from the provider.

The next request reuses the prior conversation and opaque reasoning details.
Request headers and generation overrides end before the next request. Live
tool registration/removal changes the actual provider catalog. Prompt changes
produce one system message. Context replacement removes old keys before real
tool execution. Calculator and search fixtures now declare their input schemas
so these tests execute their Actions through core Exec.

## API and state changes

- Removed child-start directives and private Strategy callbacks map to native
  request admission and an owned Session worker. No old Strategy runtime returns.
- Native request records and `Session.snapshot/2` replace `__strategy__` fields.
  `state` and `agent_state` expose the host domain snapshot to a permitted tool.
  Caller-supplied state and identity values cannot replace these fields.
- The host Agent module provides `agent_module`; the old arbitrary worker
  `agent_module` option is not restored. Base tool context is a validated
  profile map, then ordinary fields are bound into execution context.
- Old private thread `ai_message` entries map to the declared domain message
  list. Message refs keep request/run/source and caller refs. There is no
  invented legacy `signal_id` for a synthetic worker event. Native stream
  events have their own IDs and their request/run correlation remains tested.
- Cancellation returns `{:cancelled, reason}` through the native request.
  A killed task returns `:worker_crash`, as the shared Session contract defines.
  The removed worker envelope `{:react_worker_exit, :killed}` is not restored.
  Busy admission returns `{:error, :busy}` and reports the refused request ID;
  it creates no request record and consumes no extra provider call.
- ReAct returns complete model text. It does not apply CoT's conclusion parser.
  Retained incomplete-response envelope cases are still required and failing;
  this pass does not replace them with these lifecycle checks.

## Examples and refinement

The [03_02 Agent examples](../../examples/v3/profiles/03_02_tool_context.md)
add three cases: native Session, native direct Turn, and public Agent. Each
runs a real tool and a second model call. They check the named host module,
Agent ID, state snapshot, base tenant, unchanged definition and portable state.
The native DSL lists each forwarded context field. It does not depend on an
implicit full-context default.

The direct Turn case first proves that core rejects reserved `agent_id` and
`agent_state` command keys without a state change. It then supplies the other
state/module values and proves that the tool still gets the host bindings.
Session and public requests filter reserved values from request tool context.
These are distinct entry-point contracts, both checked by the examples.

The first refinement corrected fixture inputs: ReAct requires an explicit tool
list, and copied CoT text expectations needed the complete ReAct result. The
second removed unused legacy aliases and stream helpers. Example dispatch now
uses small functions, so constant loop values create no unreachable-clause
warnings. Native context projection is explicit. The full state capture exists
only in the real tool fixture that checks it; setup controls still capture only
the prepared request and selected profile.

The focused root run passes 48/78 cases, with all 24 new replacements passing.
The focused example run passes all 14 cases, including the three new cases,
with integration and pending-DSL tags included. The initial example run without
those tags excluded all 14; it is not counted as evidence. The complete runs
are recorded in the [package checkpoint](root-package-checkpoint.md).

Logs: `/tmp/jido-ai-v3-react-lifecycle-04.log` and
`/tmp/jido-ai-v3-context-identity-03.log`.

## Transferred cases

| Original case | Native case |
| --- | --- |
| child started flushes deferred start to worker pid | the owned worker receives the prompt exactly once |
| cancel forwards worker cancel signal for active request | cancellation keeps its reason and closes the provider connection |
| worker crash while active request marks request failed | a worker crash fails its request and permits a later request |
| propagates runtime ordering metadata to LLMDelta signals | streamed deltas preserve request run call and sequence IDs |
| passes complete content parts without appending them to text state | complete content parts reach both streams and the stored multimodal result |
| stores request trace up to 2000 events then marks truncated | the trace keeps its first 2000 events and records overflow through completion |
| busy start emits request error directive | rejection metadata identifies only the refused request |
| worker runtime event updates state and emits lifecycle signals | owned runtime events update inspection and publish one request lifecycle |
| steer queues input for an active run | steer queues request input and preserves its source and refs on consumption |
| queued input is dropped if the request fails before runtime drain | provider failure discards undrained input before the next request |
| inject rejects while idle | idle injection rejects without starting work or changing history |
| steer rejects request_id mismatches without mutating the queue | stale steering rejects without adding an input or model call |
| steer rejects blank content without mutating the queue | blank steering rejects without adding an input or model call |
| input_injected runtime events update run context and append a user thread entry | consumed injection commits one user message before the next model call |
| snapshot exposes conversation projected from thread state | inspection projects the committed message history |
| request completion clears ephemeral req_http_options | request HTTP and generation overrides end before the next request |
| uses runtime event model for LLM delta telemetry | delta telemetry uses the effective runtime model |
| start payload context includes state snapshot key | a real tool receives the Agent state snapshot and ignores a forged state binding |
| start installs agent module and tool context in worker context | a real tool receives the host module identity and admitted context defaults |
| register_tool adds tool to config and list_tools/1 | tool registration updates the live catalog and the next provider request |
| unregister_tool removes tool from config | tool removal updates the live catalog and the next provider request |
| set_tool_context replaces base tool context | context replacement removes old defaults before real tool execution |
| set_system_prompt replaces base system prompt | prompt replacement reaches the next provider request exactly once |
| completed request history is reused for the next turn | the next request reuses committed history and opaque reasoning details |

The remaining cases cover checkpoints, usage/event reduction, tool-result
inspection and replay, context operations, skill durability, refs and initial
state conversion. Existing acceptance examples are evidence for later ports;
they did not silently close the 30 root failures at that checkpoint. The later
context transfer accounts for its 18 replacements explicitly. No history row is closed by
this pass. All remaining provider, dependency and release gates stay open.

The final complete root run passes 2,022/2,412 cases, with 390 failures and one
existing exclusion. Exactly the 24 mapped failures resolve; no new failure
appears. The complete acceptance run passes 1,174/1,178 cases, with the same
four required ReqLLM usage failures and no exclusions. All 230 production files
compile with warnings as errors. Both builds use the full root package and
core `dbb878b6`; see the package checkpoint for revisions and logs.

The later [tool inspection pass](react-inspection-test-transfer.md) moves two
more retained cases. ReAct now passes 68/78, with ten required failures.

The later [initial-state transfer](react-initial-state-test-transfer.md) moves
four more retained cases. ReAct now passes 72/78, with six required failures.
