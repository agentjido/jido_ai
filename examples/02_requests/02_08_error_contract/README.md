# 02_08: Errors through core execution

The [Agent modules](agent.ex)
and [15 example tests](../../../test/examples/02_requests/02_08_error_contract/02_08_error_contract_test.exs)
use the shared HTTP/SSE mock, real repair callbacks, core Actions and live
Agent commits. The native Agent DSL and the public AI Agent macro use the
same error adapter.

```sh
mix test --include example test/examples/02_requests/02_08_error_contract/02_08_error_contract_test.exs
```

The example proves these cases:

- Portable repair errors retain their original structured term in `await`,
  the request record and the terminal event. A failed output has no result
  commit. Compatibility text fields remain strings.
- A nonportable cause uses the shared AI error normalizer. Process IDs,
  references, functions, improper lists and nested exceptions become data
  that can be stored. Error type, message, details and retry hints remain
  available. The Agent accepts a later request after failure.
- Transformer errors keep their outer failure tuple. They fail before HTTP.
  A nested nonportable cause is converted inside that tuple.
- Actual provider errors retain HTTP status and response-body cause details.
  ReqLLM errors can contain live request data or improper iodata; those errors
  therefore use the normalized storage form. A provider failure before output
  validation emits no output-start event.
- A repair callback can raise, exit or be killed. Each case produces a
  committed failure, one output-failure event and retained usage. Core Exec
  continues to own the callback process and its cancellation.
- Native DSL output controls preserve portable or nonportable causes. A
  rejected result does not enter domain state. Real Action and core error
  constructors retain the rejected value and cause. The AI adapter retains
  the upstream retry hint.
- Normalized JSON error messages, keys and values represent invalid UTF-8
  binaries as `base64:` strings. Known JSON error types and explicit false
  retry hints survive normalization. Unknown type names do not create atoms.
- Output error metadata redacts sensitive keys and bounds payloads. Null error
  fields at the depth limit produce a finite summary. Transport keys are valid
  JSON strings even when the original key contains invalid UTF-8.

Core Flow normally converts a foreign exception into an Action execution
error. That conversion can remove provider fields. `Jido.AI.Error.capture/1`
uses a supported Action error to carry the original cause across that boundary.
The request owner extracts the cause and applies storage conversion. The same
adapter serves generation, controls, request preparation and model decisions.
No separate executor, scheduler or error policy was added.

Output metadata uses the existing AI normalizer followed by the existing
transport sanitizer. Canonical portable errors are not display summaries.
In particular, a portable raw binary can remain in a raw request error; use
`Jido.AI.Error.normalize/1` for the JSON envelope. The `base64:` form is a
display representation, not a general raw-error restore codec.

This is partial history evidence for PRs 214, 223, 258, 275, 299 and 300.
Model-facing tool envelopes, completed tool outputs, effects, tool retries,
all reasoning methods, standalone execution, Flow-specific error adapters,
every sanitizer bound, durable recovery and root package checks remain open.
