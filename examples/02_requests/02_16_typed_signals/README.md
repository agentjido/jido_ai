# 02_16: Typed Signals and Turn conversion

The [Agents and Actions](agent.ex)
and [18 example tests](../../../test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs)
exercise the public AI Signal boundary against core v3. All ten typed Signal
definitions use static `use Jido.Signal` schemas. There is no AI Signal DSL.

```sh
mix test --include example test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs
```

The public types, sources, required fields, optional omission and defaults
remain. Known top-level string keys become the declared atoms. Nested result
values and shallow map fields remain intact, including structs and local
values allowed by `:any`. Unknown keys fail without creating atoms. Duplicate
atom/string aliases fail even if both values are equal. Non-string/non-atom
keys fail before the Zoi error renderer.

The input adapter distinguishes a missing field from an explicit `nil`. Zoi
defaults normally replace both. The adapter uses the
declared inner schema for a present `nil`: metadata remains invalid, while
`nil` remains valid for an atom or any-valued field. Zoi validates field types;
AI does not keep a second field-type validator. Use the Signal module's
`validate_data/1` when this input behavior is needed. Parsing `schema/0`
directly uses ordinary Zoi default rules.

The public behavior is explicit:

- `schema/0` returns static Zoi data. Metadata helpers keep their names and
  return that same schema. `to_json/0` remains a metadata map, not encoded JSON.
- Core constructors keep the declared type and validated data when options
  attempt to replace them. Conflicting data/base64 forms fail.
- Data validation returns Zoi errors. `new!/2` raises `Zoi.ParseError` for
  these errors and `ArgumentError` for envelope or input-key errors.
- Constructors leave `time` absent unless the caller supplies it. Event
  projection uses the actual canonical event timestamp. The output envelope
  uses specversion `1.0`.
- Duplicate atom/string data or envelope keys fail. Repeated identical keys
  in a keyword options list keep the core rule: the last value wins.

`Jido.AI.Signal.from_event/2` is a pure projection of canonical request events.
`Jido.AI.Signal.emit/1` produces core Emit Directives. A normal Agent Action
returns them with its complete next state. Core commits the state, calls
outbound Plugins and uses the configured dispatch target. A rejected outbound
Signal leaves that committed state in place and does not reach the receiver.

The live example holds incomplete tool arguments at the shared mock. It
projects and delivers a tool-name delta before the real Echo Action can run.
The result preserves request, run, model-call, iteration and sequence fields.
The second model round has a different call ID. Reversed final text deltas can
be reconstructed by sequence. The request-start event now includes its actual
query. Lifecycle projection retains the actual run ID instead of copying the
request ID into that field.

Model and tool completion, usage, request completion, actual provider failure
and cancellation also use this path. Another example converts a real ReqLLM
response with `LLMResponse.from_reqllm_response/2` and delivers real embedding
vectors. Complete image content and reasoning data survive pure projection.
A local content-part struct is not a promise of JSON transport support; the
core codec rejects non-JSON Signal data. Events with no existing typed AI
Signal, such as keepalives and output validation, produce no invented type.

DSL, data, Builder and source JSON run the same text request and produce the
same model/completion payloads. All examples use the existing shared mock.

`Jido.AI.Turn` now compiles from the shared production directory. It retains
response conversion, content, tool messages and direct execution helpers.
Direct execution uses core Exec and the shared ToolResult normalizer. Removed
Action parameter conversion is replaced with the shared declared-key/enum
adapter. Tests prove validation before execution, actual timeout cleanup and
the core no-retry timeout decision. Registry and observation options stay out
of core Exec. Unsupported execution options are rejected at the AI boundary.

This example explicitly feeds observed request events to a publisher Agent.
Session delivery uses the common bounded delivery path. The embedding case
proves the provider payload and Signal boundary.
