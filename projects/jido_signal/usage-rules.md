# Jido Signal Usage Rules

CloudEvents v1.0.2 compliant signal library for Elixir agent systems.

## Signal Creation

```elixir
# Basic signal
{:ok, signal} = Jido.Signal.new(%{
  type: "user.created",
  source: "/auth/service", 
  data: %{user_id: 123}
})

# Custom signal type (preferred)
defmodule UserCreated do
  use Jido.Signal,
    type: "user.created",
    schema: [user_id: [type: :integer, required: true]]
end

{:ok, signal} = UserCreated.new(%{user_id: 123})
```

**Signal Types**: Use dot notation (`"user.created"`, `"payment.processed"`), not camelCase/underscores.

## Dispatch

```elixir
# Direct to PID
:ok = Jido.Signal.Dispatch.dispatch(signal, {:pid, target: pid})

# Multiple destinations
configs = [
  {:pid, target: pid},
  {:logger, level: :info},
  {:http, url: "https://webhook.example.com"}
]
:ok = Jido.Signal.Dispatch.dispatch(signal, configs)
```

**Adapters**: `:pid`, `:pubsub`, `:logger`, `:http`, `:webhook`, `:console`, `:noop`

## Event Bus

```elixir
# Start bus
{:ok, _} = Jido.Signal.Bus.start_link(name: :my_bus)

# Subscribe with patterns
{:ok, sub_id} = Bus.subscribe(:my_bus, "user.*", 
  dispatch: {:pid, target: self()})

# Publish (always as list)
Bus.publish(:my_bus, [signal])
```

**Patterns**: `"user.created"` (exact), `"user.*"` (single), `"user.**"` (multi-level)

## Signal Router

```elixir
router = Jido.Signal.Router.new!([
  {"user.created", MyHandler},
  {"audit.**", AuditHandler, 100},  # priority
  {"payment.*", fn signal -> signal.data.amount > 1000 end, LargePaymentHandler}
])

:ok = Jido.Signal.Router.route(router, signal)
```

**Priority**: -100 to 100 (higher first). Exact matches before wildcards.

## Error Handling

```elixir
case Jido.Signal.Dispatch.dispatch(signal, config) do
  :ok -> :success
  {:error, %Jido.Signal.Error.DispatchError{} = error} ->
    Logger.error("Failed: #{error.message}")
end
```

## Anti-Patterns

**❌ Avoid:**
- Generic types: `"event"`, `"message"`
- Bypassing bus: `send(pid, signal)`
- Ignoring errors: `Dispatch.dispatch(signal, config)`

**✅ Use:**
- Specific types: `"user.created"`, `"order.shipped"`
- Bus routing: `Bus.publish(:my_bus, [signal])`
- Error handling: `case Dispatch.dispatch(...) do`

## Advanced Features

### Middleware
```elixir
defmodule MyMiddleware do
  use Jido.Signal.Bus.Middleware
  def before_publish(signals, _ctx, state), do: {:cont, signals, state}
end

Bus.start_link(name: :bus, middleware: [{MyMiddleware, []}])
```

### Persistent Subscriptions
```elixir
{:ok, sub_id} = Bus.subscribe(:bus, "order.*", persistent: true)
:ok = Bus.ack(:bus, sub_id, signal_id)
```

### Journal & Causality
```elixir
journal = Jido.Signal.Journal.new()
{:ok, journal} = Journal.record(journal, signal)
effects = Journal.get_effects(journal, signal.id)
```

### Serialization
```elixir
{:ok, json} = Jido.Signal.Serialization.JsonSerializer.serialize(signal)
{:ok, signal} = Jido.Signal.Serialization.JsonSerializer.deserialize(json)
```

### Snapshots & Replay
```elixir
{:ok, snapshot_ref} = Bus.snapshot_create(:bus, "user.*")
{:ok, signals} = Bus.replay(:bus, "user.*", from_timestamp)
```

## Testing

```elixir
# Create test signal
signal = Jido.Signal.new!("test.event", %{data: "value"})

# Test dispatch
Bus.subscribe(:test_bus, "test.*", dispatch: {:pid, target: self()})
Bus.publish(:test_bus, [signal])
assert_receive {:signal, ^signal}

# Use :noop adapter for testing
dispatch: :noop
```
