# 01_03 — Structured output

Use a routed `Jido.SignalAction` as the structured reply contract.

## What you will learn

- Define request and reply Signal contracts in one Action.
- Shape the model result from the reply schema.
- Define the Agent reasoning steps in an embedded `reasoning do` Flow.
- Return a correlated Reply Directive from a normal route Action.

## Run it

From the package root:

```sh
mix test test/examples/01_basics/01_03_structured_output --include example --seed 0
```

The test replaces the ReqLLM request. It checks the derived descriptor, parsed
data, and Reply Signal. It does not use an API key or the network.

## Files

- [Agent](agent.ex)
- [Test](../../../test/examples/01_basics/01_03_structured_output/structured_output_test.exs)
