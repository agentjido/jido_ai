# 01_09 — JSON SimpleAgent

This example defines and loads its own SimpleAgent through `Jido.Authoring`.
It then runs the imported Agent definition with a live model.

The `ai do` block lowers `reasoning Jido.AI.Strategy.ReAct` to a normal Jido
Agent route. `Jido.AI.Agent.Codec` stores the AI authoring form as a versioned
`jido.ai.agent` document. On import, it restores the reasoning Flow as the
direct request route. The plural `tools` field stores the ordered Action
references declared by the Agent's `tools do` block.

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
