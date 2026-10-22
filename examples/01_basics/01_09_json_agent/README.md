# 01_09 — JSON AI Agent

Export and import a complete AI Agent definition through `Jido.Authoring`.

## What you will learn

- Store the AI plugin data inside a core Agent JSON document.
- Use trusted Registry references for Actions, Flows, and controls.
- Import a model alias without creating an atom from JSON.
- Run the imported neutral Agent through its typed AI route.

## Run it

```sh
mix test test/examples/01_basics/01_09_json_agent --include example --seed 0
```

The Registry is an allowlist. Import fails when the document refers to an
Action, Flow, plugin, schema, or Agent that is not in this Registry. Inline
Actions are implementation details and cannot be imported by reference. Use a
named Action for a portable tool or control.

## Files

- [Agent and Registry](json_agent.ex)
- [Saved JSON](fixtures/agent.json)
- [Test](../../../test/examples/01_basics/01_09_json_agent/json_agent_test.exs)
