# Public Adaptive Agent API

The [Agent examples](agent.ex)
and [22 example cases](../../../test/examples/09_reasoning/09_11_adaptive_api/09_11_adaptive_api_test.exs)
run the public Adaptive API through the common Agent, Flow and Session. They
use the same mock HTTP/SSE server as the native examples. The old Strategy
execution loop is removed.

```elixir
defmodule MyApp.Assistant do
  use Jido.AI.AdaptiveAgent,
    name: "assistant",
    model: :fast,
    available_strategies: [:cod, :cot, :react, :aot, :tot, :got, :trm],
    tools: [MyApp.Search],
    method_options: %{tot: %{max_depth: 2}, trm: %{max_supervision_steps: 3}},
    max_iterations: 50
end

{:ok, request} = MyApp.Assistant.ask(server, "Compare these options")
{:ok, result} = MyApp.Assistant.await(request)
```

The host supplies the model alias and Action. The executable examples use
test-owned values. The common `Jido.AI.Agent` also accepts `reasoning: :adaptive`
and the same settings under `reasoning_options`.

## Declared settings and limits

The wrapper retains `name`, the default description, `model: :fast`, optional
tools, available methods and optional thresholds. It adds the native
`strategy_override` and `method_options` settings. All native selection checks
apply at authoring time. Nested maps pass through quoted literal data into the
common lowerer. Invalid available sets, overrides, thresholds and method options
fail before any model call.

`strategy_opts/0` retains declared values. Optional thresholds and tools stay
absent when the caller omitted them. `default_strategy` stays in this inspection
list for compatibility. The old selector stored this field but never used it.
The v3 wrapper also leaves it without an execution effect. It is not a native
DSL option and does not need to be an available method. Use `strategy_override`
to force a choice. This explicit rule preserves the actual baseline behavior.

The wrapper now uses `:method_default` for omitted count limits. The
[09_12 refinement](../09_12_method_controls/README.md) resolves the selected method's
counts at request start. ReAct keeps ten calls while TRM can use fifteen and
ToT retains its bounded search allowance. Explicit integer controls still win.
Typed repair receives its separate call allowance after request output settings
are applied. This replaces the initial combined-budget rule.

The selected method supplies its generation defaults. ReAct uses 4096 tokens
and temperature 0.2. ToT, GoT and TRM use 1024 and 0.2. AoT uses 2048 and 0.0.
Linear methods keep provider defaults unless configured. Shared explicit model
options take precedence. A non-streaming example proves six TRM calls with
custom instructions, tokens and temperature.

## Requests, results and inspection

`ask/2,3`, `ask_sync/2,3` and `await/1,2` retain their public role. The Adaptive
ask functions keep binary prompt guards. `ask_stream/2,3` and `cancel/1,2` use
the common Agent APIs. Core construction uses `new/1` for `{:ok, agent}` and
`new!/1` for the value.

Each request selects again. All seven methods return their canonical result:
text for CoD, CoT, ReAct, GoT and TRM, and result maps for AoT and ToT. Typed
CoD answers remain objects in the request record. Typed AoT answers stay inside
the method result, including after bounded repair. Public `last_result` remains
a printable string. Non-text values use `inspect/1`. The canonical result is
not replaced with that string. A selected TRM run returns its latest completed
improvement and retains its highest reviewed answer for inspection.

Public failures keep their actual structured cause in the request record.
The compatibility field prints the method's failure result when supplied, or
the cause otherwise. The tests use an actual HTTP 503, an empty terminal
response and a failed TRM improvement. They preserve selected method metadata
and prove a later successful request. The HTTP case and non-text success cases
give partial evidence for PR 234. CLI output still needs its own port.

The namespace keeps `analyze_prompt/1,2` and adds the two former Strategy
getters: `get_selected_strategy/1,2` and `get_complexity_score/1,2`. An optional
request ID reads an older retained record. The deprecated Strategy module
delegates analysis and its two original one-argument getters to the namespace.
`strategy_module/0` still returns that loadable name. `method/0` returns
`:adaptive` for profile selection.

These getters now also read committed active selection, as proved by the
[09_13 cases](../09_13_active_selection/README.md). A new request starts without selection.
After input controls and method preparation, a progress Turn commits it before
the first provider call. Last-result and completed fields still remain pending.
Older records stay available by ID. Active method phase data remains separate
work.

## Tools, cancellation and runtime mapping

ReAct and ToT run the same real Action and public before/after callbacks.
The before callback restores argument types before validation. The after
callback changes the tool result visible to the next model call. Other selected
methods receive no tool catalog. There is no private Adaptive tool executor.

The stream retains outer `method: :adaptive`, actual selected-method phase
events and one terminal result. Cancellation closes active TRM transport,
keeps known selection and usage, rejects concurrent input and permits a later
CoD request. These cases use the inherited Session owner and cancellation route.

| Old execution surface | v3 mapping |
| --- | --- |
| Strategy `init`, `cmd`, `snapshot`, `action_spec`, `signal_routes` | Core Agent definition/routes, common Flow and Session; callbacks are removed |
| Start, LLM-result, partial and request-error action atoms | Public query/cancel routes and internal common runtime events |
| `on_before_cmd` and `on_after_cmd` request tracking | Session admission and settlement; custom hook conversion remains required |
| Mutable `__strategy__` execution state | Selected Flow method and canonical request metadata |
| Current selection getters | Committed active and retained request inspection |

Old worker/phase-input conversion, runtime model and selection overrides from
Agent state, active method phase data, CLI/capability entry points, skills/resources,
complete provider/media behavior and durable recovery still need examples and
their production port. The rejected-admission method-identity gap also remains
open. Root dependencies, package validation, consumer tests, minimum-runtime
checks, migration and rollback gates are unchanged.
