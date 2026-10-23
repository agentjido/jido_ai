# Contexts, Sessions, and Threads

Use `Jido.Session` and `Jido.Thread` as portable context values. Both belong
to the `jido_ai` package. They do not start processes or execute requests.

## One context store

The Profile's `memory.history` setting names an Agent field. That field holds
one `Jido.Session`, or `nil` before the first request. Declare it with
`Jido.AI.Thread.Projection.schema()`. A Session owns one append-only Thread. The
Thread holds ordered `Jido.Thread.Entry` values, including AI messages,
context operations, and application entries.

Use `Jido.Session.state_schema()` when the field requires a Session value.
Both Agent state schemas validate canonical values without input conversion.
Use `Jido.Session.decode/1` to import an encoded Session before storing it.

The context-control Plugin holds lane and pending-operation state. It does not
hold a second Session or copy of the messages. `Jido.AI.Orchestration` is the separate
live API for request control and inspection; it is not the portable value.

## Build and project a context

```elixir
alias Jido.AI.Thread.Projection

thread = Jido.Thread.new(metadata: %{system_prompt: "Be concise."})
{:ok, session} = Projection.append(Jido.Session.new(thread: thread), [
  %{role: :user, content: "Hello"},
  %{role: :assistant, content: "Hi"}
], %{source: "/import"})

{:ok, messages} = Projection.messages(session)
```

`messages/1` returns ReqLLM messages in order for the selected context.
It applies saved replacements and lane switches. It ignores application entry
kinds. Invalid AI payloads return an error. Entry references stay outside the
provider message metadata. Text, tool correlation, binary content, and required
reasoning data have a versioned portable encoding.

The projection does not prepend `system_prompt` metadata. Agent execution uses
the selected Profile's instructions. Import and replacement can update those
instructions from the saved Thread metadata. Do not add the same system prompt
both as a message and as Profile instructions.

Use `Projection.select(thread, "lane-name")` to inspect a named lane. This
returns a selected Thread view without changing the original audit log. Do not
replace the full audit log with that view unless this is your explicit intent.

## Save and import

```elixir
restored = MyApp.SessionStore.load!("session-1")
{:ok, agent} = MyAgent.instantiate(state: %{messages: restored})
```

The application storage adapter owns encoding and decoding. It must return a
canonical `Jido.Session` value. Use the declared field name in place of
`messages` when it differs. Core Agent instantiation validates the Session and
the complete Agent state.

This state input does not restore active requests, workers, or Plugin state.
Use an execution checkpoint to resume pending work.

## Replace, compact, or switch

```elixir
{:ok, summary} = Projection.append(Jido.Thread.new(), [
  %{role: :user, content: "Summary of the earlier context"}
])

{:ok, _} = Jido.AI.Orchestration.modify_context(server, %{
  type: :replace,
  reason: :compaction,
  result_context: summary
}, op_id: "compact-1")

{:ok, _} = Jido.AI.Orchestration.modify_context(server, %{type: :switch},
  context_ref: "review", op_id: "switch-1")
```

Replacement accepts a canonical Thread or Session, or an encoded Thread map.
The `result_context` name identifies the replacement snapshot; it does not
accept the old Context struct. The old `context` input alias is removed.

An idle operation applies immediately. An operation received during a request
is deferred until that request terminates. Repeated operation IDs do not apply
twice. Operations append to the audit log; they do not erase earlier messages.
Compaction preserves trusted, matched skill activation tool pairs. Untrusted
references do not grant durability.

## Inspect and verify

Use `Jido.AI.Orchestration.snapshot(server)` for live request inspection. Use the
canonical Thread to inspect entry identity and references. Use
`snapshot.details[:tool_results]` for completed structured tool outputs rather
than parsing provider-facing tool messages.

See the [Session Agent example](../../examples/02_conversations/02_03_session_agent/README.md)
and [conversation history example](../../examples/02_conversations/02_04_conversation_history/README.md).

## Next

- [First Agent](first_react_agent.md)
- [Configuration Reference](../developer/configuration_reference.md)
