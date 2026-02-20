# GoT Weather Example

Canonical weather module: `lib/examples/weather/got_agent.ex`.

```bash
mix jido_ai --agent Jido.AI.Examples.Weather.GoTAgent "Synthesize weather travel risk for NYC, Chicago, and Denver this weekend."
```

```elixir
{:ok, pid} = Jido.AgentServer.start_link(agent: Jido.AI.Examples.Weather.GoTAgent)

{:ok, result} =
  Jido.AI.Examples.Weather.GoTAgent.multi_city_sync(
    pid,
    ["NYC", "Chicago", "Denver"]
  )
```
