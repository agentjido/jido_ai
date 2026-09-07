# 01_04 — Controls

Task: check access before a model call and check evidence before commit.

- [Agent and control Actions](../lib/examples/01_authoring/01_04_controls/agent.ex)
- [Acceptance tests](../test/examples/01_authoring/01_04_controls_test.exs)

Explicit Flow steps establish input-control, model, output-control, and state
assembly order. Denied input makes no model request. Denied output, HTTP failure,
and a decoder exception preserve live state. Accepted output commits once and
preserves the case ID.

Status: five passing integration tests. These are application control Actions.
AI control DSL lowering, request/model/operation controls, interruption, and
shared quota rules remain pending.
