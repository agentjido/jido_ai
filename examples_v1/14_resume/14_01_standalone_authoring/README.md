# 14_01 — Standalone configuration

Build standalone ReAct work from a Config and explicit execution limits.

## Read the code

Read [configuration.ex](configuration.ex), then [change.ex](change.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/14_resume/14_01_standalone_authoring --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

The public configuration runs an aliased tool with finite iteration, time and
tool-call limits. A provider failure produces a terminal error. The retained
conversion fixtures also check state effects, bounded repair and token safety.

## Limits

Use `Jido.AI.Agent` for static AI Agents. This lesson uses the public standalone
API; internal Config conversion checks stay in test support. Tokens contain
data, not live Exec values. Runtime model and transport overrides belong to the host.

## Files

- [Public configuration tests](../../../test/examples/14_resume/14_01_standalone_authoring/public_configuration_test.exs)
- [Shared multiply tool](../../support/multiply.ex)
- [14_01_standalone_authoring_test.exs](../../../test/examples/14_resume/14_01_standalone_authoring/14_01_standalone_authoring_test.exs)

Next: [14_02](../14_02_standalone_runtime/README.md)
