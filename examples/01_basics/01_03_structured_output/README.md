# 01_03 — Structured output

Use a route reply projection as the structured reply contract.

## What you will learn

- Define the request schema on the route Action.
- Shape the model result from the schema at the route reply output path.
- Define the Agent behavior in an embedded `graph do` Flow.
- Let core Jido build a correlated Reply Directive from route output.

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
