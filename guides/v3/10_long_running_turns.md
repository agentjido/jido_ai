# Long-running turns

`Jido.AI.reason/3` and `Jido.AI.run/3` execute a request in the caller process.
They return after the request completes or fails. `Jido.AI.Request` prepares a
request. It does not own a worker and it does not provide an `await/2` function.

Use request controls to bound the work:

```elixir
{:ok, result} =
  Jido.AI.run(MyApp.Agent, "Research the issue",
    timeout: 30_000,
    max_iterations: 8,
    max_model_calls: 8,
    max_tool_calls: 20
  )
```

For durable or routed work, submit a Signal to `Jido.AgentServer`. The core
runtime owns process life, admission, waiting, and cancellation. Jido AI owns
the AI request, its controls, and its result. Keep these concerns separate.

A caller wait timeout and an AI request timeout have different meanings. A
caller wait timeout stops the caller from waiting. It does not always stop the
accepted work. Use the core cancellation operation when you must stop routed
work.

Use `request_id` and `run_id` to correlate request events and the final result.
Do not store a worker PID in portable Agent, Session, or Thread state.

Next, set [controls and limits](11_controls_and_limits.md).
