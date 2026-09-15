# 14_02 — Standalone runtime

Run ReAct without managing the private Agent yourself.

## Read the code

Read [agent.ex](agent.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/14_resume/14_02_standalone_runtime --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

Enumeration starts work lazily. Completion, cancellation or consumer loss stops owned resources. Terminal tokens can return saved results without repeating model work.

## Limits

Supply explicit total timeout and tool limits when defaults do not fit. Terminal replay is not general recovery from failure or cancellation. Runtime resources must be supplied again.

## Files

- [14_02_standalone_runtime_test.exs](../../../test/examples/14_resume/14_02_standalone_runtime/14_02_standalone_runtime_test.exs)

Previous: [14_01](../14_01_standalone_authoring/README.md) | Next: [14_03](../14_03_checkpoint_resume/README.md)
