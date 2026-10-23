# Start from application state

The application creates dynamic instance data before it instantiates an Agent.
This includes a new or restored `Jido.Session` or `Jido.Thread`.

Declare the value in the Agent state schema:

```elixir
agent do
  schema Zoi.object(%{session: Jido.Session.schema()})
end
```

For a new Session, derive a fresh definition and seed its `initial_state`:

```elixir
definition = MyApp.Assistant.definition()

initial_state =
  Map.put(
    definition.initial_state,
    :session,
    Jido.Session.new!()
  )

{:ok, agent} =
  Jido.Agent.instantiate(
    %{definition | initial_state: initial_state},
    id: "assistant-1",
    state: %{}
  )
```

Create this derived definition for each instance. Reusing it would reuse the
generated Session identity. Use the derived definition only for construction;
store the Session or resulting Agent state instead of the derived definition.

For a restored Session, pass the restored value as an explicit caller override:

```elixir
restored = MyApp.SessionStore.load!("session-1")

{:ok, agent} =
  MyApp.Assistant.instantiate(
    id: "assistant-1",
    state: %{session: restored}
  )
```

Core Jido merges `initial_state` first and explicit `state:` second. It then
applies schema defaults and validates the complete state.

This starts a new Agent value from prior application data. It does not replay
model calls or tools. It does not restore a pending request, a worker, a queue,
or Plugin runtime state. A live execution checkpoint is a different contract.
