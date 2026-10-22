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

Failed and length-limited responses retain usage and fail without an answer
commit, even when they contain text, media, or a decoded object.

## Design target checks

[The target checks](../../../test/examples/02_requests/02_25_incomplete_response/design_requirements_test.exs)
test completion and content protection with synthetic data.

The runtime rejects length-truncated output (`MDL-REQ-015`). Media and hidden
reasoning are excluded from default streams and storage; diagnostics exclude
content (`OBS-REQ-032` through `OBS-REQ-036`). The Profile's `observability` block
has separate `stream_content`, `store_content`, `stream_reasoning`,
`store_reasoning`, and `diagnostics_content` permissions. All default to false.
Inspection also requires `include_content: true`. `Request.await/2` returns
the stored result, which can contain an omission placeholder. See
[model alignment](../../../docs/design/02_model_gateway/alignment.md#acceptance-matrix)
and [observation alignment](../../../docs/design/12_observation_diagnostics/alignment.md#acceptance-matrix).

## Limits

These tests exercise the Chat decoder. They do not establish exact Responses status mapping or typed partial-output acceptance. Provider finish reasons and output-control errors are different boundaries.

## Files

- [02_25_incomplete_response_test.exs](../../../test/examples/02_requests/02_25_incomplete_response/02_25_incomplete_response_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Previous: [02_24](../02_24_stream_usage/README.md) | Next: [02_27](../02_27_thread_session_values/README.md)
