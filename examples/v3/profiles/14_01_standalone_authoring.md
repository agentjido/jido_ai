# 14_01: Standalone configuration and token foundation

[Agent factory](../lib/examples/14_resume/14_01_standalone_authoring/agent.ex)
and [tests](../test/examples/14_resume/14_01_standalone_authoring_test.exs) prove
the standalone Config conversion through real v3 Agent, Flow and model work.
This was the first part of the standalone port. These tests do not call the
public Runner. [14_02](14_02_standalone_runtime.md) now proves its first native
runtime replacement. Intermediate stream resume remains required.

## One lowering path

The internal `Jido.AI.Reasoning.ReAct.Authoring.lower/3` accepts an existing
Config, explicit native limits and an optional base Agent definition. It
returns `{:ok, definition, context}`. It uses the existing AI Profile,
ToolCatalog and Authoring lowerer. It adds no DSL term or execution engine.

Config supplies the model, prompt, tool names, execution timeout/retries,
concurrency, request transformer, effect policy, iteration limit, output
contract, streaming and supported observation settings. The resulting Agent
uses the normal Session route and common reasoning Flow. Its result and history
fields are declared domain state. A caller can supply a base schema for tool
state effects. Those effects remain subject to the core commit contract.

Provider generation options, API keys and HTTP callbacks are returned in live
context, separate from the portable definition. The native ToolCatalog owns
the provider tool schema. Config's own `reqllm_tools/1` now also retains public
names, including two aliases that target the same Action.

The internal caller must supply `timeout` and `max_tool_calls`. Old Config has
no total request deadline or total tool-call bound. This step does not invent
a new public default. The Runner port must select and test those controls,
including existing long-tool behavior and the legacy iteration-limit result.
The native concurrency range is 1 through 64; larger Config values fail this
conversion explicitly.

## Tokens remain data

The existing Token and deprecated Event modules moved to the shared production
directory so that the v3 acceptance project compiles their actual source.
Token prefix `rt2`, version 2, HMAC, compression, expiry, Config fingerprint,
state projection and cancellation-token contracts remain available.

Token issuance now raises for nonportable state. Signed token decoding rejects
such state and rejects disagreement between the outer request/run IDs and the
saved State. The tests use process IDs, references and closures to reproduce
the old acceptance of live data. Valid state still decodes in another process.
This check uses the core static-data validator; it adds no separate codec.

Core `Jido.Exec.Execution` values contain live revision guards, references and
callbacks. Core documents them as live execution values, not durable storage.
They must not become token payloads. Resume must rebuild execution from AI data
and fresh runtime resources.

## Evidence and open work

Twelve integration cases prove aliased tool execution and exact options,
runtime-only transport bindings, Builder/Codec parity, typed repair, state
effects visible to a later request transformer, batch-limit rejection, streamed
deltas and cancellation, invalid limits, two aliases for one Action, token
round trips and token rejection. They use the existing shared mock model server.

The first conversion run passed 18 of 20 cases, including retained root token
tests. Two fixtures used unsupported callback forms; these were corrected.
A later alias check reproduced duplicate canonical tool names. The Config fix
uses ToolAdapter's existing `name` option. Token tests then reproduced acceptance
of live state before the new validation was added.

One fixture override replaced its complete model-options list and lost the mock
URL. One synthetic request with a dummy key reached the provider and returned
401. The fixture now merges mock options and checks its loopback host before
execution. Subsequent runs use the local mock.

Still required: the actual public run/stream/start/continue/collect adapter;
after-model, after-tools and terminal checkpoints; pending/completed tool
continuation without repeated side effects; request/run/sequence continuity;
iteration-limit behavior; stream and task ownership; queue rebinding;
`capture_thinking`, `capture_messages` and tool-argument redaction; cycle
handling; callback identity after code changes; and fresh-runtime recovery.
The token test uses another process in the same VM, not a fresh OS process.

Run from `examples/v3`:

```sh
mix test test/examples/14_resume/14_01_standalone_authoring_test.exs --include integration
```
