# 03_03 — Numeric tool inputs

Convert complete numeric strings at the model-tool boundary.

## Read the code

Read [agent.ex](agent.ex), then [flow.ex](flow.ex), then [read.ex](read.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/03_tools/03_03_numeric_inputs --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

Both an Action and Flow receive typed numeric values, including nested items. Their actual result reaches the next model call. Invalid input rejects the whole batch before tool start.

## Limits

This is schema-directed tool normalization, not general scalar coercion. Ordinary request and Signal validation remains strict.

## Files

- [03_03_numeric_inputs_test.exs](../../../test/examples/03_tools/03_03_numeric_inputs/03_03_numeric_inputs_test.exs)

See the [example catalog](../../README.md).
