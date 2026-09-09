# Provider and model test transfer

Four retained cases in the [root runner test](../../test/jido_ai/react/runtime_runner_test.exs)
now use the shared HTTP/SSE mock. All 58 original test names remain, plus the
one HTTP credential case from the previous transfer. No case was removed,
combined or skipped. Nine previous failures are resolved in the full root run. The inline-model
case already passed and now checks actual HTTP input.

| Retained case | Evidence |
| --- | --- |
| `passes inline model specs through to ReqLLM requests` | The inline map supplies the endpoint and explicit Chat protocol. The real request uses that endpoint, model ID and streaming mode. |
| `uses non-streaming generation when streaming is disabled` | Actual JSON response, `stream: false`, input/output counts, text, lifecycle events, no delta, and terminal token. Extra SDK usage metadata remains allowed. |
| `request_transformer model override is reflected in runtime turn events` | An OpenAI default changes to Anthropic. Actual Messages path, selected SDK model ID, credential header, and start/completion model labels agree. |
| `preserves reasoning_details across tool turns` | All typed reasoning fields and opaque provider data survive streamed tool calls and the next HTTP request. The real Calculator Action returns 5 with the same tool ID. |

The reasoning fixture uses a string `token` key in provider data because the
real JSON decoder returns string keys. The opaque value and all reasoning
fields remain checked. The buffered usage assertion checks the same input
and output counts while allowing total and cost fields supplied by ReqLLM.

## Shared mock contract

The [single model server](../../lib/jido_ai/test/mock_llm.ex) now accepts named
SSE events and Anthropic text, tool, and object scripts. Both buffered and
streamed replies use the Messages format. Streamed tool arguments arrive in
two JSON fragments. Objects use the requested schema tool when present.
`MockLLM.options(server, :anthropic)` supplies the base URL that the SDK expects.
The SDK adds `/v1/messages` itself.

Two new [mock contract cases](../../test/examples/support/mock_llm_test.exs) send six
real requests through ReqLLM. They check text, fragmented tools, objects,
usage, and paths. All 18 mock contract cases pass. The same server still owns
request capture, explicit waits, connection closure, and cleanup.

## Model changes within one request

Four new [02_19 integration cases](../../examples/02_requests/02_19_model_options/README.md)
cover native Agent DSL and standalone APIs with streaming on and off. Each
request goes OpenAI → Anthropic → OpenAI, with a real Action after each of
the first two calls. Tests check all three paths, model labels, model-call
counts, total usage, provider options, headers, correlated tool results,
transformer calls, and portable final state. The third call returns to the
declared default and has no Anthropic thinking option.

The two initial streamed cases failed before the third call. In ReqLLM 1.22,
the Anthropic stream builder puts a tool-only assistant in `response.context`,
then adds an empty text part to `response.message`. The two messages differ.
ReqLLM correctly rejects a different unresolved tool message when AI adds the
next tool exchange.

The [response adapter](../../lib/jido_ai/operations/response.ex) now aligns the
final context message only when its sole difference is that empty text part.
It compares every other field and keeps the full context. Different tool IDs
or arguments still fail continuation. Three [boundary cases](../../test/jido_ai/operations/response_test.exs)
prove this narrow rule and repeat-call stability. All four provider-change
cases and all 14 model-option cases now pass.

## Open requirements

This is partial provider-routing evidence. It does not close the original
Fireworks/xAI option case from PR 295, AWS credentials, WebSocket ownership,
Responses streaming, or previous-response-ID continuation. The old runner
cases for those contracts remain required. Complete provider usage supplied
as numeric strings still exposes four required ReqLLM failures in 02_24.
The same response alignment also fixes six unchanged runner tests: state
snapshot refresh with effects, no refresh when policy removes effects,
standalone effect-policy context, after-model checkpoint resume, and both
tool-heartbeat modes. The final runner result is 41/59 passed, with 18 required
failures. The full root result is 1,973/2,412 passed in 24.8 seconds, with 439
failures and one existing exclusion. Three new response-boundary tests account
for the count increase. The comparison has no new failing case.

The full forced compile passes for all 230 production files with warnings as
errors. Logs are `/tmp/jido-ai-v3-root-test-28.log` and
`/tmp/jido-ai-v3-root-compile-checkpoint-09.log`. The failure inventory is
`/tmp/jido-ai-v3-root-checkpoint-08-failures.json`.
No history row is closed by this pass.
