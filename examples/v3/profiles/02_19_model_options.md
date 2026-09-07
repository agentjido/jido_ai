# 02_19: Request model and provider options

The [fourteen integration cases](../test/examples/02_requests/02_19_model_options_test.exs)
use the [public request Agent](../lib/examples/02_requests/02_04_request_scope/agent.ex),
[native routes](../lib/examples/02_requests/02_18_admission/agent.ex),
[stream and object Agents](../lib/examples/02_requests/02_03_public_agent/agent.ex),
and a [real HTTP adapter](../lib/examples/02_requests/02_19_model_options/agent.ex).
They use one shared model server and the real ReqLLM client.

```sh
mix test --include integration test/examples/02_requests/02_19_model_options_test.exs
```

The public request helper now forwards `model` into the same declared-profile
binding used by native Agent calls. An explicit request choice takes priority
over ModelRouting. It changes only the primary model of that request. The
declared profile and later requests retain their defaults. The examples cover
aliases, strings, both ReqLLM tuple forms, inline maps and `LLMDB.Model` values.
They check actual model IDs and selected-model labels in events.

Model values, HTTP callbacks and provider options remain in runtime context.
They do not enter portable Signal data or request records. An unsupported
model shape or unknown alias fails before admission with the declared method
and original error. Model content still goes through the existing resolver and
ReqLLM validation; this does not add eager validation of every model string.

Request `llm_opts` accepts keywords and maps. The shared ReAct option helper
normalizes known string option names for the selected model. Session requests
and per-call transformers now use the same helper. Generation options override
the caller's options for one request. An explicit nested `provider_options`
value replaces that option value; it does not merge each nested field.
Nested provider data retains its provider schema. The test uses an atom `type`
inside `response_format`, as required by the current provider schema.

Nil and empty overrides retain defaults. Invalid outer option containers now
fail admission instead of being removed. Unknown option names retain the
existing helper and provider behavior. This is not a new strict option schema.
Malformed values and all cross-provider normalization cases remain in the
full provider contract gate.

The stream case observes actual SSE, headers and selected-model labels. The
HTTP callback changes a real request before Finch sends it to the shared mock.
Portable state validation proves that the callback was not stored in the Agent.

Some plain model inputs select the Responses API in the current ReqLLM data.
The same mock now serves buffered Responses text, object and function-call
replies, with usage and response IDs. A real Action executes between two
Responses calls, and its output retains the function-call ID. A typed object
uses the provider's requested structured-output function and passes local
schema validation. No second model server or AI executor was added.

Four further cases change provider within one request: OpenAI → Anthropic →
OpenAI. Both native Agent DSL and standalone calls run with streaming on and
off. Real tools execute between model calls. Assertions check selected paths,
headers, thinking options, tool IDs and results, usage, model labels, and
portable terminal state. The third call uses the declared default again.
The shared response adapter aligns an empty-text-only difference in the
Anthropic streamed tool message. Different unresolved tools still fail.
See the [provider transfer](../../../docs/v3-spike/provider-test-transfer.md).

Responses streaming currently returns an explicit unsupported response from
the mock. Streaming Responses, WebSocket sessions, continuation ownership and
recovery remain required. The complete Fireworks/xAI provider option contract
and rich-model matrix across all methods, source formats and CLI remain open.

This is partial evidence for PRs 206, 238, 248 and 295, plus the request-header
requirements linked to issue 212. The full root dependency, package, consumer,
minimum-runtime, migration and rollback gates remain open.
