# Where the answer goes

An AI request has at least three different results. The model produces
content. The request returns its final answer or an error. AgentServer stores
the committed Agent state. Do not treat these as the same value.

```elixir
agent do
  schema Zoi.object(%{
    answer: Zoi.string() |> Zoi.default(""),
    case_id: Zoi.string() |> Zoi.default("new")
  })

  ai :assistant do
    model "openai:gpt-4o-mini"
    result into: :answer
  end
end
```

`result into: :answer` maps the accepted result to one domain field. It does
not replace unrelated state such as `case_id`. The request can also return the
answer to its caller. After `ask_sync/3`, read `Jido.AgentServer.agent(server)`
to inspect the committed state, not a stale Agent value kept before the call.

Tool results have a different role. They are intermediate evidence inside the
request Context. A tool result is not automatically a domain-state update. A
model may make three tool calls and still commit one final answer. If the
application must update other domain fields, give that work an explicit Jido
Action or route with its own validated state transition.

Validation and commit are separate. A structured result must pass its schema
before `result into:` can write it. If the provider fails, a tool fails, or
result validation exhausts repair, the prior domain answer remains in place.
Request records and Thread entries can still retain evidence about that
failed attempt. This distinction matters when you show a user the last valid
answer while also reporting a failed current request.

The [first-answer test](../../test/examples/01_authoring/01_01_authoring_formats/01_01_authoring_formats_test.exs)
proves that a provider failure leaves the prior answer unchanged and that a
later request can succeed. Continue with the [DSL map](04_dsl_map.md).
