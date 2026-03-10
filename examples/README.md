# Jido.AI Examples

The runnable agents, tools, and demo scripts for `jido_ai` live in this standalone Mix project.
This keeps optional example dependencies out of the core package dependency graph while preserving
copy-pasteable demos and tests.

## Setup

```bash
mix deps.get
```

`examples/.env` is loaded automatically when present. If it does not exist, the scripts also fall
back to `../.env`.

## Run Demo Scripts

```bash
mix run scripts/demo/actions_llm_runtime_demo.exs
mix run scripts/demo/actions_tool_calling_runtime_demo.exs
mix run scripts/demo/actions_reasoning_runtime_demo.exs
mix run scripts/demo/weather_multi_turn_context_demo.exs
```

## Run Example Agents

```bash
mix jido_ai --agent Jido.AI.Examples.Weather.ReActAgent \
  "Should I bring an umbrella in Chicago this evening?"
```

## Test

```bash
mix test
```
