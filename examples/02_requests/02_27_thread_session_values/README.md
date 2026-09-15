# 02_27 — Thread and Session values

Keep an application-owned conversation as portable immutable data.

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

## Limits

`Jido.Session` is data; `Jido.AI.Orchestration` controls live requests. Closing a value does not cancel work. This lesson starts no model or Agent process.

## Files

- [02_27_thread_session_values_test.exs](../../../test/examples/02_requests/02_27_thread_session_values/02_27_thread_session_values_test.exs)

Previous: [02_25](../02_25_incomplete_response/README.md)
