# State helper and request-state test transfer

The two root test files had 76 failing cases: 42 helper cases and 34 integration
cases. Many repeated the names, fields, or availability of removed core StateOp
structs. They are now 39 native behavior cases: 25 state-candidate cases and
14 live Agent cases. This is a consolidation, not 76 new passing executions.
No skip or exclusion was added. All 39 cases run in the default root suite.

The source baseline is `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
Each old case below maps to one or more exact new cases. Names were checked
against the baseline source. The [structured map](state-test-transfer.json)
contains the same old names and replacement IDs.

## State and API decisions

Use ordinary map and list operations to build complete state. Submit that state
through `Jido.AI.Effects.state/1`. The candidate layer validates the result,
protects Plugin state, merges disjoint proposals, and rejects conflicting ones.
It does not dispatch work. Directives remain pending until a core Agent commit.
The tests check final values and failure atomicity rather than old struct shape.

Nested updates are explicit. Use `put_in` or `Map.update` to retain siblings;
use `Access.key(key, default)` when a path can be absent. `Map.merge` is shallow.
Apply nested merges at the needed level. `Map.drop` removes keys. A new payload
map replaces old data. The effect layer does not repeat the old implicit deep
merge. Compose dependent edits into one candidate. Two same-base proposals
that change the same top-level field conflict; they do not silently overwrite.

Request status, iteration, tool calls, call IDs, streaming text, usage, and
termination now belong to the shared Session/Flow. Observe them through
`Session.snapshot/2` and request records. New requests reset live counters and
pending work. Completed records and their historical call IDs remain available.
Clearing active work does not erase diagnostic call IDs from a completed record.
No public setter is provided for core-owned request fields.

Configuration belongs to the AI profile and Configuration Plugin. Live tool
registration rebuilds targets, names, and ReqLLM definitions together. Catalogs
use canonical name order. Duplicate registration is a no-op, and unregistering
all tools clears all three views. Model/generation fields are declared in the
profile or passed through the existing request option path. They are not
changed by an arbitrary StateOp against private Strategy configuration.

Conversation updates use `update_context_entries/2` on a value or
`Session.modify_context/3` on a live Agent. Cases check prepend/append order,
complete replacement, empty replacement, the next provider request, and
unrelated state. Pending tools are checked during actual parallel Action work.
State tools stage changes before the next model call and commit them with the
answer. Cancellation and invalid proposals leave domain state unchanged.

## Defect found during transfer

Successful ReAct completion omitted `termination_reason` from stored metadata.
The shared completion path now supplies `:final_answer` when a method or limit
has not already supplied a reason. Four added
[response-metadata examples](../../test/examples/02_requests/02_07_response_metadata/02_07_response_metadata_test.exs)
check plain and streamed calls, with and without a tool round. The request,
terminal event, and Session view must agree. Existing limit and method cases
still check their distinct reasons. This relates to
[HIST-14 completed metadata](history-reviews/03-media-and-errors.md).

The protected-state fixture initially proposed an unchanged empty request map.
It now proposes a forged record, so the case proves actual protection. A catalog
fixture also assumed insertion order; it now checks the documented canonical
name order consistently in all three views and on the HTTP request.

## Native cases

| ID | Executed case |
| --- | --- |
| `U/change` | [complete state updates preserve unrelated fields and leave the source immutable](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/nested` | [nested edits preserve siblings and explicit merges replace only selected values](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/new-path` | [a new nested path is explicit and retains unrelated Agent fields](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/prepend` | [candidate lists keep prepend order without a hidden merge](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/append` | [candidate lists keep append order without a hidden merge](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/replace-list` | [candidate lists keep replace order without a hidden merge](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/empty-list` | [candidate lists keep empty order without a hidden merge](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/delete` | [deletion removes selected temporary keys and keeps unrelated data](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/delete-path` | [nested deletion removes one pending ID and an absent key is harmless](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/reset` | [an explicit domain reset removes old values and retains Plugin state](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/order` | [ordered map changes form one complete state candidate](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/compose` | [disjoint state proposals and pending directives assemble without dispatch](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/conflict` | [conflicting proposals reject the entire candidate and its directives](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/empty` | [empty effects and an unchanged candidate preserve the Agent](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/protect` | [a complete proposal cannot replace Plugin-owned request records](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/schema` | [schema errors reject state and all pending work](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/portable` | [unportable data cannot enter a state candidate](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `I/idle` | [new ReAct state has a profile and an idle session with no live handles](../../test/jido_ai/strategy/stateops_integration_test.exs) |
| `I/admit` | [admission records the query and live iteration without a Strategy state field](../../test/jido_ai/strategy/stateops_integration_test.exs) |
| `I/tools` | [pending tools are tracked by ID and each completed tool leaves the pending set](../../test/jido_ai/strategy/stateops_integration_test.exs) |
| `I/stream` | [stream text appends in order and the terminal answer retains the whole text](../../test/jido_ai/strategy/stateops_integration_test.exs) |
| `I/commit` | [tool candidates commit with the answer and preserve unrelated live changes](../../test/jido_ai/strategy/stateops_integration_test.exs) |
| `I/stage` | [later tools read the staged candidate before the final Agent commit](../../test/jido_ai/strategy/stateops_integration_test.exs) |
| `I/invalid` | [invalid candidate cannot change committed domain or request state](../../test/jido_ai/strategy/stateops_integration_test.exs) |
| `I/protect` | [protected candidate cannot change committed domain or request state](../../test/jido_ai/strategy/stateops_integration_test.exs) |
| `I/cancel` | [cancellation discards staged domain changes and clears live work](../../test/jido_ai/strategy/stateops_integration_test.exs) |
| `I/reset` | [a later request resets usage and active fields while keeping prior results](../../test/jido_ai/strategy/stateops_integration_test.exs) |
| `I/catalog` | [tool registration rebuilds all catalog views in the same order and can clear them](../../test/jido_ai/strategy/stateops_integration_test.exs) |
| `I/config` | [model generation and tool options come from the normalized profile](../../test/jido_ai/strategy/stateops_integration_test.exs) |
| `I/history` | [history replacement preserves message order and empty replacement clears it](../../test/jido_ai/strategy/stateops_integration_test.exs) |
| `I/entries` | [history prepend and append use committed context entries without losing a sibling](../../test/jido_ai/strategy/stateops_integration_test.exs) |
| `U/zero` | [candidate values retain the zero type and value](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/counter` | [candidate values retain the counter type and value](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/status` | [candidate values retain the status type and value](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/answer` | [candidate values retain the answer type and value](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/false` | [candidate values retain the false type and value](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/cleared` | [candidate values retain the cleared type and value](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/tools` | [candidate values retain the tools type and value](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |
| `U/usage` | [candidate values retain the usage type and value](../../test/jido_ai/strategy/state_ops_helpers_test.exs) |

## Old cases: `test/jido_ai/strategy/state_ops_helpers_test.exs`

| Old group | Old test | Native evidence |
| --- | --- | --- |
| update_strategy_state/1 | creates SetState operation with given attributes | `U/change` |
| set_strategy_field/2 | creates SetPath operation for a single field | `U/order`, `U/status` |
| set_iteration_status/1 | creates SetPath operation for status | `I/admit` |
| set_iteration/1 | creates SetPath operation for iteration counter | `U/counter`, `I/reset` |
| set_iteration/1 | accepts zero as valid iteration | `U/zero` |
| append_conversation/1 | creates SetState operation for conversation list | `I/entries`, `U/append` |
| prepend_conversation/2 | creates SetState operation with message prepended | `I/entries`, `U/prepend` |
| prepend_conversation/2 | works with empty existing conversation | `U/empty-list` |
| set_conversation/1 | creates SetState operation for entire conversation | `I/history`, `U/replace-list` |
| set_pending_tools/1 | creates SetState operation for pending tools | `I/tools` |
| add_pending_tool/1 | creates SetState operation for single tool | `U/tools`, `I/tools` |
| clear_pending_tools/0 | creates SetState operation to clear tools | `I/tools` |
| remove_pending_tool/1 | creates DeletePath operation for tool ID | `U/delete-path`, `I/tools` |
| set_call_id/1 | creates SetPath operation for call ID | `I/admit` |
| clear_call_id/0 | creates DeletePath operation for call ID | `I/cancel`, `I/reset` |
| set_final_answer/1 | creates SetPath operation for final answer | `I/stream`, `U/answer` |
| set_termination_reason/1 | creates SetPath operation for termination reason | `I/reset` |
| set_streaming_text/1 | creates SetPath operation for streaming text | `I/stream` |
| append_streaming_text/1 | creates SetPath operation to append streaming text | `I/stream` |
| set_usage/1 | creates SetState operation for usage metadata | `U/usage`, `I/reset` |
| delete_temp_keys/0 | creates DeleteKeys operation for temp keys | `U/delete` |
| delete_keys/1 | creates DeleteKeys operation for specified keys | `U/delete` |
| reset_strategy_state/0 | creates ReplaceState operation with initial values | `U/reset`, `I/reset` |
| compose/1 | returns list of state operations unchanged | `U/order`, `U/compose` |
| compose/1 | handles empty list | `U/empty` |
| update_config/1 | creates SetState operation for config | `I/config`, `I/catalog` |
| update_config/1 | creates SetState operation with nested config | `I/catalog`, `U/nested` |
| set_config_field/2 | creates SetPath operation for nested config field | `I/catalog` |
| set_config_field/2 | creates SetPath operation for model field | `I/config` |
| update_config_fields/1 | creates multiple SetPath operations | `I/config`, `I/catalog` |
| update_config_fields/1 | handles empty map | `U/empty` |
| update_config_fields/1 | creates SetPath operations in field order | `I/config`, `I/catalog` |
| update_tools_config/3 | creates three SetPath operations for tools config | `I/catalog` |
| update_tools_config/3 | handles empty tools list | `I/catalog` |
| update_tools_config/3 | creates operations in consistent order | `I/catalog` |
| apply_to_state/2 | applies SetState operation | `U/change` |
| apply_to_state/2 | applies SetPath operation for nested key | `U/new-path` |
| apply_to_state/2 | applies multiple SetPath operations | `I/catalog`, `U/nested` |
| apply_to_state/2 | applies DeleteKeys operation | `U/delete` |
| apply_to_state/2 | applies ReplaceState operation | `U/reset` |
| apply_to_state/2 | applies operations in order | `U/order` |
| apply_to_state/2 | deep merges nested maps with SetState | `U/nested` |

## Old cases: `test/jido_ai/strategy/stateops_integration_test.exs`

| Old group | Old test | Native evidence |
| --- | --- | --- |
| Helpers | update_strategy_state/1 creates SetState operation | `U/change`, `I/commit` |
| Helpers | set_strategy_field/2 creates SetPath operation | `U/status`, `U/order` |
| Helpers | set_iteration_status/1 creates SetPath operation for status | `I/admit` |
| Helpers | set_iteration/1 creates SetPath operation for iteration | `U/counter`, `I/reset` |
| Helpers | append_conversation/1 creates SetState operation | `I/entries` |
| Helpers | set_pending_tools/1 creates SetState operation | `I/tools` |
| Helpers | clear_pending_tools/0 creates SetState operation with empty list | `I/tools` |
| Helpers | set_call_id/1 creates SetPath operation | `I/admit` |
| Helpers | set_final_answer/1 creates SetPath operation | `I/stream` |
| Helpers | set_usage/1 creates SetState operation | `I/reset` |
| Helpers | delete_keys/1 creates DeleteKeys operation | `U/delete` |
| Helpers | reset_strategy_state/0 creates ReplaceState operation | `U/reset`, `I/reset` |
| Helpers | compose/1 returns list of state operations | `U/order`, `U/compose` |
| StateOp Structure | SetState operation has required fields | `U/change`, `U/schema` |
| StateOp Structure | SetPath operation has required fields | `U/new-path`, `U/schema` |
| StateOp Structure | DeleteKeys operation has required fields | `U/delete` |
| StateOp Structure | ReplaceState operation has required fields | `U/reset` |
| ReAct Strategy StateOps | initial state has expected structure | `I/idle` |
| ReAct Strategy StateOps | start instruction initializes state correctly | `I/admit` |
| ReAct Strategy StateOps | register_tool instruction updates tool list | `I/catalog` |
| StateOps Composition | multiple state operations can be created | `U/order` |
| StateOps Composition | different state op types can be composed | `U/compose`, `U/conflict` |
| StateOps Composition | conversation state ops can be created | `I/entries` |
| StateOps Type Safety | SetPath operations have correct value types | `U/counter`, `U/status`, `U/answer` |
| StateOps Type Safety | SetState operations have map attrs | `U/change`, `U/tools`, `U/usage` |
| StateOps Type Safety | DeleteKeys operations have list of keys | `U/delete` |
| StateOps Type Safety | ReplaceState operation has map state | `U/reset` |
| Phase 9.1 Success Criteria | Helpers module exists and is accessible | `U/change`, `U/order`, `I/admit`, `I/reset` |
| Phase 9.1 Success Criteria | state ops can be composed | `U/order`, `U/compose` |
| Phase 9.1 Success Criteria | ReAct strategy uses StratState for state management | `I/idle`, `I/admit`, `I/reset` |
| Phase 9.1 Success Criteria | all StateOp types are available | `U/change`, `U/delete`, `U/new-path`, `U/reset` |
| Phase 9.1 Success Criteria | StateOps helpers create correct op types | `U/change`, `U/delete`, `U/new-path`, `U/reset` |
| Phase 9.1 Success Criteria | ReAct strategy init returns agent and directives | `I/idle` |
| Phase 9.1 Success Criteria | ReAct strategy cmd returns agent and directives | `I/admit`, `I/commit` |

## Validation and limits

The first executing replacement run passed 35/38 cases. It found the missing
termination reason and the two fixture issues described above. After those
changes, all 38 passed. The coverage review added the absent nested-path case;
all 39 then passed in 3.0 seconds. See the
[root package checkpoint](root-package-checkpoint.md) for full-package results.

The API baseline and history source-review fields are unchanged. These cases
do not close other reasoning methods, legacy direct Action observability,
complete state conversion, recovery, CLI, consumer or runtime-floor gates.
No history row was closed. The goal remains active.

Logs: `/tmp/jido-ai-v3-state-transfer-test-01.log`,
`/tmp/jido-ai-v3-state-transfer-test-02.log`, and
`/tmp/jido-ai-v3-state-transfer-test-03.log`.
