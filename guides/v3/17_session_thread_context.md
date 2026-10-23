# Session, Thread, and model Context

Use these values for different purposes:

- `Jido.Session` owns conversation identity, status, metadata, and one Thread.
- `Jido.Thread` owns ordered committed Signals.
- `ReqLLM.Context` is the selected message view for one model request.
- An active request is runtime work. It is not a Session or Thread.

Create fresh Session or Thread data in the core Agent initializer:

```elixir
defmodule MyApp.ChatAgent do
  use Jido.AI.Agent, name: "chat_agent"

  state do
    schema Zoi.object(%{session: Jido.Session.schema()})
  end

  @impl Jido.Agent
  def initialize(state, _context) do
    {:ok, Map.put_new_lazy(state, :session, &Jido.Session.new!/0)}
  end

  ai do
    model :fast
  end
end
```

Core Jido merges static `initial_state` with explicit caller `state:` before it
calls the initializer. The initializer returns the complete candidate state.
Use `Map.put_new_lazy/3` when an explicit Session or Thread must be preserved.

Session and Thread contain portable data. They do not contain provider clients,
processes, streams, or a live request queue. Closing a Session prevents another
turn from using it. It does not cancel unrelated runtime work.
