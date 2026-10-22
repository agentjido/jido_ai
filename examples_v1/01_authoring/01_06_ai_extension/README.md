# 01_06 — AI extension composition

Add AI behavior to a core Agent with `extensions: [Jido.AI.DSL]`.

## Read the code

Read [spec.exs](spec.exs).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/01_authoring/01_06_ai_extension --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

A typed answer commits while existing case data remains unchanged. Invalid profile declarations fail before model work.

## Limits

This is the explicit core-extension form. Use `Jido.AI.Agent` for a normal static AI Agent. Definition matrices belong in the authoring suite.

## Files

- [01_06_ai_extension_test.exs](../../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Previous: [01_05](../01_05_streaming/README.md) | Next: [01_07](../01_07_ai_runtime/README.md)
