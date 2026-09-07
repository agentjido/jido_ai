# History review 15: public deterministic test helpers

Reviewed on 2026-09-06 against `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
This pass completes one more source review. The total is 88 of 126.
All v3 port evidence remains pending.

Read the full 1,014-line diff for `6bee9d44`, all PR 317 feedback, issue 315,
and the final helper/runtime source. No runtime tests were run in this pass.

| Commit / PR | Retained behavior | Acceptance mapping |
| --- | --- | --- |
| `6bee9d44` / PR 317 | Published ExUnit helpers for model decisions, explicit Agent/standalone scripts, canonical event assertions and real tool execution. | HIST-22: consumer API, history isolation, script validation, scope/cleanup and assertion evidence; RELEASE: helper package |

## Preserve the consumer API and use one mock engine

[Issue 315](https://github.com/agentjido/jido_ai/issues/315) asks for consumer
tests that describe Agent behavior without constructing ReqLLM chunks or using
internal stubs. It cites the first Jidoka test helpers as useful prior work.
The application must still execute its real tools, runtime and projections.

[PR 317](https://github.com/agentjido/jido_ai/pull/317) publishes `Jido.AI.Test`,
`Jido.AI.TestCase` and an opaque ReAct script. Its public surface includes
`expect_react`, `user`, `call`, `answer`, `fail`, `react_opts`, `react_llm_opts`,
reset and three assertion helpers. Keep that useful consumer surface in the
v3 migration. The plan must not drop it because it sits under a test namespace.

The v2 implementation inserts synthetic response maps before ReqLLM in the
runner. Both streaming and non-streaming paths consume them as completed
generation responses. Tools and runtime events still run, but transport,
provider validation, streaming deltas and decoder behavior are bypassed.

For v3, lower the consumer script into the same server/script contract used
by the acceptance examples. Keep one mock engine, one request log and one
failure report. The ergonomic `user/call/answer/fail` layer describes a script;
it must not introduce a second runner branch that manufactures completed Turns.
`react_opts` and `react_llm_opts` can remain adapters for explicit test bindings.
The script struct is documented as opaque, so its private representation need
not remain the old ETS-backed form.

The server remains test infrastructure. Production Agent data, imported JSON
and ordinary request options must not acquire a new mock-mode DSL. Make test
binding and lifetime explicit in the ExUnit helper. Run the normal Agent/Flow,
ReqLLM, real tools and state assembly against that binding.

## Retain the unresolved real-history regression

The [PR 317 inline review](https://github.com/agentjido/jido_ai/pull/317#discussion_r3448986957)
explains that old assistant tool messages advance a new script. The final
`consumed_tool_turns/1` still counts all assistant messages with tool calls.
There is no later change to this helper in the audited range. The requested
fix is absent from the inspected source; this pass did not run a reproduction.

Use one long-lived report Agent in catalog 05. First complete a request that
uses a real read Action. Register a new script whose first turn calls that
Action with a different path. The second request must execute the second Action
before its final answer. Inspect both actual Action invocations, the mock
requests and separate request IDs. Repeat with the same user prompt and with
restored conversation history.

Script progress must belong to a specific test/request. It cannot be inferred
from the number of tool messages in shared history. The existing mock already
consumes entries at its request boundary. Extend that contract with explicit
request/script identity where needed, rather than adding a second history-based
cursor.

| Variant | Required evidence |
| --- | --- |
| `HIST-22/consumer-api` | From a fresh consumer package, use `Jido.AI.TestCase` and `Jido.AI.Test` with the documented script syntax. Exercise implicit test binding and explicit Agent/standalone options. A real Action reads the requested fixture; its actual output reaches the next captured model request. Run both generation and real SSE forms. |
| `HIST-22/history-isolation` | Run two tool-using requests on one Agent, including repeated prompts and restored history. Each new script starts at its own first turn. Previous tools, steering text, message projection or compaction cannot silently skip steps or select another script. |
| `HIST-22/script-validation` | Reject missing/empty prompts, missing turns, missing terminal answer/failure, extra turns after a terminal, duplicate `user`, nested builders, invalid calls and malformed explicit scripts. Preserve useful mismatch/exhaustion errors. Failed builders clean up. Declared mock scripts fail on unmatched or unused work instead of reaching a real provider. |
| `HIST-22/scope-and-cleanup` | Run concurrent tests and Agents with equal prompt text. Scripts, requests and diagnostics remain isolated. Stop the first registering test while another script is active; the other test still works. Explicit binding works outside the test process tree. Finish, fail or cancel with unused steps and verify cleanup plus an informative report. |
| `HIST-22/assertion-evidence` | Preserve final-answer string/regex, requested tool name/arguments and no-runtime-failure assertions over canonical events. Add checks that fail on missing or invalid evidence. Distinguish a requested tool from successful Action execution; assert actual output/state separately. Test failed tools and partial traces so a helper cannot produce false passing integration evidence. |
| `RELEASE/test-helper-package` | Ship the documented helper modules and ExUnit integration in the package. Compile a fresh consumer, build the Testing documentation group and run current type checks. Retain required ExUnit PLT support. Ordinary production startup must not start a mock server or depend on test registry state. |

## Baseline limits that the new tests must expose

The builder requires one normalized nonempty user text and a terminal answer
or failure. It rejects nested builders and removes builder state in an `after`
block. Each `call` is one model turn with one tool call; multiple calls are
sequential turns, not a parallel batch. IDs default to `tc_1`, `tc_2`, and so on.
Usage and text options are supported. Do not reinterpret existing scripts as
parallel tool batches when adding advanced mock features.

Registered scripts are keyed by group leader and latest user text in a public
named ETS table. The first process that creates the table owns it. This is not
an explicit supervised test owner. Script replacement, equal prompts, owner
exit and asynchronous tests need evidence. The current helper suite is marked
`async: false`; the documentation's `async: true` example is not concurrency
proof.

An explicit script with a mismatched prompt returns an error. A registry lookup
with no match returns `:not_scripted`, which lets the runner call ReqLLM. An
answer/failure removes a registered script, while an explicit script remains
in its options. Steering, cycle-warning messages or repair prompts can alter
the latest-user match. The unified server must keep active test calls local
and report mismatches rather than silently remove the test boundary.

`assert_tool_called` inspects model-requested tool calls in `llm_completed`
events. It does not prove the Action succeeded. Argument comparison normalizes
only top-level keys and uses exact map equality, not a recursive subset match.
`assert_no_runtime_failure` only scans available failure/cancellation events;
missing trace data can yield an empty scan. `assert_final_answer` can use a
result string without proving successful terminal status. Preserve useful
assertion semantics while making their evidence limits explicit.

The baseline failure turn returns its reason without reporting its configured
usage. The streaming script path emits no actual provider deltas. These helpers
cannot prove interrupted-call accounting, streaming, session reuse, object
decoding or malformed-provider behavior. Those cases must use the actual wire
responses from the unified mock.

Define the `fail/1` adapter explicitly. The old helper can return an arbitrary
Elixir reason directly; an HTTP provider error passes through a decoder and
can have a different shape. Preserve supported failure expectations through
documented provider fixtures and error conversion. Report any unsupported raw
term or API change in the migration guide. Do not claim exact equivalence by
silently bypassing the real provider boundary again.

## Integration with the refinement passes

Add HIST-22 within the existing catalog families 03, 05 and 18. No new top-level
Agent family is needed. Before shared operations, agree on one script contract
and explicit test binding. During live requests, prove request identity, real
tools, histories and cleanup. At the final package gate, test published helpers
from a separate consumer. Keep each historical regression linked to its case.

The commit also moves `Jido.AI.TestCase` from internal test support into `lib`,
adds `:ex_unit` to the Dialyzer PLT and adds a Testing documentation group.
Retain their purpose with the new package layout. Do not copy the removed
internal case module and create a duplicate module definition.

Source: [public helpers](../../../lib/jido_ai/test.ex),
[script implementation](../../../lib/jido_ai/test/react_script.ex),
[case template](../../../lib/jido_ai/test_case.ex),
[runner boundary](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/react/runner.ex), and
[package configuration](../../../mix.exs).
Tests: [helper suite](../../../test/jido_ai/test_helpers_test.exs).
Guides: [package overview](../../../guides/user/package_overview.md) and
[standalone runtime](../../../guides/user/standalone_react_runtime.md).
