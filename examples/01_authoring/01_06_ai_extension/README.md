# 01_06 — AI authoring extension

Task: author AI behavior inside the existing Agent DSL and common lowering API.

- [DSL source](spec.exs)
- [Acceptance tests](../../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs)

Four enabled example tests prove compilation and live execution of the AI
DSL, common lowering and lowered Builder/data/Agent-JSON equality, and invalid
profile rejection before model work, and rich alias resolution at request time. The code under test is in the production
AI package. Example tests remain excluded by default.

The source model record selects the mock server's chat protocol. It remains a
real ReqLLM request. Source-profile JSON, stable Flow IDs, mixed routes/Plugins,
and bounded runtime cases are covered by [01_07](../01_07_ai_runtime/README.md).
