# 14_12: Native terminal state restore

The [Agents](../lib/examples/14_resume/14_12_terminal_state/agent.ex) and
[tests](../test/examples/14_resume/14_12_terminal_state_test.exs) define six
integration cases. Native Agent DSL uses the existing AI profile, ReAct Flow,
output control and Session. The shared mock supplies real HTTP and SSE replies.

Each buffered/streamed pair ends with success, a raw error map, or the exact
`{:incomplete_response, :incomplete}` tuple. Errors come from an output control
after real model and tool work. They do not test the SDK's decoding of provider
finish reasons. [02_25](02_25_incomplete_response.md) covers that separate path.

The first model calls a real tool and reports four tokens. The second supplies
the answer with empty usage. Request inspection retains the total, two model
calls and one tool result. One terminal event is present. Public event
collection also keeps earlier usage when terminal usage is empty.

```elixir
{:ok, view} = Jido.AI.Session.snapshot(server, request_id: request.id)
{:ok, saved} = Jido.Agent.checkpoint(view.agent)
{:ok, agent} = Jido.Agent.restore(MyAgent, saved)
{:ok, restored_server} = Jido.start_agent(MyJido, agent)
```

The test copies the checkpoint through safe ETF decoding, stops the old
Server, and starts the restored Agent. The old request record and trace are
equal. There is no active request or live worker. Restoration makes no model
call and does not execute the completed tool again. A later request uses the
saved tool history once and keeps its own usage and result set. The first
request remains unchanged. Actual HTTP flags prove both response modes.

Failures are in `view.request.error`, with nil request result.
`Request.await/1` returns `{:error, raw_error}`. The standalone ReAct collector
keeps raw errors in its result field. Native Agent checkpoints and standalone
signed ReAct tokens are separate APIs. The retained root tests and
[14_03](14_03_checkpoint_resume.md) cover signed tokens. This example does not
convert v2 Agent/Plugin payloads or restore active execution. Those requirements
remain open. [14_11](14_11_initial_state.md) covers conversation-only import.

Run from `examples/v3`:

```sh
mix test test/examples/14_resume/14_12_terminal_state_test.exs --include integration --include pending_dsl --seed 0
```

The [source case map](../../../docs/v3-spike/react-terminal-test-transfer.md)
records six retained root cases and the exact limits of this evidence.
