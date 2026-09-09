# ReAct terminal-state test transfer

All 78 [root ReAct cases](../../test/jido_ai/strategy/react_test.exs) remain and
pass. The [complete case map](react-setup-test-transfer.json) records 24 setup,
24 lifecycle, 18 context, two inspection, four initial-state and six terminal
cases. It has no unported row. Every original name at
`fc5bc1434ddb69493fe8a68443f03bc6a198c5a2` has one current test. No case was
removed, combined or skipped. This does not close the other Strategy files or
the full package migration.

| Original case | V3 case |
| --- | --- |
| `request_completed event marks request terminal and keeps checkpoint token` | `native checkpoints and standalone tokens keep terminal result and usage` |
| `llm_completed events merge nested provider usage without crashing` | `request usage sums real model calls and collection keeps nested provider metadata` |
| `request_completed with empty usage preserves accumulated LLM usage` | `empty final model usage and empty terminal event usage preserve earlier accounting` |
| `terminal checkpoint after request completion does not reopen active request` | `terminal checkpoint restore and token collection do not reopen completed work` |
| `request_failed with {:incomplete_response, :incomplete} preserves structured error` | `blank provider failure and the exact incomplete tuple retain their error values` |
| `request_failed preserves raw error in snapshot result` | `request inspection preserves a raw error map after real model work` |

## Checkpoint and inspection changes

Native Agents save through `Jido.Agent.checkpoint/1` and restore through
`Jido.Agent.restore/2`. The checkpoint keeps portable request records, usage,
results, errors and history. `Session.snapshot/2` returns the stored request and
its details. A failure is in `view.request.error`; `view.request.result` is nil.
`Request.await/1` returns `{:error, raw_error}`. The public ReAct event collector
keeps the raw error in its result field. These are explicit replacements for
the old private Strategy snapshot layout.

Standalone ReAct keeps its signed token API. The tests create and decode a
real final token, check saved result/usage, and collect the completed token
without more model requests. The terminal checkpoint event follows request
completion. No synthetic token or old Strategy worker event proves this path.

The [14_12 examples](../../examples/14_resume/14_12_terminal_state/README.md) add six
native cases: buffered/SSE responses with completion, a raw error map, or the
exact incomplete-response tuple. Each executes a real tool and two provider
calls before checkpointing. A safe ETF copy restores into a new Server, keeps
the old request and trace, and runs a later request with separate usage. Old
tools do not rerun. This proves terminal native Agent restore. Full v2 Agent
and Plugin checkpoint conversion remains required; these examples do not
convert an old payload or prove restoration of active work.

## Usage and error boundaries

Two real model responses accumulate 17 input and eight output tokens. A
separate public collector check retains the original nested numeric costs,
boolean, list-replacement and image-count assertions. The SDK can change
provider fields before collection, so the nested-map case is not a claim about
all provider wire formats. The [02_24 usage examples](../../examples/02_requests/02_24_stream_usage/README.md)
keep four required SDK numeric-string failures visible.

A real tool response supplies usage; the final model response supplies an
empty map. The stored total stays intact. A copy of the actual event stream
with empty terminal usage also keeps that total through `ReAct.collect_stream/1`.
This explicitly tests the collector fallback, as distinct from provider decoding.

An actual blank Chat SSE response with finish reason `incomplete` becomes
`{:incomplete_response, :error}` under the current SDK. The test records that
decoded result. An output control after real model work separately returns
the exact `{:incomplete_response, :incomplete}` tuple or the original raw 503
map. Await, inspection and event collection retain those values. A direct
collector input also retains the exact tuple with `:llm_response` metadata.
The control path does not claim to prove a provider's status decoding. The
[02_25 examples](../../examples/02_requests/02_25_incomplete_response/README.md) and
[02_08 contract](../../examples/02_requests/02_08_error_contract/README.md) cover the
related provider and public error paths. Old wrapper-envelope root failures
remain required work.

## Refinement and checks

No production file changed in this pass. Test helpers now separate native
checkpoints, standalone tokens and collector inputs. The root file no longer
calls the retired Strategy runtime. The first focused run found two fixture
errors: duplicate mock child IDs and unsupported mock reply syntax. Unique
child IDs and actual raw provider JSON fix those errors without a second mock.
Integration expectations use one helper to avoid constant-branch warnings.

The focused root result is 78/78 passed in 9.1 seconds. The initial integration
group passed all 54 cases in 9.1 seconds. Full final results and failure
comparisons are in the [root checkpoint](root-package-checkpoint.md).
Logs: `/tmp/jido-ai-v3-react-terminal-second.log` and
`/tmp/jido-ai-v3-terminal-examples-first.log`.

API inventory and history source-review fields are unchanged. No history row
or release gate is closed by this transfer.

Final complete checks: root 2,070/2,430 passed, 360 failed and one existing
exclusion; acceptance 1,192/1,196 passed, four required SDK failures and no
exclusions. The root comparison resolves exactly the six mapped failures and
adds no new failure. Acceptance adds six passing cases and keeps the same four
failed names. The full production compile passes for all 231 files with
warnings as errors. The final full acceptance run has no new terminal-test
compiler warning.
