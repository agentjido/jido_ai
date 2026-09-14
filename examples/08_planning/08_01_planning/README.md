# 08_01 — Planning Actions and capability

[Agent examples](agent.ex) and
[example tests](../../../test/examples/08_planning/08_01_planning/08_01_planning_test.exs) use the
production Plan, Decompose and Prioritize Actions on v3. Each Action runs through
a direct `run/2`, core Exec, and a live Agent capability route. All use the same
HTTP mock implementation and shared provider boundary.

```sh
mix test test/examples/08_planning/08_01_planning/08_01_planning_test.exs --include example --seed 0
mix test test/jido_ai/skills/planning --seed 0
```

Eighteen example cases and twelve native API/Plugin cases cover this port.
Integration cases are excluded by default. They are only evidence when run with
`--include example`.

## Existing results

| Action | Retained behavior |
| --- | --- |
| `Plan` | Goal, constraints, resources and requested step count enter the original prompt. The result keeps full `plan` text, parsed `steps`, goal, resolved model input and usage. |
| `Decompose` | Goal and context enter the original prompt. Requested depth is clamped to 1–5 before generation. The result keeps full `decomposition` text, parsed two-level `sub_goals`, goal, effective depth, model and usage. |
| `Prioritize` | Tasks, criteria and context enter the original prompt. The result keeps full `prioritization` text, recommended `ordered_tasks`, `scores`, model and usage. |

These are text-generation Actions with parsed result maps. Unstructured output
keeps its original text and returns empty parser results. `max_steps` is prompt
guidance; it does not validate or enforce the number of returned steps. These
Actions do not execute generated tasks. Catalog 08 still needs its validated
plan-to-Flow example, bounded execution and repair.

The priority parser retains plain, parenthesized and range score forms. A new
wire test found that trailing empty regex captures caused the latter forms to
be lost. The parser now reads the first populated score capture. Range scores
retain the lower bound, as in the original parser. Multi-block provider content
uses the existing Turn text extractor. Usage remains the three token counters;
provider blocks, usage and custom headers are checked at the HTTP boundary.

## One request preparation path

The three Actions retain their public names, schemas, category, tags and version.
Their sources moved from `actions/planning` to `operations/planning`. The common
request helper replaces repeated model/default/provider preparation. Prompts
and method parsers remain in their Actions. No alternate model transport is
present; requests pass through `Jido.AI.Runtime.ModelCall.request/5`.

Action defaults remain 4,096 tokens, with temperatures 0.7 for Plan, 0.6 for
Decompose and 0.5 for Prioritize. The Planning Plugin keeps its shared 0.7
temperature default. Explicit parameters take precedence. Trusted caller model
and generation defaults take precedence over Plugin defaults. An omitted model
uses `:planning`; all model inputs supported by the shared model resolver work.

The core pre-validation callback records which keys were supplied before Zoi
adds defaults. An explicit value equal to a schema default remains explicit.
The callback replaces a caller-supplied marker. Known string keys use the common
schema input normalizer. Existing `provided_params` context remains supported.
The internal marker is removed before generation. It is not a provider option.

Provider settings come from trusted `context.model_options`. Action generation
parameters override the corresponding top-level options. `timeout` maps to
ReqLLM `receive_timeout`. A test holds the real provider connection and confirms
that this timeout fires before the outer Exec deadline. Nested transport
options retain ReqLLM's own precedence. Exec cancellation closes active work.
Invalid goals, task inputs, model aliases and malformed defaults fail before a
provider request. Direct Prioritize calls retain their three task-input errors.

Defaults can still come from `plugin_state.planning`, `state.planning`, or a
current Agent struct under `context.agent`. Map-safe access replaces the old
Access call on a struct. A matching RunStrategy regression fixed the same
boundary in callable reasoning.

## Agent declaration

```elixir
use Jido.Agent, name: "planning_case"

agent do
  schema Zoi.object(%{
    result: Zoi.any() |> Zoi.default(nil),
    case_id: Zoi.string() |> Zoi.default("release-17")
  })

  plugin Jido.AI.Plugins.Planning,
    config: [into: :result, default_max_tokens: 512]
end

routes do
  route "planning.plan", Jido.AI.Actions.Planning.RunCapability
  route "planning.decompose", Jido.AI.Actions.Planning.RunCapability
  route "planning.prioritize", Jido.AI.Actions.Planning.RunCapability
end
```

The Plugin owns its `:planning` defaults. Core creation and an empty restored
state use the declared values. `into` must name a domain field, not Plugin state.
The Plugin binds the Action from the fixed Signal name. Caller action/result
field input and private context cannot change that binding. The source-map
`signal_routes/1` helper returns the three explicit routes to `RunCapability`.

The same candidate helper serves reasoning and Planning capabilities. It calls
the selected Action with core Exec and returns the whole Agent state. Only the
selected result field changes. The example combines Planning, reasoning and an
ordinary route on one Agent. Provider failure preserves previously committed
results and Plugin state. It cannot undo a completed provider request.

## Public API

The three Actions keep their public result maps and catalog accessors. The
Planning Plugin provides its schema, state key, Signal patterns, and route
helper. Use keyword options in the core Plugin declaration. Supported options
are `default_model`, `default_max_tokens`, `default_temperature`, and `into`.
Core initializes Plugin state from `state_spec/1`. Declare routes directly, or
use `signal_routes/1` in source attributes. `RunCapability` performs domain
projection. Direct Action use retains the result map.

This example does not execute or repair generated plans and does not cover
durable recovery.
