# Context And Message Projection

You need deterministic conversation state and explicit message projection to LLM input format.

After this guide, you can build and inspect history using `Jido.AI.Context`.

## Agent History, Session, And Thread

Four values have separate jobs:

- The Profile `memory.history` field stores the canonical portable message maps.
- `agent.state.jido_ai_contexts[profile_id].session` stores a portable `Jido.Session`.
- `session.thread` stores the append-only `Jido.Thread` entries for lane operations and audit data.
- `Jido.AI.Context` is the materialized LLM projection returned by the public context getter.

`Jido.Thread` and `Jido.Session` are ordinary portable values. They have no
process, Plugin, storage adapter, AgentServer, or execution behavior.

See the checked [Thread and Session example](../../examples/02_requests/02_27_thread_session_values/README.md)
for direct construction, selection, lifecycle, and encoding.

## Build Context

```elixir
alias Jido.AI.Context

context =
  Context.new(system_prompt: "You are concise.")
  |> Context.append_user("Hello")
  |> Context.append_assistant("Hi")
  |> Context.append_user("Summarize this chat")
```

## Project To Messages

```elixir
messages = Context.to_messages(context)
# [%{role: :system, ...}, %{role: :user, ...}, ...]

recent_messages = Context.to_messages(context, limit: 2)
```

## Import Existing Messages

```elixir
raw = [
  %{role: "user", content: "Question"},
  %{role: "assistant", content: "Answer"}
]

context = Context.new() |> Context.append_messages(raw)
```

Use `Jido.AI.Turn.extract_text/1` when normalizing diverse provider response shapes.

## Restore Snapshot Conversation Safely

When restoring from `snapshot.details.conversation`, split out one leading
system message first. Otherwise, that system message becomes a normal context
entry and may be duplicated during projection.

```elixir
saved_messages = snapshot.details.conversation

{system_prompt, conversation_messages} =
  case saved_messages do
    [%{role: role, content: content} | rest]
    when role in [:system, "system"] and is_binary(content) ->
      {content, rest}

    _ ->
      {nil, saved_messages}
  end

context =
  Context.new(system_prompt: system_prompt)
  |> Context.append_messages(conversation_messages)
```

Use `snapshot.details.conversation` for message restore/import workflows. Tool
messages in that conversation are serialized for LLM projection, so do not parse
them to recover structured tool payloads. For completed ReAct tool outputs, use
`snapshot.details[:tool_results]`.

## ReAct Context Operations

Canonical strategy signal for context lifecycle:

- `jido.ai.context.modify`

Busy semantics in ReAct:

- if idle, context operation applies immediately
- if a request is active, operation is deferred and applied after terminal state

## Compaction Is Replace

Compaction is represented as a standard context replace operation with reason metadata:

```elixir
%{
  op_id: "op_123",
  context_ref: "default",
  operation: %{
    type: :replace,
    reason: :compaction,
    result_context: compacted_context,
    meta: %{from_seq: 1, to_seq: 100}
  }
}
```

## Failure Mode: Unexpected Missing Context

Symptom:
- assistant ignores previous turns

Fix:
- verify you append both user and assistant/tool entries
- avoid too-small `limit` values during projection
- inspect with `Context.debug_view/2` or `Context.pp/1`

## Defaults You Should Know

- Entries are stored reversed internally for append speed
- `Context.to_messages/2` reorders to chronological output
- `limit: nil` includes the full context

## When To Use / Not Use

Use this when:
- you need explicit control over message windows
- you need an import/export-friendly context format

Do not use this when:
- strategy internals already manage conversation state for your use case

## Breaking Change

`Jido.AI.Thread` remains removed. Use canonical Session and Thread values for conversations.
The `jido_ai` package now provides `Jido.Thread` as a portable interaction log
and `Jido.Session` as a portable envelope that owns one thread. These values do
not restore the old core Thread Plugin or `Jido.Thread.Agent` helper.

`Jido.Session` can span many requests. `Jido.AI.Session` is the separate live
request API for admission, steering, cancellation, completion, and inspection.
If you previously restored state with `initial_state: %{thread: ...}`,
use `Jido.AI.Agent.from_initial_state(MyAgent, %{messages: session})` before
starting the Server. Declare any unrelated application `:thread` field in the
v3 Agent schema. Use the Profile's declared conversation field in place of
`messages` when it has another name. The special `:context` import is removed.
See the [import example](../../examples/14_resume/14_11_initial_state/README.md).

## Next

- [First Agent](first_react_agent.md)
- [Configuration Reference](../developer/configuration_reference.md)
