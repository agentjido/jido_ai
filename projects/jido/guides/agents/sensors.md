# Agent Sensors in Jido

## Overview

Sensors provide a mechanism for monitoring and responding to external events in Jido's agent system. They act as event producers that dispatch signals back to their parent agent, enabling reactive behavior patterns.

Learn more about [sensors](sensors/overview.md) in the sensors guide. This guide is focused on how Agents utilize Sensors to monitor and respond to external events.

## Core Concepts

- Sensors are initialized during agent server startup
- Each sensor receives the agent's PID as its target
- Sensors automatically dispatch signals back to their parent agent
- Multiple sensors can be configured per agent

## Basic Configuration

The simplest way to add sensors to an agent is through the `:sensors` option when starting the server:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent"


  def start_link(opts) do
    # Start agent with sensors
    {:ok, pid} = Jido.Agent.Server.start_link(
      child_spec: [
        {Jido.Sensors.Heartbeat, interval: 5000},
        {Jido.Sensors.FileWatcher, path: "/tmp/watch"}
      ]
    )
  end
end
```

```

```
