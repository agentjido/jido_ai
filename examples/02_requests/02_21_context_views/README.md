# 02_21: Public context views and history changes

[Agent](agent.ex) and
[tests](../../../test/examples/02_requests/02_21_context_views/02_21_context_views_test.exs) use the
compiled public `Jido.AI` module, core Actions and the shared HTTP model server.

## Contract

`get_strategy_context/1` reads the history field declared by the selected AI
profile. Its Context ID is stable for that Agent ID and profile ID. An Agent
without history returns `nil`. A neutral definition also returns `nil`.
A declared empty history returns an empty Context with the current base prompt.

`update_context_entries/2` accepts Context entries in reverse order, as returned
by `Context.entries`. It stores chronological message maps in the declared
domain field. The input must be portable and must project into valid ReqLLM
messages. Invalid roles, missing tool IDs, invalid tool calls, process handles
and non-map entries cannot commit. The pure helper returns the updated Agent
or raises an error. It leaves an Agent without a history field unchanged.

A host Action can call the helper with `context.jido_ai_agent` and return the
resulting domain state. Core validates and commits that state. The example's
`case.history` route demonstrates this operation. The route is application
code; this change adds no DSL term or generated history route.

An active request keeps its admitted history. A history change affects the
next request. Later completion adds new assistant entries to the current
committed history, so it does not replace a newer summary with an old snapshot.
The v2 helper changed private `run_context` while active. Consumers that need
to add input to active work must use Session steering or injection. This
helper does not replace an active worker's private message buffer.

## Preserved data

Context reads and subsequent model requests preserve thinking, message order,
tool call/result IDs, reasoning details and stored references. Reads preserve
timestamps instead of assigning new times. Existing string timestamps stay
strings; this helper is not a timestamp parser. String-keyed message maps also
retain their supported fields. Malformed thinking values do not replace valid
content or become model text.

New assistant and tool history entries receive the request's message references.
Existing entry references remain intact, including consumed steering sources.
Message references remain separate from the runtime event's request identity.

## Evidence

Nine example cases cover:

- Exact Entry data through a public read, a real request and later reads.
- Decoded thinking through committed history and the next HTTP request.
- Plain Agents, neutral definitions, empty history and a live stateless profile.
- A real history Action during a held model call, followed by completion and a
  second request with the updated history.
- Invalid input rejection with the entire committed Agent unchanged.
- Reconstruction from portable v3 state, interrupted-request failure, provider
  cleanup and a later request without replay of the interrupted work.
- Real tool and assistant references across two requests.
- String-keyed stored messages with thinking and references.
- Malformed stored thinking with preserved visible content.

The reconstruction case uses an in-memory Erlang term round trip. It does not
prove offline v2 conversion, durable storage recovery, binary resource rebinding
or rollback. Skill compaction and activation records still need their own port.

## Refinement

The first checks exposed lost thinking, reset timestamps, a neutral-state crash
and acceptance of an invalid role. `Context.append_messages/2` now reuses the
existing entry conversion used by `Context.coerce/1`. One duplicate conversion
function was removed. History replacement uses the existing ReqLLM message
schema and core Agent update path. No new executor, process or mock was added.

Run from the repository root:

```sh
mix test test/examples/02_requests/02_21_context_views/02_21_context_views_test.exs --include example
```
