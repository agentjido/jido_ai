# History review 12: observation and token reporting

Reviewed on 2026-09-06 against `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
This pass completes two more source reviews. The total is 82 of 126.
All v3 port evidence remains pending.

Read both complete commit diffs, their merged PR descriptions, the original
PR 222 discussion and inline reviews, and issues 219 and 311 with all comments.
Inspect the final source and tests for the affected contracts. No baseline
runtime tests were run in this pass. Historical test reports are source evidence
only. They do not establish that the current package or v3 port passes.

| Commit / merged PR | Retained behavior | Acceptance mapping |
| --- | --- | --- |
| `09485efa` / PR 229 | Public tool-start events, optional signal metadata, valid shared LLM event names, error normalization and CLI trace fields. | HIST-13: event contract, public metadata, tool projections, startup failure; HIST-14: Action error display; HIST-19: trace correlation; RELEASE: test module identity |
| `6d021352` / PR 312 | Shared token normalization and reporting across direct Actions, directives and ReAct; preserve stream and terminal usage. | HIST-13: usage source precedence, cumulative stream usage, terminal usage, usage signal policy, operation usage parity |

## Preserve the real user workflows

[Issue 219](https://github.com/agentjido/jido_ai/issues/219) describes tool tracing
that required custom wrappers because tool-start signals were absent. The
[maintainer response](https://github.com/agentjido/jido_ai/issues/219#issuecomment-4137364333)
links the fix to PR 229. The acceptance example must observe a real registered
Action through the public Agent path. It must receive start and result events
without a wrapper that emits substitute events.

The [original PR 222](https://github.com/agentjido/jido_ai/pull/222)
was split into PRs 229, 230 and 231. Its inline review found invalid five-part
LLM event names, invalid embedding inputs used in telemetry length measurement,
and empty embedding results used in an unsafe dimension calculation. Preserve
these negative cases. Use the final merged changes to determine behavior;
the abandoned umbrella diff is not another released feature set.

[Issue 311](https://github.com/agentjido/jido_ai/issues/311) reports that token
measurements were still zero after the user installed PR 309. The
[final response](https://github.com/agentjido/jido_ai/issues/311#issuecomment-4763018364)
identifies PR 312 as the later token fix. It also directs consumers to
`metadata.tool_result` for permitted tool details. Review 11 defines that
payload's actual bounds. A successful first fix does not close both symptoms.

Extend the catalog 13 report Agent. Let one model call request a real Action
that returns nested report data. Let a second call produce the answer. Capture
HTTP requests, public events, telemetry, final usage and Agent state. The
consumer must show the tool start, retain permitted report fields, and report
the correct counts for each call and for the whole request.

## Event contracts and execution evidence

PR 229 uses the shared `[:jido, :ai, :llm, event]` namespace for Chat, Complete,
GenerateObject and Embed. The operation is metadata, not another event-path
segment. Request, model-call and tool-execution events have separate meanings.
Required metadata keys can be nil when the source has no value. Do not invent
call IDs, elapsed time, or a worker origin to fill those fields.

Direct Action start events occur before input validation and model resolution.
They prove that the Action started; they do not prove an HTTP request occurred.
Measure actual provider work at the shared mock. A rejected input can therefore
have Action start/error events and zero model requests.

The new `ai.tool.started` signal requires the call ID and tool name. Arguments
are optional. Metadata is additive on tool and LLM results. Existing callers
can omit it. The LLM response helper retains both accepted result tuple forms
and the canonical Turn form. Reuse the error contract from review 03, including
canonical retry flags taking precedence over legacy aliases.

| Variant | Required evidence |
| --- | --- |
| `HIST-13/llm-event-contract` | Run each direct LLM Action through real execution and the mock transport. Attach handlers to the valid shared event paths. Match operation, model, available correlation fields, duration and success/error outcome. Cover invalid input and invalid model with zero HTTP calls. Disabled observation and disabled deltas retain execution behavior. |
| `HIST-13/public-signal-metadata` | Use old inputs without metadata and new inputs with request/run/iteration metadata. Retain existing required payloads and accepted LLM result forms. A real tool emits start and result with the same call ID. Known IDs stay correlated across public events and telemetry. |
| `HIST-13/tool-terminal-projections` | Hold a real tool, then complete, fail, retry, or time it out. Preserve public lifecycle meaning and internal execution diagnostics. One legacy timeout can emit both timeout and error observations; neither creates another execution, terminal request result, or usage charge. |
| `HIST-13/startup-failure` | Fail worker or supervisor startup before tool/model execution. Deliver a structured terminal failure with available correlation fields. Emit no false successful-start evidence and leave no owned worker behind. Signal-construction failure must not hang the request. |
| `HIST-14/action-error-display` | Call each direct LLM Action with validation and provider failures. Retain documented user-facing strings, including timeout, while canonical runtime errors retain their structured cause. Synthetic private details must not enter the display result. Shared error handling must not turn failure into success. |
| `HIST-19/trace-correlation` | Capture real CLI trace output for direct Action and tool events. Show supplied IDs and origin/operation/method fields. An absent call ID does not become `call=?` or another fabricated identity. Retain the existing non-interactive CLI contract. |
| `RELEASE/test-module-identity` | Compile the package tests with unique module names so duplicate modules cannot hide coverage. PR 229 includes the StateOps helper test-module rename; v3 does not need the removed StateOps implementation to retain this check. |

The tool-start event occurs outside the legacy retry loop. It is not a count of
all attempts. Tool timeout and tool error can both describe the same failure.
Use distinct request, call and attempt identities when accounting needs them.
Do not count diagnostic events as extra business work.

## One usage owner, three distinct merge rules

PR 312 shares `Usage.token_counts/1` across telemetry and usage signals. It
accepts a Response with usage, an atom-keyed usage wrapper, or a direct usage
map. It also searches one nested `tokens` map. A string-keyed `"usage"` wrapper
is not an accepted wrapper in this helper. Do not claim arbitrary recursive
provider normalization.

The current lookup searches the outer map before nested tokens. Within each
map, all listed atom aliases precede all listed string aliases. For example,
atom `:prompt_tokens` precedes string `"input_tokens"`. Explicit zero is valid.
Negative values become zero. Numeric floats and complete numeric strings are
truncated to nonnegative integers. Invalid values permit the next alias.
A supplied total is retained even if input plus output differs. Only a missing
valid total uses that sum. Preserve raw provider metadata beside these counts.

| Boundary | Baseline rule | Required v3 decision or proof |
| --- | --- | --- |
| Several chunks in one model call | Keep the maximum canonical input, output and total counters independently; other fields use the latest shallow merge. | Do not add cumulative chunks. Define handling for decreasing adjustments and partial chunks whose independently derived totals conflict. |
| Separate model calls | Add known counters and merge metadata with the rules from review 11. | Normalize each call before request aggregation. Preserve call identity and prevent duplicate charging. |
| Terminal request snapshot | A nonempty terminal map replaces accumulated usage. Empty, nil or invalid usage keeps the accumulated value. | Do not add the snapshot again. Cover sparse nonempty snapshots and explicit zero so valid accumulated counts do not disappear by accident. |

Stream usage selection has another order: a nonempty processed Turn wins;
otherwise use StreamResponse metadata; otherwise use accumulated chunk usage.
The baseline fills an empty value. It does not combine complementary fields
from all three sources. Chunk usage is captured even when delta capture is off.
The per-stream scratch value is removed after processing. Both success and
failure need isolation checks across consecutive calls.

The existing stream test stubs processing. The v3 example must send actual
provider JSON/SSE and use the real decoder. Use focused helper cases only for
accepted input forms that the decoder cannot produce.

| Variant | Required evidence |
| --- | --- |
| `HIST-13/usage-source-precedence` | Exercise supported outer/nested maps, aliases, mixed atom/string keys, malformed values, numeric strings/floats, zero and explicit totals. Record exact precedence. Send conflicting and complementary processed, stream-metadata and chunk records. Keep source availability distinct from observed zero. |
| `HIST-13/stream-cumulative-usage` | Send repeated and increasing cumulative usage chunks through real SSE. Count one model call once. Include partial input/output chunks, decreasing values, capture disabled, two calls and cleanup after error/cancel. Preserve raw metadata and define a consistent final total. |
| `HIST-13/terminal-usage` | Accumulate two model calls, then deliver normal, empty, nil, invalid, sparse and explicit-zero terminal usage. Compare public stream collection, request state, final result and telemetry. A terminal snapshot must not double count or erase known usage without a documented rule. Check failed and cancelled requests after provider work. |
| `HIST-13/usage-signal-policy` | Compare `ai.usage`, completion telemetry and request totals for normal, cached, total-only, all-zero and absent usage. Preserve cache counters and available correlation. Record legacy signal suppression and define v3 availability behavior before connecting quotas. |
| `HIST-13/operation-usage-parity` | Run Chat, Complete, GenerateObject, Embed, non-streaming generation and streaming generation through real provider decoding. Match available usage in operation results, observations and the request total. Keep each operation's public result shape. Include invalid inputs, empty embeddings, absent dimensions and provider errors. |

The legacy `ai.usage` helper emits only when input or output is positive.
It suppresses a positive total-only record, zero counts and absent usage.
Telemetry can still contain a positive total. V3 must make that distinction
explicit; a missing signal cannot prove that no provider work occurred.
The helper adds cache counters to metadata, but does not supply every request
correlation field. A broader v3 guarantee needs new evidence.

Public stream collection updates accumulated usage on model completion. Its
failure and cancellation reducers do not apply terminal usage as the success
reducer does. The PR does not prove that all interrupted provider work is
accounted for. Retain the failure/cancellation cases in the quota gate.

## Embedding and validation checks

The original inline review requires invalid embedding list entries to return
validation errors rather than crash during telemetry length measurement. The
merged code filters the telemetry input before measuring it. Test that behavior
with an invalid entry and verify zero provider calls.

Source inspection also shows incompatible response assumptions in the current
Embed Action. Its result formatter expects a list of vectors. Its completion
metadata first looks up `response[:usage][:dimensions]`. Both inspected local
ReqLLM versions return vectors by default and require `return_usage: true` for
an embedding/usage map. Embed does not set that option. Merely enabling it also
requires adapting the list-only formatter. The final baseline tests stub vector
lists; this pass did not run them or reproduce the suspected failure.

The v3 case must prove an actual embedding response, optional usage, correct
dimensions and the existing public `embeddings/count/model/dimensions` shape.
Do not stub a convenient response shape that the selected ReqLLM call cannot
return. Retain empty-output handling at the adapter boundary even if a provider
rejects an empty input batch before HTTP dispatch.

## Refinement and evidence

At shared operations, keep one usage adapter with explicit chunk, call and
terminal rules. At live requests, reconcile actual calls, public events, state
and cleanup. At method and quota ports, test interruption and duplicate delivery.
At the final package gate, compile the documented event names and consumer
payload examples. Use the existing catalog families and unified mock server.

PR 312 reports a broad historical test run and a smaller smoke run with many
excluded tests. It also reports existing warnings under warnings-as-errors.
These reports do not replace fresh v3 checks or make excluded cases pass.

Source: [Observe](../../../lib/jido_ai/observe.ex),
[Usage](../../../lib/jido_ai/usage.ex),
[Action helpers](../../../lib/jido_ai/actions/helpers.ex),
[Embed](../../../lib/jido_ai/operations/llm/embed.ex),
[directive helpers](../../../lib/jido_ai/directive/helpers.ex),
[tool execution](../../../lib/jido_ai/directive/tool_exec.ex),
[LLM response](../../../lib/jido_ai/signals/llm_response.ex),
[tool start](../../../lib/jido_ai/signals/tool_started.ex),
[ReAct runner](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/react/runner.ex), and
[stream collection](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/react.ex).

Tests: [Observe](../../../test/jido_ai/observe_test.exs),
[Usage](../../../test/jido_ai/usage_test.exs),
[public signals](../../../test/jido_ai/signal_test.exs),
[directive execution](../../../test/jido_ai/directive/exec_runtime_test.exs),
[Chat](../../../test/jido_ai/skills/llm/actions/chat_action_test.exs),
[Embed](../../../test/jido_ai/skills/llm/actions/embed_action_test.exs),
[ReAct runner](../../../test/jido_ai/react/runtime_runner_test.exs),
[ReAct projection](../../../test/jido_ai/strategy/react_test.exs), and
[CLI trace](../../../test/jido_ai/cli/adapters/mix_task_contract_test.exs).

## Chat port evidence: 2026-09-07

[Example 16_02](../../../examples/16_capabilities/16_02_chat/README.md) supplies the
new execution evidence. All four standalone LLM Actions now have actual HTTP and canonical telemetry evidence. Embedding requests return usage to the Action internally while preserving its vector result. Empty vectors, invalid inputs and provider failures are covered. Invalid typed output reports completed provider usage in error telemetry. CLI and the full cross-operation failure accounting gate remain open.

## Quota accounting evidence: 2026-09-07

[13_01](../../../examples/13_policy/13_01_quota/README.md) now tests per-call budget
records through real model transport, independent of the Agent commit. It
covers duplicate reports, separate repair/nested calls, cumulative stream
snapshots and partial failure usage. The ledger preserves the distinction
between known tokens and unknown cost. The profile documents zero-response
ambiguity after provider normalization. These checks add partial evidence;
they do not close all telemetry, provider or durable recovery requirements.
