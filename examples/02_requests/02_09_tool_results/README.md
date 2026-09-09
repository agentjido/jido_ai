# 02_09: Tool results and request inspection

The [Agent modules](agent.ex)
and [19 example tests](../../../test/examples/02_requests/02_09_tool_results/02_09_tool_results_test.exs)
use the shared HTTP mock, real Actions and a nested Flow. The native Agent DSL
and public AI Agent macro use the same tool result adapter.

```sh
mix test --include example test/examples/02_requests/02_09_tool_results/02_09_tool_results_test.exs
```

The example proves these cases:

- A real directory read fails with an Action error. The model receives a valid
  error envelope with the cause and tool/call IDs, and can return an answer.
- Text, numbers, maps and three-element result tuples use the canonical success
  envelope. Invalid return values and raised exceptions use the error envelope.
- Core raw outputs expose their actual value.
- A nested Flow failure retains its supported error type and details.
- Content parts stay separate from the JSON envelope. Three binary file forms
  (ToolResult, map carrier and bare list) reach the real ReqLLM chat encoder.
  The mock receives the exact bytes in a separate image data URI.
- ReqLLM rejects PDF and text-file attachments on this chat path before a
  second HTTP request. The request retains the completed tool result, original
  bytes, file ID, media type, filename and supported metadata. The formatter
  still produces valid JSON. These cases do not claim provider acceptance of
  PDF/text content or file restore support. The binary fixtures test encoding;
  they do not test image rendering or model interpretation.
- Completed results retain IDs, arguments, status, attempts, duration and native
  result tuples. Model messages and stored results follow call order when two
  tools complete in reverse order. Repeated completion data updates the same
  record without running the Action again.
- Cancellation stops the remaining parallel work and retains the completed
  tool. A later provider failure also retains completed tools. A later request
  does not inherit the previous request's tool results.
- Nonportable values use the existing bounded transport form for model JSON
  and stored inspection. This form redacts sensitive keys and removes live
  resources. It is not a raw-value restore format.

The public Agent retry example also checks exact attempt counts, explicit
nonretryable errors, stored attempts and the model-facing error envelope.
Tools with returned effects are not retried. The [02_10 example](../02_10_tool_effects/README.md) now stages allowed state proposals
and typed Directives through the core commit boundary.

One shared `Jido.AI.Turn.Content` formatter now serves the existing Turn API
and the v3 loop. `Jido.AI.ToolResult` adapts core output wrappers and reuses
`PendingToolCall` for completed records. One ordered reducer serves the Flow
result and the request event owner. Core Exec and Map still execute tools.
The adapter also unwraps batch outputs and rejects stream/opaque outputs;
those output kinds still need dedicated acceptance cases.

This is partial evidence for PRs 230, 250, 258, 296, 299, 300 and 306. Required
input validation and unknown-tool response policy, nonempty effects, every
retry case, direct Turn/ReAct APIs, source-format equality, all reasoning
methods, durable restore and root package checks remain open.
