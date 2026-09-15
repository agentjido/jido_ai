# 09_10 — Adaptive method selection

Select a reasoning method before running the normal request flow.

## Read the code

Read [agent.ex](agent.ex), then [check.ex](check.ex), then [number.ex](number.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/09_reasoning/09_10_adaptive --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

Selection adds no model call. The selected method retains its own result shape and limits. A later request can select a different method.

## Limits

Selection uses fixed keyword and complexity rules, not a trained quality judge. Only ReAct and ToT use tools. Selected-method restrictions still apply; no durable phase resume is claimed.

## Files

- [09_10_adaptive_test.exs](../../../test/examples/09_reasoning/09_10_adaptive/09_10_adaptive_test.exs)
- [Shared close_case.ex](../../support/close_case.ex)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Previous: [09_08](../09_08_trm/README.md) | Next: [09_14](../09_14_callable_reasoning/README.md)
