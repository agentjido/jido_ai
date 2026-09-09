# History review 11: telemetry, usage and tool payloads

Reviewed on 2026-09-06 against `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
This pass completes five more source reviews. The total is 80 of 126.
All v3 port checks remain pending. No runtime tests ran.

The review read all five complete diffs, their PR discussion and issues 265,
294, 307 and 326. It checked the final usage, sanitizer, tool and CoT worker
code. The larger observability foundation and later token-emission commit
still need separate complete reviews.

## Commit dispositions

| Commit | Final requirement to retain | Required cases |
| --- | --- | --- |
| `d4a72348` / PR 276 | Tool execution events retain the tool-call ID without inserting observer metadata into Action context. | HIST-13: tool correlation, telemetry context |
| `faac362a` / PR 297 | Shared usage merging adds counters and retains provider metadata across model turns without arithmetic failures. | HIST-13: usage merge, usage after answer, total sources |
| `2d967b57` / PR 300 | Telemetry and tool transport have explicit redaction and bounded-data profiles. | HIST-13: telemetry bounds, transport shape, sanitizer termination; RELEASE: sanitizer docs |
| `f362485d` / PR 309 | Token extraction accepts provider aliases; successful tool payloads retain nested data in `tool_result`. Keep stable AoT coverage and valid result types. | HIST-13: token shapes, tool payload; RELEASE: current type checks, stable lifecycle coverage |
| `301279ce` / PR 338 | Ordinary Actions reached through AI reasoning honor global, instance and explicit observation policy. | HIST-13: observer option paths; action logging and precedence from review 10 |

## One report Agent exercises the consumer contract

[Issue 307](https://github.com/agentjido/jido_ai/issues/307) reports a dependency
update that changed real telemetry consumers: model token counts became zero,
and a tool's returned data became only a type/size summary. The report links a
consumer bridge. Its source path returned HTTP 404 during this review, so the
report and final merged tests are the evidence; no current bridge behavior was
inferred from that unavailable file.

Extend the existing catalog 13 Agent with one model/tool/model sequence. A real
Action returns a report containing nested `result`, `content` and `output`
fields, plus a synthetic secret and a permitted attachment. Capture the Action
result, public tool event, telemetry event and next model request separately.
Use a second tool with another call ID in a parallel variant.

The telemetry consumer must recover the permitted nested report from
`tool_result`. Its `result` field remains a summary of the canonical result
tuple. The next model request receives the transport representation, with
attachments handled separately. Both views retain their own limits. The Action's
raw result and Agent domain state are not replaced by the telemetry summary.

| Variant | Required evidence |
| --- | --- |
| `HIST-13/tool-correlation` | Match tool start, stop and exception events to the actual call IDs, including parallel tools, retries, timeout, validation failure and unknown tool. Keep request/run/call identity through direct batches, standalone ReAct and live Agent work. A retry shares tool identity but retains attempt identity; it must not look like another model-selected tool. |
| `HIST-13/telemetry-context` | Give a real Action an application marker and separate observer metadata. The observer sees the supplied IDs; the Action sees its original context. Explicit observer metadata overrides context only in observation. Existing caller context fields remain intact. Invalid observer metadata cannot replace the business context or become Exec options. |
| `HIST-13/tool-payload` | Preserve small nested `result/content/output` values under `tool_result`, for atom and string keys. Redact sensitive values and retain applicable bounds. Keep `result` as a summary. Failed tools expose the documented error event/summary without inventing a successful payload; a valid nil result is still a valid tool result. |
| `HIST-13/token-shapes` | Through real provider responses and public AI Actions, verify Response structs, usage wrappers, direct maps and accepted token aliases. Verify the exact source/key precedence from review 12; explicit zero stays zero; absent totals use input plus output. Match observed counts to captured calls. Also retain direct helper checks for accepted data shapes that the wire decoder does not produce. |

The [PR 276 user confirmation](https://github.com/agentjido/jido_ai/pull/276#issuecomment-4364469431)
supports the ID fix. Its final implementation adds a separate
`telemetry_metadata` option and strips it before execution. The observation
view merges that map over context. The Action continues to receive the original
context. Its fallback uses `call_id` when `tool_call_id` is absent. An empty
batch-tool ID does not cause the helper to invent one.

The [PR 309 inline review](https://github.com/agentjido/jido_ai/pull/309#discussion_r3358017760)
found that a new top-level `tool_result` key alone did not fix nested payload
loss. The final change uses transport-style value handling below that key.
It keeps the telemetry limits and current depth; it does not reset to the larger
transport limits. Thus “full tool payload” means permitted detail within those
bounds, not unlimited data or an unredacted copy.

The extractor accepts the actual three-part execution result. Success provides
the payload; failure returns nil, which the event builder removes. The final
[maintainer review](https://github.com/agentjido/jido_ai/pull/309#pullrequestreview-4468978518)
requires correct result types and keeps the AoT lifecycle test in the stable
default suite. Retain `RELEASE/current-type-checks` and
`RELEASE/stable-lifecycle-coverage`; do not copy obsolete Dialyzer exceptions or
exclude the lifecycle test to close those gates.

## Usage has counters and metadata with different merge rules

[Issue 294](https://github.com/agentjido/jido_ai/issues/294) describes a
classifier that returned an answer and then crashed when nested cost maps or
booleans reached arithmetic merging. The report also describes restarted Agent
processes left behind. The final [PR 297](https://github.com/agentjido/jido_ai/pull/297)
fixes shared paths in ReAct state/projection, CoT/CoD projection, Turn parsing
and `CallWithTools` automatic execution.

The final merge rule is narrower than “sum every number.” Known counter names
and suffixes identify additive values. Nested maps merge recursively. Nil
preserves the other value. Other metadata uses the latest non-nil value; lists
are replaced, not concatenated. Numeric-looking IDs such as `"001"` remain
strings. Cost decimals retain their value instead of being truncated to tokens.

| Variant | Required evidence |
| --- | --- |
| `HIST-13/usage-merge` | Combine two actual model turns with token counters, nested cost maps, booleans, lists and provider IDs. Add supported counters, preserve decimal costs and leading-zero IDs, use the accepted latest metadata/list rule, and retain fields absent from the next record. Cover malformed top-level input, nil and mixed numeric representations with focused shared-helper tests. |
| `HIST-13/usage-after-answer` | Run the classifier through real CoT/CoD requests, then inspect the same Agent after final delivery and start another request. Monitor worker/Agent lifetime and verify no hidden restart or orphan. Use a real ReAct or `CallWithTools` two-call run to prove accumulation; retain the CoT projection regression as a focused test. |
| `HIST-13/total-sources` | Mix calls with explicit provider totals and calls with only input/output counters. Resolve each call's total before request aggregation. Preserve a supplied total even when it differs from the simple sum. Keep per-call, request and session usage separate; duplicate events cannot charge the same call twice. |

The issue describes a multi-draft CoD run. The checked final CoT worker makes
one model call per run, and the strategy clears request usage at start. The
new CoT regression injects two completion events directly. It proves safe
projection of those values, not a built-in multi-draft runtime. Do not add an
invented loop merely to reproduce the issue wording. Exercise actual supported
paths and preserve the reported no-crash requirement.

Provider metadata is not a billing ledger. For example, `cost.line_items` keeps
the latest list; unrecognized numeric metadata is not automatically additive.
Keep raw per-call usage available when the application needs each line item.
Canonical counters and budgets share one normalization/aggregation owner.
Replay deduplication is a v3 requirement, not a property of `Usage.merge/2`.

`ensure_total_tokens` adds a total only when one is not already numeric.
Applying that helper only after merging heterogeneous records can retain an
earlier partial total. The mixed-source case must prove the correct call and
request totals. The later token-emission commit is now covered by
[review 12](12-observation-and-token-reporting.md). Its source review is not
port evidence. That review records mixed atom/string precedence and the distinct
chunk, call and terminal rules.

## Keep one sanitizer with explicit boundary profiles

[Issue 265](https://github.com/agentjido/jido_ai/issues/265) requires bounded,
redacted telemetry and transport-safe payloads. [PR 300](https://github.com/agentjido/jido_ai/pull/300)
adds one package-local sanitizer and delegates from `Observe`. Ordinary emits
and span starts apply the telemetry profile. Tool-result JSON encoding applies
the transport profile. Existing recursive `sanitize_sensitive` remains a
redaction-only API; it is not the full transport conversion.

| Profile | Depth | List items | Map entries | String characters | Inspect setting |
| --- | --- | --- | --- | --- | --- |
| Telemetry | 4 | 10 | 32 | 512 | 512 |
| Transport | 8 | 100 | 100 | 16,384 | 2,048 |

Supported positive integer options override these defaults. Truncation markers
report omitted items/entries. Sensitive key matching is case-insensitive and
uses the defined names, key fragments and suffixes. This is key-based redaction;
it does not detect every secret embedded in free text.

| Variant | Required evidence |
| --- | --- |
| `HIST-13/telemetry-bounds` | Observe actual emitted metadata and span starts, with small, wide, deep and oversized nested data. Keep required correlation fields, bounded values and truncation markers. Verify redaction and disabled/feature-gated behavior. Test `tool_result` detail without losing telemetry bounds. |
| `HIST-13/transport-shape` | A real tool returns tuples, structs, invalid UTF-8 values, refs, functions and large nested data. The next provider request gets valid bounded JSON with documented summaries and redaction. Retain the success/error envelope and separate media parts. Include malformed or oversized keys and verify the encoding boundary itself. |
| `HIST-13/sanitizer-termination` | Exercise error-like maps with nil type/message, large tuples, wide required metadata and unusual keys under a bounded test task. Sanitizing cannot loop, lose mandatory correlation or crash the request. Define actual output/work limits before claiming all arbitrary terms are bounded. |

The existing implementation leaves binary keys unchanged, traverses every
transport tuple element and computes full list lengths for omission counts.
The error summary fallback can revisit a map whose type/message keys are nil.
These are source-level gaps to test, not verified fixes. Required metadata is
inserted before map truncation, which does not reserve those fields. The new
tests must prove their retention with wide metadata.

Keep field limits distinct from an overall byte/work budget. An inspect
`printable_limit` is not proof of a strict serialized byte cap. Define and test
the needed bounds at the shared sanitizer, instead of adding inconsistent
truncation in each Action or provider adapter. For `RELEASE/sanitizer-docs`,
compile the shipped examples and document the final profiles, summary shapes
and permitted `tool_result` detail.

## Ordinary routed Actions use the same observation policy

[Issue 326](https://github.com/agentjido/jido_ai/issues/326) reports full argument
and context logs despite `log_args: :none`. [PR 338](https://github.com/agentjido/jido_ai/pull/338)
applies core observation options to the ordinary Action fallback reached from
reasoning. This differs from model-selected tool execution and needs its own
live route in the example.

For `HIST-13/observer-option-paths`, route an ordinary Signal to a real Action
on the AI Agent. Test global and instance policy, explicit instruction overrides,
and `:full`, `:keys_only` and `:none`. Assert the Action result and permitted
logs/telemetry, including synthetic sensitive context. Compare the same Action
through a model tool and an ordinary core Agent. Observer choices cannot alter
business input or allow unsupported execution options through to Exec.

The inline review suggested asserting `:debug` for a global debug setting.
The final tests also set `log_args` to `:none` or `:keys_only`; core policy raises
the action threshold to at least warning and selects silent action telemetry.
The warning assertion therefore reflects the final policy. Preserve the policy
combination, not an isolated review suggestion.

The baseline test stubs Exec and checks options. That is not enough for v3:
the inspected new Exec rejects legacy `log_level`, `telemetry` and `retry` run
options. As [review 10](10-lifecycle-and-execution-policy.md) requires, move
observer policy to its proper owner and lower retry policy through the supported
execution contract. Reuse `HIST-13/action-logging` and
`HIST-13/logging-precedence` with real execution.

At shared operations, retain one usage adapter, one sanitizer and explicit
observer context. At live requests and method ports, reconcile actual calls,
events, usage and process lifetime. At package validation, retain stable tests,
current type checks and documented consumer payloads. Extend the same mock
server only for provider wire shapes these cases actually need.

## Baseline evidence

Source: [usage](../../../lib/jido_ai/shared/usage.ex),
[Action helpers](../../../lib/jido_ai/shared/actions/helpers.ex),
[automatic tools](../../../lib/jido_ai/operations/tool_calling/call_with_tools.ex),
[Turn](../../../lib/jido_ai/shared/turn.ex),
[Observe](../../../lib/jido_ai/shared/observe.ex),
[sanitizer](../../../lib/jido_ai/shared/observe_sanitize.ex),
[reasoning fallback](../../../lib/jido_ai/reasoning/helpers.ex),
[ReAct runner](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/react/runner.ex), and
[CoT worker](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/chain_of_thought/worker/strategy.ex).

Tests: [usage](../../../test/jido_ai/usage_test.exs),
[Turn](../../../test/jido_ai/turn_test.exs),
[Observe](../../../test/jido_ai/observe_test.exs),
[tool encoding](../../../test/jido_ai/executor_test.exs),
[tool integration](../../../test/jido_ai/integration/tools_phase2_test.exs),
[automatic tools](../../../test/jido_ai/skills/tool_calling/actions/call_with_tools_test.exs),
[ReAct runner](../../../test/jido_ai/react/runtime_runner_test.exs),
[ReAct projection](../../../test/jido_ai/strategy/react_test.exs),
[CoT projection](../../../test/jido_ai/strategy/chain_of_thought_test.exs),
[directive execution](../../../test/jido_ai/directive/exec_runtime_test.exs), and
[reasoning fallback](../../../test/jido_ai/reasoning/helpers_test.exs).

## Native TRM usage evidence: 2026-09-07

The [09_08 example](../../../examples/09_reasoning/09_08_trm/README.md) adds TRM to
the common usage path. Its retained Machine no longer adds arbitrary map
values; it uses the shared nested merge and derives a missing total when both
canonical counters are present. A full five-cycle Agent run makes 15 real model
calls and stores 225 tokens. Failed model phases retain failed-call and prior
usage. This is partial evidence; all provider and interruption variants still
require the broader history cases.

## Chat port evidence: 2026-09-07

[Example 16_02](../../../examples/16_capabilities/16_02_chat/README.md) supplies the
new execution evidence. The callable tool Flow now accumulates decoded nested usage over two real tool rounds. It retains prior usage after a later provider failure. Actual follow-up requests retain reasoning details and Responses identity. This does not close all native session or interrupted-provider accounting cases.

## Quota accounting evidence: 2026-09-07

[13_01](../../../examples/13_policy/13_01_quota/README.md) now tests per-call budget
records through real model transport, independent of the Agent commit. It
covers duplicate reports, separate repair/nested calls, cumulative stream
snapshots and partial failure usage. The ledger preserves the distinction
between known tokens and unknown cost. The profile documents zero-response
ambiguity after provider normalization. These checks add partial evidence;
they do not close all telemetry, provider or durable recovery requirements.

## Tool-start redaction execution evidence: 2026-09-07

[14_06](../../../examples/14_resume/14_06_trace_and_cycles/README.md) applies the
existing sensitive-key sanitizer to real tool-start events. Nested secret
values become explicit redaction markers while the real tool gets complete
inputs. Flat standalone options and native DSL observation settings use the
same Session boundary. These three cases extend PR 300's partial evidence;
they do not prove every sanitizer bound, provider payload or package gate.
