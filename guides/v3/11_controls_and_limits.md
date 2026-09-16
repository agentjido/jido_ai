# Controls and limits

Controls bound runtime work and enforce checks at the edges of a request.
Start with `timeout`, `max_model_calls`, and—when tools are present—
`max_iterations` and `max_tool_calls`. These values are separate: one provider
operation can have HTTP retries, one ReAct iteration can contain tool work,
and one request can contain several model operations.

```elixir
controls do
  timeout 30_000
  max_iterations 4
  max_model_calls 4
  max_tool_calls 3
end
```

The DSL also accepts stage controls. An input control can reject a request
before model work. A model control can check a proposed model operation. An
operation control can check tool work. An output control can reject an answer
before its domain-state commit. Put a rule at the earliest stage with enough
information to decide it. That reduces wasted model calls and avoids a late
rejection after an avoidable external effect.

Controls are not all authorization. A model instruction does not enforce tool
access; a timeout does not make a non-idempotent tool safe to retry. Set a
specific tool policy for effects and a specific quota for use across
requests. Keep limits in the profile so they are visible at the authoring
surface and test them with a model script that exceeds one bound.

The [controls example](../../examples/01_authoring/01_04_controls/README.md)
demonstrates an input rule and an output rule. The [call-count example](../../examples/02_requests/02_20_call_counts/README.md)
separates started model operations from HTTP attempts. Continue with
[streaming and steering](12_stream_steer_cancel.md).
