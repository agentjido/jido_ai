# Getting Started

Quick setup and first signal dispatch for the Jido Signal library.

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:jido_signal, "~> 1.0"}
  ]
end
```

## Create a Signal

Basic signal creation (preferred):

```elixir
# Preferred: positional constructor (type, data, attrs)
{:ok, signal} = Jido.Signal.new("user.created", %{user_id: "123", email: "user@example.com"},
  source: "/auth/registration"
)
```

Also available:

```elixir
# Map/keyword constructor (backwards compatible)
{:ok, signal} = Jido.Signal.new(%{
  type: "user.created",
  source: "/auth/registration",
  data: %{user_id: "123", email: "user@example.com"}
})
```

With dispatch configuration:

```elixir
# Using the positional form
{:ok, signal} = Jido.Signal.new("metrics.collected", %{cpu: 80, memory: 70},
  source: "/monitoring",
  jido_dispatch: {:pid, [target: pid, delivery_mode: :async]}
)
```

## Dispatch to a Process

Synchronous dispatch to PID:

```elixir
config = {:pid, [target: pid, delivery_mode: :sync]}
:ok = Jido.Signal.Dispatch.dispatch(signal, config)
```

Asynchronous dispatch:

```elixir
config = {:pid, [target: pid, delivery_mode: :async]}
:ok = Jido.Signal.Dispatch.dispatch(signal, config)
# Process receives: {:signal, signal}
```

Named process dispatch:

```elixir
config = {:named, [target: {:name, :my_process}, delivery_mode: :async]}
:ok = Jido.Signal.Dispatch.dispatch(signal, config)
```

Multiple destinations:

```elixir
configs = [
  {:pid, [target: pid1, delivery_mode: :async]},
  {:logger, [level: :info]}
]
:ok = Jido.Signal.Dispatch.dispatch(signal, configs)
```

## Basic Error Handling

Dispatch returns structured errors:

```elixir
case Jido.Signal.Dispatch.dispatch(signal, config) do
  :ok -> 
    :success
  {:error, %Jido.Signal.Error.DispatchError{} = error} ->
    Logger.error("Dispatch failed: #{error.message}")
    {:error, :dispatch_failed}
end
```

Signal creation errors:

```elixir
case Jido.Signal.new(%{type: "", source: "/test"}) do
  {:ok, signal} -> 
    signal
  {:error, reason} ->
    Logger.error("Invalid signal: #{reason}")
    {:error, :invalid_signal}
end
```

Process not alive:

```elixir
config = {:pid, [target: dead_pid, delivery_mode: :async]}
{:error, %Jido.Signal.Error.DispatchError{}} = 
  Jido.Signal.Dispatch.dispatch(signal, config)
```
