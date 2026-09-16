# Stream, steer, and cancel

`ask_stream/3` starts a request and returns both its handle and an event
stream. Consume events to show progress, but await the handle for the final
result. The final answer and committed state remain authoritative even if a
consumer disconnects or misses a progress event.

```elixir
{:ok, %{request: request, events: events}} =
  MyApp.Agent.ask_stream(server, "Review this change")

Enum.each(events, &IO.inspect/1)
{:ok, answer} = Jido.AI.Request.await(request)
```

Steering is different from a new request. With `controls do; steering true;
end`, `Jido.AI.Orchestration.steer/3` can queue a correction for a running
request. Acceptance means queued, not yet consumed. The next eligible model
step consumes it. If the request has closed its input queue, a late correction
is rejected. A queued correction does not raise the request's model-call or
time limits. Successful settlement promotes consumed input to completed
Context; pending or failed input stays outside the default completed view.

`Jido.AI.Orchestration.cancel/2` asks the runtime to stop a request. A caller
wait timeout is not cancellation. The request may have already completed an
effectful tool call before cancellation, so tool design still needs safe
retry and effect policy. Use the handle or request ID to target the right
request. Do not use a bare Agent PID when two requests could be confused.

The [steering example](../../examples/02_requests/02_02_steering/README.md)
tests queued input, consumption, closure, and cancellation. Run [Steer a
turn](../livebooks/steer_turn.livemd) to see a held mock response and one
queued correction. Next, read [failure boundaries](13_failures_and_recovery.md).
