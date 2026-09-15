# 14_07 — Caller-owned input queues

Bind an existing input queue to a standalone request.

## Read the code

Read [agent.ex](agent.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/14_resume/14_07_standalone_input --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

Input is consumed in order within the remaining budget. Completion and cancellation seal the borrowed queue; its owner still controls the process.

## Limits

Use one queue per active run. Checkpoints keep consumed history, not queue PIDs or undrained items. Bind a new queue on resume; delivery is not durable.

## Files

- [14_07_standalone_input_test.exs](../../../test/examples/14_resume/14_07_standalone_input/14_07_standalone_input_test.exs)

Previous: [14_06](../14_06_trace_and_cycles/README.md) | Next: [14_08](../14_08_query_append/README.md)
