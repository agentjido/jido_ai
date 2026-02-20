# CoT Weather Example

Canonical weather module: `lib/examples/weather/cot_agent.ex`.

```bash
mix jido_ai --agent Jido.AI.Examples.Weather.CoTAgent "How should I decide between biking and transit in rainy weather?"
```

```elixir
{:ok, pid} = Jido.AgentServer.start_link(agent: Jido.AI.Examples.Weather.CoTAgent)

{:ok, response} =
  Jido.AI.Examples.Weather.CoTAgent.weather_decision_sync(
    pid,
    "Should I run outdoors or at the gym if rain is likely?"
  )
```
