# 01_03 — Structured output

Task: obtain a nonempty typed answer, with at most one repair.

- [Agent and repair Flow](agent.ex)
- [Acceptance tests](../../../test/examples/01_authoring/01_03_structured_output/01_03_structured_output_test.exs)

ReqLLM sends the application JSON schema. The application validates the result
with Zoi. A schema failure becomes Iterate state and real feedback in the next
model request. Two total attempts bound the work. Exhaustion preserves a
non-default prior Agent state. Provider errors do not become schema repairs.

Status: two passing example tests. Imported schemas, attachments, result
metadata, and current AI repair callbacks remain part of the full port.
