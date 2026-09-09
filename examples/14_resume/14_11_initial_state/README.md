# 14_11: Initial conversation state import

The [Agents](agent.ex) and
[tests](../../../test/examples/14_resume/14_11_initial_state/14_11_initial_state_test.exs) define seven
example cases. They use native Agent DSL and public AI Agents, buffered and
streamed model responses, and the same shared mock as all other examples.

## Import before startup

```elixir
saved_context =
  Jido.AI.Context.new(system_prompt: "Saved instructions")
  |> Jido.AI.Context.append_user("Previous question")
  |> Jido.AI.Context.append_assistant("Previous answer")

{:ok, agent} =
  Jido.AI.Agent.from_initial_state(MyAgent, %{context: saved_context},
    id: "restored-agent"
  )

{:ok, server} = Jido.start_agent(MyJido, agent)
```

The source can also be a neutral `Jido.Agent` definition. Use `profile: :review`
when importing into another declared profile. The normal profile selection
rules apply; a definition with multiple profiles and no default needs selection.
The selected profile must declare a history field. A supplied Context and that
same history field are ambiguous and are rejected, even when the list is empty.
Other declared application fields retain their values and core schema checks.
The import supplies required history fields before core instantiation.

A non-nil saved prompt becomes a portable override for the selected profile.
Nil uses that profile's configured prompt. Empty text remains an explicit empty
prompt. Other profiles keep their prompts and histories. Core state size checks
include the imported prompt. No provider request or tool execution occurs during
import.

The Context's reverse entry order becomes chronological domain history.
User/assistant/tool messages, typed image bytes, timestamps and refs remain data.
The v3 Context projection ID is derived from Agent ID and profile ID. It is not
the old Context ID. Import does not recreate a prior session thread revision or
claim ownership of old request IDs. Existing message refs stay on the messages;
new thread entries use current owned request identity.

## Scope and invalid input

This is the replacement for the old conversation-only
`initial_state: %{context: context}` startup recipe. It is not a decoder or
converter for a full v2 Agent checkpoint. Old `__strategy__`, request records
and Plugin-owned state need their separate conversion. They are rejected here.
No saved worker, pending input, model count or effect is inferred from Context.
Standalone State conversion remains the separate [14_09 API](../14_09_state_migration/README.md).

An AI Context under `:thread` is rejected. A non-AI Thread value is ordinary
application data if its field is declared in the destination schema. Unknown
fields, duplicate atom/string aliases, invalid Context shapes, live process
values and unknown options are errors. Plain decoded Context maps can use
atom or string fields; unknown Context format fields are rejected.

History must have a complete tool exchange: each result must match one declared
call, and all calls must have results. Duplicate, orphaned, interrupted and open
exchanges are rejected. Completed historical tools need not remain in the
current catalog; import does not execute them. Pending tool continuation belongs
to an explicit checkpoint path with its own execution evidence.

After import, use ordinary native checkpoint/restore or core instantiation with
saved v3 state. Do not pass the resulting Plugin state back through this initial
conversation import API.

## Evidence and refinement

Four examples import mixed text/image history and a completed tool exchange.
They start real model work, save portable native state, restart the Server and
make a second request. Each checks its HTTP streaming flag, old tool ID, one
copy of tool history, unchanged refs, eight final messages and no tool replay.
The native definitions have required history and application fields.

Two profile examples prove saved-prompt and nil-prompt behavior at the actual
provider while an unrelated profile keeps its own data. The last example
rejects ambiguous selection, unknown profiles, conflicting history and old
runtime state without changing the definition or starting model work.

The first refinement moved history preparation before core instantiation, so a
required history field works without an artificial default. The second moved
the existing standalone tool-history check into the shared History module.
Both conversion paths now use the same call/result ordering rules. No second
runtime, mock server or DSL term was added.

Run from the repository root:

```sh
mix test test/examples/14_resume/14_11_initial_state/14_11_initial_state_test.exs --include example --include pending_dsl
```

The [source test transfer](../../../docs/v3-spike/react-initial-state-test-transfer.md)
records four retained cases and the boundaries that remain open.
