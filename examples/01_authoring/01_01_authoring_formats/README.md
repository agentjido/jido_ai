# 01_01 — One AI answer

Use an AI profile and a generated command to write one answer into Agent state.

## Read the code

Read [the Agent](agent.ex), then the tests. The `ai` block owns the model,
limits, and result destination. Call `Agent.ask_sync/3` to wait for the answer.
The core `Agent.answer/3` helper returns the admission Agent revision only.

## Run it

From the package root:

```sh
mix test test/examples/01_authoring/01_01_authoring_formats --include example --seed 0
```

Expected result: all tests pass without credentials or a remote provider.
They use the [local model server](../../support/mock_llm.ex) through real ReqLLM
transport and AgentServer, with [test setup](../../../test/examples/support/example_case.ex).

## Important behavior

The answer is `Ready`; existing domain data remains unchanged. A provider
failure preserves the previous answer and records a failed request. A later
request can succeed. Retained request records do not enable Context retention.

## Limits

This lesson uses one static AI DSL definition, not an authoring-format matrix.
See [AI extension composition](../01_06_ai_extension/README.md) and the
[authoring tests](../../../test/authoring) for alternate forms.

## Files

- [Agent](agent.ex)
- [Tests](../../../test/examples/01_authoring/01_01_authoring_formats/01_01_authoring_formats_test.exs)

Next: [01_02](../01_02_tool_flow/README.md)
