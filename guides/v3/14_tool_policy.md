# Tool access and effects

The `tools` block declares what a profile can expose. A request can narrow
access with `allowed_tools`. This is an access decision made before model-
selected work executes, not a sentence in the prompt. Keep an operation out
of the profile if the Agent should never perform it.

```elixir
tools do
  action MyApp.ReadAccount, as: :read_account
  action MyApp.UpdateAccount, as: :update_account
end

# A caller can narrow the profile for one request.
MyApp.Agent.ask(server, "Read the balance", allowed_tools: ["read_account"])
```

Read-only work and effectful work need different policy. A tool that writes to
a database, sends a message, or starts a payment may complete before the AI
answer is committed. Final-result failure cannot reverse that effect. Require
application authorization and idempotency where needed. Set an effect policy
at the reasoning boundary if the application uses one; do not assume a
model-facing tool description is enforcement. A request-scoped allowlist can
reduce capability, but should not grant a tool that the profile did not
declare.

Test a permitted call and a denied call with MockLLM. Confirm that the denied
call does not invoke the Action. The [tool-limit example](../../examples/02_requests/02_13_tool_limits/README.md)
shows execution bounds. Run [Allow and deny a tool](../livebooks/tool_policy.livemd)
to inspect the visible tool set and result. Continue with [quotas](15_budgets_and_quotas.md).
