# Long-running turns

An agentic request can take minutes. Do not keep one AgentServer callback open
while the model and tools run. `ask/3` returns a handle after admission.
`Jido.AI.Request.await/2` waits for settlement and can be called later. A
caller's wait timeout and the AI work timeout have different meanings: the
first stops waiting; the second bounds work.

```elixir
{:ok, request} = MyApp.Agent.ask(server, "Research the issue")
# Do other application work here.
{:ok, answer} = Jido.AI.Request.await(request, timeout: 30_000)
```

The AI Coordinator owns the live request, its work process, input queue, and
event stream. AgentServer owns the committed Agent value. A `Jido.Session` is
a portable value, not the live worker. This division lets the AgentServer
accept a separate domain Signal while the AI work is pending. A second AI
request to the same busy profile can be rejected; do not assume it is queued.

Keep every request bounded with profile controls. A tool timeout is not a
substitute for an overall request timeout. A caller that stops awaiting does
not necessarily cancel accepted work; call the public cancellation API when
you intend to stop it. Use a request ID to correlate events, settlement, and
inspection. Do not store the handle or a worker PID inside portable Agent
state.

Run [A bounded long turn](../livebooks/long_turn.livemd). Its mock provider
holds a response so you can inspect a pending request and release it. The
live path cannot promise the same pause. Next, set [controls and limits](11_controls_and_limits.md).
