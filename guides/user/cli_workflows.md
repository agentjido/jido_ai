# CLI Workflows

You want fast one-shot automation or batch processing from shell workflows.

After this guide, you can run `mix jido_ai` in one-shot, stdin, and agent-module modes.

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

## Strategy Type Sweep

Use this block to smoke test each built-in strategy adapter with `--type`:

```bash
for strategy in react aot cod cot tot got trm adaptive; do
  mix jido_ai --type "$strategy" "Give one sentence about strategy ${strategy}."
done
```

## CLI Task Options and Constraints

Supported `mix jido_ai` flags:
- `--type` (`react | aot | cod | cot | tot | got | trm | adaptive`)
- `--agent`
- `--model`
- `--tools`
- `--system`
- `--max-iterations`
- `--stdin`
- `--format` (`text | json`)
- `--quiet`
- `--timeout`
- `--trace`

Adapter mapping:
- `react -> Jido.AI.Reasoning.ReAct.CLIAdapter`
- `aot -> Jido.AI.Reasoning.AlgorithmOfThoughts.CLIAdapter`
- `cod -> Jido.AI.Reasoning.ChainOfDraft.CLIAdapter`
- `cot -> Jido.AI.Reasoning.ChainOfThought.CLIAdapter`
- `tot -> Jido.AI.Reasoning.TreeOfThoughts.CLIAdapter`
- `got -> Jido.AI.Reasoning.GraphOfThoughts.CLIAdapter`
- `trm -> Jido.AI.Reasoning.TRM.CLIAdapter`
- `adaptive -> Jido.AI.Reasoning.Adaptive.CLIAdapter`

Constraints:
- If `--agent` is provided, it bypasses ephemeral agent creation.
- `--agent` ignores `--model`, `--tools`, and `--system`.
- If the agent module exports `cli_adapter/0`, that adapter is used.

## CLI Error Formatting

Text mode (`--format text`) prints prefixed lines:

```text
Fatal: Unknown agent type: nope. Supported: react, aot, cod, cot, tot, got, trm, adaptive
Error: Timeout waiting for agent completion
```

JSON mode (`--format json`) emits machine-readable objects:

```json
{"ok":false,"error":"Unknown agent type: nope. Supported: react, aot, cod, cot, tot, got, trm, adaptive"}
{"ok":false,"query":"prompt","error":"Timeout waiting for agent completion","elapsed_ms":60001}
```

## Skill CLI

```bash
mix jido_ai.skill list priv/skills
mix jido_ai.skill show priv/skills/code-review/SKILL.md --body
mix jido_ai.skill validate priv/skills --strict
mix jido_ai.skill validate priv/skills --json
```

Skill CLI error handling:
- `mix jido_ai.skill list` with no paths prints usage
- `mix jido_ai.skill validate` with no paths prints usage
- `--strict` exits non-zero if any skill fails validation

## Defaults You Should Know

- default type: `react`
- supported types: `react | aot | cod | cot | tot | got | trm | adaptive`
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
