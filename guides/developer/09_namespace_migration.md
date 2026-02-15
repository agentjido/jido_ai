# Namespace Migration Guide (2.0 Beta)

This release applies a strict namespace migration to `ai.*` runtime contracts.
There is no compatibility layer in `2.0.0-beta`.

## Core Rules

- Use `ai.<domain>.<event>` for shared runtime signals (`ai.request.*`, `ai.llm.*`, `ai.tool.*`, `ai.embed.*`, `ai.usage`).
- Use `ai.<strategy>.query` for strategy query entry signals (`ai.react.query`, `ai.cot.query`, `ai.tot.query`, `ai.got.query`, `ai.trm.query`, `ai.adaptive.query`).
- Keep ReAct control actions strategy-scoped (`ai.react.cancel`, `ai.react.register_tool`, `ai.react.unregister_tool`, `ai.react.set_tool_context`).
- Use `request_id` (not `call_id`) for request-rejection payloads (`ai.request.error`).

## Telemetry Roots

- Request lifecycle: `[:jido, :ai, :request, ...]`
- LLM lifecycle: `[:jido, :ai, :llm, ...]`
- Tool lifecycle: `[:jido, :ai, :tool, ...]`
- ReAct machine telemetry: `[:jido, :ai, :strategy, :react, ...]`

## Breaking Changes Checklist

- Replace all old `react.*` shared runtime signal names with `ai.*` names.
- Update `RequestError` and `EmitRequestError` payloads to use `request_id`.
- Update ReAct action atoms to `:ai_react_*`.
- Remove legacy tests/docs expecting old namespace aliases.

See `/Users/mhostetler/Source/Jido/jido_ai/todo/module_namespace_breaking_changes.md` for the full old-to-new mapping table.
