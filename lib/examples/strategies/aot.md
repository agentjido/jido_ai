# AoT Weather Example

Canonical weather module: `lib/examples/weather/aot_agent.ex`.

```bash
mix jido_ai --agent Jido.AI.Examples.Weather.AoTAgent "Find the best weather-safe weekend option with one backup plan."
```

```elixir
{:ok, pid} = Jido.AgentServer.start_link(agent: Jido.AI.Examples.Weather.AoTAgent)

{:ok, result} =
  Jido.AI.Examples.Weather.AoTAgent.weekend_options_sync(
    pid,
    "Find the best weather-safe weekend option with one fallback."
  )
```
