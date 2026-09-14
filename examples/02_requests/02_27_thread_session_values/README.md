# 02_27: Thread and Session values

This example uses `Jido.Thread` as an immutable append-only interaction log and
`Jido.Session` as a portable value that owns one Thread. It uses no model,
provider, Agent process, Plugin process, external service, or storage adapter.

- [Example module](thread_session_values.ex)
- [Runnable demo](demo.exs)
- [Example tests](../../../test/examples/02_requests/02_27_thread_session_values/02_27_thread_session_values_test.exs)

## Build and inspect a Thread

```elixir
alias Jido.Thread

empty = Thread.new(id: "case-42", now: 1_000)

thread =
  Thread.append(empty, [
    %{kind: :ai_message, payload: %{role: :user, content: "Review this case"}},
    %{kind: :case_note, payload: %{status: "open"}}
  ])

Thread.entry_count(thread)                 # 2
Thread.get_entry(thread, 0)                # first entry
Thread.filter_by_kind(thread, :ai_message) # matching entries
Thread.slice(thread, 0, 1)                 # inclusive sequence range
```

`append/2` returns a complete new value. It does not change `empty`. The Thread
assigns monotonic sequence numbers and revisions. Entries can keep portable
payload data and correlation references.

## Own the Thread with a Session

```elixir
alias Jido.Session

session = Session.from_thread(thread, id: "support-session")
session = Session.put_metadata(session, %{owner: "support"})
closed = Session.close(session)

Session.open?(closed) # false
```

A Session revision includes both Thread appends and Session lifecycle changes.
A closed Session rejects new entries. It does not cancel or stop live work.

## Save and restore portable data

```elixir
document = Session.encode(session)
{:ok, restored} = Session.decode(document)
```

The documents have a type and version. Decode rejects unknown fields,
unsupported versions, and nonportable values. A Thread or Session cannot keep a
PID, task, function, provider client, or stream sink.

## Portable value and live API

`Jido.Session` is portable data. It can span several AI requests and can be
stored in declared Agent state. `Jido.AI.Session` is a different module. It owns
live request operations such as inspection, steering, cancellation, and context
changes on an AgentServer.

See [02_01](../02_01_session/README.md) for live request ownership. The
[thread and context guide](../../../guides/user/thread_context_and_message_projection.md)
explains how Jido AI stores one portable Session and Thread per
history-enabled profile.

Run the checked example:

```sh
mix test test/examples/02_requests/02_27_thread_session_values --include example --seed 0
```

Run the small terminal demo:

```sh
mix run examples/02_requests/02_27_thread_session_values/demo.exs
```
