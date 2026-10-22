# 02_27 — Thread and Session values

Keep an application-owned context as portable immutable data.

## Read the code

Read [demo.exs](demo.exs), then [thread_session_values.ex](thread_session_values.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/02_requests/02_27_thread_session_values --include example --seed 0
mix run examples/02_requests/02_27_thread_session_values/demo.exs
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

Appending returns a new Thread or Session. Encode/decode preserves portable entries and rejects unsupported data. A closed Session rejects new entries.

## Design target checks

[The target checks](../../../test/examples/02_requests/02_27_thread_session_values/design_requirements_test.exs)
check unknown-key and future-version rejection, atom safety, immutable
projection, and bounded sanitization of malformed/runtime data.

The default model projection excludes unresolved tool
exchanges (`VAL-REQ-024`), and multimodal summaries exclude hidden thinking
(`VAL-REQ-007`). Raw Thread entries still retain the unresolved evidence.
Synthetic content is used throughout. These fixed cases do not prove arbitrary
input safety or uniform behavior across every public value. See
[value alignment](../../../docs/design/01_ai_values/alignment.md#acceptance-matrix).

## Limits

`Jido.Session` is data; `Jido.AI.Orchestration` controls live requests. Closing a value does not cancel work. This lesson starts no model or Agent process.

## Files

- [02_27_thread_session_values_test.exs](../../../test/examples/02_requests/02_27_thread_session_values/02_27_thread_session_values_test.exs)

Previous: [02_25](../02_25_incomplete_response/README.md)
