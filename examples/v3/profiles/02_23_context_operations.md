# 02_23: Context operations and lane history

[Agents](../lib/examples/02_requests/02_23_context_operations/agent.ex) and
[tests](../test/examples/02_requests/02_23_context_operations_test.exs) use core
Agent requests, real tools and the shared HTTP model server.

## Public API

```elixir
replacement =
  Jido.AI.Context.new(system_prompt: "Review this case.")
  |> Jido.AI.Context.append_user("Saved case summary")

{:ok, agent} =
  Jido.AI.Session.modify_context(server,
    %{type: :replace, reason: :manual, result_context: replacement},
    profile: :assistant,
    context_ref: "case-42",
    op_id: "restore-case-42"
  )

{:ok, agent} =
  Jido.AI.Session.modify_context(server, %{type: :switch},
    profile: :assistant, context_ref: "case-43", op_id: "switch-case-43"
  )
```

The selected profile must declare `memory.history`. Native and public macro
Agents use the same operation Action. The lowerer adds context routes and a
pure state Plugin only when history is declared. The Plugin has no runtime
process. The new `jido.ai.context.modify` Signal returns errors for invalid
operations. The retained `ai.react.context.modify` route accepts atom/string
fields and preserves the old invalid-input no-op behavior.

An operation can be `replace` or `switch`. Reasons are `manual`, `restore`,
`compaction` or `system`; absent reason means `manual`. An absent context ref
uses the active lane, initially `default`. An absent operation ID uses the
Signal ID. The most recent 128 applied operation IDs are retained per profile.
Reusing a retained ID does not alter context or append another operation. This
is a bounded deduplication window, not permanent exactly-once execution.

While the selected profile has pending work, one pending operation is stored.
A later operation replaces it. Current model/tool work keeps its admitted
context and prompt. The pending operation applies in the terminal commit after
success, failure, cancellation, task loss or Session-owner recovery. The final
request result remains intact. A replacement with no system prompt preserves
the current configured prompt. A new lane starts with no prior conversation.
Switching back restores that lane's history and saved prompt.

## State and Thread ownership

`jido_ai_contexts[profile_id]` contains the active ref, pending operation,
applied IDs and a portable `Jido.Thread` value. Session admission and history
commits append `ai_message` entries with request/run refs and the active context
ref. Applied operations append `ai_context_operation`. Direct history changes
and one-Turn history changes are reconciled by `ai_context_snapshot` before
the next context operation or Session message batch. They do not receive a
user operation ID. There is one journal per profile and no second message loop.

The Thread can grow with conversation history. The Agent's state-size limit
still applies to the complete candidate. Context changes that fail validation
or storage do not commit. State validation checks profile identity, pending
operation shape, unique bounded IDs, Thread sequence/count data and message
payloads. Restore rejects invalid values before a Session can apply them.

The public getters now accept a profile ID: `get_strategy_context/2` and
`get_strategy_config/2`. Their one-argument forms keep their default selection.
`Session.snapshot/2` selects those views using its selected request's profile.
Its details include `active_context_ref` and `pending_context_op`. Configuration
and conversation are current committed profile data, not an old private prompt.

The private standalone Agent also has context state. Native standalone tokens
exclude this owned Plugin field from the application domain. Resume recreates
private context bookkeeping from the saved messages. It does not promise to
transfer external context-operation journals through a standalone token.

## Compaction

Only `reason: :compaction` preserves accepted durable skill entries. Selection
requires a tool result named `load_skill`, skill-activation refs and a matching
assistant call ID/name. The matching original call and result stay together.
Mixed assistant batches retain only selected skill calls. Replacement copies
with the same IDs are removed, including copies with a conflicting function
name or arguments. Ordinary replacement can remove these entries.

This resolves the old helper's conflicting-assistant defect. It also accepts
typed ReqLLM calls and string-keyed call maps. The examples capture the next
real model request to check the retained call, instructions and prompt.

The compactor trusts accepted current history, as the old helper did. These
cases import that history through the host API. The real runtime origin,
callback approval, scoped catalogue, resource and binary path now has separate
proof in [18_01](18_01_skill_runtime.md). User refs cannot establish runtime
skill provenance. Direct host imports remain a trusted operation.

## Evidence and limits

Thirty-one integration cases cover idle/deferred operations, lane isolation,
operation IDs, request-profile inspection, actual tools, compaction, source
formats, invalid state and recovery. A real persistence adapter stores a pending
operation, then loses the reply to the completed request write. Loading stored
state proves that the answer, replacement, prompt and applied ID committed
together. A separate state round trip proves interrupted-request recovery with
one pending application and no provider replay.

The first full run exposed route scope and private checkpoint-domain defects.
The fixes keep routes absent for profiles without history and keep owned context
state out of standalone application schemas. The Plugin-stack example now
includes the pure context Plugin and proves that it has no child process.
No old Strategy callback or `Thread.Agent` API was restored. Full old Agent
conversion, skill provenance, all storage/failure variants, CLI and root package
acceptance remain open.

Run from `examples/v3`:

```sh
mix test test/examples/02_requests/02_23_context_operations_test.exs --include integration
```

## Caller refs and owned Thread IDs

`RefsBuffered` and `RefsStream` are native Agent DSL examples. They declare
history, steering and an explicit tool-context projection. Along with the
public Agent, they keep caller refs through a tool round, steer/inject and
portable state reconstruction. The next request reuses tool history once.
All 31 focused cases pass with integration and pending-DSL tags included.

Model-message refs keep caller correlation labels. The separate `ai_message`
Thread entry refs keep the owned request and run IDs. Caller `signal_id`,
`request_id` and `run_id` values cannot replace Thread identity, including string
aliases. Other caller refs remain available. Imported historical Context values
are still a trusted host operation; this fix does not rewrite old stored data.

Refs remain available to request transformers and their state views. The shared
Generate boundary keeps them out of HTTP bodies and preserves other provider
metadata. Response context restoration requires an exact matching input prefix.
Provider data cannot create private AI refs or repair an unresolved tool mismatch.
See the [context transfer](../../../docs/v3-spike/react-context-test-transfer.md)
for the retained root cases, boundary tests, refinement and full results.
