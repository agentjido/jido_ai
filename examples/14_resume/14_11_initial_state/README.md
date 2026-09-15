# 14_11 — Initial conversation import

Import portable conversation data before starting an Agent.

## Read the code

Read [agent.ex](agent.ex), then [echo.ex](echo.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/14_resume/14_11_initial_state --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

`Jido.AI.Agent.from_initial_state/3` restores complete historical exchanges and selected-profile prompts without model calls or tool replay. Invalid or ambiguous input is rejected.

## Limits

The destination must declare history and domain fields. This imports conversation data, not active requests, workers, pending tools or Plugin state. Use explicit checkpoints for execution continuation.

## Files

- [14_11_initial_state_test.exs](../../../test/examples/14_resume/14_11_initial_state/14_11_initial_state_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Previous: [14_10](../14_10_failure_position/README.md) | Next: [14_12](../14_12_terminal_state/README.md)
