# 01_04 — Input and output controls

Reject unauthorized work before generation and reject an answer without an evidence marker.

## Read the code

Read [the Agent](agent.ex), [Access](access.ex), then [Evidence](evidence.ex).
The profile declares both controls. The host supplies authorization in execution
context; the user's query must not grant permission.

## Run it

From the package root:

```sh
mix test test/examples/01_authoring/01_04_controls --include example --seed 0
```

Expected result: all tests pass without credentials or a remote provider.
They use the [local model server](../../support/mock_llm.ex) through real ReqLLM
transport and AgentServer, with [test setup](../../../test/examples/support/example_case.ex).

## Important behavior

Missing or false authorization prevents the model call. An answer without
`[evidence]` fails before state commit. A valid answer commits, including after
a previous rejection. Provider and decoder errors preserve the previous state.

## Limits

The marker is not proof that an answer is true or has valid sources. The Access
control illustrates a policy boundary, not a complete authentication system.

## Files

- [Agent](agent.ex)
- [Tests](../../../test/examples/01_authoring/01_04_controls/01_04_controls_test.exs)

Previous: [01_03](../01_03_structured_output/README.md) | Next: [01_05](../01_05_streaming/README.md)
