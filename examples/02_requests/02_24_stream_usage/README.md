# 02_24 — Stream usage

Retain usage from streamed model responses through native and standalone calls.

## Read the code

Read [agent.ex](agent.ex), then [echo.ex](echo.ex).
Then read the matching tests below.

The source generates two AI Agents to compare delta capture on and off. Both
use the same tool and usage rules; this is a transport comparison, not a new
Agent authoring pattern.

## Run it

From the package root:

```sh
mix test test/examples/02_requests/02_24_stream_usage --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

Integer and numeric-string usage cases retain input, output and total counters.
All cases run through real HTTP/SSE transport without skip tags.

## Limits

The ReqLLM pin includes [the upstream fix](https://github.com/agentjido/req_llm/pull/1009)
for numeric-string counters. Processed zero usage is not replaced by a fallback.
These local wire fixtures do not prove the behavior of every live provider.

## Files

- [02_24_stream_usage_test.exs](../../../test/examples/02_requests/02_24_stream_usage/02_24_stream_usage_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Previous: [02_22](../02_22_request_inspection/README.md) | Next: [02_25](../02_25_incomplete_response/README.md)
