# 02_13 — Tool preflight and time limits

Bound tool attempts, retries and the complete request.

## Read the code

Read [agent.ex](agent.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/02_requests/02_13_tool_limits --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

The complete prepared batch is validated before execution. A rejected second call starts no tool. Timeout and cancellation stop owned work.

## Limits

A core timeout is not retried unless the error permits retry. Cancellation cannot undo external I/O. The long acceptance test exceeds 31 seconds to check the configured 45-second tool budget.

## Files

- [02_13_tool_limits_test.exs](../../../test/examples/02_requests/02_13_tool_limits/02_13_tool_limits_test.exs)
- [public_agent_test.exs](../../../test/examples/02_requests/02_13_tool_limits/public_agent_test.exs)
- [Shared multiply.ex](../../support/multiply.ex)

Previous: [02_11](../02_11_completion/README.md) | Next: [02_16](../02_16_typed_signals/README.md)
