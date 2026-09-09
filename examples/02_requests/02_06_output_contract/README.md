# 02_06: Output validation, events and metadata

The [Agent modules](agent.ex)
and [19 example tests](../../../test/examples/02_requests/02_06_output_contract/02_06_output_contract_test.exs)
use one typed ticket schema and the shared HTTP/SSE model server. Model
responses pass through real ReqLLM decoding, schema validation and core execution.

```sh
mix test --include example test/examples/02_requests/02_06_output_contract/02_06_output_contract_test.exs
```

The example proves these cases:

- Arrays of objects receive declared key and enum conversion. Zoi defaults
  apply before the final result is committed. Invalid items and unknown enums
  cause bounded repair or failure.
- Invalid output from an Agent without business tools can enter repair. The
  last permitted attempt can succeed. Error mode and zero retries make no
  repair call. Exhaustion keeps the domain result unchanged.
- Object generation can use a provider schema tool. The runtime validates
  that object without treating the schema tool as a business operation.
- Output start, repair, validation and failure events retain request/run IDs,
  ordered sequence numbers, attempt numbers and schema summaries. A terminal
  request event follows output finalization.
- Completed request metadata retains `output`, including validation status,
  attempt and the original raw preview. Raw bypass has no stale output events
  or metadata. Later requests retain the configured typed contract.
- A streamed tool round and synthetic thinking do not enter the final JSON
  text. Actual tool output reaches the next provider request.
- Provider failure, repair cancellation, the outer deadline, an output control
  rejection and an invalid domain result retain failed output metadata and
  available usage. A held callback is stopped through core execution ownership.
- The existing AI output telemetry families emit correlated start, repair,
  validated and error events. Telemetry metadata omits model payloads. The
  Agent ID comes from trusted Plugin initialization.
- DSL, data, Builder and source JSON preserve observation flags. Disabling
  delta capture keeps normal output telemetry and non-delta request events.
  Disabling telemetry alone keeps request events, including enabled deltas.
  Invalid flag values fail before model work. The shared capture rule is
  verified in [02_15](../02_15_early_tool_activity/README.md).
- Validated-event map previews redact sensitive keys and bound Unicode text.
  The canonical result still contains the actual value. The existing binary
  raw preview is a bounded string; it does not parse JSON text to redact fields.

`Jido.AI.Runtime.OutputState` retains one output transition path. It reports
metadata and events to the existing session owner in one operation. The owner
keeps partial metadata for task failure and cancellation. Success, failure and
cancel records still commit through ordinary core Actions and the request
Plugin. Output repair continues through the existing Flow.

`Jido.AI.Observe` moved into the shared source directory with its module and
implementation retained. The new event adapter uses that public telemetry
boundary. Profiles accept `observability` maps with `emit_telemetry?` and
`emit_llm_deltas?` boolean flags. Other observation options, lifecycle Signals,
tool payload events, spans and full observation precedence remain required work.

This is partial history evidence for PR 269, PR 300, PR 337 and PR 339. It does
not establish full reasoning metadata, arbitrary error serialization, standalone
ReAct parity or durable recovery. A session process crash can still lose its
transient usage and event state. The root package now uses local v3 dependencies. The complete root suite
and the remaining release checks must still pass.

Two added cases prove bounded provider-error repair. With two repair attempts,
an initial invalid answer and a 503 can be followed by a valid object or a
second 503. Both paths count three actual model calls and two repair attempts.
Recovery records repaired output; exhaustion records one output failure and
retains available usage. The retained single-failure case now explicitly uses
one attempt and keeps its original assertions.
