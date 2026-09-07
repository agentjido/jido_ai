# 02_05: Request transformation and output repair

The [Agent modules](../lib/examples/02_requests/02_05_request_transform/agent.ex)
and [14 integration tests](../test/examples/02_requests/02_05_request_transform_test.exs)
use the public Agent helpers and native core Agent DSL. One mock server records
real ReqLLM requests. Each test runs with local responses and no provider keys.

```sh
mix test --include integration test/examples/02_requests/02_05_request_transform_test.exs
```

The transformer receives the public ReAct Config and State structures. It can
change messages, model, options and the tool catalog for each model call.
The selected model is resolved before provider options are merged. Model
controls run after transformation. The tool definitions and execution lookup
come from the same selected catalog.

The example proves these cases:

- Each repair attempt gets fresh HTTP headers and its actual repair prompt.
  Model and message changes reach the server. A valid first result needs no repair.
- Repair input includes the original user message, failed answer and validation
  error. A content-part query keeps its supported text and image summary.
- Repair uses non-streaming object generation. Business tools remain disabled,
  even when a transformer tries to restore tools or streaming. ReqLLM can use
  its own schema tool to implement object generation.
- Transformer errors and invalid messages stop before the next HTTP request.
  Native model-call limits also stop before another transformation. Controls
  see the changed model and can reject it before provider work.
- A configured repair callback receives the transformed model, options,
  messages and request IDs. Its output passes the same schema validator.
  Invalid callback output uses the declared repair count and then fails.
- Four-argument callbacks take precedence when a module also exports the
  three-argument form. Direct `Output.repair/5` overrides support both forms.
- Stored external captures become module/function references. DSL, direct data,
  Builder and source JSON execute those same references. Missing registry entries,
  closures and invalid callback arities fail during construction. Callback
  identity affects the existing output fingerprint.
- Callback state uses actual model call IDs and the current event sequence.
  Repair retains the original conversation, raw answer and tool catalog.
  A tool selection change affects both the provider request and real execution.

Provider repairs use the shared generation Action, deadline and usage account.
A configured callback can repair locally and consumes no model call by itself.
If application callback code performs its own external I/O, that code remains
responsible for that I/O and its usage. The outer core execution deadline still
bounds the callback. This example does not prove callback cancellation cleanup.

Config, State, PendingToolCall and RequestTransformer moved into the shared
source directory with their public module names retained. This is not a port
of the complete standalone ReAct runner. Pending-tool recovery, cycle state,
thinking accumulators, response continuation, output events and full metadata
still need their own cases. The callback state adapter does not reconstruct
those unported fields. The selected-model example uses two OpenAI model records;
cross-provider options and WebSocket ownership remain separate required checks.

History evidence is partial for PR 343 and PR 339. Fresh-runtime callback
restore and token compatibility remain open. All history rows keep their
pending migration status until their full required case set passes.
