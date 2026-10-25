# Model Context projection

The model receives a projection from committed Thread Signals. It does not
receive the raw Session or Thread.

```elixir
{:ok, context} =
  Jido.AI.Context.project(session, {MyApp.Agent, "my_app.ask"},
    input: :question,
    output: :answer
  )
```

The route reference selects one Agent route by the exact request Signal type.
The route handler input schema validates request data. The schema at the route
reply output path validates reply data. The field options select text from the
validated data Maps.

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
    route: {MyApp.Agent, "my_app.ask"},
    input: :question,
    output: :answer
  ]
)
```

Jido AI adds Agent instructions and the current user input after the projected
history. The older `conversation:` option still accepts a clean ReqLLM Context.
