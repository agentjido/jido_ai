# Conversation storage and projection

## Ownership

The Profile's `memory.history` field holds a `Jido.Session`. That Session owns
one append-only `Jido.Thread`. The context-control Plugin stores only the active
lane, one pending operation, and a bounded list of applied operation IDs. It
does not store messages or a second Session.

`Jido.AI.Thread.Projection` encodes AI entries and selects provider input. It has no
state. Internal `Session.Transcript` reads and commits the declared Session
field. `Model.Messages` removes private references before provider calls and
restores them only when the response retains the exact input prefix. In-flight provider
messages are request snapshots, not another committed store. Core Agent state
updates remain the commit boundary.

## Entry contracts

`:ai_message` payloads have string keys and a version. They contain role,
content, tool calls, tool-call correlation, message metadata, and reasoning
details. Binary parts use explicit base64 encoding. References such as
`request_id`, `run_id`, source, and lane remain in `Thread.Entry.refs`, outside
provider metadata. Entry identity, sequence, and time belong to Thread.Entry.

`:ai_context_operation` payloads also have a version. They contain operation ID,
lane, type, reason, optional base sequence, metadata, and an encoded canonical
Thread snapshot for replacement. A switch has no replacement snapshot.
`Jido.AI.Thread.Operation` validates and encodes this internal contract.

Application entry kinds are retained by Thread but excluded from model input.
Malformed AI payloads return errors rather than becoming provider messages.

## Selection and lifecycle

`Projection.select/2` chooses a named lane, or the last selected lane. A
replacement resets the selected message view to its saved Thread entries.
Subsequent AI entries extend that view. Selection does not mutate the audit log.

An admitted request retains its input snapshot. User, assistant, and tool
messages append through the existing runtime commit path. Session-mode history
can be published during execution; turn-mode history commits with its result.
These modes do not have identical publication timing.

An idle context operation applies immediately. During a request, the latest
pending operation applies after termination. Repeated applied IDs do not append
another operation. Compaction retains trusted, matched skill activation pairs;
caller-supplied references alone do not grant durability.

## Import and checkpoints

`Agent.from_initial_state/2,3` accepts canonical Session values or encoded Session
maps in declared fields. It preserves their entries and rejects incomplete tool
exchanges. It does not import live request or Plugin state. The legacy special
`:context` input and reverse-order history replacement API are removed.

Standalone `ReAct.State.context` is a canonical Thread. Its state checkpoint
format is version 4 and encodes that Thread. Execution checkpoint data retains
the pending runtime position and resumes through the shared Agent/Flow runtime.
Do not use a conversation import to resume tool execution.

## Contract evidence

- [Conversation codec and selection tests](../../test/jido_ai/conversation_test.exs)
- [Content and reference tests](../../test/jido_ai/conversation_content_test.exs)
- [Runtime ownership and replacement tests](../../test/jido_ai/conversation_runtime_test.exs)
- [Import tests](../../test/jido_ai/operations/initial_state_test.exs)
- [Standalone examples](../../examples/14_resume/README.md)
