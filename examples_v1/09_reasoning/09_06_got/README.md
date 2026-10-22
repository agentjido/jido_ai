# 09_06 — Graph of Thoughts

Generate and combine reasoning through a bounded graph.

## Read the code

Read [agent.ex](agent.ex), then [check.ex](check.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/09_reasoning/09_06_got --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

The result is a combined conclusion. Request metadata retains graph nodes, edges and usage. Failure retains diagnostics without an answer commit.

## Limits

Aggregation is performed by model prompts, not a deterministic voting engine. General multi-leaf branching is not established. Tools, steering, rich input and typed output are unsupported for this method.

## Files

- [09_06_got_test.exs](../../../test/examples/09_reasoning/09_06_got/09_06_got_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Previous: [09_04](../09_04_tot/README.md) | Next: [09_08](../09_08_trm/README.md)
