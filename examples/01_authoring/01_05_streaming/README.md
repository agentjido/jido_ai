# 01_05 — Streaming and cancellation

Observe text while an AI request runs, and cancel it through the public session API.

## Read the code

Read [the Agent](agent.ex), then the tests. `Agent.ask_stream/3` returns the
request handle and event stream. Use `Jido.AI.Request.await/2` for the final
result and `Jido.AI.Orchestration.cancel/2` to cancel owned work.

## Run it

From the package root:

```sh
mix test test/examples/01_authoring/01_05_streaming --include example --seed 0
```

Expected result: all tests pass without credentials or a remote provider.
They use the [local model server](../../support/mock_llm.ex) through real ReqLLM
transport and AgentServer, with [test setup](../../../test/examples/support/example_case.ex).

## Important behavior

A text delta arrives before the complete answer enters state. Cancellation
stops the provider connection and closes the request stream without replacing
the previous answer. A later request succeeds. Tests monitor process cleanup.

## Limits

Request records can change before the answer commits. Partial text is not a
committed answer. This lesson does not cover durable replay or tool rollback.
The tests select a Chat-compatible model record through the public model option
to use the local SSE fixture.

## Files

- [Agent](agent.ex)
- [Tests](../../../test/examples/01_authoring/01_05_streaming/01_05_streaming_test.exs)

Previous: [01_04](../01_04_controls/README.md) | Next: [01_06](../01_06_ai_extension/README.md)
