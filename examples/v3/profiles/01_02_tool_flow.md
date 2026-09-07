# 01_02 — Action and Flow tools

Task: request two calculations, then answer with their actual outputs.

- [Agent and operations](../lib/examples/01_authoring/01_02_tool_flow/agent.ex)
- [Acceptance tests](../test/examples/01_authoring/01_02_tool_flow_test.exs)

The model selects an Action and a nested Flow from a fixed catalog. The entire
batch is validated before Map starts. Real tool outputs are placed in the next
ReqLLM context with the original IDs and order. Unknown tools or invalid
arguments cause no tool effect and no state commit.

Status: three passing integration tests. This is one tool batch followed by
an answer, not the full ReAct loop. Dynamic discovery, interception, approval,
parallel domain-state changes, and shared budgets remain required feature ports.
