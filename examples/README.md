# Jido.AI Examples

The runnable agents, tools, and demo scripts for `jido_ai` live in this top-level `examples/`
folder. They stay out of the root `elixirc_paths`, so the core package does not compile example
modules by default.

Run everything from the repository root. `.env` is loaded from the repo root when present.

## Run Demo Scripts

```bash
mix run examples/scripts/demo/actions_llm_runtime_demo.exs
mix run examples/scripts/demo/actions_tool_calling_runtime_demo.exs
mix run examples/scripts/demo/actions_reasoning_runtime_demo.exs
mix run examples/scripts/demo/weather_multi_turn_context_demo.exs
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
