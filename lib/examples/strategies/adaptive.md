# Adaptive Weather Example

Canonical weather module: `lib/examples/weather/adaptive_agent.ex`.

```bash
mix jido_ai --agent Jido.AI.Examples.Weather.AdaptiveAgent "I have flights through two cities this weekend. Give me a weather-aware plan."
```

```elixir
{:ok, pid} = Jido.AgentServer.start_link(agent: Jido.AI.Examples.Weather.AdaptiveAgent)

{:ok, response} =
  Jido.AI.Examples.Weather.AdaptiveAgent.coach_sync(
    pid,
    "Need a weather-aware commute and backup plan for tomorrow."
  )
```
