# 01_07 — Production AI runtime

- [Agent and controls](../lib/examples/01_authoring/01_07_ai_runtime/agent.ex)
- [Integration tests](../test/examples/01_authoring/01_07_ai_runtime_test.exs)

The AI block declares named models, generation options, Action and Flow tools,
ordered controls, concurrency limits and typed output with bounded repair.
Ordinary routes and a Plugin share the same core Agent. Core commits the complete
candidate only after the Flow succeeds. A terminal Action now carries that
candidate and any typed Directives across the core commit boundary.

Tests check real tool IDs and results in the next model input, source-profile
JSON with host Registry IDs, a stored AI entry Action, repair feedback,
model and iteration budgets, full-batch preflight, each control boundary,
concurrency, cancellation and child cleanup, a blocked-control deadline,
provider errors, route defaults, and malformed definitions. A separate case
checks redaction of provider structs in output errors.

This is one-Turn execution. It does not claim the legacy request/session,
streaming, steering, approval or recovery APIs are ported.
