# 02_15: Early tool activity and delta capture

The [Agent and document Action](../lib/examples/02_requests/02_15_early_tool_activity/agent.ex)
and [13 integration tests](../test/examples/02_requests/02_15_early_tool_activity_test.exs)
use real streamed tool arguments from the shared mock. The Action writes a
test-owned file only after complete argument decoding and admission.

```sh
mix test --include integration test/examples/02_requests/02_15_early_tool_activity_test.exs
```

The PR 247 example sends a named tool fragment, then holds the document body.
Before release, the public request stream receives a canonical `:llm_delta`
with `chunk_type: :tool_call` and `delta: "write_document"`. No file exists and
no Action has started. After release, validation accepts the complete body,
the real Action writes it, and the next model request receives the canonical
tool result with the actual byte count.

This preserves the old payload: tool-name activity only. It does not expose
raw argument fragments or assign a tool-call ID to that early notification.
Request ID, run ID, model-call ID, iteration and sequence identify its model
round. The later tool-start event has the executable call ID. Empty names
emit no delta. Unknown or blocked tools can have early model activity but
still fail admission without executing.

Native and public Agents share one observation policy:

```elixir
observability %{emit_telemetry?: true, emit_llm_deltas?: false}
```

Both fields default to enabled. `emit_llm_deltas?: false` suppresses public
content, thinking and tool-activity deltas and their telemetry. It retains
other request events, complete model results, validation, usage and tool
execution. `emit_telemetry?: false` alone disables telemetry while allowing
enabled request deltas. The public `Jido.AI.Agent` option has the same meaning.
There is no separate native capture option.

Provider chunks always reset internal activity, including unnamed argument
fragments. The example spans more than 700 ms with a 300 ms idle limit, with
capture both enabled and disabled. Suppressed or empty-name deltas cannot
cause an idle failure while real chunks continue to arrive.

The session event owner applies the capture flag before assigning sequence.
Enabled events retain one sequence through the first model call, tool work
and final model text. The example reconstructs reversed final text deltas by
sequence and checks that the model-call IDs change between rounds. This
uses public request events; it does not prove a separate Signal projection.

Cancellation and a disconnected argument stream stop the provider and leave
the file unwritten. Source data, Builder and source JSON execute the same
definition as the DSL. A disabled-capture source JSON variant also executes
the real tool and returns the final result. Invalid observation flags fail
before activation.

A declared tool round with no usable tool call or text now fails with
`{:incomplete_response, :tool_calls}` before history or model completion.
The decoder can produce this condition when it removes an empty tool name.
Usage is still counted. A blank successful `:stop` remains valid, and provider
object requests keep their existing output-validation path. This is a named
v3 change: v2 could continue an empty tool round until another limit applied.

The refinement uses the existing delta flag for both native and public
Agents. It corrects the earlier native test that treated the flag as a
telemetry-only setting. The [output example](02_06_output_contract.md) now
checks that output telemetry and non-delta request events remain available.

This is partial PR 247 evidence. Standalone ReAct and other reasoning methods,
`ai.llm.delta` Signal projection and delivery, complete content-part deltas,
durable replay and the full package gate remain required. Early activity is
not proof that a tool has been approved or has executed.
