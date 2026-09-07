# Resolve method defaults at request start

The [Agent example](../lib/examples/09_reasoning/09_12_method_controls/agent.ex)
and [19 integration cases](../test/examples/09_reasoning/09_12_method_controls_test.exs)
preserve the selected method's default counts. Adaptive no longer gives ReAct
the larger ToT budget.

```elixir
controls do
  max_iterations :method_default
  max_model_calls :method_default
  max_tool_calls :method_default
  timeout 60_000
end
```

These are values of existing control fields. No extra Adaptive settings or
method executor are added. Fixed methods can also use these values. A profile
keeps the declared policy as static data. After request options and the output
contract are applied, the common Prepare step selects the method and resolves
the counts. The resulting Flow state has positive integer limits. Explicit
integer values remain exact.

The public Adaptive wrapper and common Agent Adaptive option use these defaults
unless the caller supplies counts. Other existing public wrappers keep their
current configured limits. Native profiles keep their existing integer defaults
unless the author uses `:method_default` explicitly.

| Selected method | Default iterations |
| --- | --- |
| CoD, CoT, AoT | 1 |
| ReAct | 10 |
| ToT | Two phases per node, with bounded tool follow-ups and parser repairs; 802 with default settings |
| GoT | Twice the node limit; 40 with default settings |
| TRM | Three calls per supervision step; 15 with default settings |

The shared method helper caps these derived bounds at 10,000. A default model
call limit is the resolved iteration count plus the output repair allowance.
The default tool count is 10,000 for ToT and 16 for other methods. A timeout
must remain a positive integer; it cannot use `:method_default`.

The actual public request test runs ten ReAct tool rounds, stops with the
existing public maximum-iteration text, then completes all fifteen TRM phases
on the same Agent. Native ReAct instead returns its existing control error at
that limit. Both stop before an eleventh provider call. Explicit Agent and
request limits allow a twelve-call ReAct request. The default ReAct tool count
rejects a batch of seventeen calls before any Action runs; explicit tool policy
permits the same batch.

Typed repair has an independent call allowance. Both an Adaptive typed CoD
request and a fixed native CoT request with a per-request output schema complete
after real validation failure and repair. Resolution occurs at runtime so an
output change cannot lose its repair allowance during static profile creation.

The same declared default policy passes through DSL, source data, Builder and
registered source JSON. Each form completes an actual fifteen-call TRM request.
Direct Flow execution and ordinary Agent turns do the same. Validation rejects
unknown markers, invalid counts and an automatic timeout.

This closes the larger-budget regression from the initial public Adaptive port.
Active selection inspection, old state/command conversion, runtime Agent-state
overrides, CLI/capability and skill paths, complete provider contracts, durable
recovery and root package/release gates remain open. Failed requests currently
retain usage without a top-level model_calls field in all cases; these tests
use actual mock request counts for those failures.

The [09_13 follow-up](09_13_active_selection.md) also restores committed active
Adaptive selection. The other open gates above remain required.
