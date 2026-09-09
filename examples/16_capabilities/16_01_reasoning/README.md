# 16_01 — Reasoning capability Plugins

[Agent examples](agent.ex) and
[example tests](../../../test/examples/16_capabilities/16_01_reasoning/16_01_reasoning_test.exs)
run the seven public reasoning Plugins on core v3. They use the shared HTTP/SSE
mock and the production `RunStrategy` Action from example 09_14.

```sh
mix test test/examples/16_capabilities/16_01_reasoning/16_01_reasoning_test.exs --include example --seed 0
mix test test/jido_ai/plugins/reasoning --seed 0
```

There are 17 example cases and 21 focused Plugin contract cases. Default
example runs exclude the example cases. Excluded cases are not passing
cases. The full root package still requires its dependency and API migration.

## Declaration

Use the existing core Plugin and route declarations. This adds no DSL keyword:

```elixir
use Jido.Agent, name: "case_reasoning"

agent do
  schema Zoi.object(%{
    result: Zoi.any() |> Zoi.default(nil),
    review: Zoi.any() |> Zoi.default(nil),
    case_id: Zoi.string() |> Zoi.default("case-17")
  })

  plugin Jido.AI.Plugins.Reasoning.ChainOfThought,
    config: [into: :result, timeout: 5_000]

  plugin Jido.AI.Plugins.Reasoning.ChainOfDraft,
    config: [into: :review, timeout: 5_000]
end

routes do
  route "reasoning.cot.run", Jido.AI.Actions.Reasoning.RunCapability
  route "reasoning.cod.run", Jido.AI.Actions.Reasoning.RunCapability
end
```

The example also puts a capability beside an `ai :assistant` profile in the
same Agent. The native profile and the callable capability both use the common
AI Profile, Session and Flow implementation. The callable request retains its
isolated request lifetime; it does not reuse the host's private AI bindings.

## Ownership and result

Each Plugin owns `:reasoning_<method>` with four fields: `strategy`,
`default_model`, `timeout`, and `options`. The method has one allowed value.
Creation and an empty restored state use the declared defaults. An ordinary
Action cannot change these fields. This does not convert a complete v2 Agent
snapshot or resume pending v2 work.

Options are a keyword list. Supported keys are `default_model`, `timeout`,
`options`, and `into`. Defaults remain `:reasoning`, `30_000`, `%{}`, and
`:result`. Invalid or duplicate declaration options fail core definition
validation. `into` must name a declared domain field; this is checked before
provider work. It cannot name a Plugin state key.

The adapter reads the declarations and committed Plugin state for each command.
It replaces caller-supplied private bindings, Plugin state, and supplied-key
metadata. Both Plugin orders are tested. Caller `strategy` and `into` values
cannot change the fixed method or result field. Explicit request model, timeout,
and method options retain `RunStrategy` precedence. Trusted caller defaults
remain supported by that Action.

`RunCapability` calls `RunStrategy` through core Exec and returns the complete
candidate Agent state. Only the selected result field changes. It contains the
existing `%{strategy, status, output, usage, diagnostics}` result envelope. AoT
and ToT retain their structured outputs. TRM returns its latest completed
improvement while its retained method data keeps the highest reviewed answer.
A failed run returns an error and
preserves prior domain and Plugin state. It does not undo provider work.
Timeout closes the provider work; the same host can run another request.

## Public API migration

| v2 surface | v3 surface |
| --- | --- |
| Plugin module names and seven `reasoning.<method>.run` Signals | Retained |
| `schema/0`, `state_key/0` and catalog name/description/category/tags/version | Retained; the existing metadata version remains `2.0.0` |
| `actions/0` | Retains the callable `RunStrategy` catalog entry |
| `signal_patterns/0` | Retained |
| `signal_routes/1` | Retained as an explicit source-map helper; targets `RunCapability` to return a complete state |
| A map in the Agent Plugin configuration | Use a keyword list in the core declaration |
| `plugin_spec/1` and generated v2 manifest | Use the core `{Plugin, keyword_options}` declaration |
| `mount/2` | Core initializes the schema from `state_spec/1` |
| `handle_signal/2` strategy override | Shared v3 preparation binds the capability; the route Action fixes its method |
| `transform_result/3` identity callback | No callback; the route Action returns the full candidate state |
| Implicit route installation | Declare the route, or append the `signal_routes/1` result to a source map |

`RunStrategy` remains the direct Action API. Routing it directly as a domain
Action requires the caller to assemble the complete state, as shown in 09_14.
Custom Signal aliases are not inferred by the capability adapter. The seven
fixed namespaces are retained. A route to `RunCapability` on an unrelated
Signal returns `:reasoning_capability_not_bound` when a reasoning Plugin is
present.

## Core error regression

Invalid configuration exposed a core defect: a caught `state_spec/1` exception
matched the generic `{state_key, schema_struct}` clause. Core then passed the
error struct to Zoi as a schema. Core now preserves exception error tuples first. A valid Plugin schema can
still use `:error` as its field name.
Tests cover raised, thrown, exited, and returned structured errors through the
public Agent constructor, plus the valid `:error` field. This changes error handling only; Plugin callback
order and state ownership stay with core.

## Scope still open

Chat, Planning, ModelRouting, Policy, Retrieval, Quota, PluginStack options and
full legacy default-Plugin conversion remain required. So do CLI use, nested
AI-tool budgets, complete method options and metadata, typed/rich method
variants, durable recovery, root dependency cutover, package and consumer checks,
minimum-runtime checks, and migration/rollback validation. The 126 history
statuses remain pending; these tests add partial evidence only.
