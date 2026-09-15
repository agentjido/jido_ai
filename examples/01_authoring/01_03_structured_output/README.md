# 01_03 — Structured output

Validate a model result with Zoi and allow one repair before committing it.

## Read the code

Read [the Agent](agent.ex), then the tests. The result schema requires a
non-empty `answer`. `max_repairs 1` and `max_model_calls 2` bound the work;
no custom repair Flow is needed.

## Run it

From the package root:

```sh
mix test test/examples/01_authoring/01_03_structured_output --include example --seed 0
```

Expected result: all tests pass without credentials or a remote provider.
They use the [local model server](../../support/mock_llm.ex) through real ReqLLM
transport and AgentServer, with [test setup](../../../test/examples/support/example_case.ex).

## Important behavior

An invalid object produces validation feedback for the next model call.
The valid result becomes `state.answer == %{answer: "Fixed"}`. Repair exhaustion
preserves the previous state. Provider errors do not start schema repair.
A later request can succeed.

## Limits

Schema validation checks structure, not factual accuracy. The model response
is scripted; this is not a live-provider quality test.

## Files

- [Agent](agent.ex)
- [Tests](../../../test/examples/01_authoring/01_03_structured_output/01_03_structured_output_test.exs)

Previous: [01_02](../01_02_tool_flow/README.md) | Next: [01_04](../01_04_controls/README.md)
