# TRM Weather Example

Canonical weather module: `lib/examples/weather/trm_agent.ex`.

```bash
mix jido_ai --agent Jido.AI.Examples.Weather.TRMAgent "Improve my severe-weather emergency plan for a 2-day power outage."
```

```elixir
{:ok, pid} = Jido.AgentServer.start_link(agent: Jido.AI.Examples.Weather.TRMAgent)

{:ok, response} =
  Jido.AI.Examples.Weather.TRMAgent.storm_readiness_sync(
    pid,
    "Two-day winter storm with likely outages."
  )
```
