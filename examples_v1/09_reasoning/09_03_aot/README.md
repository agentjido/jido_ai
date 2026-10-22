# 09_03 — Algorithm of Thoughts

Use algorithmic search instructions in one model generation.

## Read the code

Read [agent.ex](agent.ex), then [check.ex](check.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/09_reasoning/09_03_aot --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

The method parses the puzzle response into an answer map. Limits, output validation and failure preserve the common request contract.

## Limits

AoT does not execute tools or accept steering. A parsed search explanation is not proof that the model performed a correct search.

## Files

- [aot_lifecycle_test.exs](../../../test/examples/09_reasoning/09_03_aot/aot_lifecycle_test.exs)
- [09_03_aot_test.exs](../../../test/examples/09_reasoning/09_03_aot/09_03_aot_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Previous: [09_02](../09_02_method_api/README.md) | Next: [09_04](../09_04_tot/README.md)
