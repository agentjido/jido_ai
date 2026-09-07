# 02_03: Public Agent helpers

The [Agent modules](../lib/examples/02_requests/02_03_public_agent/agent.ex) use
the production `Jido.AI.Agent` macro. The
[11 integration tests](../test/examples/02_requests/02_03_public_agent_test.exs)
use one mock HTTP server and real core Agent, Flow, Exec, and tool work.

```sh
mix test --include integration test/examples/02_requests/02_03_public_agent_test.exs
```

The option adapter lowers to the same AI profile as the native `agent do`
extension. It creates one session Plugin. It does not create a Strategy, a
second request store, or a second input queue.

The tests cover these public results:

- `ask/3` returns `{:ok, handle}` after admission commits. `await/2` reads the
  committed result. `ask_sync/3` combines those operations.
- `ask_stream/3` returns `{:ok, %{request: handle, events: enumerable}}`. The
  sequence has one terminal event. Provider deltas use the existing event type.
- `steer/3` and `inject/3` return `{:ok, agent}` or
  `{:error, {:rejected, reason}}`. They use the same control path as Session.
  The default input source is `/ai/react/agent`.
- `cancel/2` retains advisory cast delivery, the selected request ID, and a
  reason. Await returns `{:error, {:cancelled, reason}}`. An old request ID
  cannot cancel a later request.
- Typed results remain typed. `last_answer` uses the existing text projection.
  The new `last_result` field stores the typed value.

The macro accepts the basic model, prompt, tools, output, generation, HTTP,
Plugin and route options. A bare module attribute works for `system_prompt`.
Tool context uses the existing literal check. Unsupported options and callbacks
produce explicit compile errors during this partial port.

Tool retries use core Exec continuations. The public macro retains one retry
by default and fixed backoff. Native catalog entries default to zero retries.
Each attempt has the tool timeout and the outer request deadline. Tests cover
a successful retry, exhaustion, and a non-retryable error. Tool context merges
base and request values. Reserved state and AI runtime keys remain host-owned.

The v3 `state` tool context is the snapshot before request admission. The
current query and request identity are in the runtime request context. This
timing is explicit; it must not be mistaken for a read of later live state.

Core `new/1` returns `{:ok, agent}`; `new!/1` returns the Agent directly. A
completed Agent passes the core checkpoint/restore round trip. This does not
prove v2 checkpoint conversion, durable pending work, or fresh-process restore.

Two core boundaries affect this example. A Map target cannot return an Action
continuation, so the tool wrapper uses one nested `Exec.run` to consume retries.
The core reentry guard can reject an independent history task while another
Turn runs. The history path retries only those explicit pre-execution reentry
errors within five seconds. It does not retry timeouts or control input.

Still open: full ReAct and facade execution; all legacy request options; tool
effects and callbacks; skills and default capability Plugins; early tool events,
heartbeats and stream timeouts; full source-format parity; and durable recovery.
The root package dependency cutover is also pending.
