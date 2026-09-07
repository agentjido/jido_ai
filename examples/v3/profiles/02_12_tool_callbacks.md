# 02_12: Tool callbacks and request state

The [Agents and Actions](../lib/examples/02_requests/02_12_tool_callbacks/agent.ex)
and [32 integration tests](../test/examples/02_requests/02_12_tool_callbacks_test.exs)
use the shared model mock, real core tool execution and the production
`Jido.AI.ToolInterceptor` contract.

```sh
mix test --include integration test/examples/02_requests/02_12_tool_callbacks_test.exs
```

A native profile can name a trusted callback module:

```elixir
ai :assistant do
  tool_interceptor MyApp.ToolCallbacks
  # Models, reasoning, tools and result declarations follow.
end
```

DSL, data, Builder and source JSON use the same profile field. Without an
explicit module, the host Agent's optional `before_tool_call/2` and
`after_tool_call/3` functions apply. The public `Jido.AI.Agent` macro now permits
those callbacks. Caller context cannot select another callback module.

The alias case comes from PR 347. A real Action lists a long product key. The
after callback returns `item-1` to the model and proposes an explicit alias
map in candidate state. The next model call selects `item-1`. The before
callback restores the original key before schema validation and execution.
The same Action accepts the original key through direct Exec without callbacks.
The alias map commits only after the final answer is accepted.

The examples also prove these rules:

- Resolve the full batch, run argument callbacks, validate all arguments, then
  run operation controls. A rejected batch starts no tool. A callback cannot
  change the call ID, public tool name or executable identity.
- Before callbacks run once per prepared call, before real retry attempts.
  Result callbacks run once after the final attempt, including final errors.
  They receive canonical three-element result tuples. Invalid two-element
  results fail explicitly.
- ReAct collects all concurrency chunks before result callbacks. A monitored
  tool finishes ahead of an earlier tool; result callbacks still run in model
  call order. A later callback failure preserves earlier completion evidence
  and does not commit staged state. Completed Action I/O remains completed.
- Effects are filtered after callback transformation. Caller context cannot
  widen the profile policy. Dropped effects have recorded counts. Transformed
  values reach completion data and the next model request.
- Callbacks receive trusted request/run IDs, Agent identity, application
  context, effective policy and the current candidate state. The next request
  transform receives that state and completed tool records in its ReAct view.
- Explicit errors, interruption, malformed results, exceptions, throws and
  exits produce failed requests. Interruption is a failure with an interrupt
  reason; this example does not implement approval or durable pause/resume.
- Core Exec owns callback lifetime. Cancellation stops a held callback, and
  the request deadline bounds it. A later request can run after cancellation.
- Literal Flow tools retain their executable identity through callbacks.
  Native one-Turn and session Agents use the same callback operations.

The 11 retained ToolInterceptor tests also pass. They cover missing optional
hooks, identity checks, result shapes, effect policy and caught failures.

This is partial PR 347 evidence. The ToT alias/result path, direct AI tool
facades, pending-work restore, callback replay and full package validation
remain required. Completed records describe approved callback results; a tool
that finishes before a cancelled batch reaches its result callback has not
produced that approved result. Durable recovery must define that state.
