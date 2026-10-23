# Model Context projection

The model receives a projection from committed Thread Signals. It does not
receive the raw Session or Thread.

```elixir
{:ok, context} =
  Jido.AI.Context.project(session, MyApp.Ask,
    input: :question,
    output: :answer
  )
```

The SignalAction defines the request and reply Signal types and schemas. The
field options select text from their data Maps.

Projection rules are:

- Include only complete request and reply pairs.
- Match replies with the Jido causation ID.
- Keep committed request order.
- Ignore unrelated Signals.
- Ignore incomplete requests and orphan replies.
- Reject malformed matching request or reply data.
- Do not change Session or Thread.

Pass a Session or Thread directly to a request with the same projection:

```elixir
MyAgent.reason("What is my name?",
  context: session,
  projection: [
    signal_action: MyApp.Ask,
    input: :question,
    output: :answer
  ]
)
```

Jido AI adds Agent instructions and the current user input after the projected
history. The older `conversation:` option still accepts a clean ReqLLM Context.
