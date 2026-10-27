# Pure or Live Execution

Your AI Agent runs the same reasoning Flow whether you call `cmd/3` on an
instance or send the request to a `Jido.AgentServer`. The difference is who
keeps the Session between requests, who serializes them, and which runtime
features exist. This guide compares the two paths for `jido.ai.request` and
shows how to receive stream Signals on each. It uses `MyApp.SupportAgent`
from [Define an AI Agent](define-an-ai-agent.livemd); the core
[Pure or Live Execution](https://hexdocs.pm/jido/pure-or-live-execution.html)
guide covers the general Agent contract.

```elixir
# Pure: you hold the Session and pass it forward
agent = MyApp.SupportAgent.instantiate!(id: "support-1")
{:ok, agent, [_reply]} = MyApp.SupportAgent.cmd(agent, first_request)
{:ok, agent, [_reply]} = MyApp.SupportAgent.cmd(agent, second_request)
agent.state.session.rev
# => 8

# Live: the server commits the Session after each request
{:ok, _jido} = Jido.start()
{:ok, server} = Jido.start_agent(MyApp.SupportAgent, id: "support-live")
{:ok, _committed, [_reply]} = Jido.AgentServer.call(server, first_request, 60_000)
{:ok, committed, [_reply]} = Jido.AgentServer.call(server, second_request, 60_000)
committed.state.session.rev
# => 8
```

In both cases the second model call sees the first exchange: its messages
are `user`, `assistant`, `user`. Each single-answer request adds four Session
revisions.

## Compared

| | `cmd/3` | Agent Server |
| --- | --- | --- |
| Success | `{:ok, candidate, [%Reply{}]}` | `{:ok, committed, [%Reply{}]}` |
| Session between requests | In the candidate; you pass it to the next call | Committed by the server |
| Concurrent requests | Each caller gets its own candidate | One Turn at a time |
| Model and tool I/O | Runs in your process | Runs in the server |
| Stream and review Signals | `context: %{jido_ai_dispatch: ...}` on `cmd/3` | `context: %{jido_ai_dispatch: ...}` on `call/3` or `submit/3` |
| Tool review waits | Blocked before the model call | Supported when the server has `persistence:` |
| Plugins | `prepare/2`, `reduce/2` | Plus `admit/3`, runtimes, `after_commit/3` |
| Persistence | None | Optional, with hibernate and thaw |

The reply is the same on both paths: a `Jido.Agent.Directive.Reply` whose
Signal has type `jido.ai.response` and data with `status`, `output`,
`usage`, `model_calls`, and the rest of the request summary.

## Pure Execution

`cmd/3` runs the whole reasoning Flow in the calling process and returns the
next Agent. The input Agent never changes:

```elixir
agent = MyApp.SupportAgent.instantiate!(id: "support-1")

first_request =
  MyApp.SupportAgent.request_signal!(%{
    input: "Where is order A-1001?",
    options: MyApp.OfflineModel.options()
  })

{:ok, next_agent, [%Jido.Agent.Directive.Reply{signal: reply}]} =
  MyApp.SupportAgent.cmd(agent, first_request)

{agent.state.session, next_agent.state.session.rev, reply.data.status}
# => {nil, 4, :completed}
```

`MyApp.OfflineModel` is the offline provider from
[Getting Started](getting-started.livemd). Without `options`, ReqLLM calls
the real provider.

"Pure" describes the Agent value, not the request. `cmd/3` sends the HTTP
request to the model and runs each tool Action the model calls. It doesn't
commit, persist, or serialize anything.

To continue the conversation, pass the candidate to the next call. If two
processes both call `cmd/3` with the same Agent, each gets its own Session
branch. Jido doesn't merge them.

### Outcomes

| Request | `cmd/3` returns | Session |
| --- | --- | --- |
| Completed | `{:ok, next, [reply]}`, `status: :completed` | User and assistant messages, attempts, outcome |
| Blocked or failed | `{:ok, next, [reply]}`, `status: :blocked` or `:failed` | Outcome recorded; no assistant message |
| Invalid request data | `{:error, %Jido.Action.Error.InvalidInputError{}}` | Unchanged |

A blocked request still produces a next Agent. Keep it: its Session records
the outcome. For example, input that contains `"ignore previous
instructions"` returns `status: :blocked, reason_code: :input` and adds two
revisions.

### Tool Review

A request that needs tool review must wait for an approval Signal. `cmd/3`
can't wait, so the input guard blocks the request before any model call:

```elixir
review =
  MyApp.SupportAgent.request_signal!(%{
    input: "Refund $5 on order A-1001.",
    review_tools: true,
    options: MyApp.OfflineModel.options()
  })

{:ok, _agent, [%Jido.Agent.Directive.Reply{signal: reply}]} =
  MyApp.SupportAgent.cmd(agent, review)

Map.take(reply.data, [:status, :reason_code, :reason, :model_calls])
# => %{status: :blocked, reason_code: :review,
#      reason: "execution host does not support waits", model_calls: 0}
```

An Agent Server without `persistence:` returns the same reply.
[Tool Review and Cycle Limits](tool-review-and-cycle-limits.livemd) covers
review waits.

## Live Execution

The Agent Server owns one committed Agent. Each `jido.ai.request` is one
Turn: the server runs the Flow, commits the returned state, and replies.

```elixir
{:ok, _jido} = Jido.start()
{:ok, server} = Jido.start_agent(MyApp.SupportAgent, id: "support-live")

{:ok, committed, [%Jido.Agent.Directive.Reply{signal: reply}]} =
  Jido.AgentServer.call(server, first_request, 60_000)

{committed.state.session.rev, reply.type}
# => {4, "jido.ai.response"}

Jido.AgentServer.agent(server).state.session.rev
# => 4
```

The next request reads the committed Session. You don't pass state around.
`Jido.AgentServer.status/1` reports `state_version`, which goes up by one
per committed request.

### Timeouts

`call/3` waits 5,000 ms by default. A request with tool rounds and several
model calls can take longer, and a caller timeout exits the caller without
cancelling the Turn. Pass a timeout that covers `limits.elapsed_ms` (default
120,000 ms):

```elixir
Jido.AgentServer.call(server, first_request, timeout: 130_000)
```

### Submit And Await

`submit/3` queues the request and returns a handle; `await/2` collects the
same result `call/3` would return. Call `await/2` from the process that
submitted:

```elixir
second_request =
  MyApp.SupportAgent.request_signal!(%{
    input: "When will it arrive?",
    options: MyApp.OfflineModel.options()
  })

pending = Jido.AgentServer.submit(server, second_request)

# ... other work ...

{:ok, committed, [%Jido.Agent.Directive.Reply{signal: reply}]} =
  Jido.AgentServer.await(pending, 130_000)
```

### Don't Cast Requests

`Jido.AgentServer.cast/3` doesn't work for `jido.ai.request`. The route
always returns a Reply Directive, and a cast has no caller to receive it. The
Turn fails at the directive stage, logs `AgentServer cast turn failed`, and
commits nothing. The model call has already run by then, so you pay for
tokens and lose the Session update. Use `submit/3` when you don't want to
block.

## Stream Signals

With `stream: true`, the model call streams and Jido AI publishes progress
Signals. It sends them only to the dispatch target in the
`jido_ai_dispatch` context key, as a `Jido.Signal.Dispatch` config. On the
pure path, pass it to `cmd/3`:

```elixir
request = MyApp.SupportAgent.request_signal!(%{input: "Where is order A-1001?", stream: true})

{:ok, next_agent, [reply]} =
  MyApp.SupportAgent.cmd(agent, request, context: %{jido_ai_dispatch: {:pid, target: self()}})
```

On the live path, pass the same context to `call/3` or `submit/3`:

```elixir
Jido.AgentServer.call(server, request,
  context: %{jido_ai_dispatch: {:pid, target: self()}},
  timeout: 130_000
)
```

Your process receives `{:signal, %Jido.Signal{}}` messages:

| Type | Sent | Extra data |
| --- | --- | --- |
| `jido.ai.model.stream.started` | Before the provider stream opens | |
| `jido.ai.model.stream.chunk` | Once per chunk | `chunk`: `type`, `text`, `name`, `arguments`, `metadata` |
| `jido.ai.model.stream.completed` | After the stream ends | `outcome`, `finish_reason`, `response_id` |
| `jido.ai.model.stream.failed` | If the stream fails | `reason` |
| `jido.ai.review.requested` | When a tool call needs review | `review_id`, `tool_calls`, `options`, `expires_at_ms` |

Every stream Signal carries `request_id`, `run_id`, `session_id`,
`thread_id`, `model`, `model_call`, `model_attempt`, `model_index`,
`tool_rounds`, `stream_id`, `sequence`, and `timestamp_ms`. `request_id` is
the request Signal's `id`. `sequence` starts at `0` and counts up within one
`stream_id`; each model call in a tool loop gets a new `stream_id`. The
Signal `source` is the Agent's source, such as `/my_app/support_agent`.

Three rules:

- Without `jido_ai_dispatch`, nothing is published, even with
  `stream: true`.
- The server's `default_dispatch:` option doesn't carry these Signals. Only
  the request context does.
- The `jido.ai.response` reply is never dispatched. It comes back from
  `cmd/3`, `call/3`, or `await/2`.

Use any `Jido.Signal.Dispatch` adapter, such as `{:pubsub, ...}` for a
LiveView. Streaming requests bypass the `Req.Test` plug; to run them
offline, mock `ReqLLM.stream_text/3` as
[Mock Model Calls with ReqLLM](mock-model-calls-with-reqllm.livemd) shows. [Stream Model Output](stream-model-output.livemd) covers ordering
and the chunk shapes.

## Choosing

| You want to | Use |
| --- | --- |
| Test a Flow, tools, or replies without processes | `cmd/3` |
| Replay a conversation from stored requests | `cmd/3` in a loop |
| Run one request in a job worker that stores the Session itself | `cmd/3` |
| Serve many callers for one conversation | Agent Server |
| Keep the Session across restarts | Agent Server with `persistence:` |
| Pause for tool review | Agent Server with `persistence:` |
| Run Plugin runtimes or `admit/3` | Agent Server |

A typical application tests with `cmd/3` and the offline model, then runs
each conversation as one Agent Server in production.
[Test AI Agents](test-ai-agents.livemd) shows the testing side.
