# 02_14: Stream activity and tool keepalives

The [Agents and real tool](../lib/examples/02_requests/02_14_stream_activity/agent.ex)
and [16 integration tests](../test/examples/02_requests/02_14_stream_activity_test.exs)
use the shared HTTP/SSE model mock. They hold actual tool and provider work,
inspect public request events, and monitor cleanup.

```sh
mix test --include integration test/examples/02_requests/02_14_stream_activity_test.exs
```

Native session requests use these millisecond settings:

```elixir
requests do
  mode :session
  streaming true
  idle_timeout 300
  tool_heartbeat 25
end
```

The fields are optional. `tool_heartbeat: 0` or omission disables keepalives.
A zero or omitted `idle_timeout` derives the runtime idle limit from the
largest selected tool timeout plus 60,000 ms. The native no-tool fallback is
65,000 ms. The public Agent also retains its configured global tool timeout
in that calculation, including when its tool catalog is empty. Its normal
15,000 ms tool default therefore gives 75,000 ms. The total request deadline
remains a separate bound and can stop work before that idle limit.

The public Agent accepts `stream_timeout_ms`, its `stream_receive_timeout_ms`
alias, and `tool_heartbeat_ms`. `ask`, `ask_sync` and `ask_stream` share one
request conversion. A valid primary idle option takes precedence over its
alias. An invalid high-level override is ignored; a later request keeps the
Agent default. An explicit zero disables an enabled heartbeat for one request
or selects automatic idle calculation. Native source values must be
non-negative integers. These settings currently require session mode; a
one-Turn declaration rejects them before activation.

One session process owns request events and activity timers:

- Real provider chunks reset the runtime idle timer, including tool-argument
  fragments with no visible text. This internal activity does not create a
  public keepalive or pretend that tool execution started.
- A tool-start event opens its activity window. Positive heartbeat intervals
  emit canonical `:keepalive` events with `data.source: :tool_execution`.
  They reset runtime inactivity and reach the public enumerable. Parallel
  tools share one heartbeat timer and one sequence counter. Retries and
  backoff stay inside the tool window.
- Completion closes the tool window. A separate work-finished notification
  also closes it when result callbacks are deferred until batch completion.
  Heartbeats stop before later model work. A silent provider still times out.
- The runtime idle timer stops owned work and commits a failed request with
  `:stream_timeout`. Its failed event has `error_type: :stream_timeout`.
  A consumer's finite `stream_event_timeout_ms` only ends enumeration. It
  does not cancel the request; the caller can release the tool and await it.
- Tool attempt and total request deadlines still stop actual work while
  heartbeats run. Completion, failure and cancellation stop timers. Timer
  messages carry request/run IDs and fresh tokens, so stale messages cannot
  change another request or extend a finished activity window.

The public long-tool case holds a worker for at least 650 ms with a 300 ms
runtime idle limit and a 150 ms consumer idle limit. Both remain active with
keepalives. Other cases prove order across parallel tools, retries, multiple
rounds and injected input; explicit zero and invalid overrides; automatic idle
calculation; tool failure and timeout; and total-deadline cleanup. A provider
sends tool arguments over more than 700 ms with no public keepalive before
tool start, which proves internal activity uses real decoded chunks.

DSL, source data, Builder and source JSON produce the same definition and
execute held tools under the same policy. All timer references remain outside
portable Agent state. Killing the event owner also stops the actual tool and
its timers; recovery marks the stored request interrupted. The recovered
owner does not retain the old transient sink or replay a terminal event.

This is partial PR 308 evidence. Standalone ReAct, Start/Continue/Collect,
checkpoint token compatibility, durable sink replay, early tool-call Signals,
other reasoning methods and full package checks remain open. The example
does not prove sequence continuity across owner restart or a transferable
event enumerable.
