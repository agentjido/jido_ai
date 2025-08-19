# JidoChat System Architecture Guide

## Overview

JidoChat is a structured chat room system that supports human and agent participants with customizable turn-taking strategies and persistence. The system is built on Elixir's OTP principles, utilizing GenServers, Supervisors, and PubSub for robust, fault-tolerant operation.

## Core Features

- Multiple persistence adapters (ETS, In-Memory, Ecto)
- Flexible turn-taking strategies
- Support for human and AI agent participants
- Message history management
- Conversation context extraction for LLMs
- Real-time message broadcasting
- Participant management
- Room-based communication

## System Architecture

### Core Components

1. **Room Management**
   - Registry-based room tracking
   - Supervision tree for fault tolerance
   - State persistence across restarts
   - Message limit management
   - Participant tracking

2. **Message Handling**
   - Real-time message broadcasting
   - Message history management
   - Message type support (text, attachment, audio, system, reaction)
   - Message metadata management

3. **Participant Management**
   - Support for human and agent participants
   - Participant type-specific behavior
   - Participant metadata handling

4. **Turn-taking Strategies**
   - Multiple strategy implementations
   - Round-robin support
   - PubSub-based coordination
   - Free-form chat support

5. **Persistence Layer**
   - Multiple adapter support
   - ETS-based persistence
   - In-memory storage option
   - Consistent persistence API

6. **PubSub System**
   - Message broadcasting
   - Topic-based subscriptions
   - Turn notification support
   - Room-wide communication

## Data Structures

### Room
```elixir
%Jido.Chat.Room{
  id: String.t(),
  name: String.t(),
  participants: [Participant.t()],
  messages: [Message.t()],
  turn_strategy: module(),
  current_turn: String.t() | nil,
  message_limit: non_neg_integer(),
  metadata: map(),
  persistence_adapter: module(),
  message_broker: pid()
}
```

### Message
```elixir
%Jido.Chat.Message{
  id: String.t(),
  content: String.t(),
  type: message_type(),
  participant_id: String.t(),
  timestamp: DateTime.t(),
  metadata: map()
}
```

### Participant
```elixir
%Jido.Chat.Participant{
  id: String.t(),
  name: String.t(),
  type: :human | :agent,
  metadata: map()
}
```

### Conversation
```elixir
%Jido.Chat.Conversation{
  messages: [formatted_message()],
  participants: [Participant.t()],
  metadata: map()
}
```

## Public API

### Room Creation and Management
```elixir
Jido.Chat.create_room(room_id, opts \\ [])
Jido.Chat.join_room(room_pid, participant)
Jido.Chat.post_message(room_pid, participant_id, content)
Jido.Chat.get_conversation_context(room_pid, opts \\ [])
```

### Room Behavior
```elixir
Room.join(room, participant)
Room.leave(room, participant_id)
Room.post_message(room, participant_id, content)
Room.get_messages(room, opts \\ [])
Room.get_participants(room)
```

### Message Broker Operations
```elixir
MessageBroker.subscribe(pid, topic)
MessageBroker.broadcast(pid, topic, message)
MessageBroker.register_participant(pid, participant, topic)
```

## Turn-taking Strategies

### Available Strategies

1. **FreeForm**
   - Allows unrestricted posting
   - No turn management
   - Suitable for casual chat scenarios

2. **RoundRobin**
   - Enforces turn order for non-human participants
   - Maintains fair distribution of turns
   - Supports human override

3. **PubSubRoundRobin**
   - Coordinates turns via PubSub
   - Supports distributed operation
   - Maintains participant order

## Persistence Layer

### Available Adapters

1. **ETS Adapter**
   - Default persistence mechanism
   - Fast, in-memory storage
   - Survives process restarts
   - Named table: `:jido_rooms`

2. **Memory Adapter**
   - Agent-based storage
   - Useful for testing
   - Simple key-value storage

### Persistence Operations
```elixir
Persistence.save(room_id, room_state)
Persistence.load(room_id)
Persistence.delete(room_id)
Persistence.load_or_create(room_id)
```

## Application Configuration

### Supervisor Tree
- Registry for room management
- Persistence layer supervision
- Phoenix.PubSub system
- Global message broker

### Default Configuration
- PubSub adapter: Phoenix.PubSub
- Persistence adapter: Jido.Chat.Room.Persistence.ETS
- Default message limit: 1000
- Default strategy: Strategy.FreeForm

## Testing Considerations

1. **Room Testing**
   - Isolation via unique room IDs
   - Strategy behavior verification
   - Message limit testing
   - Participant management testing

2. **PubSub Testing**
   - Message broadcast verification
   - Turn coordination testing
   - Participant registration testing

3. **Persistence Testing**
   - State preservation verification
   - Adapter behavior testing
   - Recovery testing

## Development Guidelines

1. **Adding New Features**
   - Maintain existing behavior contracts
   - Follow established pattern matching
   - Implement proper error handling
   - Add comprehensive tests
   - Update documentation

2. **Message Handling**
   - Use proper message types
   - Include necessary metadata
   - Follow turn-taking rules
   - Handle errors gracefully

3. **Persistence Considerations**
   - Implement proper cleanup
   - Handle race conditions
   - Consider distributed scenarios
   - Test recovery paths