# Jido.Chat

[![Hex.pm](https://img.shields.io/hexpm/v/jido_chat.svg)](https://hex.pm/packages/jido_chat)
[![Hex Docs](https://img.shields.io/badge/hex-docs-green.svg)](https://hexdocs.pm/jido_chat)
[![Mix Test](https://github.com/agentjido/jido_chat/actions/workflows/elixir-ci.yml/badge.svg)](https://github.com/agentjido/jido_chat/actions/workflows/elixir-ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/agentjido/jido_chat/badge.svg?branch=main)](https://coveralls.io/github/agentjido/jido_chat?branch=main)
[![Apache 2 License](https://img.shields.io/hexpm/l/jido_chat)](https://opensource.org/licenses/Apache-2.0)

`Jido.Chat` is a structured chat room system built in Elixir that enables seamless interaction between human users and AI agents. Built on OTP principles, it provides a robust foundation for real-time chat applications with intelligent participants.

## Key Features

### Room Management

- **Flexible Room Creation**: Create isolated chat rooms with custom configurations
- **Dynamic Supervision**: OTP-based room lifecycle management
- **Thread Support**: Built-in conversation threading capabilities

### Participant Management

- **Multi-Type Support**: Handle both human and AI agent participants
- **Role-Based Access**: Define participant roles and permissions
- **Real-Time Status**: Track participant presence and activity

### Message Handling

- **Rich Message Types**: Support for text, system, and rich content messages
- **@mentions**: Built-in mention parsing and handling
- **Thread Management**: Organize conversations with threading

### Integration

- **Event-Driven Architecture**: Built on Jido's signal system
- **Extensible Channel System**: Pluggable interfaces for different protocols
- **Customizable Behaviors**: Override defaults with custom implementations

## Installation

Add `jido_chat` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido_chat, "~> 0.5.0"}
  ]
end
```

## Basic Usage

### Creating a Room

```elixir
# Start a basic chat room
{:ok, pid} = Jido.Chat.create_room("project-bus", "main-room")

# Access an existing room
{:ok, pid} = Jido.Chat.get_room("project-bus", "main-room")
```

### Managing Participants

```elixir
# Create participants
{:ok, human} = Jido.Chat.Participant.new("user123", :human,
  display_name: "Alice")

{:ok, agent} = Jido.Chat.Participant.new("agent456", :agent,
  display_name: "Support Bot")

# Add to room
:ok = Jido.Chat.join_room("project-bus", "main-room", human)
:ok = Jido.Chat.join_room("project-bus", "main-room", agent)
```

### Sending Messages

```elixir
# Send a basic message
{:ok, msg} = Jido.Chat.post_message("project-bus", "main-room",
  "user123", "Hello @Support Bot!")

# Send a rich message
{:ok, msg} = Jido.Chat.post_message("project-bus", "main-room",
  "agent456",
  "Here's a chart",
  type: :rich,
  payload: %{
    type: "chart",
    data: [1, 2, 3]
  }
)
```

### Retrieving Messages

```elixir
# Get all messages
{:ok, messages} = Jido.Chat.get_messages("project-bus", "main-room")

# Get thread messages
{:ok, thread} = Jido.Chat.get_thread("project-bus", "main-room", thread_id)
```

## Advanced Usage

### Custom Room Implementation

```elixir
defmodule MyApp.CustomRoom do
  use Jido.Chat.Room

  @impl true
  def handle_message(room, message) do
    # Custom message handling logic
    {:ok, message}
  end

  @impl true
  def handle_join(room, participant) do
    # Custom join logic
    {:ok, participant}
  end
end
```

### Custom Channel Integration

```elixir
defmodule MyApp.WebSocket.Channel do
  @behaviour Jido.Chat.Channel

  @impl true
  def send_message(room_id, sender_id, content, opts) do
    # Implement WebSocket message sending
  end

  @impl true
  def handle_incoming(room_id, message) do
    # Handle incoming WebSocket messages
  end
end
```

## Testing

The package includes a comprehensive test suite:

```bash
# Run tests
mix test

# Run tests with coverage
mix test --cover

# Run full quality checks
mix quality
```

## Supervision Tree

Jido.Chat uses a structured supervision tree for resilience:

```
Jido.Chat.Application.Supervisor
├── Registry
└── Jido.Chat.Supervisor
    ├── Room 1
    ├── Room 2
    └── Room N
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## Documentation

- [HexDocs](https://hexdocs.pm/jido_chat) - API documentation
- [Architecture Guide](guides/architecture.md) - System design

## License

This project is licensed under the Apache License 2.0 - see [LICENSE.md](LICENSE.md)
