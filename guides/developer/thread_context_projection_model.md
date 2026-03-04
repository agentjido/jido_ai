# Thread-Context Projection Model

This guide defines the ReAct data model after the `thread -> context` materialized-view rename.

## Ownership Boundaries

- Core append-only event log: `agent.state[:__thread__]` (`Jido.Thread`).
- ReAct materialized LLM state: `agent.state[:__strategy__].context` (`Jido.AI.Context`).
- In-flight turn state: `agent.state[:__strategy__].run_context`.

`Jido.Thread` remains the source-of-truth audit log. ReAct `context` is a deterministic projection for LLM input.

## Canonical Core Thread Entry Kinds

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
- append user `:ai_message` to core thread
- initialize `run_context`

2. Run progression:
- append assistant/tool `:ai_message` entries as runtime events arrive
- update `run_context` in lockstep

3. Context modify during active run:
- store only `pending_context_op`
- do not mutate `run_context` mid-flight

4. Terminal transition:
- finalize run state first
- apply deferred op second (append `:ai_context_operation`, then update materialized context)

## Projection Rule

For a lane (`context_ref`):
- find latest `:replace` anchor
- fold subsequent `:ai_message` events by sequence
- produce deterministic `Jido.AI.Context` at any seq boundary

## Idempotency

`op_id` is required for deterministic operation semantics. If already applied:
- no duplicate core-thread append
- no duplicate materialized mutation

## Compaction

Compaction is represented as a normal context operation:
- `type: :replace`
- `reason: :compaction`
- `result_context`: compacted snapshot
- provenance in `meta`

Core thread remains append-only.

## Compatibility Break

ReAct runtime/checkpoint payload is now context-only:
- `thread` key removed
- token payload version bumped (`v2`, `rt2.` prefix)
- legacy payloads with `thread` key are rejected
