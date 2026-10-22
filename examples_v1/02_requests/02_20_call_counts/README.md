# 02_20 — Model operation counts

Track started model operations separately from HTTP attempts.

## Read the code

Read [agent.ex](agent.ex), then [echo.ex](echo.ex), then [input.ex](input.ex), then [model.ex](model.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/02_requests/02_20_call_counts --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

HTTP retry remains one model operation. Tool continuation starts another operation. Failure and cancellation retain the observed count; each new request starts its own count.

## Limits

A started model operation is not proof of a successful answer or an exact bill. Owner-loss evidence is limited to observed and committed state.

## Files

- [02_20_call_counts_test.exs](../../../test/examples/02_requests/02_20_call_counts/02_20_call_counts_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Previous: [02_19](../02_19_model_options/README.md) | Next: [02_22](../02_22_request_inspection/README.md)
