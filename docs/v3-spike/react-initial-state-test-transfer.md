# ReAct initial-state test transfer

All 78 [root ReAct cases](../../test/jido_ai/strategy/react_test.exs) remain.
This pass transfers four initial-context cases to `Agent.from_initial_state/3`.
At this checkpoint the file passed 72/78 cases, with six required failures.
The later [terminal transfer](react-terminal-test-transfer.md) completes all 78. The
[complete case map](react-setup-test-transfer.json) records 24 setup, 24 lifecycle,
18 context, two inspection, four initial-state and six terminal rows. It matches
every original name at `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2` and every
current name. No case was removed, combined or skipped.

| Original case | V3 case |
| --- | --- |
| `init with initial context from agent.state` | `initial Context import preserves history and its saved prompt` |
| `init with initial context without system_prompt gets config prompt` | `initial Context import fills a nil prompt from the profile` |
| `init rejects legacy :thread context payloads` | `initial state import rejects an AI Context under the legacy Thread key` |
| `init ignores non-context :thread state from core thread plugins` | `initial state import keeps a declared non-AI Thread value separate from conversation history` |

The old cases called the removed Strategy initializer on a manually built
Agent. V3 imports application state and optional Context before Server startup.
The returned instance uses core construction, schema validation and state size
limits. History and prompt overrides use the existing AI state fields. A later
request uses ordinary Agent/Flow/Session execution.

Three retained cases now complete real provider requests. They check saved
history order, saved/configured prompt behavior, the derived v3 Context ID and
retained application Thread data. The legacy Thread-key case retains its error
message through a tagged error. The API does not restore the private Strategy
container. The old Context ID is not the v3 projection ID; the example documents
that identity change. Message refs remain unchanged.

Nine new [boundary tests](../../test/jido_ai/operations/initial_state_test.exs)
cover required history/application fields, core defaults, empty prompts,
Plugin/unknown keys, conflicting aliases/history, missing history policy,
invalid options/profiles/sources, malformed/live data, tool-exchange order,
decoded Context maps and the final state size limit. The preparation function
is shared with normal history replacement. The existing standalone migration
now calls the shared tool-history validator with its original error mapping.

The [14_11 examples](../../examples/14_resume/14_11_initial_state/README.md) add seven
cases across public and native buffered/streamed Agents and two selected-profile
prompt variants. They prove actual HTTP inputs, image bytes, complete saved tool
history, no replay and a later native reconstruction. The final rejection case
starts no model request. Together with the existing 14_09 and 02_23 groups,
all 60 focused examples pass before the final decoded-input validation change;
the complete package run verifies that final change.

The first implementation tried core construction before importing history.
Refinement changed the order to support required history fields. A legacy
Thread error also needed validation before unknown-domain-key rejection. A test
fixture used the wrong existing tool-result argument order; the corrected test
retains the complete, orphaned, duplicate and interrupted exchange assertions.
No core or dependency file changed.

Initial conversation import is now implemented. Full old Agent checkpoint and
Plugin-state conversion remain separate, required work. This pass does not
close parent runtime conversion, active request recovery, pending skill work,
usage/checkpoint/raw-error ReAct cases or any other release gate.

Focused logs: `/tmp/jido-ai-v3-initial-state-before.log`,
`/tmp/jido-ai-v3-initial-state-first.log`,
`/tmp/jido-ai-v3-initial-state-final.log`, and
`/tmp/jido-ai-v3-initial-state-examples.log`.
See the [root checkpoint](root-package-checkpoint.md) for the final full results.


Final complete checks: root 2,064/2,430 passed, 366 failed, one existing
exclusion; acceptance 1,186/1,190 passed, four required ReqLLM failures and no
exclusions. Root resolves the four mapped failures and adds nine passing cases.
Acceptance adds seven passing examples. Neither comparison adds a failing
case. Final production compile passes for all 231 files. After grouping function
clauses to remove a compiler warning, all 13 boundary cases and 60 focused
examples pass again. The clause bodies and their relative order are unchanged.
