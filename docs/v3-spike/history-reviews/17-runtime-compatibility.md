# History review 17: runtime compatibility and clause order

Reviewed on 2026-09-06 against `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
This pass completes one more source review. The total is 91 of 126.
All v3 port evidence remains pending.

Read the complete 477-line diff for `e2b2d275`, including the lockfile and both
workflows. The commit has no associated merged PR and adds no tests. Inspect
its production changes as behavior, not just compiler maintenance. No runtime
tests were run in this pass.

## Error and authoring behavior

The commit moves specific clauses before broader matches. This changes results
for inputs which the broader clause previously captured:

- `Error.normalize({:error, reason}, ...)` unwraps the reason before the generic
  `{type, message}` clause. A binary reason now uses the caller's fallback type
  instead of inventing an `:error` type from the wrapper.
- `{:unknown_tool, message}` takes the explicit non-retryable path. Other typed
  message tuples retain their type-based retry decision.
- A nil message in a typed envelope becomes `"Execution failed"`, rather than
  the atom string `"nil"`.
- Observation summaries recognize an exception before treating it as an ordinary
  map. They use its module label and bounded `Exception.message/1`.
- Literal-option validation reports module attributes and pinned variables with
  their specific compile errors before the broad local-function-call clause.

Retain these distinctions in the common error and authoring layers. Test both
the public result and the provider-visible tool response. A compile result alone
does not establish error classification, retry decisions or user diagnostics.
Keep the existing distinction between accepted prompt module attributes and
the stricter literal tool-context rules. If v3 accepts a wider trusted source
form, define that as an explicit authoring change. Imported data remains inert.

The deleted map/struct AST branches were already covered by the preceding tuple
branch. Literal maps and structs must still work. Likewise, map error details
already take `merge_error_details`' map clause before its fallback normalizer.
Do not interpret the removed private map clause as a new nested-details format.

## Repeated tools and stored state

The runner now uses a declared `prev_tool_signature` field instead of adding
`__prev_tool_signature__` to the state map. State creation clears it; `to_map`
and `from_map` retain it, including the string-keyed form on input.

The final signature sorts strings derived from tool names and inspected arguments.
It does not use tool-call IDs or compare tool results. It warns after a repeated
tool round succeeds. The tools have already run twice. Thus, it is guidance to
the model, not duplicate-side-effect prevention or an execution cache.

Extend the ordinary tool-loop example with a real counter Action. Let the mock
request the same name and arguments twice, with distinct IDs. Check two real
executions and two distinct counter results. The next model request must contain
the repeat guidance, then the mock supplies a final answer. Repeat with reordered
calls in a batch, changed arguments, a failed round and a fresh request. Preserve
normal tool-call/result pairing and configured iteration limits.

Use the canonical tool-call form from actual ReqLLM decoding. The signature
helper reads atom keys despite a comment that mentions both key forms. Do not
assume a private helper accepts raw provider JSON; prove normalization at the
boundary. Stored signature conversion and a fresh request reset need separate
tests. Portable data is not proof that live Exec state can resume.

## Reasoning dispatch and removed private clauses

| Change | Final behavior to preserve |
| --- | --- |
| CoT `from_map` checks nil before atoms | Missing/nil atom-key status becomes `"idle"`, rather than `"nil"`. Known atom and string status values still convert. The helper does not itself normalize all string-keyed maps. |
| Adaptive replaces a map lookup with seven function clauses | CoD, CoT, ReAct, AoT, ToT, GoT and TRM remain selectable. Unknown override atoms have no matching clause. Validate configuration before dispatch in v3; do not expose a private function-clause failure as normal input handling. |
| AoT removes a nil machine-update clause | The caller already filters nil messages. Unknown instructions still follow ordinary Action handling; invalid result IDs keep their guard. |
| ToT removes a generic LLM-result conversion clause | LLM results already use dedicated tool-aware processing. Preserve tool-round handling, call-ID correlation and partial messages. |
| TRM removes a default phase branch | `resolve_result_phase` already normalizes to reasoning, supervision or improvement, with reasoning as fallback. Preserve explicit metadata and status precedence. |
| RunStrategy removes an `already_started` branch | Both inspected v2 and local v3 `Jido.start/1` convert it to `{:ok, pid}`. Repeated independent RunStrategy calls must work with one runtime and clean up their own Agent work. |
| ListTools, Query, Turn and ReAct remove private fallback clauses | Their callers establish list or Agent-map input first. Preserve schema formats, uploaded-file references, text/iodata handling and default active context through those public boundaries. |
| CLI removes an unused Logger requirement | Retain the accepted CLI behavior. No new logging feature or example is implied. |

Adaptive's known-method clauses do not constitute input validation. Test invalid
and empty available-method sets as well as overrides. Current tests cover known
selection and fallback, but the inspected selection path can pass an arbitrary
override atom to dispatch. This is a source finding, not a runtime reproduction.

## Required acceptance variants

These cases extend existing catalog families and remain pending.

| Variant | Required evidence |
| --- | --- |
| `HIST-14/clause-order` | A real tool returns nested `{:error, reason}`, typed binary-message errors, unknown-tool errors, nil messages and map details. Assert canonical type/message/details/retry fields, public errors and next-model tool content. Check extra-detail precedence and JSON conversion. |
| `HIST-13/exception-summary` | A real failing Action emits an observation with an exception. Check the module label, actual bounded exception message, redaction and absence of raw handles/stacktrace in model-facing output. Use an exception whose message comes from its fields, not only a plain message map. |
| `HIST-02/literal-diagnostics` | Compile valid nested literal maps, structs, lists and aliases. Check attribute, pinned-variable and call errors with useful locations. Compare accepted source/data forms after lowering and preserve the separate prompt-attribute contract. |
| `HIST-20/repeated-tool-state` | Run the counter loop through the shared mock and real Actions. Check repeat guidance after execution, changed/batch arguments, failure, fresh-request reset and supported stored-field conversion. Do not claim exactly-once tool execution or durable runtime resume. |
| `HIST-20/method-dispatch` | Convert missing/nil/known CoT status and run each Adaptive method through actual Agent/Flow requests. Validate unknown overrides and invalid available sets. Preserve AoT guards, ToT tool-aware result handling and TRM phase precedence under success and failure. |
| `RELEASE/runtime-harness` | Reuse one complete runtime for repeated RunStrategy calls, with real mocked model transport, distinct Agent/request ownership and cleanup. No removed fallback clause can be the only protection against a reachable invalid public input. |

## Runtime and dependency gate

The commit explicitly sets quality and release jobs to OTP 29/Elixir 1.20.
Its test matrix is OTP 27/Elixir 1.18, OTP 28/Elixir 1.18, OTP 28/Elixir 1.19
and OTP 29/Elixir 1.20. The final callers retain these inputs. This does not
change the package's declared `~> 1.18` floor.

Keep the existing `RELEASE/runtime-matrix`, `RELEASE/workflow-contract` and
`RELEASE/release-simulation` requirements from [review 06](06-release-and-documentation.md).
The earlier isolated acceptance run on Elixir 1.20.3/OTP 29 is not full package
proof, and it does not test the supported floor.

The lock changes include Jido 2.3.0 to 2.3.2, Action 2.3.0 to 2.3.1, Signal
2.2.0 to 2.2.2, Req 0.5.18 to 0.6.1, ReqLLM 1.14.0 to 1.16.0 and LLMDB
2026.5.2 to 2026.6.1. Tooling/parser dependencies also change. Ten former
transitive entries disappear, including Lua/Luerl, Memento, Msgpax, PubSub,
Uniq and DeepMerge. Several dependency edges become optional.

For `RELEASE/dependency-runtime`, build a fresh consumer from the final v3
package declarations and lock resolution. Check that required provider, schema,
catalog, parser and runtime modules load without accidental transitive installs.
Retest the existing operation, file, schema and reasoning cases against that
resolved set. Preserve capabilities, not obsolete dependency versions or removed
transitive packages. A local workspace dependency graph cannot close this gate.

The runtime simplification pass must check assumptions before it removes code:
which boundary validates a value, which branch handles it, and which example
proves the behavior. Keep one error conversion and declared state shape. Do not
recreate the old Strategy runtime to preserve its private helper functions.

Source: [commit](https://github.com/agentjido/jido_ai/commit/e2b2d275ccdb3d3b1bf8cfcae106e13776475e39),
[Agent authoring](../../../lib/jido_ai/agent/definition.ex),
[errors](../../../lib/jido_ai/error.ex),
[observation](../../../lib/jido_ai/observe/sanitize.ex),
[runner](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/react/runner.ex),
[state](../../../lib/jido_ai/reasoning/react/state.ex),
[Adaptive](../../../lib/jido_ai/reasoning/adaptive/strategy.ex), and
[RunStrategy](../../../lib/jido_ai/operations/run_strategy.ex).
Tests: [Agent](../../../test/jido_ai/agent_test.exs),
[errors](../../../test/jido_ai/error/model_test.exs),
[observation](../../../test/jido_ai/observe_test.exs),
[runtime](../../../test/jido_ai/react/runtime_runner_test.exs),
[CoT conversion](../../../test/jido_ai/chain_of_thought/machine_test.exs), and
[Adaptive](../../../test/jido_ai/strategy/adaptive_test.exs).

## Native Adaptive evidence: 2026-09-07

The [09_10 profile](../../../examples/09_reasoning/09_10_adaptive/README.md) now proves
all seven methods through actual Agent/Flow calls. It checks invalid or empty
available sets, unknown or unavailable overrides, thresholds and method options
before provider work. ReAct and ToT run actual tools. TRM failure retains its
phase data and cause. An ordinary core Action also runs while AI work is active.
Sixteen retained pure-selection tests pass against the extracted selector.

This gives partial evidence for `HIST-20/method-dispatch`. It does not close
legacy command/phase conversion, CoT status conversion, the other acceptance
variants above or the runtime matrix. The public Adaptive API still needs its
own port and examples. All history statuses remain pending.

The [public 09_11 cases](../../../examples/09_reasoning/09_11_adaptive_api/README.md)
also execute each method through AdaptiveAgent and reject invalid settings at
authoring. Deprecated Strategy analysis and getters remain loadable; its old
execution callbacks are removed. This does not close old phase-input/state
conversion, active inspection, per-method default controls or the runtime gate.

## Callable runtime evidence: 2026-09-07

[09_14](../../../examples/09_reasoning/09_14_callable_reasoning/README.md) proves the
RunStrategy runtime cases with actual mock transport. Calls can share an existing
host runtime while they retain distinct linked Agents and request/run IDs. A
standalone call needs no implicit named instance. This replaces the old global
`Jido.start/1` path, whose first caller could also own the runtime's lifetime.
Cancellation closes the private Agent, Session and provider. Runtime-floor and
full package checks remain open.
