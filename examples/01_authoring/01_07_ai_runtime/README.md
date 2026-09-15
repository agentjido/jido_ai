# 01_07 — AI profiles and core composition

Combine a typed AI result, Action and Flow tools, and Plugin-owned state.

## Read the code

Read [agent.ex](agent.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/01_authoring/01_07_ai_runtime --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

Tool results reach the next model call. The commit counter advances only on successful core commits. Rejected work preserves the prior domain result.

## Limits

This is one-Turn execution. Session steering, streaming and restore are separate lessons. Test observers and barriers are supplied only by the tests.

## Files

- [01_07_ai_runtime_test.exs](../../../test/examples/01_authoring/01_07_ai_runtime/01_07_ai_runtime_test.exs)
- [Shared quote.ex](../support/quote.ex)
- [Shared close_case.ex](../../support/close_case.ex)
- [Shared commit_counter.ex](../../support/commit_counter.ex)
- [Shared mock_llm.ex](../../support/mock_llm.ex)
- [Shared multiply.ex](../../support/multiply.ex)

Previous: [01_06](../01_06_ai_extension/README.md) | Next: [01_08](../01_08_model_helpers/README.md)
