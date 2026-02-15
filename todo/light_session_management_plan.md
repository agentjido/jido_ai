# ReAct Light Session Management in jido_ai (All in Package, ReAct-First)

## Summary
Implement a light, additive session layer inside `jido_ai` that uses existing `jido` primitives (`Jido.Thread`, `Jido.Persist`, `Jido.AgentServer`) and removes internal duplication by migrating ReAct off `Jido.AI.Thread`.
Scope is ReAct only for v1, with optional persist/thaw and core ops plus transcript/window APIs.

## Locked Decisions
1. Package boundary: all work ships in `jido_ai` (no required `jido` core changes).
2. Strategy scope: ReAct only in v1.
3. Durability: optional persist/thaw when storage is provided.
4. API compatibility: additive; existing `ask/await/ask_sync` remain unchanged.
5. Architecture: migrate ReAct internals to `Jido.Thread` now, with compatibility shims for existing snapshot/transcript consumers.

## Public API Additions and Changes
1. Add `Jido.AI.Session` at `lib/jido_ai/session.ex` with:
   - `open(agent_module, session_id, opts \\ [])`
   - `message(server, content, opts \\ [])`
   - `await(request_handle, opts \\ [])`
   - `cancel(server, opts \\ [])`
   - `status(server)`
   - `transcript(server, opts \\ [])`
   - `window(server, token_budget, opts \\ [])`
   - `hibernate(server, storage_or_jido)`
2. Add `Jido.AI.Session.Transcript` at `lib/jido_ai/session/transcript.ex`:
   - `to_messages(thread, opts \\ [])`
   - `window(thread, token_budget, opts \\ [])`
3. Keep existing ReAct agent APIs unchanged in `lib/jido_ai/agents/strategies/react_agent.ex`.
4. Keep `lib/jido_ai/thread.ex` as legacy compatibility surface for now, documented as non-canonical.

## Canonical Session Data Model (v1)
1. Canonical event log is `agent.state.__thread__` (`Jido.Thread`), not `agent.state.__strategy__.thread`.
2. ReAct entry conventions in `Jido.Thread.Entry`:
   - `kind: :message`, payload `%{role, content, thinking, tool_calls}`
   - `kind: :tool_result`, payload `%{tool_call_id, name, content}`
   - `kind: :error`, payload `%{type, message, details}`
3. Thread metadata stores system prompt: `thread.metadata.system_prompt`.
4. Cross-correlation goes in `entry.refs`: `request_id`, `run_id`, `call_id`, `agent_id`.

## Internal Implementation Plan
1. Add a small thread codec helper at `lib/jido_ai/session/thread_codec.ex` for ReAct-specific append/projection helpers.
2. Migrate `lib/jido_ai/strategies/react/machine.ex`:
   - Replace `Jido.AI.Thread` with `Jido.Thread`.
   - Keep pure state transitions.
   - `to_map/1` no longer serializes full thread struct into strategy state.
   - `from_map/2` accepts canonical thread input and supports legacy map restoration.
3. Update `lib/jido_ai/strategies/react.ex`:
   - Read canonical thread from top-level `agent.state.__thread__`.
   - After machine update, write back canonical thread to `agent.state.__thread__`.
   - Preserve `details.conversation` shape via `Session.Transcript.to_messages/2`.
   - Keep existing request/tool/telemetry behavior unchanged.
4. Add compatibility migration logic:
   - If legacy strategy state has `:thread` or only `:conversation`, rebuild canonical `Jido.Thread` once and continue with canonical path.
5. Add session convenience flow in `Jido.AI.Session.open/3`:
   - If storage provided and resume enabled, try `Jido.Persist.thaw`.
   - If not found, start fresh server with `id == session_id`.
6. Implement `Jido.AI.Session.message/3` as thin wrapper over existing ReAct request signaling (`ai.react.query`) and `Jido.AI.Request`.

## Failure Modes and Behavior Contracts
1. Unsupported strategy in `Jido.AI.Session` returns `{:error, :unsupported_strategy}`.
2. Missing thread returns empty transcript (`[]`) rather than raising.
3. Invalid token budget for `window/3` returns `{:error, :invalid_token_budget}`.
4. Persist/thaw errors are propagated unchanged (`:not_found`, `{:error, :thread_mismatch}`, etc.).
5. Busy/cancel/error flows continue to produce deterministic request outcomes and append corresponding thread entries.

## Test Plan and Acceptance Criteria
1. Add transcript tests at `test/jido_ai/session/transcript_test.exs`:
   - `:message` and `:tool_result` projection parity with current ReAct context.
   - system prompt inclusion, limit behavior, token-window behavior.
2. Update ReAct machine tests at `test/jido_ai/react/machine_test.exs`:
   - canonical `Jido.Thread` usage.
   - legacy state restoration path.
   - conversation projection unchanged.
3. Add session API tests at `test/jido_ai/session_test.exs`:
   - open new, resume existing, message/await, cancel, status, transcript/window.
4. Add persistence integration tests using ETS storage:
   - hibernate after first request, thaw, send second request, transcript contains both turns.
   - checkpoint does not persist full thread under `__strategy__`.
5. Preserve existing ReAct API behavior:
   - current `ask/await/ask_sync` tests remain green with no caller changes.

## Documentation Updates
1. Add new guide `guides/developer/10_sessions.md` with:
   - architecture, thread conventions, session API usage, persistence examples.
2. Update `guides/developer/01_architecture_overview.md` to mark `Jido.Thread` as canonical session log for ReAct.
3. Update `README.md` with a short "Session API (ReAct)" section.
4. Register new guide in `mix.exs` docs extras list.

## Assumptions and Defaults
1. No new policy/routing/circuit-breaker work in v1.
2. No cross-strategy unification in v1; only ReAct is session-enabled.
3. Session identity defaults to agent instance ID.
4. Persistence is opt-in and storage-backend-driven.
5. `Jido.AI.Thread` remains available but non-canonical in this release.
