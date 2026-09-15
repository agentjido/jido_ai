# 16_02 — Chat capability Plugin

Expose chat, completion, embedding, structured output and tool routes on a core Agent.

## Read the code

Read [agent.ex](agent.ex), then [echo_flow.ex](echo_flow.ex), then [echo.ex](echo.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/16_capabilities/16_02_chat --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

The selected Action result commits to the domain field. Real tool results reach follow-up model calls. Invalid input or provider failure preserves the previous result.

## Limits

Callable Chat Actions do not add native session history or approval policy. The descriptive `tool_policy` field is not authorization. Supply a suitable embedding model for embedding work.

## Files

- [16_02_chat_test.exs](../../../test/examples/16_capabilities/16_02_chat/16_02_chat_test.exs)
- [Shared set_case.ex](../../support/set_case.ex)

Previous: [16_01](../16_01_reasoning/README.md) | Next: [16_03](../16_03_routing_policy/README.md)
