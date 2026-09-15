# 02_25 — Blank failures and partial content

Keep failed blank responses distinct from usable partial output.

## Read the code

Read [agent.ex](agent.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/02_requests/02_25_incomplete_response --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

Blank failed responses retain usage and fail without an answer commit. Usable length-limited text and image content can complete under the existing untyped contract.

## Limits

These tests exercise the Chat decoder. They do not establish exact Responses status mapping or typed partial-output acceptance. Provider finish reasons and output-control errors are different boundaries.

## Files

- [02_25_incomplete_response_test.exs](../../../test/examples/02_requests/02_25_incomplete_response/02_25_incomplete_response_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Previous: [02_24](../02_24_stream_usage/README.md) | Next: [02_27](../02_27_thread_session_values/README.md)
