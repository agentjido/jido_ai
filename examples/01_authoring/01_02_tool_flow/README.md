# 01_02 — Action and Flow tools

Let the model select an Action or Flow, then use their results in an answer.

## Read the code

Read [the Agent](agent.ex), [Multiply](../../support/multiply.ex), then
[Quote](../support/quote.ex). Multiply is shared across sections. Quote is shared
within this section and has an explicit Flow output. Their named modules give
the tools stable identities.

## Run it

From the package root:

```sh
mix test test/examples/01_authoring/01_02_tool_flow --include example --seed 0
```

Expected result: all tests pass without credentials or a remote provider.
They use the [local model server](../../support/mock_llm.ex) through real ReqLLM
transport and AgentServer, with [test setup](../../../test/examples/support/example_case.ex).

## Important behavior

The next model call receives results `6` and `20`, with their original call IDs.
The final answer enters Agent state. An unknown tool or invalid arguments in a
batch prevent every tool in that batch from starting. The model-call limit
stops further model calls without committing an answer.

## Limits

These tools have no external side effects. A later model failure does not undo
a tool's external work. The tests do not prove rollback for such work.

## Files

- [Agent](agent.ex)
- [Tests](../../../test/examples/01_authoring/01_02_tool_flow/01_02_tool_flow_test.exs)

Previous: [01_01](../01_01_authoring_formats/README.md) | Next: [01_03](../01_03_structured_output/README.md)
