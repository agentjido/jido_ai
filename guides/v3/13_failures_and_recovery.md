# Failures and recovery

Preparation failures use the normal tagged error contract. They include an
invalid input, invalid options, a missing AI configuration, an unknown model,
or unknown visible tools.

Execution failures can include:

- input control rejection
- provider failure
- incomplete or missing output
- invalid structured output
- hidden or invalid tool calls
- tool failure
- model, tool, iteration, or time limits
- output control rejection
- cancellation by the core runtime

Use `run/2` when the application needs explicit failed request data:

```elixir
{:error, result} = MyAgent.run("Try this request")

result.status
result.error
result.request_id
result.events
```

A failed result ends with one `:request_failed` event. A limit error uses
`:limit_reached` as the result status.

For routed work, do not call `Jido.AI.Turn.complete/4` with a failed result.
The function rejects it and does not build candidate state. Core Jido leaves
the last committed Agent state unchanged.

Retry only after error classification. Use a new request ID for a new logical
attempt. Reuse an application idempotency key when an external tool effect
must not occur twice.
