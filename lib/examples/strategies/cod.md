# CoD Weather Example

Canonical weather module: `lib/examples/weather/cod_agent.ex`.

```bash
mix jido_ai --agent Jido.AI.Examples.Weather.CoDAgent "Give me a fast weather-aware commute recommendation with one backup."
```

```elixir
{:ok, pid} = Jido.AgentServer.start_link(agent: Jido.AI.Examples.Weather.CoDAgent)

{:ok, response} =
  Jido.AI.Examples.Weather.CoDAgent.quick_plan_sync(
    pid,
    "Need a quick commute plan for rainy weather tomorrow morning."
  )
```
