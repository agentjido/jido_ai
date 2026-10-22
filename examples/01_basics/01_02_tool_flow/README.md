# 01_02 — Action and Flow tools

Let the model select a Jido Action or Flow. Return each result to the model.

## What you will learn

- Declare tools in a typed `tools` block.
- Give a tool a stable model-facing alias with `:as`.
- Run Action and Flow tools through `Jido.Exec`.
- Reject a mixed valid and invalid tool-call batch before any tool runs.
- Bound the loop with the `controls` block.

## Run it

```sh
mix test test/examples/01_basics/01_02_tool_flow --include example --seed 0
```

All tests are offline. They replace model calls and run the real Jido Action,
Flow, and ReqLLM tool adapters.

## Important behavior

A valid tool batch runs, and its correlated results enter the next model call.
If any call in a batch is invalid, no tool in that batch runs. The model gets
one correlated error result for each call and can correct the request within
the configured limits.

Action and Flow effects are not dispatched by this stateless response layer.
The adapter returns an explicit error if an executable produces effects.

## Files

- [Agent, Action, and Flow](agent.ex)
- [Tests](../../../test/examples/01_basics/01_02_tool_flow/tool_flow_test.exs)

Previous: [basic AI Agent](../01_01_basic_agent/README.md) | Next:
[structured output](../01_03_structured_output/README.md)
