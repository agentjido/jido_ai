# 02_01 — Request sessions

Run several AI requests while ordinary domain commands can also commit.

## Read the code

Read [agent.ex](agent.ex).
Then read the matching tests below.

This lesson uses the core AI extension with explicit `Request` helpers. These
helpers return tagged tuples. Use `Jido.AI.Agent` and its generated helpers for
normal static AI Agents.

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

## Limits

Await timeout does not cancel work. Use `Session.cancel/2`. Owner loss can remove an event sink; committed interruption state remains inspectable. This is not durable stream replay.

## Files

- [02_01_session_test.exs](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs)
- [Shared close_case.ex](../../support/close_case.ex)
- [Shared commit_counter.ex](../../support/commit_counter.ex)
- [Shared mock_llm.ex](../../support/mock_llm.ex)
- [Shared multiply.ex](../../support/multiply.ex)

Next: [02_02](../02_02_steering/README.md)
