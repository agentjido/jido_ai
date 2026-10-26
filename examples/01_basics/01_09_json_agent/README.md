# 01_09 — JSON AI Agent

Export and import a complete graph-based AI Agent definition through
`Jido.Authoring`, then run it with a real model.

## What you will learn

- Store the AI plugin data inside a core Agent JSON document.
- Select the Agent's workflow graph in JSON.
- Use trusted Registry references for Actions, Flows, and controls.
- Import a direct provider model name from JSON.
- Run the imported Agent graph to an explicit completed result.

## Run it

First, add `OPENAI_API_KEY` to `.env`. The saved JSON selects
`openai:gpt-4o-mini` directly.

Run the complete live example:

```sh
mix run examples/01_basics/01_09_json_agent/run.exs
```

Run the offline authoring checks:

```sh
mix test test/examples/01_basics/01_09_json_agent --include example --seed 0
```

Run the automated live check:

```sh
mix test.live test/live/json_agent_test.exs --seed 0
```

The Registry is an allowlist. Import fails when the document refers to an
Action, Flow, plugin, schema, or Agent that is not in this Registry. Inline
Actions are implementation details and cannot be imported by reference. Use a
named Action for a portable tool or control.

## Files

- [Agent and Registry](json_agent.ex)
- [Saved JSON](fixtures/agent.json)
- [Live Runner](run.exs)
- [Test](../../../test/examples/01_basics/01_09_json_agent/json_agent_test.exs)
