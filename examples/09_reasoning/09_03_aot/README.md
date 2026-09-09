# 09_03 — Algorithm of Thoughts through the shared Flow

[Agent example](agent.ex) ·
[Example tests](../../../test/examples/09_reasoning/09_03_aot/09_03_aot_test.exs) ·
[Default lifecycle case](../../../test/examples/09_reasoning/09_03_aot/aot_lifecycle_test.exs)

AoT retains its current algorithm: one model generation with search examples
in its prompt, followed by parsing into the AoT result map. It does not perform
host-side DFS or BFS. The search-style setting selects the prompt preference.
All model execution uses the existing Prepare, CallModel and Decide Flow.
Agent, Session, controls, events and result commits keep their existing owners.

```elixir
ai :assistant do
  models do
    model(:answer, "openai:gpt-4o-mini", generation: [temperature: 0.0, max_tokens: 2048])
  end

  reasoning :algorithm_of_thoughts do
    model(:answer)
    options(profile: :short, search_style: :dfs, require_explicit_answer: true)
  end

  requests do
    mode(:session)
    streaming(true)
  end

  result(nil, into: :reply)
end
```

Use a declared domain field for `:reply` and an ordinary route to
`ai(:assistant)`, as in the executable example. DSL, data, Builder and source
JSON run the same profile and Flow. Direct Flow and ordinary Agent calls also
keep the full result map.

## Settings and result contract

| Method option | Default | Allowed values |
| --- | --- | --- |
| `profile` | `:standard` | `:short`, `:standard`, `:long` |
| `search_style` | `:dfs` | `:dfs`, `:bfs` |
| `examples` | `[]` | List of text examples; trim blanks; empty selects the profile examples |
| `require_explicit_answer` | `true` | Boolean |

`reasoning.options` accepts a map or a keyword list with unique keys. Unknown
settings and invalid values fail before model work. Temperature and token
limits belong to the named model's generation options. AoT supplies 0.0 and
2048 when those options are omitted. Explicit profile, request and transport
settings use common precedence. Total request duration has the shared
60-second default and can be set through `controls.timeout`.

The prompt examples, search-style text and user framing remain exact. Native
instructions can replace the method system prompt. The original user query
remains in the request record. Multimodal queries retain their ordered parts
after a text part that supplies the AoT framing. Declared tools and steering
are invalid for this method. An unsolicited provider tool call fails without
execution or a second model call.

An ordinary successful result keeps these fields:

```elixir
%{
  answer: "(4 + (8 - 6)) * 4 = 24",
  found_solution?: true,
  first_operations_considered: 1,
  backtracking_steps: 3,
  raw_response: response_text,
  usage: measured_usage,
  termination: %{reason: :success, status: :completed, duration_ms: elapsed},
  diagnostics: parser_details
}
```

The result, request record, output control and final typed Signal contain that
map. `found it` without an explicit answer fails with
`:missing_explicit_answer` when an answer is required. No solution markers
produce `:no_solution`. When an explicit answer is optional, a found marker
can succeed with a nil answer. The parser does not invent answer text.

Search failures use `{:error, {:failed, reason, result}}`. Provider and output
control failures keep the AoT result envelope with `:error` termination.
`diagnostics.error` retains display text and the new `diagnostics.cause` keeps
the structured cause. The session owner supplies measured usage in the failure
result from its existing accounting. Caller wait timeout, cancellation, owner
loss and outer execution/commit failures still use the shared request errors;
they are not all converted into a parsed AoT result.

Empty normal output is `:no_solution`. Empty truncated output fails with its
incomplete-response cause. A nonempty partial response with a valid answer can
finish after the provider's token limit, preserving the accepted partial-content
rule. Failed transport does not become a successful partial answer. This example
does not yet prove retention of every partial delta in a transport-error result.

## Typed answers and repair

For AoT, `result` schema validates the **answer field**, while `into` selects the
domain field for the **whole AoT result map**. The model produces search text
and a final answer line containing JSON. It is not placed in provider object
mode. Shared Output validation parses that JSON into the declared value.
The complete result retains search metrics and contains the validated answer.
Output controls see that complete result.

A request transformer keeps this method rule. It can refresh model request
options on both the initial and repair calls, but does not cause a typed AoT
answer to select provider object mode. The example changes a request header on
each call and verifies the actual wire format and committed full result.

Invalid typed answers can use the existing bounded repair model call or a
configured repair callback. Usage includes real calls, not callbacks. A callback
returns the typed answer directly; diagnostics record `:repair_callback` rather
than invented search metrics. Exhaustion fails and preserves domain state.
Missing explicit method answers are method failures, not automatic schema-repair
requests. The `require_explicit_answer` setting still applies.

## Public API and retained data

`use Jido.AI.AoTAgent` retains explore/explore_sync/await, strategy_opts and
answer helpers through the common Agent macro. It keeps `ai.aot.query`,
`ai.aot.cancel`, last_prompt, last_result and completed. Per-request history is
fresh by default. A later request starts after success, failure or cancellation.
`strategy_opts/0` reports normalized method settings and declared model options;
wire overrides still follow the common precedence. `answer/1` also returns a
new typed answer when a result schema is declared.

The public wrapper retains legacy string conversion and blank filtering for
example values. Nonnumeric public temperature values use 0.0, as before. The
native method profile requires text examples. This conversion stays at the
compatibility boundary.

Use `AlgorithmOfThoughts.method/0` for profile selection and `get_result/1,2`
for committed result inspection. The namespace prompt and call-ID helpers
remain. `strategy_module/0` returns a loadable deprecated result adapter. That
adapter retains get_result only. Replace old init/cmd/snapshot callbacks,
action atoms and Strategy routes with ordinary Agent/Flow/Session APIs.

Machine and Result now compile from `shared`. Seven retained Machine tests run
unchanged. Direct finite transitions replace Fsmx. Busy rejection, stale-call
checks, parsing, result maps and internal-string/external-atom statuses remain.
Missing status now restores to idle instead of the erroneous string `"nil"`.
The Machine's usage projection uses the shared helper to retain provider data.
Its map conversion does not validate a versioned v2 checkpoint.

## Observation and evidence

Canonical events, typed Signals and telemetry use the actual AoT method.
Telemetry and Signal flags are separate. Known structured control error types
survive the AoT failure envelope. Cancellation retains its reason, closes work
and uses the cancellation event. Owner loss interrupts the old request and
permits a new request without replaying old work.

The existing Session event owner now measures live request duration with its
monotonic clock for success, failure and cancellation. It no longer supplies
a zero placeholder for those events. The measurement starts at canonical
request start and includes time until terminal publication. Ordinary output
telemetry has `:agent_turn` origin; session telemetry has `:worker_runtime`
origin. These values describe the actual execution paths.

There are 25 example cases, excluded by default. The port of the
historical AoT lifecycle case remains in the default suite, as required by
PRs 231 and 309. It uses the same mock server and real Agent/Flow execution,
checks the original puzzle answer, and compares Signal/telemetry request IDs
and measured usage. A held provider makes its nonzero duration check explicit.
The old root mixed-method test file still awaits the full suite transfer.

```sh
mix test test/examples/09_reasoning/09_03_aot/aot_lifecycle_test.exs --include example
mix test --include example test/examples/09_reasoning/09_03_aot/09_03_aot_test.exs
mix test test/jido_ai/algorithm_of_thoughts/machine_test.exs
```

CLI and capability entry points, every old callback shape, complete partial
transport capture, generated media output, v2 state conversion and root package
and runtime-floor checks remain open. This is not a complete package migration.
