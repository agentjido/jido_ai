# 16_01 — Reasoning capability Plugins

Add callable reasoning routes to a domain Agent.

## What you will learn

- Bind a validated Profile to each reasoning Plugin.
- Submit prompt-only input and keep policy in the host Profile.
- Keep separate results when native AI and callable reasoning share an Agent.

## Read the code

Read [agent.ex](agent.ex), then [mixed_agent.ex](mixed_agent.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/16_capabilities/16_01_reasoning --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

CoT and CoD write the result fields declared in their Profiles while preserving
other state. A mixed Agent can combine native AI with callable reasoning.
The host Profile sets the model, method, timeout, and result field. Signal input
contains only `prompt`; input cannot replace the host policy. Provider failure
leaves prior state unchanged. A timeout stops provider work, and the same
capability can accept another prompt.

## Limits

Core Plugin composition is the point of this lesson, so it uses `Jido.Agent`. A capability call is not a long-lived session or durable worker.

## Files

- [16_01_reasoning_test.exs](../../../test/examples/16_capabilities/16_01_reasoning/16_01_reasoning_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)
- [Shared set_case.ex](../../support/set_case.ex)

Next: [16_02](../16_02_chat/README.md)
