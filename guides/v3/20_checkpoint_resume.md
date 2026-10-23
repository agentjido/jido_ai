# Start from application state

The application creates dynamic instance data before it instantiates an Agent.
This includes a new or restored `Jido.Session` or `Jido.Thread`.

Declare the value in the Agent state schema:

```elixir
state do
  schema Zoi.object(%{session: Jido.Session.schema()})
end
```

For a new Session, use the core Agent initializer:

```elixir
@impl Jido.Agent
def initialize(state, _context) do
  {:ok, Map.put_new_lazy(state, :session, &Jido.Session.new!/0)}
end

{:ok, agent} = MyApp.Assistant.instantiate(id: "assistant-1")
```

The initializer runs for each instance. Do not put a generated Session in the
static definition because all instances would then use the same Session value.

For a restored Session, pass the restored value as an explicit caller override:

```elixir
restored = MyApp.SessionStore.load!("session-1")

{:ok, agent} =
  MyApp.Assistant.instantiate(
    id: "assistant-1",
    state: %{session: restored}
  )
```

Core Jido merges static `initial_state` with explicit caller `state:` first. It
then calls `initialize/2`. The callback returns the complete candidate state.
Core Jido applies schema defaults and validates that returned state.

This starts a new Agent value from prior application data. It does not replay
model calls or tools. It does not restore a pending request, a worker, a queue,
or Plugin runtime state. A live execution checkpoint is a different contract.
