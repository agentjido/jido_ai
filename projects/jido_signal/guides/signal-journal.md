# Signal Journal

The Signal Journal provides durable append-only storage for signals with powerful causality tracking and conversation management. It maintains relationships between signals, enabling complete audit trails and sophisticated signal analysis.

## Purpose and Architecture

The Journal serves as the foundational persistence layer for signal-driven systems, offering:

- **Durable Storage**: Append-only signal persistence with configurable adapters
- **Causality Tracking**: Maintains cause-effect relationships between signals 
- **Conversation Management**: Groups related signals by subject/conversation ID
- **Replay Capability**: Stream historical signals for system recovery or analysis
- **Audit Trail**: Complete traceability of signal flows and relationships

The Journal operates independently from the Bus, providing a pluggable persistence layer that can integrate with any storage backend.

## Core Concepts

### Signal Relationships

The Journal tracks three types of relationships:

- **Causality**: Which signal caused another signal (cause → effect)
- **Conversations**: Signals grouped by subject/conversation ID
- **Temporal Ordering**: Chronological sequence of all signals

### Persistence Adapters

The Journal uses a behavior-based adapter pattern for storage:

- **InMemory**: Fast in-process storage using Agent (default)
- **ETS**: Shared ETS tables for cross-process access
- **Custom**: Implement `Jido.Signal.Journal.Persistence` for databases, files, etc.

## Getting Started

### Basic Journal Operations

Create a journal and record signals:

```elixir
# Create journal with default InMemory adapter
journal = Jido.Signal.Journal.new()

# Create and record signals
signal1 = Jido.Signal.new!(type: "user.registered", source: "/auth")
{:ok, journal} = Jido.Signal.Journal.record(journal, signal1)

# Record with causality relationship
signal2 = Jido.Signal.new!(type: "email.sent", source: "/notifications")
{:ok, journal} = Jido.Signal.Journal.record(journal, signal2, signal1.id)
```

### Query and Analysis

```elixir
# Query all signals
all_signals = Jido.Signal.Journal.query(journal)

# Filter by criteria
user_signals = Jido.Signal.Journal.query(journal, type: "user.*")
recent_signals = Jido.Signal.Journal.query(journal, after: DateTime.utc_now() |> DateTime.add(-3600))

# Get causality relationships
effects = Jido.Signal.Journal.get_effects(journal, signal1.id)
cause = Jido.Signal.Journal.get_cause(journal, signal2.id)

# Trace complete causal chains
forward_chain = Jido.Signal.Journal.trace_chain(journal, signal1.id, :forward)
backward_chain = Jido.Signal.Journal.trace_chain(journal, signal2.id, :backward)
```

## Persistence Adapters

### InMemory Adapter (Default)

Best for: Testing, single-process applications, temporary storage

```elixir
# Uses default InMemory adapter
journal = Jido.Signal.Journal.new()

# Explicit InMemory adapter
journal = Jido.Signal.Journal.new(Jido.Signal.Journal.Adapters.InMemory)
```

**Characteristics:**
- Fast read/write operations
- Data lost on process termination
- Single process access only
- Low memory overhead for small datasets

### ETS Adapter

Best for: Multi-process access, shared state, development environments

```elixir
# Create with ETS adapter
journal = Jido.Signal.Journal.new(Jido.Signal.Journal.Adapters.ETS)

# Or start with custom table prefix
{:ok, pid} = Jido.Signal.Journal.Adapters.ETS.start_link("my_app_")
journal = %Jido.Signal.Journal{
  adapter: Jido.Signal.Journal.Adapters.ETS,
  adapter_pid: pid
}
```

**Characteristics:**
- Cross-process data sharing
- Survives individual process crashes
- Higher memory usage than InMemory
- Automatic table cleanup on termination

### Custom Adapters

Implement the `Jido.Signal.Journal.Persistence` behavior for custom storage:

```elixir
defmodule MyApp.Journal.DatabaseAdapter do
  @behaviour Jido.Signal.Journal.Persistence

  @impl true
  def init do
    # Initialize database connection
    {:ok, connection_pid}
  end

  @impl true
  def put_signal(signal, connection) do
    # Store signal in database
    :ok
  end

  @impl true
  def get_signal(signal_id, connection) do
    # Retrieve signal from database
    {:ok, signal} | {:error, :not_found}
  end

  @impl true
  def put_cause(cause_id, effect_id, connection) do
    # Store causality relationship
    :ok
  end

  @impl true
  def get_effects(signal_id, connection) do
    # Get all effects for a signal
    {:ok, effect_ids_mapset}
  end

  @impl true
  def get_cause(signal_id, connection) do
    # Get cause for a signal
    {:ok, cause_id} | {:error, :not_found}
  end

  @impl true
  def put_conversation(conversation_id, signal_id, connection) do
    # Add signal to conversation
    :ok
  end

  @impl true
  def get_conversation(conversation_id, connection) do
    # Get all signals in conversation
    {:ok, signal_ids_mapset}
  end
end

# Use custom adapter
journal = Jido.Signal.Journal.new(MyApp.Journal.DatabaseAdapter)
```

## API Reference

### Creating Journals

```elixir
# Default InMemory adapter
journal = Jido.Signal.Journal.new()

# Specific adapter
journal = Jido.Signal.Journal.new(Jido.Signal.Journal.Adapters.ETS)
```

### Recording Signals

```elixir
# Basic recording
{:ok, journal} = Jido.Signal.Journal.record(journal, signal)

# With causality
{:ok, journal} = Jido.Signal.Journal.record(journal, effect_signal, cause_signal.id)

# Error cases
{:error, :cause_not_found} = Jido.Signal.Journal.record(journal, signal, "invalid_id")
{:error, :causality_cycle} = Jido.Signal.Journal.record(journal, signal, creates_cycle_id)
{:error, :invalid_temporal_order} = Jido.Signal.Journal.record(journal, old_signal, new_signal.id)
```

### Querying Signals

```elixir
# Query with filters
signals = Jido.Signal.Journal.query(journal, [
  type: "user.created",
  source: "/registration",
  after: DateTime.utc_now() |> DateTime.add(-3600),
  before: DateTime.utc_now()
])

# All signals (empty filter)
all_signals = Jido.Signal.Journal.query(journal, [])
```

### Causality Analysis

```elixir
# Get direct effects
effects = Jido.Signal.Journal.get_effects(journal, signal_id)

# Get direct cause
cause = Jido.Signal.Journal.get_cause(journal, signal_id)

# Trace complete chains
forward_chain = Jido.Signal.Journal.trace_chain(journal, signal_id, :forward)
backward_chain = Jido.Signal.Journal.trace_chain(journal, signal_id, :backward)
```

### Conversation Management

```elixir
# Signals are grouped by subject field
signal1 = Jido.Signal.new!(type: "chat.message", subject: "conversation_123")
signal2 = Jido.Signal.new!(type: "chat.message", subject: "conversation_123")

{:ok, journal} = Jido.Signal.Journal.record(journal, signal1)
{:ok, journal} = Jido.Signal.Journal.record(journal, signal2)

# Get all signals in conversation (chronological order)
conversation = Jido.Signal.Journal.get_conversation(journal, "conversation_123")
```

## Integration with Event Bus

While the Journal operates independently, it integrates naturally with the Bus for comprehensive signal management:

```elixir
# Bus with Journal integration pattern
defmodule MyApp.SignalHandler do
  def handle_signal(signal, journal) do
    # Process the signal
    result = process_business_logic(signal)
    
    # Create response signal
    response = create_response_signal(result)
    
    # Record in journal with causality
    {:ok, journal} = Jido.Signal.Journal.record(journal, response, signal.id)
    
    # Publish to bus for further distribution
    Jido.Signal.Bus.publish(:my_bus, [response])
    
    {:ok, journal}
  end
end

# Middleware for automatic journal recording
defmodule MyApp.JournalMiddleware do
  use Jido.Signal.Bus.Middleware

  @impl true
  def init(opts) do
    journal = Jido.Signal.Journal.new()
    {:ok, %{journal: journal}}
  end

  @impl true
  def before_publish(signals, _context, state) do
    # Record all signals in journal
    journal = Enum.reduce(signals, state.journal, fn signal, acc ->
      {:ok, new_journal} = Jido.Signal.Journal.record(acc, signal)
      new_journal
    end)
    
    {:cont, signals, %{state | journal: journal}}
  end
end
```

## Performance Considerations

### Memory Management

```elixir
# InMemory adapter grows indefinitely
# Monitor signal count in production
signal_count = length(Jido.Signal.Journal.query(journal, []))

# Implement periodic cleanup for old signals
def cleanup_old_signals(journal, cutoff_time) do
  old_signals = Jido.Signal.Journal.query(journal, before: cutoff_time)
  # Custom logic to remove old signals based on adapter
end
```

### Query Optimization

```elixir
# Efficient: Specific type filters
user_signals = Jido.Signal.Journal.query(journal, type: "user.created")

# Less efficient: Querying all then filtering in Elixir
all_signals = Jido.Signal.Journal.query(journal, [])
user_signals = Enum.filter(all_signals, &String.starts_with?(&1.type, "user."))

# For large datasets, implement filtering in custom adapters
```

### Adapter Selection

- **InMemory**: < 10,000 signals, single process
- **ETS**: < 100,000 signals, multi-process sharing needed
- **Custom Database**: > 100,000 signals, persistence across restarts

## Usage Examples

### Event Sourcing Pattern

```elixir
defmodule MyApp.UserAggregate do
  def process_command(journal, command_signal) do
    # Validate command
    case validate_command(command_signal) do
      :ok ->
        # Create event signal
        event_signal = create_event_from_command(command_signal)
        
        # Record with causality
        {:ok, journal} = Jido.Signal.Journal.record(journal, event_signal, command_signal.id)
        
        # Return new state
        {:ok, journal, event_signal}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  def rebuild_state(journal, aggregate_id) do
    # Get all events for this aggregate
    events = Jido.Signal.Journal.query(journal, 
      type: "user.*", 
      source: "/user/#{aggregate_id}"
    )
    
    # Replay events to rebuild state
    Enum.reduce(events, %{}, &apply_event/2)
  end
end
```

### Audit Trail

```elixir
defmodule MyApp.AuditService do
  def trace_user_action(journal, user_id, action_signal_id) do
    # Get the complete causal chain
    chain = Jido.Signal.Journal.trace_chain(journal, action_signal_id, :forward)
    
    # Build audit report
    %{
      user_id: user_id,
      initial_action: action_signal_id,
      caused_events: Enum.map(chain, &format_audit_entry/1),
      timestamp: DateTime.utc_now()
    }
  end
  
  def compliance_report(journal, start_time, end_time) do
    # Get all signals in time range
    signals = Jido.Signal.Journal.query(journal, 
      after: start_time, 
      before: end_time
    )
    
    # Group by conversation and analyze
    signals
    |> Enum.group_by(& &1.subject)
    |> Enum.map(&generate_conversation_report/1)
  end
end
```

### Debugging and Analysis

```elixir
defmodule MyApp.Debug do
  def analyze_signal_flow(journal, start_signal_id) do
    # Trace forward to see all effects
    effects_chain = Jido.Signal.Journal.trace_chain(journal, start_signal_id, :forward)
    
    # Trace backward to see all causes  
    causes_chain = Jido.Signal.Journal.trace_chain(journal, start_signal_id, :backward)
    
    %{
      signal_id: start_signal_id,
      caused_by: causes_chain,
      caused: effects_chain,
      total_related: length(effects_chain) + length(causes_chain)
    }
  end
  
  def find_orphaned_signals(journal) do
    all_signals = Jido.Signal.Journal.query(journal, [])
    
    Enum.filter(all_signals, fn signal ->
      no_cause = is_nil(Jido.Signal.Journal.get_cause(journal, signal.id))
      no_effects = Enum.empty?(Jido.Signal.Journal.get_effects(journal, signal.id))
      no_cause and no_effects
    end)
  end
end
```

## Error Handling

### Validation Errors

```elixir
case Jido.Signal.Journal.record(journal, signal, cause_id) do
  {:ok, journal} -> 
    # Success
    journal
    
  {:error, :cause_not_found} ->
    Logger.error("Attempted to link to non-existent signal: #{cause_id}")
    journal
    
  {:error, :causality_cycle} ->
    Logger.error("Causality cycle detected for signal: #{signal.id}")
    journal
    
  {:error, :invalid_temporal_order} ->
    Logger.error("Invalid temporal order: effect before cause")
    journal
end
```

### Adapter Failures

```elixir
# ETS adapter cleanup on process termination
defmodule MyApp.JournalSupervisor do
  use Supervisor
  
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl true
  def init(_init_arg) do
    children = [
      {MyApp.JournalManager, []}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end

defmodule MyApp.JournalManager do
  use GenServer
  
  def init(_) do
    journal = Jido.Signal.Journal.new(Jido.Signal.Journal.Adapters.ETS)
    {:ok, %{journal: journal}}
  end
  
  def terminate(_reason, %{journal: journal}) do
    # Cleanup ETS tables
    if journal.adapter_pid do
      Jido.Signal.Journal.Adapters.ETS.cleanup(journal.adapter_pid)
    end
  end
end
```

## Best Practices

1. **Choose the Right Adapter**: InMemory for ephemeral data, ETS for shared state, custom for persistence
2. **Validate Causality**: Always check for cycles and temporal consistency
3. **Monitor Memory Usage**: Journal grows indefinitely without manual cleanup
4. **Use Conversations**: Group related signals with meaningful subject IDs
5. **Handle Errors Gracefully**: Journal operations can fail, plan for error recovery
6. **Index Queries**: For custom adapters, optimize common query patterns
7. **Batch Operations**: Record multiple signals efficiently when possible
8. **Clean Up Resources**: Properly terminate adapters to prevent resource leaks

The Signal Journal provides the foundation for sophisticated event-driven architectures with complete traceability and powerful analysis capabilities. Combined with the Bus, it enables robust, observable, and maintainable signal processing systems.
