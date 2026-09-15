# 14_12 — Terminal Agent restore

Restore a native Agent checkpoint after a request finishes.

## Read the code

Read [agent.ex](agent.ex), then [control.ex](control.ex), then [echo.ex](echo.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/14_resume/14_12_terminal_state --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

Restored request records and trace remain equal, with no live worker or repeated completed tool. A later request uses the saved history once.

## Limits

This does not restore active execution. Native Agent checkpoints and signed standalone ReAct tokens are separate APIs. Output-control failures do not prove provider finish-reason decoding.

## Files

- [14_12_terminal_state_test.exs](../../../test/examples/14_resume/14_12_terminal_state/14_12_terminal_state_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Previous: [14_11](../14_11_initial_state/README.md)
