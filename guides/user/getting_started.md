# Getting Started With Jido.AI

You want a working agent quickly, without guessing where strategy, requests, and model aliases fit.

After this guide, you will have a `Jido.AI.Agent` running with one tool and a synchronous query path.

## Prerequisites

- Elixir `~> 1.18`
- API key configured for your provider

## 1. Add Dependencies

```elixir
# mix.exs
defp deps do
  [
    {:jido, "~> 2.0.0-rc.5"},
    {:jido_ai, "~> 2.0.0-rc.0"}
  ]
end
```

```bash
mix deps.get
```

## 2. Configure Model Aliases

```elixir
# config/config.exs
config :jido_ai,
  model_aliases: %{
    fast: "provider:fast-model",
    capable: "provider:capable-model"
  }
```

Use `Jido.AI.resolve_model/1` when you need to confirm runtime resolution.

## 3. Define a First Agent

```elixir
defmodule MyApp.WeatherAgent do
  use Jido.AI.Agent,
    name: "weather_agent",
    model: :fast,
    tools: [Jido.AI.Examples.Tools.ConvertTemperature],
    system_prompt: "You are a concise assistant. Use tools when needed."
end

{:ok, pid} = Jido.AgentServer.start(agent: MyApp.WeatherAgent)
{:ok, answer} = MyApp.WeatherAgent.ask_sync(pid, "Convert 21C to F")
```

This path uses:
- `Jido.AI.Agent` macro for agent wiring
- `Jido.AI.Request` under the hood for request tracking
- `Jido.AI` model alias resolution

## Failure Mode: Unknown Model Alias

Symptom:

```elixir
** (ArgumentError) Unknown model alias: :my_model
```

Fix:
- Add the alias under `config :jido_ai, model_aliases: ...`
- Or pass a direct model string like `"provider:exact-model-id"`

## Failure Mode: CompileError In tool_context

Symptom:

```elixir
** (CompileError) Unsafe construct in tool_context or tools: function call ...
```

Fix:
- `tool_context` must be literal data: module aliases, atoms, strings, numbers, lists, and maps
- Function calls, module attributes (`@my_attr`), and pinned variables (`^var`) are rejected at compile time

```elixir
# BAD — function call in tool_context
use Jido.AI.Agent,
  name: "my_agent",
  tools: [MyTool],
  tool_context: %{timestamp: DateTime.utc_now()}

# GOOD — literal data only
use Jido.AI.Agent,
  name: "my_agent",
  tools: [MyTool],
  tool_context: %{domain: MyApp.Domain, env: :production}
```

## Defaults You Should Know

- ReAct model default alias: `:fast` (resolved at runtime via `Jido.AI.resolve_model/1`)
- ReAct max iterations default: `10`
- Request await timeout default: `30_000ms`

## When To Use / Not Use

Use this path when:
- You need a working tool-using agent fast
- You want a stable starting point for production hardening

Do not use this path when:
- You need deep strategy tuning first (start with strategy playbook)
- You only need one-shot LLM calls (use actions directly)

## Next

- [Strategy Selection Playbook](strategy_selection_playbook.md)
- [First Agent](first_react_agent.md)
- [Configuration Reference](../developer/configuration_reference.md)
