# ReAct tool inspection transfer

This pass retains all 78 [ReAct cases](../../test/jido_ai/strategy/react_test.exs).
Two more cases now use native Agent, Request and Session APIs. The focused run
passes 68/78 cases. Ten cases remain required failures. The
[complete case map](react-setup-test-transfer.json) records every original name
at `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2` and every current name.
It has 24 setup, 24 lifecycle, 18 context, two inspection and ten unported rows.

| Original case | Native case |
| --- | --- |
| `snapshot formats pending tool calls with string keys` | `inspection normalizes string-key provider calls while a real tool runs` |
| `snapshot exposes completed tool results after final answer` | `completed tool inspection keeps one result per call after replay and the final answer` |

The first case sends a raw JSON provider response with string-key tool data.
A real calculator holds execution while inspection checks the call ID, name,
arguments, running status and nil result. After release, its result is five.
The second case executes a calculator and a search Action that returns a timeout.
While the next model response is held, the test resends the actual calculator
completion to the Session owner. Inspection keeps one result per call and the
active model phase. The duplicate observation does not add tool history or run
an Action again. A later event after completion cannot change the saved request.
A new held request has no completed results from its predecessor; the old
request remains selectable.

## Shared fixes and API details

Running calls now include `result: nil`. A completion changes the displayed
phase only when it removes a matching pending call. Repeated completion events
remain observations in the trace. They are not effect receipts, and this change
does not claim durable exactly-once tool execution.

The real search Action exposed a second boundary issue. Core wraps a returned
non-exception error in an execution error with `reason` and `retry` fields.
Tool normalization now recovers a typed error map from that exact wrapper.
It retains its type, message, details and retry hint. Additional execution
fields and exception structs keep the existing normalization. The shared
AI operation cause bridge is unchanged. Five new
[boundary cases](../../test/jido_ai/operations/tool_result_test.exs) check these
limits, including atom/string error fields, an explicit false retry hint and
nested skill exceptions.

V3 inspection uses `view.request.result` for the final answer and
`view.request.error` for a saved failure. `view.details.tool_results` contains
completed records with status, attempts, duration, position and the result tuple.
The result error adds the actual tool name and call ID to its details. Active
calls show prepared provider arguments. Completed records show the validated
arguments received by the tool. For an Action schema these can have atom keys
and coerced values. The old synthetic Strategy test had no validation step.
The transferred test now checks that distinction explicitly. Empty collections
are `[]`; the old absence of the private snapshot field is not retained.

No removed Strategy container or Snapshot type is restored. The common
Session inspection and tool-result boundary serve the existing authoring forms.
No core or dependency file changed.

## Integration and refinement

The [02_22 examples](../../examples/02_requests/02_22_request_inspection/README.md) add
named buffered and streaming Agent DSL definitions. Both use the one shared
mock, execute real success/failure tools, replay an observed completion twice,
finish the request, reject stale mutation, and start a later request. They check
the actual HTTP streaming flag, exactly two tool history messages, portable
Agent state, retained old results and no repeated tool execution. All 16 cases
in this example group pass.

The first test run failed on missing nil results and a phase change caused by
replay. The next run exposed loss of the Action's typed error. The final change
uses a narrow tool-boundary conversion and leaves general error storage alone.
It also retains the existing distinction between prepared and validated tool
arguments. The first complete acceptance run found a skill regression: a typed
error's nested exception did not implement Access. Retry-hint lookup now uses
Map functions for maps and structs. The unchanged skill example and the new
boundary case both pass. The combined skill/inspection group passes 37 cases;
the five boundary and 21 error-model cases pass together. No test was removed,
combined or skipped.

Focused logs:
`/tmp/jido-ai-v3-react-inspection-before.log`,
`/tmp/jido-ai-v3-react-inspection-final.log`,
`/tmp/jido-ai-v3-tool-result-boundary-02.log`, and
`/tmp/jido-ai-v3-inspection-examples-final.log`.
The final root focus includes 21 unchanged error-model cases: 89/99 pass and
only the ten unported ReAct cases fail. See the
[root checkpoint](root-package-checkpoint.md) for complete package checks.

Initial Agent state conversion, two checkpoint cases, usage, saved raw errors,
the remaining root failures, four required ReqLLM failures and all release gates
remain open. The migration goal remains active.


Final complete checks: root 2,051/2,421 passed, 370 failed, one existing
exclusion; acceptance 1,179/1,183 passed, four required ReqLLM failures, no
exclusions. The root comparison resolves the two mapped failures, adds five
passing boundary cases and adds no failing case. The acceptance comparison
adds the two examples and keeps every prior passing case. Production compile
passes for all 230 files with warnings treated as errors.

The later [initial-state transfer](react-initial-state-test-transfer.md) moves
four more retained cases. ReAct now passes 72/78, with six required failures.
