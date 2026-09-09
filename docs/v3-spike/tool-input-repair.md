# Tool input and error repair — 2026-09-07

The root suite found two shared regressions after the core dependency cutover.
Tool input normalization retained numeric strings, so valid tool calls failed
before execution. Core Exec now catches Action exceptions. The AI adapter no
longer received a raised exception and therefore omitted the server log.

`SchemaInput.normalize_tool/2` now adds numeric conversion at the AI tool
boundary. Both direct Turn execution and Session catalog admission use it.
Core Action and Flow validation still decide whether the normalized value is
valid. This does not change strict `SchemaInput.normalize/2`, typed Signals or
request validation. Numeric strings must parse completely. Invalid values remain
unchanged for validation. Unknown keys do not create atoms. The adapter does not
enable broad scalar coercion, alter defaults, or bypass validation.

The shared ToolResult adapter now logs an Action exception caught by core Exec.
It uses the exception type in the log message, with the native details in log
metadata. The public error adapter still removes the stacktrace. Ordinary
returned errors do not acquire an exception log. Core Exec still owns execution
and timeouts; no second task runner was added.

## Retained behavior

All 32 original direct tool tests remain, with the same names and assertions.
Eight additional cases test nested numbers, invalid integers, unknown keys,
atom-key precedence and strict non-tool input. The complete file has 40 passes.
No tests were removed, merged, skipped or weakened in this pass.

| Root file | Existing failures fixed | Behavior |
| --- | ---: | --- |
| [executor_test.exs](../../test/jido_ai/executor_test.exs) | 13 | String numbers, typed floats, real Action results and errors, direct execution, timeout type and telemetry, server exception log |
| [tools_phase2_test.exs](../../test/jido_ai/integration/tools_phase2_test.exs) | 7 | Registry execution, multiple Actions, numeric input, timeout, complete tool turns, sequential state and error propagation |

The failure inventory changed from 482 to 462. Every removed failure entry is
in these two files. There are no new failing cases. The root count increases
from 2,388 to 2,396 because of the eight added cases. The final root result is
1,934 passed, 462 failed and one existing exclusion. All four doctests pass.

The [03_03 integration example](../../examples/03_tools/03_03_numeric_inputs/README.md)
adds four cases with a native Agent DSL, the shared mocked LLM, and actual Action
and Flow tools. It checks nested values, real execution, correlated model input,
stored results and all-or-nothing batch admission. The first run reached every
behavior assertion but used incorrect terminal phase labels. The test now uses
the public Session labels `:request_completed` and `:request_failed`. All four
cases pass. The production phase contract was unchanged.

This pass does not close a release-history row or change the immutable API
inventory. Direct Action helper options and context, removed Strategy and Plugin
callers, standalone runtime, state conversion and final package gates remain
required work. See the [current checkpoint](root-package-checkpoint.md).

Logs: `/tmp/jido-ai-v3-tool-input-test-03.log`,
`/tmp/jido-ai-v3-tool-input-examples-02.log`, and
`/tmp/jido-ai-v3-root-test-23.log`.
The failure inventory is `/tmp/jido-ai-v3-root-checkpoint-05-failures.json`.
