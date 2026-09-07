# 01_08 — Shared public model helpers

- [Shared implementation](../../../lib/jido_ai/shared/models.ex)
- [Public delegates](../../../lib/jido_ai/shared/facade.ex)
- [Integration tests](../test/examples/01_authoring/01_08_model_helpers_test.exs)

Six cases test the shared implementation now called by the public model helpers:
per-kind defaults, caller/nested option precedence, prompt normalization, text,
objects, SSE, actual gateway headers, usage, rich model identity and tagged
errors. They use the same HTTP/SSE mock as the Agent examples.

The header cases have the `HIST-01/stream-headers` tag and supply partial evidence
for issue 212 and commits `8f669705` and `26bb4106`. They do not yet prove the
legacy ReAct option path, Finch hook ordering or final dependency/installer QA.

The later [03_01 example](03_01_dynamic_catalog.md) compiles the complete
`Jido.AI` facade from the production shared directory and tests its public
text, object, stream and `ask` calls. The facade now uses v3 tool, prompt and
history APIs. Full root package and consumer checks remain separate gates.
