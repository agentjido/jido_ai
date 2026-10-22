# 14_03 — Checkpoint resume

Pause after a model response or complete tool round, then resume with fresh resources.

## Read the code

Read [agent.ex](agent.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/14_resume/14_03_checkpoint_resume --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

After-tools resume retains completed results without executing those tools again. The new-VM test retains identity, counters and history under the same code.

## Limits

Tokens are caller-owned and replayable, not durable single-consumer records. Resume checks code, permissions and remaining budgets. Partial tool batches and external side-effect rollback are not supported.

## Files

- [14_03_checkpoint_resume_test.exs](../../../test/examples/14_resume/14_03_checkpoint_resume/14_03_checkpoint_resume_test.exs)

Previous: [14_02](../14_02_standalone_runtime/README.md) | Next: [14_04](../14_04_standalone_actions/README.md)
