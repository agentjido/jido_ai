# Event Bus

The Event Bus provides publish/subscribe messaging with middleware hooks, persistent subscriptions, and snapshot functionality.

## Basic Publish/Subscribe

Start a bus and publish signals:

```elixir
# Start the bus
{:ok, _pid} = Jido.Signal.Bus.start_link(name: :my_bus)

# Create and publish signals
signal = Jido.Signal.new!("user.created", %{user_id: 123})
{:ok, _recorded} = Jido.Signal.Bus.publish(:my_bus, [signal])

# Subscribe to signal patterns
{:ok, sub_id} = Jido.Signal.Bus.subscribe(:my_bus, "user.*")

# Subscribe with specific dispatch
{:ok, sub_id} = Jido.Signal.Bus.subscribe(:my_bus, "user.*", 
  dispatch: {:pid, target: self(), delivery_mode: :async}
)
```

Unsubscribe:

```elixir
:ok = Jido.Signal.Bus.unsubscribe(:my_bus, sub_id)
```

## Middleware Hooks

Implement custom middleware to intercept signals:

```elixir
defmodule MyMiddleware do
  use Jido.Signal.Bus.Middleware

  @impl true
  def init(opts), do: {:ok, %{}}

  @impl true
  def before_publish(signals, context, state) do
    # Transform or validate signals before publishing
    {:cont, signals, state}
  end

  @impl true
  def before_dispatch(signal, subscriber, context, state) do
    # Filter or modify signal before dispatch to subscriber
    if authorized?(signal, subscriber) do
      {:cont, signal, state}
    else
      {:skip, state}  # Skip this subscriber
    end
  end

  @impl true
  def after_dispatch(signal, subscriber, result, context, state) do
    # Log or handle dispatch results
    {:cont, state}
  end

  defp authorized?(signal, subscriber), do: true
end
```

Start bus with middleware:

```elixir
{:ok, _pid} = Jido.Signal.Bus.start_link(
  name: :my_bus,
  middleware: [{MyMiddleware, []}]
)
```

## Persistent Subscriptions

Create persistent subscriptions that survive client disconnections:

```elixir
# Create persistent subscription
{:ok, sub_id} = Jido.Signal.Bus.subscribe(:my_bus, "order.*",
  persistent: true,
  dispatch: {:pid, target: self(), delivery_mode: :async}
)

# Acknowledge processed signals
:ok = Jido.Signal.Bus.ack(:my_bus, sub_id, signal_id)

# Reconnect after disconnection
{:ok, last_timestamp} = Jido.Signal.Bus.reconnect(:my_bus, sub_id, self())
```

Persistent subscriptions maintain checkpoints and replay missed signals on reconnection.

## Snapshots and Replay

Create snapshots of signal history:

```elixir
# Create snapshot of all user events
{:ok, snapshot_ref} = Jido.Signal.Bus.snapshot_create(:my_bus, "user.*")

# Read snapshot data
{:ok, snapshot_data} = Jido.Signal.Bus.snapshot_read(:my_bus, snapshot_ref.id)

# List all snapshots
snapshots = Jido.Signal.Bus.snapshot_list(:my_bus)

# Delete snapshot
:ok = Jido.Signal.Bus.snapshot_delete(:my_bus, snapshot_ref.id)
```

Replay signals from specific timestamp:

```elixir
# Replay all signals from timestamp
{:ok, signals} = Jido.Signal.Bus.replay(:my_bus, "*", timestamp)

# Replay specific signal types
{:ok, user_signals} = Jido.Signal.Bus.replay(:my_bus, "user.*", timestamp)
```

## Advanced Configuration

Configure bus with custom router and options:

```elixir
custom_router = Jido.Signal.Router.new!()

{:ok, _pid} = Jido.Signal.Bus.start_link(
  name: :my_bus,
  router: custom_router,
  middleware: [
    {Jido.Signal.Bus.Middleware.Logger, []},
    {MyCustomMiddleware, [option: :value]}
  ]
)
```

Persistent subscription options:

```elixir
{:ok, sub_id} = Jido.Signal.Bus.subscribe(:my_bus, "events.*",
  persistent: true,
  max_in_flight: 100,    # Max unacknowledged signals
  start_from: :origin    # :origin, :current, or timestamp
)
```
