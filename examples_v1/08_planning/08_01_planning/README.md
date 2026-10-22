# 08_01 — Planning Actions

Generate plans, decompositions and priority lists through a capability Plugin.

## Read the code

Read [agent.ex](agent.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/08_planning/08_01_planning --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

Plan, Decompose and Prioritize retain original text and parsed results. The Agent commits the selected result field. Invalid input and provider failure preserve prior domain state.

The reasoning Plugin binds a Profile at construction. Its route accepts only
the prompt and commits the reasoning envelope to `review`. Planning keeps its
separate `result` field; neither operation replaces the other result.

## Limits

These Actions do not validate or execute a generated plan. Step counts are prompt guidance. Durable plan execution and repair are outside this lesson.

## Files

- [08_01_planning_test.exs](../../../test/examples/08_planning/08_01_planning/08_01_planning_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)
- [Shared set_case.ex](../../support/set_case.ex)

See the [example catalog](../../README.md).
