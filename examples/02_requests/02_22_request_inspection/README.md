# 02_22 — Request inspection

Read a committed request and its current live execution state.

## Read the code

Read [agent.ex](agent.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/02_requests/02_22_request_inspection --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

`Session.snapshot/2` returns the core revision, retained request and trace. Live work has the same request/run identity. Unknown IDs return `:request_not_found`.

## Limits

The live view is a later sample, not the same atomic snapshot as committed state. Worker PIDs stay outside portable state. Saved traces can be prefixes, not full durable event logs.

## Files

- [02_22_request_inspection_test.exs](../../../test/examples/02_requests/02_22_request_inspection/02_22_request_inspection_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)
- [Shared multiply.ex](../../support/multiply.ex)

Previous: [02_20](../02_20_call_counts/README.md) | Next: [02_24](../02_24_stream_usage/README.md)
