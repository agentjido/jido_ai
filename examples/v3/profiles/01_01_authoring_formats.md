# 01_01 — Authoring formats

Task: ask one question through equivalent core authoring forms.

- [Agent and Flow](../lib/examples/01_authoring/01_01_authoring_formats/agent.ex)
- [Acceptance tests](../test/examples/01_authoring/01_01_authoring_formats_test.exs)

The Agent and Flow each have equal DSL, Builder, direct-data, and JSON values.
All forms run real model work. The Agent forms produce equal direct and live
results. The terminal Action preserves the case ID and increments the commit
counter. Only AgentServer commits the candidate.

Status: two passing integration tests. Registry IDs in this fixture are generated
for a single-version round trip. Stable application-owned artifact IDs and AI
source-profile formats remain authoring implementation requirements.
