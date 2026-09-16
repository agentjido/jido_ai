# Session, Thread, and Context

Use these names for different things. `Jido.Session` is a portable value that
holds a `Jido.Thread`. The Thread is an append-only record of entries. A
Context is the selected, valid conversation that the next model request sees.
The active AI request is live runtime work, not a Session value.

```elixir
agent do
  schema Zoi.object(%{
    reply: Zoi.string() |> Zoi.default(""),
    messages: Jido.AI.Thread.Projection.schema()
  })

  ai :assistant do
    model "openai:gpt-4o-mini"
    memory history: :messages
    result into: :reply
  end
end
```

The `memory` declaration names the Agent field that holds the Session. The
first completed request creates conversation data there. A later request can
select prior completed entries for model input. The raw Thread can also hold
request settlement, context operations, and application entries. Not every
entry becomes a provider message. This is why a Thread is not just a list of
chat messages.

Session and Thread values can be encoded and moved between processes. They do
not carry worker PIDs, provider clients, or a pending request's live queue.
Closing a Session value does not cancel active AI work. Use
`Jido.AI.Orchestration` for live control and AgentServer for committed state.

Run [Two requests in one Session](../livebooks/two_requests.livemd). Its mock
script checks that the second model request sees the first completed exchange.
Read [Thread and Session values](../../examples/02_requests/02_27_thread_session_values/README.md)
for codecs and validation. Next, see [how Context is built](18_context_projection.md).
