# Context History And Projection Model

This guide defines the V3 context history, portable session thread, and materialized projection.

## Ownership Boundaries

- Canonical message history: the Profile `memory.history` field in Agent state.
- Portable interaction value: `agent.state.jido_ai_contexts[profile_id].session` (`Jido.Session`).
- Append-only lane thread: `session.thread` (`Jido.Thread`).
- Materialized LLM view: `Jido.AI.Context`, returned by `Jido.AI.get_strategy_context/2`.
- In-flight turn state: live request execution state outside portable Agent state.

The declared history field is the source of truth for model messages. The
Agent-owned session thread records lane operations and the message batches that
support deterministic lane projection.

## Thread Entry Kinds

### `:ai_message`

Payload fields:
- `context_ref`
- `role` (`:user | :assistant | :tool`)
- `content`
- optional `tool_calls`, `tool_call_id`, `name`, `thinking`
- `request_id`, `run_id`

### `:ai_context_operation`

Payload fields:
- `op_id`
- `context_ref`
- `operation`

Operation map fields:
- `type` (`:replace` implemented now, `:switch` implemented now)
- `reason` (`:manual | :restore | :compaction | :system`)
- `result_context` for `:replace` (full context snapshot)
- optional `base_seq`, `meta`

## Materialized ReAct State

- `context`
- `run_context`
- `active_context_ref`
- `pending_context_op` (deferred while run active, latest wins)
- `applied_context_ops` (bounded op-id dedupe list)
- `projection_cursor_seq`

## Lifecycle

1. Run start:
- use materialized `context` for `active_context_ref`
- append the user `:ai_message` to the session thread
- initialize `run_context`

2. Run progression:
- append assistant/tool `:ai_message` entries when history commits
- append drained steering/injection input as user `:ai_message` when runtime emits `:input_injected`
- update `run_context` in lockstep

3. Context modify during active run:
- store only `pending_context_op`
- do not mutate `run_context` mid-flight

4. Terminal transition:
- finalize request state first
- apply deferred op second (append `:ai_context_operation`, then update materialized context)

## Projection Rule

For a lane (`context_ref`):
- find latest `:replace` anchor
- fold subsequent `:ai_message` events by sequence
- produce deterministic `Jido.AI.Context` at any seq boundary

## Steering Scope

- ReAct steering is user-style only in this version
- drained `steer` / `inject` input projects as `role: :user`
- hidden/system-role steering is not projected or persisted

## Idempotency

`op_id` is required for deterministic operation semantics. If already applied:
- no duplicate thread append
- no duplicate materialized mutation

## Compaction

Compaction is represented as a normal context operation:
- `type: :replace`
- `reason: :compaction`
- `result_context`: compacted snapshot
- provenance in `meta`

The session thread remains append-only.

## Compatibility Break

Old ReAct runtime/checkpoint payloads remain context-only:
- the old private runtime `thread` key is not restored
- token payload version bumped (`v2`, `rt2.` prefix)
- legacy private runtime payloads with `thread` are rejected

This rule does not reject the new portable `Jido.Thread` value in declared
Agent state. Native Agent checkpoints can retain `Jido.Session` and its thread.
