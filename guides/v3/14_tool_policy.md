# Tool access and effects

The Agent `tools` block declares its complete tool set:

```elixir
tools do
  action MyApp.ReadAccount, as: :read_account
  action MyApp.UpdateAccount, as: :update_account
end
```

A caller can reduce that set for one request:

```elixir
{:ok, result} =
  MyApp.Agent.reason("Read the balance",
    visible_tools: [:read_account]
  )
```

Required rules:

- A request can select only declared tools.
- Hidden tools are not sent to the model.
- A forged hidden-tool call is rejected before execution.
- Raw provider `tools:` request options are rejected.
- The `:request_started` event records visible tool names.

`visible_tools: []` sends no application tool definitions. `nil` or an omitted
option keeps all declared tools visible.

A model-facing description is not authorization. An effectful Action still
needs application access checks. An external effect can finish before a later
model or output failure. Use idempotency for work that must not repeat.
