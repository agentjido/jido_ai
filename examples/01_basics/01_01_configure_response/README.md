# 01_01 — Configure an AI response

Add the Jido AI Plugin to a core Jido Agent and define the model and
instructions for its response.

## What you will learn

- Add `Jido.AI.Plugin` through the core Agent extension list.
- Use the `ai` block to declare a model and instructions.
- Read the normalized configuration from an Agent definition or instance.

## Read the code

Read [the Agent](agent.ex), then read
[the test](../../../test/examples/01_basics/01_01_configure_response/configure_response_test.exs).

## Run it

From the package root:

```sh
mix test test/examples/01_basics/01_01_configure_response --include example --seed 0
```

Expected result: one test passes without an API key or network call.

## Important behavior

The Plugin stores normalized AI response configuration in the Agent definition.
The same configuration is available from an Agent instance.

## Limits

This example does not call a model or produce an answer. It teaches only the
first stable configuration contract.

## Files

- [Agent](agent.ex)
- [Test](../../../test/examples/01_basics/01_01_configure_response/configure_response_test.exs)

Next: model response execution will be the next example after that public
contract exists.
