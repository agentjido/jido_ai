# 02_16 — Typed Signals

Project AI request events into typed Signals and deliver them after a core commit.

## Read the code

Read [agent.ex](agent.ex), then [echo.ex](echo.ex), then [outbound.ex](outbound.ex), then [publish.ex](publish.ex), then [publisher.ex](publisher.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/02_requests/02_16_typed_signals --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

Signal validation preserves declared fields and rejects invalid input. The publisher delivers projected events after state commit; rejected delivery leaves that commit intact.

## Limits

Not every request event has a typed Signal. Local content structs do not imply JSON transport support. Signal observation is not durable event delivery.

## Files

- [02_16_typed_signals_test.exs](../../../test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Previous: [02_13](../02_13_tool_limits/README.md) | Next: [02_19](../02_19_model_options/README.md)
