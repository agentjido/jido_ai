# 09_14 — Callable reasoning

Call a reasoning method as an Action or through an Agent route.

## Read the code

Read [agent.ex](agent.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/09_reasoning/09_14_callable_reasoning --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

`Jido.Exec.run/4` returns the method result, usage and diagnostics. The inline route commits that result while preserving case state. Cancellation stops the private request resources.

## Limits

The private runtime is owned by the call. It is not a durable worker. Provider failure is a failure envelope, not a successful answer.

## Files

- [09_14_callable_reasoning_test.exs](../../../test/examples/09_reasoning/09_14_callable_reasoning/09_14_callable_reasoning_test.exs)

Previous: [09_10](../09_10_adaptive/README.md) | Next: [09_16](../09_16_reasoning_tool/README.md)
