# 18_02 — Automatic skill authoring

Declare skills in an AI profile and let its live owner prepare the catalog.

## Read the code

Read [agent.ex](agent.ex), then [echo.ex](echo.ex), then [review.ex](review.ex), then [trust.ex](trust.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/18_skills/18_02_skill_authoring --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

The session prepares the skill index and loading tools at startup. Static construction does not read files. Invalid discovery fails before model work.

## Limits

Automatic skills require a ReAct request and a live owner. Declared paths are a trust decision. Restore rebuilds resources; it does not serialize provider handles. This is not dynamic tool-source support.

## Files

- [18_02_skill_authoring_test.exs](../../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs)

Previous: [18_01](../18_01_skill_runtime/README.md)
