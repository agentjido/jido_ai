# Alternatives

This guide explores alternative solutions to building agent and workflow systems in Elixir. Understanding these alternatives helps you make informed decisions about when to use Jido versus other approaches.

## Built-in Elixir Solutions

### Agent Module

The built-in [Agent](https://hexdocs.pm/elixir/Agent.html) module provides simple state management without the complexity of full agent systems. Use it when you need basic state management without complex behaviors or signal routing.

```elixir
{:ok, agent} = Agent.start_link(fn -> %{} end)
Agent.update(agent, fn state -> Map.put(state, :key, "value") end)
```

### GenServer

[GenServer](https://hexdocs.pm/elixir/GenServer.html) offers process management and state machines. Choose it for direct process communication and simple request/response patterns without complex workflows.

## Data Processing Frameworks

### Broadway

[Broadway](https://github.com/dashbitco/broadway) excels at data ingestion and processing. Ideal for stream processing with back-pressure and rate limiting, without agent-based decision making.

### Flow

[Flow](https://github.com/dashbitco/flow) provides data-flow processing for parallel operations. Best for MapReduce-style operations when you don't need persistent agent state.

### Oban

[Oban](https://github.com/sorentwo/oban) offers PostgreSQL-backed job processing. Choose it for durable background jobs and scheduling without agent behaviors.

## Agent Systems

### Swarm.ex

[Swarm.ex](https://github.com/nrrso/swarm_ex) provides a swarm intelligence framework. Suitable for collective behavior simulations and distributed problem-solving without Jido's focus on individual agent reasoning.

## When to Choose Jido

Select Jido when you need:

1. Complex agent behaviors with multi-step reasoning
2. Distributed intelligence with sensor-driven responses
3. Extensible architecture with custom skills and pluggable sensors

Want to add or edit this list? Open a [pull request](https://github.com/agentjido/jido/edit/main/guides/about/alternatives.md).

For a broader list of Elixir packages, visit [Awesome Elixir](https://github.com/h4cc/awesome-elixir).
