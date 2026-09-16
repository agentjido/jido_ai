# 14_08 — Query append on resume

Append a new query while retaining saved context and execution limits.

## Read the code

Read [agent.ex](agent.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/14_resume/14_08_query_append --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

Pending tools finish before appended input reaches the next model call. History, identity, usage and counters continue without repeating completed effects.

## Limits

New input uses the remaining budget; it does not reset limits. Restart after failure or cancellation is unsupported. A copied token remains replayable.

## Files

- [14_08_query_append_test.exs](../../../test/examples/14_resume/14_08_query_append/14_08_query_append_test.exs)

Previous: [14_07](../14_07_standalone_input/README.md) | Next: [14_10](../14_10_failure_position/README.md)
