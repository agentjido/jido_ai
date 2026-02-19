# Streaming Boundary Refactor: Directive-First, Remove 3-Action API

## Decision

Adopt **directive-first streaming** as the single architecture.

- Keep: `Jido.AI.Directive.LLMStream` runtime path.
- Remove: `StartStream` / `ProcessTokens` / `EndStream` action flow.
- Remove: `Jido.AI.Streaming.Registry` and streaming plugin wrapper.

This reduces duplicated abstractions and aligns streaming with the agent runtime contract.

## Current Problem

There are currently two streaming architectures:

- Directive path (already direct and coherent):
  - `lib/jido_ai/directive/llm_stream.ex`
  - Uses `ReqLLM.stream_text/3` and `ReqLLM.StreamResponse.process_stream/2` directly.
  - Emits `ai.llm.delta` and final `ai.llm.response` signals.

- Action path (extra lifecycle indirection):
  - `lib/jido_ai/actions/streaming/start_stream.ex`
  - `lib/jido_ai/actions/streaming/process_tokens.ex`
  - `lib/jido_ai/actions/streaming/end_stream.ex`
  - `lib/jido_ai/streaming/registry.ex`
  - `lib/jido_ai/plugins/streaming.ex`

The second path exists to split streaming into 3 invocations via `stream_id`, but this is not required for strategy runtime execution and duplicates behavior already solved by directives.

## Why the 3-Action API Is Now Tech Debt

- Duplicates core streaming semantics with a second lifecycle model.
- Introduces process-local registry state without strong ownership model.
- Adds cleanup/leak risk (`stream_id` entries can persist unless explicitly deleted).
- Adds concurrency/race risk around multi-consumer or repeated processing attempts.
- Increases docs and test surface area with little strategic value.
- Plugin state (`active_streams`) is currently not authoritative for stream lifecycle.

## Boundary Principle Going Forward

`ReqLLM.StreamResponse` is a transient execution object and should be consumed inside one runtime execution boundary.

`Jido.AI` should expose streaming as **directive runtime behavior**, not a split start/process/end API requiring external lifecycle bookkeeping.

## Removal Scope (Planned)

### Modules to remove

- `lib/jido_ai/actions/streaming/start_stream.ex`
- `lib/jido_ai/actions/streaming/process_tokens.ex`
- `lib/jido_ai/actions/streaming/end_stream.ex`
- `lib/jido_ai/streaming/registry.ex`
- `lib/jido_ai/plugins/streaming.ex`

### Tests/docs to update

- All tests under `test/jido_ai/skills/streaming/`
- `test/jido_ai/registry_lifecycle_test.exs` (streaming registry assertions)
- Any integration tests asserting streaming plugin action counts/routes
- Guides referencing `stream.start -> stream.process -> stream.end`
  - `guides/user/streaming_workflows.md`
  - `guides/developer/actions_catalog.md`
  - `guides/developer/plugins_and_actions_composition.md`
  - `guides/developer/architecture_and_runtime_flow.md` (registry lifecycle section)

## Cutover Plan

### Phase 1: Contract confirmation

- Confirm supported streaming contract is directive-only:
  - `Directive.LLMStream` emits deltas + terminal response signal.
- Confirm no external package/users depend on `stream.start/process/end` actions.

### Phase 2: Remove action/plugin/registry path

- Delete streaming actions, registry, and streaming plugin module.
- Remove references from plugin inventories and docs.
- Remove tests that are only asserting old plugin/action shape.

### Phase 3: Strengthen directive docs and tests

- Expand directive streaming guide around:
  - chunk emission semantics
  - tool-call chunks vs content/thinking chunks
  - error signaling
  - timeout behavior
- Ensure integration tests cover full runtime flow for streaming deltas + final turn.

### Phase 4: Optional compatibility bridge (only if needed)

If backward compatibility is required, provide temporary wrappers that return explicit deprecation errors pointing to directive usage. Timebox this to one release.

## Acceptance Criteria

- Only one streaming path remains in library code: `Directive.LLMStream`.
- No references to `Jido.AI.Streaming.Registry` remain.
- No `stream.start/process/end` routes remain.
- Documentation describes one canonical streaming workflow.
- Integration tests prove delta + final response flow still works end-to-end.

## Risks and Mitigations

- Risk: downstream users call old streaming actions directly.
  - Mitigation: add changelog migration section and optional short-lived deprecation wrappers.

- Risk: coverage drops when deleting many tests.
  - Mitigation: replace with directive-centric integration tests that validate user-visible behavior.

- Risk: perceived feature loss (manual token processing hooks).
  - Mitigation: expose callback/filter hooks in directive runtime if truly needed, without registry lifecycle split.

## Migration Note for Release

For users currently relying on `StartStream/ProcessTokens/EndStream`:

- Migrate to directive execution with `Jido.AI.Directive.LLMStream`.
- Consume incremental output via `ai.llm.delta` signals.
- Consume final result via `ai.llm.response` signal.
- Do not manage stream lifecycle manually via registry IDs.

## Open Questions

- Do we need a temporary compatibility window for the old actions?
- Do we need one small helper module for shared streaming callback policy (content/thinking/tool-call hooks), or keep it local to directive runtime?
