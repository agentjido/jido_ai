# Stream usage fallback port

The shared native model operation now uses
[`Jido.AI.Usage.Stream`](../../lib/jido_ai/usage/stream.ex) to process a
ReqLLM stream. Core Exec still owns the operation and its deadline. ReqLLM
still decodes and materializes provider content. No model server, executor or
provider parser was added.

## Preserved source rules

The first nonempty map wins: processed response, stream metadata, then captured
chunk usage. The selected map is normalized through the existing AI Usage
helper. Its canonical counts retain supplied totals and derive an absent total
from input and output. A nonempty processed zero wins over positive fallback
sources. Sparse processed metadata does not borrow counters from another source.
No available map leaves usage absent.

Several chunks in one call retain the maximum input, output and total counts
independently. Other fields use the latest shallow map. Thus independent maxima
can differ from input plus output; the fallback preserves that baseline rule.
Separate model calls still use the existing additive Usage merge. Terminal
request snapshots still use the existing collection rule.

The adapter normalizes accepted decoded chunk counters before ReqLLM's final
accumulator consumes them. Stream reduction carries the per-call accumulator.
On normal exhaustion it reads metadata while the SDK handle is still live.
ReqLLM closes that handle after materialization. A unique reference holds the
final two fallback maps only until source selection. An `after` clause removes
that temporary entry on success, returned failure or an uncaught throw.
Interrupted enumeration does not await unfinished stream metadata.

## Evidence and limits

All 12 new [boundary tests](../../test/jido_ai/usage/stream_test.exs) pass.
They use pure source maps and actual ReqLLM materialization of decoded chunks.
They do not replace provider transport. Cases cover source priority, missing
sources, numeric strings without a total, explicit zero, sparse maps, shallow
metadata replacement, independent maxima, returned errors, callback exceptions,
uncaught throws and consecutive calls in one process.

The original root test `propagates usage from streaming meta chunks into request
completion` remains unchanged. It now passes through the native runner. All
58 original runner names remain, plus the separate HTTP credential case from
the prior pass. No old test was removed, merged or skipped. The full root
comparison resolves that one case and introduces no new failing root case.

[02_24](../../examples/02_requests/02_24_stream_usage/README.md) adds eight required
HTTP/SSE cases. Four pass and four expose a ReqLLM defect. A passing decoded
boundary case is not counted as proof of a failing provider-wire case.

The current OpenAI decoder requires prompt, completion and total fields. When
the total field is missing, it emits a nonempty zero map. With all three fields
present as numeric strings, it preserves strings. The stream server then calls
`ReqLLM.Usage.merge/2` through its chunk accumulator. `recompute_totals/1` adds
`"3" + "1"` and raises before the AI consumer can normalize those values.
The new real HTTP cases prove this failure with both native and standalone
requests, with delta capture enabled and disabled.

ReqLLM 1.22.0 remains the latest release shown on the
[upstream release page](https://github.com/agentjido/req_llm/releases)
when checked on 2026-09-07. No dependency files, provider code or dependency
requirements were changed in this pass. No upstream message was sent.
The dependency repair must normalize supported counters before stream-server
arithmetic and preserve source availability, explicit zero and supplied totals.
Do not discard these cases or replace their string values with integers to
obtain a passing suite. Incomplete provider maps need a separate decoder check.

The original AWS credential test remains required and failing. Other root
migration failures, the dependency gate and all release gates remain open.
The immutable API baseline and history source-review fields are unchanged.
No history row was closed.

## Runs

- Initial new boundary run: 0/11 passed; the shared adapter was absent.
- Initial native example command used the wrong Mix directory and ran no tests.
- First actual example run: 2/8 passed; four cases had a missing request source.
- Corrected example run before the port: 4/8 passed; the four remaining failures
  are the numeric-string SDK defect.
- Combined boundary, Usage and runner check: 51/78 passed in 7.4 seconds.
  All 12 new boundary cases and the original usage regression pass. The 27
  remaining runner failures were already required migration work.
- Complete root run: 1,961/2,409 passed in 27.1 seconds, with 448 failures and one
  existing exclusion. All four doctests pass.

Logs: `/tmp/jido-ai-v3-usage-source-root-*.log`,
`/tmp/jido-ai-v3-usage-examples-*.log`, and `/tmp/jido-ai-v3-root-test-27.log`.
Failure inventory: `/tmp/jido-ai-v3-root-checkpoint-07-failures.json`.

The complete example run passes 1,143/1,147 cases in 145.5 seconds, with four
failures and no exclusions. The only failures are the four new numeric-string
cases in 02_24. All prior 1,139 cases still pass. Integration and pending-DSL
tags are included. Log: `/tmp/jido-ai-v3-acceptance-usage-source.log`.
The full forced compile passes for 230 production files.
