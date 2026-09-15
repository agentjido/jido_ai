# 14_10 — Failure position

Distinguish reasoning position from the number of model operations.

## Read the code

Read [agent.ex](agent.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/14_resume/14_10_failure_position --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

Output repair increases model calls without advancing reasoning position. Failure and cancellation retain the last observed position and known usage.

## Limits

Position is boundary metadata, not proof that interrupted external work is safe to retry. Owner loss does not create durable recovery or an exact unobserved count.

## Files

- [14_10_failure_position_test.exs](../../../test/examples/14_resume/14_10_failure_position/14_10_failure_position_test.exs)

Previous: [14_08](../14_08_query_append/README.md) | Next: [14_11](../14_11_initial_state/README.md)
