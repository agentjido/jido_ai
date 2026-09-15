# 09_04 — Tree of Thoughts

Generate, score and select thought branches within a bounded search.

## Read the code

Read [agent.ex](agent.ex), then [check.ex](check.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/09_reasoning/09_04_tot --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

The scripted search selects the better candidate and retains ranked candidates, the tree, usage and termination data. Request failure does not commit a domain answer.

## Limits

Search duration is a stop rule checked between phases; use the request timeout for a hard deadline. Text queries are supported; steering and typed result schemas are rejected. This is not durable search resume.

## Files

- [09_04_tot_test.exs](../../../test/examples/09_reasoning/09_04_tot/09_04_tot_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Previous: [09_03](../09_03_aot/README.md) | Next: [09_06](../09_06_got/README.md)
