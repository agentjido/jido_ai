# ToT Weather Example

Canonical weather module: `lib/examples/weather/tot_agent.ex`.

```bash
mix jido_ai --agent Jido.AI.Examples.Weather.ToTAgent "Plan three weekend activity options in Seattle with weather uncertainty."
```

```elixir
{:ok, pid} = Jido.AgentServer.start_link(agent: Jido.AI.Examples.Weather.ToTAgent)
{:ok, result} = Jido.AI.Examples.Weather.ToTAgent.weekend_options_sync(pid, "Seattle, WA")
IO.puts(Jido.AI.Examples.Weather.ToTAgent.format_top_options(result, 3))
```
