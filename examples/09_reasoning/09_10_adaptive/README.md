# Adaptive selection through the shared Flow

The [Agent example](agent.ex) and
[22 example cases](../../../test/examples/09_reasoning/09_10_adaptive/09_10_adaptive_test.exs)
select and run all seven existing methods. Selection uses the existing keyword
and complexity rules. It does not call a model. The selected profile then runs
through the same Flow and Session as a fixed method.

```elixir
reasoning :adaptive do
  model(:answer)
  options(
    available_strategies: [:cod, :cot, :react, :aot, :tot, :got, :trm],
    complexity_thresholds: %{simple: 0.3, complex: 0.7},
    method_options: %{tot: %{branching_factor: 2, max_depth: 1}}
  )
end
```

Declare models, tools, controls, requests, result fields and routes as shown in
the example. The same definition works through DSL, source data, Builder and
registered source JSON. Direct Flow execution and ordinary Agent turns use the
same selector. Ordinary core Actions also remain available during a session:
the example closes a case while CoD is active and retains that domain change
when the AI result commits.

## Selection rules and settings

| Setting | Default | Rule |
| --- | --- | --- |
| `available_strategies` | `[:cod, :cot, :react, :tot, :got, :trm]` | Non-empty list of distinct known short names. Add `:aot` to enable it |
| `complexity_thresholds` | `%{simple: 0.3, complex: 0.7}` | Numbers from 0 to 1, with simple no greater than complex. Omitted keys retain defaults |
| `strategy_override` | `nil` | A known member of the available list. It wins over automatic selection |
| `method_options` | `%{}` | Map from short method names to their existing option maps or keyword lists |

The available names map to CoD, CoT, ReAct, AoT, ToT, GoT and TRM. Unknown
settings, invalid methods, empty/duplicate available sets, unavailable overrides
and invalid method options fail before model work. There is no recursive
Adaptive-in-Adaptive configuration.

The retained task precedence is iterative reasoning, synthesis, tool use,
exploration, simple query, then general. It uses substring matches. Iterative
tasks prefer TRM, then ToT. Synthesis prefers GoT, then ToT. Tool use prefers
ReAct. Exploration prefers AoT, ToT, then GoT. If task selection has no match,
the complexity score selects preferred available methods, then the first
available entry. Scores below the simple threshold prefer CoD/CoT; scores above
the complex threshold prefer AoT/ToT/GoT; the inclusive middle prefers ReAct.
Length, sentence structure, keywords and constraints contribute to the score.

The [selector](../../../lib/jido_ai/reasoning/adaptive/selection.ex) contains the
algorithm. Focused selector tests retain the rule checks. Executable profiles
reject an empty available-method list.

Each new request selects again. Repair and tool rounds keep that choice. An
override records score 0.5 and task type `:manual_override`. The common call,
iteration and time limits apply to the selected method. Method options do not
raise those shared limits. The example declares 20 calls and iterations; a full
five-cycle TRM request needs at least 15 of each.

## Tools, output and metadata

Selection runs before prompts, generation defaults, history and output are
prepared. The selected method receives its existing model role and method
options. ReAct and ToT can use the declared tools through core Exec. The other
methods receive an empty catalog. A request transformer cannot enable tools
for a method that does not execute them. The common tools check now enforces
that rule for fixed linear/AoT methods too.

Typed output follows the selected method's contract. CoD can return a validated
object. AoT validates a typed answer inside its result map and can repair it
through the same selected method. ToT, GoT and TRM retain their current native
typed-output rejection. That rejection occurs before model work; a later
request can select a method that accepts the same output schema. Rich query
selection and steering are rejected in this native slice.

Successful results keep the selected method's shape: text for linear, ReAct,
GoT and TRM, and the full AoT/ToT result maps. Existing method metadata remains
in place. `meta.adaptive` adds the short strategy name, full method name,
complexity score, task type and selection source (`:automatic` or `:override`).
For TRM, the returned text is the latest completed improvement. Its method
metadata still retains the highest reviewed answer.
Failures retain that selection in method details with the canonical cause and
available usage. Model-start observation also stores selection in the Session,
so cancellation can retain it before a successful result exists.

The outer request and canonical events keep `method: :adaptive`. Model, delta
and tool events identify the selected method in `data.selected_method`.
Signals and telemetry carry this value alongside the outer Adaptive identity.
Actual phase IDs and model-call IDs come from the selected method and common
runtime. Selection adds no provider usage or extra model call. This explicit
outer/selected distinction replaces reliance on an old delegated Strategy name.

## Recovery

The cases cover failure during selected TRM improvement, model limits, output
rejection, cancellation, a deadline, owner loss and a different later choice.
They verify provider cleanup, busy rejection, prior usage and domain commit
behavior. These are current interruption checks, not durable phase resumption.

Durable phase resumption is outside this example. Restore a V3 Session or start
a new request through the same Agent profile.
