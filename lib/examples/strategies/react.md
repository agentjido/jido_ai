# ReAct Weather Example

Canonical weather module: `lib/examples/weather/react_agent.ex`.

```bash
mix jido_ai --agent Jido.AI.Examples.Weather.ReActAgent "Should I bring an umbrella in Chicago this evening?"
```

```elixir
{:ok, pid} = Jido.AgentServer.start_link(agent: Jido.AI.Examples.Weather.ReActAgent)

{:ok, response} =
  Jido.AI.Examples.Weather.ReActAgent.commute_plan_sync(
    pid,
    "Seattle, WA"
  )
```
