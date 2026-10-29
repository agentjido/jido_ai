# 01_09 — JSON SimpleAgent

This example defines and loads its own SimpleAgent through `Jido.Authoring`.
It then runs the imported Agent definition with a live model.

The `ai do` block lowers `reasoning Jido.AI.Reasoning.ReAct` to a normal Jido
Agent Plugin. `Jido.Agent.Codec` stores it as a versioned
`jido.agent.definition` document. The AI Plugin stores the reasoning Flow,
its input defaults, and the ordered Action references from the `tools do`
block. On import, the extension restores the direct request route.

The JSON document contains data and Registry references. It does not contain
Elixir code. The application-owned Registry decides which Agent, Flow, Action,
and schema references the importer can use.

## Run it

Add `OPENAI_API_KEY` to `.env`, then run:

```sh
set -a
source .env
set +a
mix run examples/01_basics/01_09_json_agent/run.exs
```

Run the offline test:

```sh
mix test test/jido_ai_test.exs --seed 0
```

## Files

- [Registry and import](json_agent.ex)
- [Stored Agent](fixtures/agent.json)
- [Live runner](run.exs)
