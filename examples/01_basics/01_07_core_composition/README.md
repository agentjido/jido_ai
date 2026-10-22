# 01_07 — Core composition

Keep core Agent data and AI response data in separate sections.

## What you will learn

- Put core state schema in the `agent` block.
- Put model configuration in the top-level `ai` block.
- Keep other Agent extensions when you use `Jido.AI.Agent`.
- Generate a response without changing an Agent instance.

## Run it

```sh
mix test test/examples/01_basics/01_07_core_composition --include example --seed 0
```

This layer is stateless. A later runtime layer can decide how and when to
commit a response to Agent state.

## Files

- [Agent and extension](agent.ex)
- [Test](../../../test/examples/01_basics/01_07_core_composition/core_composition_test.exs)
