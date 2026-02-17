# CLI Workflows

You want fast one-shot automation or batch processing from shell workflows.

After this guide, you can run `mix jido_ai` in one-shot and stdin modes.

## One-Shot Query

```bash
mix jido_ai --type react --model anthropic:claude-haiku-4-5 "Calculate 15 * 23"
```

## Batch Mode From Stdin

```bash
cat queries.txt | mix jido_ai --stdin --format json --quiet
```

## Run With Existing Agent Module

```bash
mix jido_ai --agent MyApp.WeatherAgent "Will it rain in Seattle?"
```

## Skill CLI

```bash
mix jido_ai.skill list priv/skills
mix jido_ai.skill validate priv/skills --strict
```

## Defaults You Should Know

- default type: `react`
- default timeout: `60_000ms`
- default output format: `text`

## When To Use / Not Use

Use CLI workflows when:
- you need manual testing, shell scripting, or quick incident triage

Do not use CLI workflows when:
- you need embedded in-app orchestration; use direct module APIs

## Next

- [Getting Started](getting_started.md)
- [Strategy Selection Playbook](strategy_selection_playbook.md)
- [CLI Adapter Internals](../developer/architecture_and_runtime_flow.md)
