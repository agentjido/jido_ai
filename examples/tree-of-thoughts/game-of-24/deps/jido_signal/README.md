# Jido.Signal

[![Hex.pm](https://img.shields.io/hexpm/v/jido_signal.svg)](https://hex.pm/packages/jido_signal)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/jido_signal/)
[![CI](https://github.com/agentjido/jido_signal/actions/workflows/elixir-ci.yml/badge.svg)](https://github.com/agentjido/jido_signal/actions/workflows/elixir-ci.yml)
[![License](https://img.shields.io/hexpm/l/jido_signal.svg)](https://github.com/agentjido/jido_signal/blob/main/LICENSE.md)
[![Coverage Status](https://coveralls.io/repos/github/agentjido/jido_signal/badge.svg?branch=main)](https://coveralls.io/github/agentjido/jido_signal?branch=main)

> **Agent Communication Envelope and Utilities**

_`Jido.Signal` is part of the [Jido](https://github.com/agentjido/jido) project. Learn more about Jido at [agentjido.xyz](https://agentjido.xyz)._

## Overview

`Jido.Signal` is a sophisticated toolkit for building event-driven and agent-based systems in Elixir. It provides a complete ecosystem for defining, routing, dispatching, and tracking signals throughout your application, built on the CloudEvents v1.0.2 specification with powerful Jido-specific extensions.

Whether you're building microservices that need reliable event communication, implementing complex agent-based systems, or creating observable distributed applications, Jido.Signal provides the foundation for robust, traceable, and scalable event-driven architecture.

## Why Do I Need Signals?

**Agent Communication in Elixir's Process-Driven World**

Elixir's strength lies in lightweight processes that communicate via message passing, but raw message passing has limitations when building complex systems:

- **Phoenix Channels** need structured event broadcasting across connections
- **GenServers** require reliable inter-process communication with context
- **Agent Systems** demand traceable conversations between autonomous processes
- **Distributed Services** need standardized message formats across nodes

Traditional Elixir messaging (`send`, `GenServer.cast/call`) works great for simple scenarios, but falls short when you need:

- **Standardized Message Format**: Raw tuples and maps lack structure and metadata
- **Event Routing**: Broadcasting to multiple interested processes based on patterns
- **Conversation Tracking**: Understanding which message caused which response
- **Reliable Delivery**: Ensuring critical messages aren't lost if a process crashes
- **Cross-System Integration**: Communicating with external services via webhooks/HTTP

```elixir
# Traditional Elixir messaging
GenServer.cast(my_server, {:user_created, user_id, email})  # Unstructured
send(pid, {:event, data})  # No routing or reliability

# With Jido.Signal
{:ok, signal} = UserCreated.new(%{user_id: user_id, email: email})
Bus.publish(:app_bus, [signal])  # Structured, routed, traceable, reliable
```

Jido.Signal transforms Elixir's message passing into a sophisticated communication system that scales from simple GenServer interactions to complex multi-agent orchestration across distributed systems.

## Key Features

### **Standardized Signal Structure**
- CloudEvents v1.0.2 compliant message format
- Custom signal types with data validation
- Rich metadata and context tracking
- Flexible serialization (JSON, MessagePack, Erlang Term Format)

### **High-Performance Signal Bus**
- In-memory GenServer-based pub/sub system
- Persistent subscriptions with acknowledgment
- Middleware pipeline for cross-cutting concerns
- Complete signal history with replay capabilities

### **Advanced Routing Engine**
- Trie-based pattern matching for optimal performance
- Wildcard support (`*` single-level, `**` multi-level)
- Priority-based execution ordering
- Custom pattern matching functions

### **Pluggable Dispatch System**
- Multiple delivery adapters (PID, PubSub, HTTP, Logger, Console)
- Synchronous and asynchronous delivery modes
- Batch processing for high-throughput scenarios
- Configurable timeout and retry mechanisms

### **Causality & Conversation Tracking**
- Complete signal relationship graphs
- Cause-effect chain analysis
- Conversation grouping and temporal ordering
- Comprehensive system traceability for debugging and auditing

## Installation

Add `jido_signal` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido_signal, "~> 1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Quick Start

### 1. Start a Signal Bus

Add to your application's supervision tree:

```elixir
# In your application.ex
children = [
  {Jido.Signal.Bus, name: :my_app_bus}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

### 2. Create a Subscriber

```elixir
defmodule MySubscriber do
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{})
  def init(state), do: {:ok, state}

  # Handle incoming signals
  def handle_info({:signal, signal}, state) do
    IO.puts("Received: #{signal.type}")
    {:noreply, state}
  end
end
```

### 3. Subscribe and Publish

```elixir
alias Jido.Signal.Bus
alias Jido.Signal

# Start subscriber and subscribe to user events
{:ok, sub_pid} = MySubscriber.start_link([])
{:ok, _sub_id} = Bus.subscribe(:my_app_bus, "user.*", dispatch: {:pid, target: sub_pid})

# Create and publish a signal
{:ok, signal} = Signal.new(%{
  type: "user.created",
  source: "/auth/registration",
  data: %{user_id: "123", email: "user@example.com"}
})

Bus.publish(:my_app_bus, [signal])
# Output: "Received: user.created"
```

## Core Concepts

### The Signal

Signals are CloudEvents-compliant message envelopes that carry your application's events:

```elixir
# Basic signal
{:ok, signal} = Signal.new(%{
  type: "order.created",
  source: "/ecommerce/orders",
  data: %{order_id: "ord_123", amount: 99.99}
})

# With dispatch configuration
{:ok, signal} = Signal.new(%{
  type: "payment.processed",
  source: "/payments",
  data: %{payment_id: "pay_456"},
  jido_dispatch: [
    {:pubsub, topic: "payments"},
    {:webhook, url: "https://api.partner.com/webhook", secret: "secret123"}
  ]
})
```

### Custom Signal Types

Define strongly-typed signals with validation:

```elixir
defmodule UserCreated do
  use Jido.Signal,
    type: "user.created.v1",
    default_source: "/users",
    schema: [
      user_id: [type: :string, required: true],
      email: [type: :string, required: true, format: ~r/@/],
      name: [type: :string, required: true]
    ]
end

# Usage
{:ok, signal} = UserCreated.new(%{
  user_id: "u_123",
  email: "john@example.com",
  name: "John Doe"
})

# Validation errors
{:error, reason} = UserCreated.new(%{user_id: "u_123"})
# => {:error, "Invalid data for Signal: Required key :email not found"}
```

### The Router

Powerful pattern matching for signal routing:

```elixir
alias Jido.Signal.Router

routes = [
  # Exact matches have highest priority
  {"user.created", :handle_user_creation},
  
  # Single-level wildcards
  {"user.*.updated", :handle_user_updates},
  
  # Multi-level wildcards
  {"audit.**", :audit_logger, 100},  # High priority
  
  # Pattern matching functions
  {fn signal -> String.contains?(signal.type, "error") end, :error_handler}
]

{:ok, router} = Router.new(routes)

# Route signals to handlers
{:ok, targets} = Router.route(router, %Signal{type: "user.profile.updated"})
# => {:ok, [:handle_user_updates, :audit_logger]}
```

### Dispatch System

Flexible delivery to multiple destinations:

```elixir
alias Jido.Signal.Dispatch

dispatch_configs = [
  # Send to process
  {:pid, target: my_process_pid},
  
  # Publish via Phoenix.PubSub
  {:pubsub, target: MyApp.PubSub, topic: "events"},
  
  # HTTP webhook with signature
  {:webhook, url: "https://api.example.com/webhook", secret: "secret123"},
  
  # Log structured data
  {:logger, level: :info, structured: true},
  
  # Console output
  {:console, format: :pretty}
]

# Synchronous dispatch
:ok = Dispatch.dispatch(signal, dispatch_configs)

# Asynchronous dispatch
{:ok, task} = Dispatch.dispatch_async(signal, dispatch_configs)
```

## Advanced Features

### Persistent Subscriptions

Ensure reliable message delivery with acknowledgments:

```elixir
# Create persistent subscription
{:ok, sub_id} = Bus.subscribe(:my_app_bus, "payment.*", 
  persistent?: true, 
  dispatch: {:pid, target: self()}
)

# Receive and acknowledge signals
receive do
  {:signal, signal} ->
    # Process the signal
    process_payment(signal)
    
    # Acknowledge successful processing
    Bus.ack(:my_app_bus, sub_id, signal.id)
end

# If subscriber crashes and restarts
Bus.reconnect(:my_app_bus, sub_id, self())
# Unacknowledged signals are automatically replayed
```

### Middleware Pipeline

Add cross-cutting concerns with middleware:

```elixir
middleware = [
  # Built-in logging middleware
  {Jido.Signal.Bus.Middleware.Logger, [
    level: :info,
    include_signal_data: true
  ]},
  
  # Custom middleware
  {MyApp.AuthMiddleware, []},
  {MyApp.MetricsMiddleware, []}
]

{:ok, _pid} = Jido.Signal.Bus.start_link(
  name: :my_bus, 
  middleware: middleware
)
```

### Causality Tracking

Track signal relationships for complete system observability:

```elixir
alias Jido.Signal.Journal

# Create journal
journal = Journal.new()

# Record causal relationships
Journal.record(journal, initial_signal, nil)  # Root cause
Journal.record(journal, response_signal, initial_signal.id)  # Caused by initial_signal
Journal.record(journal, side_effect, initial_signal.id)     # Also caused by initial_signal

# Analyze relationships
effects = Journal.get_effects(journal, initial_signal.id)
# => [response_signal, side_effect]

cause = Journal.get_cause(journal, response_signal.id)
# => initial_signal
```

### Signal History & Replay

Access complete signal history:

```elixir
# Get recent signals matching pattern
{:ok, signals} = Bus.replay(:my_app_bus, "user.*", 
  since: DateTime.utc_now() |> DateTime.add(-3600, :second),
  limit: 100
)

# Replay to new subscriber
{:ok, new_sub} = Bus.subscribe(:my_app_bus, "user.*", 
  dispatch: {:pid, target: new_process_pid},
  replay_since: DateTime.utc_now() |> DateTime.add(-1800, :second)
)
```

### Snapshots

Create point-in-time views of your signal log:

```elixir
# Create filtered snapshot
{:ok, snapshot_id} = Bus.snapshot_create(:my_app_bus, %{
  path_pattern: "order.**",
  since: ~U[2024-01-01 00:00:00Z],
  until: ~U[2024-01-31 23:59:59Z]
})

# Read snapshot data
{:ok, signals} = Bus.snapshot_read(:my_app_bus, snapshot_id)

# Export or analyze the signals
Enum.each(signals, &analyze_order_signal/1)
```

## Use Cases

### Microservices Communication
```elixir
# Service A publishes order events
{:ok, signal} = OrderCreated.new(%{order_id: "123", customer_id: "456"})
Bus.publish(:event_bus, [signal])

# Service B processes inventory
# Service C sends notifications  
# Service D updates analytics
```

### Agent-Based Systems
```elixir
# Agents communicate via signals
{:ok, signal} = AgentMessage.new(%{
  from_agent: "agent_1",
  to_agent: "agent_2", 
  action: "negotiate_price",
  data: %{product_id: "prod_123", offered_price: 99.99}
})
```

### Event Sourcing
```elixir
# Commands become events
{:ok, command_signal} = CreateUser.new(user_data)
{:ok, event_signal} = UserCreated.new(user_data, cause: command_signal.id)

# Store in journal for complete audit trail
Journal.record(journal, event_signal, command_signal.id)
```

### Distributed Workflows
```elixir
# Coordinate multi-step processes
workflow_signals = [
  %Signal{type: "workflow.started", data: %{workflow_id: "wf_123"}},
  %Signal{type: "step.completed", data: %{step: 1, workflow_id: "wf_123"}},
  %Signal{type: "step.completed", data: %{step: 2, workflow_id: "wf_123"}},
  %Signal{type: "workflow.completed", data: %{workflow_id: "wf_123"}}
]
```

## Documentation

- **[Getting Started Guide](https://hexdocs.pm/jido_signal/getting-started.html)** - Step-by-step tutorial
- **[Core Concepts](https://hexdocs.pm/jido_signal/core-concepts.html)** - Deep dive into architecture  
- **[API Reference](https://hexdocs.pm/jido_signal)** - Complete function documentation
- **[Guides](https://hexdocs.pm/jido_signal/guides.html)** - Advanced usage patterns

## Development

### Prerequisites

- Elixir 1.17+
- Erlang/OTP 26+

### Setup

```bash
git clone https://github.com/agentjido/jido_signal.git
cd jido_signal
mix deps.get
```

### Running Tests

```bash
mix test
```

### Quality Checks

```bash
mix quality  # Runs formatter, dialyzer, and credo
```

### Generate Documentation

```bash
mix docs
```

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details on:

- Setting up your development environment
- Running tests and quality checks
- Submitting pull requests
- Code style guidelines

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE.md](LICENSE.md) file for details.

## Related Projects

- **[Jido](https://github.com/agentjido/jido)** - The main Jido agent framework
- **[Jido Workbench](https://github.com/agentjido/jido_workbench)** - Development tools and utilities

## Links

- [Hex Package](https://hex.pm/packages/jido_signal)
- [Documentation](https://hexdocs.pm/jido_signal)
- [GitHub Repository](https://github.com/agentjido/jido_signal)
- [Agent Jido Website](https://agentjido.xyz)
- [CloudEvents Specification](https://cloudevents.io/)

---

**Built with ❤️ by the Jido team**
