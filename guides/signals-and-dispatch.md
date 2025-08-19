# Signals and Dispatch

## Signal Structure

Signals implement the CloudEvents v1.0.2 specification with Jido extensions:

```elixir
# Basic signal
{:ok, signal} = Jido.Signal.new(%{
  type: "user.created",
  source: "/auth/service",
  data: %{user_id: "123", email: "user@example.com"}
})

# Signal fields
signal.id              # UUID v4 (auto-generated)
signal.specversion     # "1.0.2"
signal.type            # "user.created"
signal.source          # "/auth/service"
signal.data            # %{user_id: "123", email: "user@example.com"}
signal.time            # ISO 8601 timestamp (auto-generated)
signal.datacontenttype # "application/json" (default)
signal.jido_dispatch   # Dispatch configuration
```

## Dispatch Adapters

### PID Adapter

Direct process delivery:

```elixir
# Async delivery (fire-and-forget)
config = {:pid, [target: pid, delivery_mode: :async]}
:ok = Jido.Signal.Dispatch.dispatch(signal, config)

# Sync delivery (with response)
config = {:pid, [
  target: pid,
  delivery_mode: :sync,
  timeout: 10_000
]}
```

### Named Process Adapter

Delivery to registered processes:

```elixir
config = {:named, [
  target: {:name, :my_server},
  delivery_mode: :async
]}
```

### PubSub Adapter

Phoenix.PubSub broadcast:

```elixir
config = {:pubsub, [
  target: :my_app_pubsub,
  topic: "events"
]}
```

### HTTP Adapter

HTTP endpoint delivery:

```elixir
config = {:http, [
  url: "https://api.example.com/events",
  method: :post,
  headers: [{"x-api-key", "secret"}],
  timeout: 5000,
  retry: %{max_attempts: 3, base_delay: 1000}
]}
```

## Sync vs Async Patterns

### Synchronous Dispatch

Blocks until all deliveries complete:

```elixir
:ok = Jido.Signal.Dispatch.dispatch(signal, config)
```

### Asynchronous Dispatch

Returns task immediately:

```elixir
{:ok, task} = Jido.Signal.Dispatch.dispatch_async(signal, config)
:ok = Task.await(task)
```

### Batch Dispatch

Multiple destinations with concurrency control:

```elixir
configs = List.duplicate({:pid, [target: pid]}, 1000)
:ok = Jido.Signal.Dispatch.dispatch_batch(
  signal, 
  configs, 
  batch_size: 100,
  max_concurrency: 5
)
```

### Multiple Destinations

Send to multiple adapters:

```elixir
configs = [
  {:pubsub, [target: :pubsub, topic: "events"]},
  {:logger, [level: :info]},
  {:http, [url: "https://webhook.example.com"]}
]
:ok = Jido.Signal.Dispatch.dispatch(signal, configs)
```

## Custom Signal Types

Define structured signal types:

```elixir
defmodule UserCreatedSignal do
  use Jido.Signal,
    type: "user.created",
    default_source: "/auth/service",
    datacontenttype: "application/json",
    schema: [
      user_id: [type: :string, required: true],
      email: [type: :string, required: true],
      name: [type: :string, required: false]
    ]
end

# Usage
{:ok, signal} = UserCreatedSignal.new(%{
  user_id: "123",
  email: "user@example.com"
})

# Override defaults
{:ok, signal} = UserCreatedSignal.new(
  %{user_id: "123", email: "user@example.com"},
  source: "/different/source",
  jido_dispatch: {:pubsub, topic: "user-events"}
)
```

### Schema Validation

Custom signals validate data against schema:

```elixir
# Valid
{:ok, signal} = UserCreatedSignal.new(%{
  user_id: "123",
  email: "user@example.com"
})

# Invalid - missing required field
{:error, reason} = UserCreatedSignal.new(%{
  user_id: "123"
  # email is required
})
```

## Error Handling

### Validation Errors

```elixir
# Invalid dispatch config
{:error, reason} = Jido.Signal.Dispatch.validate_opts({:invalid, []})

# Invalid signal data
{:error, reason} = Jido.Signal.new(%{})  # missing type and source
```

### Delivery Errors

```elixir
# Process not alive
{:error, :process_not_alive} = 
  Jido.Signal.Dispatch.dispatch(signal, {:pid, [target: dead_pid]})

# HTTP timeout
{:error, :timeout} = 
  Jido.Signal.Dispatch.dispatch(signal, {:http, [url: "...", timeout: 1]})
```

### Batch Errors

```elixir
# Some failures
{:error, errors} = Jido.Signal.Dispatch.dispatch_batch(signal, configs)
# errors = [{index, reason}, ...]
```
