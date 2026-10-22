# 09_02 — Linear method APIs

Select Chain of Thought and Chain of Draft through their public method APIs.

## Read the code

Read [agent.ex](agent.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/09_reasoning/09_02_method_api --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

Separate profiles run through the same Session runtime. Public accessors read steps, conclusions and raw responses from committed results.

## Limits

This lesson teaches method selection through source definitions. It does not introduce a separate executor or measure reasoning quality.

## Files

- [09_02_method_api_test.exs](../../../test/examples/09_reasoning/09_02_method_api/09_02_method_api_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Next: [09_03](../09_03_aot/README.md)
