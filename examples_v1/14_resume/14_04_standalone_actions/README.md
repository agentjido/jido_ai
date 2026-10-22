# 14_04 — Standalone Actions and Flow

Compose Start and Collect in a Flow and commit the aggregate through an inline Agent route.

## Read the code

Read [agent.ex](agent.ex), then [flow.ex](flow.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/14_resume/14_04_standalone_actions --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

The Flow returns the actual result, usage and termination reason. Its definition and Agent state contain no live stream. Cancellation stops owned work.

## Limits

A lazy stream exists only during execution. Cancelling an active execution and issuing a cancelled token are different operations. Tokens do not provide exactly-once external work.

## Files

- [14_04_standalone_actions_test.exs](../../../test/examples/14_resume/14_04_standalone_actions/14_04_standalone_actions_test.exs)

Previous: [14_03](../14_03_checkpoint_resume/README.md) | Next: [14_06](../14_06_trace_and_cycles/README.md)
