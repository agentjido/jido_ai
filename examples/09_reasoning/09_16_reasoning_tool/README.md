# 09_16 — Reasoning as a model tool

Expose `RunStrategy` directly as a model-callable Action.

## Read the code

Read [agent.ex](agent.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/09_reasoning/09_16_reasoning_tool --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

The outer request receives the real inner method result and uses it in its next model call. Cancellation stops inner work. Invalid tool input fails before execution.

## Limits

Existing atom labels can be accepted through schema conversion; unknown names do not create atoms. Nested work still needs explicit budgets. Dynamic tool sources remain deferred.

## Files

- [09_16_reasoning_tool_test.exs](../../../test/examples/09_reasoning/09_16_reasoning_tool/09_16_reasoning_tool_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Previous: [09_14](../09_14_callable_reasoning/README.md)
