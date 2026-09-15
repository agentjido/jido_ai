# 18_01 — Skill activation and resources

Bind a host skill catalog and load approved skill resources.

## Read the code

Read [agent.ex](agent.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/18_skills/18_01_skill_runtime --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

Successful activation commits trusted instructions. Resource access uses the host binding and policy. Owner exit clears live activation scopes.

## Limits

Activation handles are not portable. Restore needs fresh host bindings and activation. Opaque provider IDs are not filesystem paths. Provider callbacks are not guaranteed to run exactly once.

## Files

- [18_01_skill_runtime_test.exs](../../../test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs)
- [public_agent_test.exs](../../../test/examples/18_skills/18_01_skill_runtime/public_agent_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Next: [18_02](../18_02_skill_authoring/README.md)
