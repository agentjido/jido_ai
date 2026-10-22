# 01_08 — Public model helpers

Resolve model IDs and aliases through the shared public model API.

## Read the code

This direct public-API lesson keeps executable calls in its matching tests;
it needs no placeholder Agent module.

## Run it

From the package root:

```sh
mix test test/examples/01_authoring/01_08_model_helpers --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

The tests resolve valid model inputs and reject invalid aliases or settings without starting unwanted provider work.

## Limits

This direct API lesson has no Agent source file. It does not export a rich model record as portable configuration.

## Files

- [01_08_model_helpers_test.exs](../../../test/examples/01_authoring/01_08_model_helpers/01_08_model_helpers_test.exs)

Previous: [01_07](../01_07_ai_runtime/README.md)
