# 02_01 — Request sessions

Run several AI requests while ordinary domain commands can also commit.

## Read the code

Read [agent.ex](agent.ex).
Then read the matching tests below.

This lesson uses `Jido.AI.Agent` and its built-in request helpers.
`Agent.ask/3` returns `{:ok, request}`. With streaming enabled,
`Agent.ask_stream/3` returns `{:ok, %{request: request, events: events}}`.
No custom request wrappers are needed.

## Run it

From the package root:

```sh
mix test test/examples/02_requests/02_01_session --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

Admission returns a request handle; `Request.await/2` reads its committed outcome. Busy requests are rejected. A later answer preserves intervening domain changes.

`store_content true` permits the Agent to retain tool arguments and results for
later requests. Failed or cancelled requests do not enter completed conversation.
If required content was not retained, continuation returns an explicit error;
the runtime does not keep a second hidden copy.

## Design target checks

[The target checks](../../../test/examples/02_requests/02_01_session/design_requirements_test.exs)
prove that a request survives stream-sink termination (`SES-REQ-022`) and that
content-free tool keepalives do not extend its deadline (`OBS-REQ-016`).
The held tool is a [test fixture](../../../test/examples/support/runtime_barriers.ex),
not an application callback. The tests confirm that it terminates at the deadline.
These cases do not prove every owner-loss or transport-disconnect path.

## Limits

Await timeout does not cancel work. Use `Jido.AI.Orchestration.cancel/2`. Owner loss can remove an event sink; committed interruption state remains inspectable. This is not durable stream replay.

## Files

- [02_01_session_test.exs](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs)
- [Shared close_case.ex](../../support/close_case.ex)
- [Shared commit_counter.ex](../../support/commit_counter.ex)
- [Shared mock_llm.ex](../../support/mock_llm.ex)
- [Shared multiply.ex](../../support/multiply.ex)

Next: [02_02](../02_02_steering/README.md)
