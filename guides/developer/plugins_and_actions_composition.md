# Plugins And Actions Composition

You need a reliable way to compose mountable capabilities (plugins) with executable primitives (actions) without coupling to strategy internals.

After this guide, you can choose the right extension surface for each requirement.

## Pick Your Extension Surface

Jido AI gives you three extension surfaces — **plugins**, **actions**, and **strategies**. Each solves a different problem. Start with the scenario that matches yours.

### Scenario A: You're building a reusable chat capability

You want any agent in your system to gain chat powers by adding one line to its plugin list.

**Reach for a Plugin.**

```elixir
defmodule MyApp.Assistant do
  use Jido.Agent,
    name: "assistant",
    plugins: [
      {Jido.AI.Plugins.Chat, %{default_model: :capable, auto_execute: true}}
    ]
end
```

Plugins give you lifecycle hooks (`mount/2`), capability-level defaults, and stable signal contracts (`chat.message`, `chat.simple`, etc.) that the rest of your app can rely on. When you need the same capability across many agents, plugins are the answer.

### Scenario B: You're adding LLM calls to a background job

You have an Oban worker or a one-off Mix task that needs to call an LLM. You don't need an agent, lifecycle hooks, or signal routing — you just need to run an action and get a result.

**Use an Action directly via `Jido.Exec`.**

```elixir
{:ok, result} =
  Jido.Exec.run(Jido.AI.Actions.Chat.SimpleChat, %{
    model: :fast,
    prompt: "Summarize this support ticket."
  })
```

Actions are the lowest-level primitive. They validate params, call the LLM, and return `{:ok, result}` or `{:error, reason}`. No plugin state, no agent process required.

### Scenario C: You want a custom multi-step reasoning approach

You need chain-of-thought, tree-of-thoughts, or your own bespoke reasoning loop that orchestrates multiple LLM calls with intermediate evaluation.

**Configure a Strategy (and optionally wrap it in a Reasoning plugin).**

```elixir
defmodule MyApp.Analyst do
  use Jido.AI.Agent,
    name: "analyst",
    strategy: {Jido.AI.Reasoning.ReAct.Strategy, [tools: [MyApp.Tools.Search], model: :reasoning]},
    plugins: [
      {Jido.AI.Plugins.Reasoning.ChainOfThought, %{default_model: :reasoning}}
    ]
end
```

Strategies own the multi-step execution loop. Reasoning plugins provide signal routing and defaults on top of strategies so you can trigger them via `reasoning.cot.run` and friends.

### Decision Table

| You need to…                                  | Use a…       | Example                                    |
| --------------------------------------------- | ------------ | ------------------------------------------ |
| Add a reusable capability to multiple agents   | **Plugin**   | `Jido.AI.Plugins.Chat`                     |
| Make a single LLM call in a script or job      | **Action**   | `Jido.Exec.run(SimpleChat, params)`        |
| Orchestrate multi-step reasoning               | **Strategy** | `Jido.AI.Reasoning.ReAct.Strategy`         |
| Expose a capability via stable signal contract | **Plugin**   | `chat.message`, `reasoning.cot.run`        |
| Compose actions without agent lifecycle        | **Action**   | Chain actions with `Jido.Exec`             |
| Customize reasoning defaults per agent         | **Plugin**   | `Jido.AI.Plugins.Reasoning.ChainOfThought` |

---

The rest of this guide covers the contracts and defaults for each surface.

## Public Plugin Surface (v3)

Public capability plugins:

- `Jido.AI.Plugins.Chat`
- `Jido.AI.Plugins.Planning`
- `Jido.AI.Plugins.Reasoning.ChainOfDraft`
- `Jido.AI.Plugins.Reasoning.ChainOfThought`
- `Jido.AI.Plugins.Reasoning.AlgorithmOfThoughts`
- `Jido.AI.Plugins.Reasoning.TreeOfThoughts`
- `Jido.AI.Plugins.Reasoning.GraphOfThoughts`
- `Jido.AI.Plugins.Reasoning.TRM`
- `Jido.AI.Plugins.Reasoning.Adaptive`

Internal runtime plugin:

- `Jido.AI.Plugins.TaskSupervisor` (infrastructure, not a public capability recommendation)

Removed public plugins:

- `Jido.AI.Plugins.LLM`
- `Jido.AI.Plugins.ToolCalling`
- `Jido.AI.Plugins.Reasoning`

## Compose In Agent Definition

```elixir
defmodule MyApp.Assistant do
  use Jido.Agent,
    name: "assistant",
    plugins: [
      {Jido.AI.Plugins.Chat, %{default_model: :capable, auto_execute: true}},
      {Jido.AI.Plugins.Planning, %{}},
      {Jido.AI.Plugins.Reasoning.ChainOfThought, %{default_model: :reasoning}}
    ]
end
```

## Plugin Signal Contracts

- `Jido.AI.Plugins.Chat`
  - `chat.message` -> tool-aware chat (`CallWithTools`) with auto-execute defaulting to `true`
  - `chat.simple` -> direct chat generation
  - `chat.complete` -> completion convenience path
  - `chat.embed` -> embedding generation
  - `chat.generate_object` -> schema-constrained structured output
  - `chat.execute_tool` -> direct tool execution by tool name
  - `chat.list_tools` -> tool inventory for the active chat capability
- `Jido.AI.Plugins.Planning`
  - `planning.plan` -> structured plan generation (`Jido.AI.Actions.Planning.Plan`)
  - `planning.decompose` -> goal decomposition (`Jido.AI.Actions.Planning.Decompose`)
  - `planning.prioritize` -> task ordering (`Jido.AI.Actions.Planning.Prioritize`)
- `Jido.AI.Plugins.Reasoning.*`
  - `reasoning.cod.run`
  - `reasoning.cot.run`
  - `reasoning.aot.run`
  - `reasoning.tot.run`
  - `reasoning.got.run`
  - `reasoning.trm.run`
  - `reasoning.adaptive.run`
  - All route to `Jido.AI.Actions.Reasoning.RunStrategy` with fixed strategy identity.

### TaskSupervisor Internal Runtime Contract

`Jido.AI.Plugins.TaskSupervisor` is internal runtime infrastructure enabled by
default via `Jido.AI.PluginStack.default_plugins/1`. It is not part of the
public capability plugin surface.

State key contract:

- Plugin state key is `:__task_supervisor_skill__`
- `mount/2` stores `%{supervisor: pid}` under `agent.state.__task_supervisor_skill__`
- Runtime directives resolve this supervisor via `Jido.AI.Directive.Helpers.get_task_supervisor/1`

Lifecycle and cleanup contract:

- `mount/2` starts an anonymous `Task.Supervisor` linked to the mounting agent process
- Each agent instance receives its own supervisor PID
- When the owning agent process terminates, the linked supervisor terminates automatically

### ModelRouting Runtime Contract

`Jido.AI.Plugins.ModelRouting` is a cross-cutting runtime plugin (enabled by
default in `Jido.AI.Agent`) that assigns model aliases by signal type when the
caller does not explicitly provide one.

Route precedence:

- Exact route keys win first (`"chat.simple"`)
- Wildcard route keys are fallback (`"reasoning.*.run"`)
- Explicit payload model (`:model` or `"model"`) bypasses plugin routing

Wildcard behavior:

- `*` matches exactly one dot-delimited segment
- `"reasoning.*.run"` matches `"reasoning.cot.run"`
- `"reasoning.*.run"` does not match `"reasoning.cot.worker.run"`

Production-style config shape (using `Jido.Agent` so you can mount/configure
this plugin directly):

```elixir
defmodule MyApp.RoutedAssistant do
  use Jido.Agent,
    name: "routed_assistant",
    strategy: {Jido.AI.Reasoning.ReAct.Strategy, [tools: [MyApp.Tools.Search], model: :fast]},
    plugins: [
      {Jido.AI.Plugins.ModelRouting,
       %{
         routes: %{
           "chat.message" => :capable,
           "chat.simple" => :fast,
           "chat.generate_object" => :thinking,
           "reasoning.*.run" => :reasoning
         }
       }}
    ]
end
```

If you are using `Jido.AI.Agent`, `ModelRouting` is already mounted by default.
Do not add a second `ModelRouting` plugin instance (duplicate state key). Use
`Jido.Agent` when you need custom `ModelRouting` plugin config.

### Policy Runtime Contract

`Jido.AI.Plugins.Policy` is a cross-cutting runtime plugin (enabled by default
in `Jido.AI.Agent`) that hardens request/query inputs and normalizes outbound
result/delta envelopes.

Enforce mode behavior:

- `mode: :enforce` rewrites violating request/query signals to `ai.request.error`
- `mode: :monitor` keeps request/query signals unchanged while still observing
- `block_on_validation_error: true` controls whether validation failures block

Rewrite semantics:

- Enforceable request/query signal types include `chat.*`, `ai.*.query`, and
  `reasoning.*.run`
- Prompt/query fields are validated via `Jido.AI.Validation.validate_prompt/1`
- Violations rewrite to `ai.request.error` with `reason: :policy_violation`

Normalization and sanitization:

- `ai.llm.response` and `ai.tool.result` normalize malformed `data.result` to
  `{:error, %{code: :malformed_result, ...}}`
- `ai.llm.delta` strips control bytes from `data.delta` and truncates to
  `max_delta_chars`

Policy hardening config shape (using `Jido.Agent` so you can mount/configure
this plugin directly):

```elixir
defmodule MyApp.PolicyHardenedAssistant do
  use Jido.Agent,
    name: "policy_hardened_assistant",
    strategy: {Jido.AI.Reasoning.ReAct.Strategy, [tools: [MyApp.Tools.Search], model: :fast]},
    plugins: [
      {Jido.AI.Plugins.Policy,
       %{
         mode: :enforce,
         block_on_validation_error: true,
         max_delta_chars: 2_000
       }}
    ]
end
```

If you are using `Jido.AI.Agent`, `Policy` is already mounted by default. Do
not add a second `Policy` plugin instance (duplicate state key). Use
`Jido.Agent` when you need custom `Policy` plugin config.

### Retrieval Runtime Contract

`Jido.AI.Plugins.Retrieval` is an optional cross-cutting runtime plugin that
enriches `chat.message` and `reasoning.*.run` prompts with in-process memory.

Retrieval enrichment lifecycle:

- Read mounted retrieval state (`enabled`, `namespace`, `top_k`, `max_snippet_chars`)
- Skip enrichment when plugin `enabled: false`
- Skip enrichment when payload sets `disable_retrieval: true`
- Resolve query text from `prompt` or `query`
- Recall top-k snippets from namespace memory
- Rewrite prompt with relevant memory block and attach `data.retrieval` metadata

Opt-out behavior:

- Global opt-out: mount plugin with `enabled: false`
- Per-request opt-out: set `disable_retrieval: true` in signal payload

Namespace behavior:

- `namespace` config is used for both enrichment and retrieval action routes
  (`retrieval.upsert`, `retrieval.recall`, `retrieval.clear`)
- If omitted, namespace falls back to agent id, then `"default"`

Retrieval action route contracts:

- `retrieval.upsert` -> `Jido.AI.Actions.Retrieval.UpsertMemory`
  - Required params: `text`
  - Optional params: `id`, `metadata`, `namespace`
  - Returns `%{retrieval: %{namespace, last_upsert}}`
- `retrieval.recall` -> `Jido.AI.Actions.Retrieval.RecallMemory`
  - Required params: `query`
  - Optional params: `top_k` (default `3`), `namespace`
  - Returns `%{retrieval: %{namespace, query, memories, count}}`
- `retrieval.clear` -> `Jido.AI.Actions.Retrieval.ClearMemory`
  - Required params: none
  - Optional params: `namespace`
  - Returns `%{retrieval: %{namespace, cleared}}`

Retrieval plugin config shape:

```elixir
defmodule MyApp.RetrievalEnabledAssistant do
  use Jido.AI.Agent,
    name: "retrieval_enabled_assistant",
    plugins: [
      {Jido.AI.Plugins.Retrieval,
       %{
         enabled: true,
         namespace: "weather_ops",
         top_k: 3,
         max_snippet_chars: 280
       }}
    ]
end

signal =
  Jido.Signal.new!(
    "chat.message",
    %{prompt: "Should I bike to work in Seattle tomorrow?", disable_retrieval: true},
    source: "/cli"
  )
```

### Quota Runtime Contract

`Jido.AI.Plugins.Quota` is an optional cross-cutting runtime plugin that
tracks rolling request/token usage and rejects over-budget requests.

Quota state keys:

- `enabled` toggles budget enforcement
- `scope` selects the quota namespace
- `window_ms` defines rolling budget window duration
- `max_requests` sets per-window request budget (`nil` disables request cap)
- `max_total_tokens` sets per-window token budget (`nil` disables token cap)
- `error_message` sets rejection message for blocked requests

Quota action route contracts:

- `quota.status` -> `Jido.AI.Actions.Quota.GetStatus`
  - Required params: none
  - Optional params: `scope`
  - Returns `%{quota: %{scope, window_ms, usage, limits, remaining, over_budget?}}`
- `quota.reset` -> `Jido.AI.Actions.Quota.Reset`
  - Required params: none
  - Optional params: `scope`
  - Returns `%{quota: %{scope, reset}}`

Scope resolution precedence for quota actions:

1. Explicit action param (`scope`)
2. `context[:plugin_state][:quota][:scope]`
3. `context[:state][:quota][:scope]`
4. `context[:agent][:id]`
5. `"default"`

`GetStatus` context defaults for limits/window:

- `window_ms`: `context[:plugin_state][:quota][:window_ms]` -> `context[:state][:quota][:window_ms]` -> `60_000`
- `max_requests`: `context[:plugin_state][:quota][:max_requests]` -> `context[:state][:quota][:max_requests]` -> `nil`
- `max_total_tokens`: `context[:plugin_state][:quota][:max_total_tokens]` -> `context[:state][:quota][:max_total_tokens]` -> `nil`

Usage accounting contract:

- `ai.usage` increments counters for `requests` and `total_tokens`
- `total_tokens` is preferred, with fallback to `input_tokens + output_tokens`
- Quota status snapshots expose `usage`, `limits`, `remaining`, and `over_budget?`

Budget rejection contract:

- Budgeted signal types include `chat.*`, `ai.*.query`, and `reasoning.*.run`
- When quota is exceeded, requests rewrite to `ai.request.error`
- Rejection payload uses `reason: :quota_exceeded`
- `request_id` is resolved from request correlation fields when present

Quota plugin config shape:

```elixir
defmodule MyApp.QuotaGuardedAssistant do
  use Jido.AI.Agent,
    name: "quota_guarded_assistant",
    plugins: [
      {Jido.AI.Plugins.Quota,
       %{
         enabled: true,
         scope: "assistant_ops",
         window_ms: 60_000,
         max_requests: 50,
         max_total_tokens: 20_000,
         error_message: "quota exceeded for current window"
       }}
    ]
end

signal =
  Jido.Signal.new!(
    "chat.message",
    %{prompt: "Summarize this report in one paragraph.", call_id: "req_123"},
    source: "/cli"
  )

# Expected rewrite shape when over budget:
# %Jido.Signal{
#   type: "ai.request.error",
#   data: %{
#     request_id: "req_123",
#     reason: :quota_exceeded,
#     message: "quota exceeded for current window"
#   }
# }
```

### CoD Plugin Handoff (`reasoning.cod.run`)

```elixir
defmodule MyApp.CoDPluginAgent do
  use Jido.AI.Agent,
    name: "cod_plugin_agent",
    plugins: [
      {Jido.AI.Plugins.Reasoning.ChainOfDraft,
       %{
         default_model: :reasoning,
         timeout: 30_000,
         options: %{llm_timeout_ms: 20_000}
       }}
    ]
end

signal =
  Jido.Signal.new!(
    "reasoning.cod.run",
    %{
      prompt: "Give me a terse plan with one backup.",
      strategy: :cot
    },
    source: "/cli"
  )
```

Execution handoff:

- Route dispatch maps `reasoning.cod.run` to `Jido.AI.Actions.Reasoning.RunStrategy`.
- `Jido.AI.Plugins.Reasoning.ChainOfDraft` overrides payload strategy to `strategy: :cod`.
- `RunStrategy` applies plugin defaults (`default_model`, `timeout`, `options`) from plugin state when omitted by caller params.

### CoT Plugin Handoff (`reasoning.cot.run`)

```elixir
defmodule MyApp.CoTPluginAgent do
  use Jido.AI.Agent,
    name: "cot_plugin_agent",
    plugins: [
      {Jido.AI.Plugins.Reasoning.ChainOfThought,
       %{
         default_model: :reasoning,
         timeout: 30_000,
         options: %{llm_timeout_ms: 20_000}
       }}
    ]
end

signal =
  Jido.Signal.new!(
    "reasoning.cot.run",
    %{
      prompt: "Lay out the reasoning steps and one fallback.",
      strategy: :cod
    },
    source: "/cli"
  )
```

Execution handoff:

- Route dispatch maps `reasoning.cot.run` to `Jido.AI.Actions.Reasoning.RunStrategy`.
- `Jido.AI.Plugins.Reasoning.ChainOfThought` overrides payload strategy to `strategy: :cot`.
- `RunStrategy` applies plugin defaults (`default_model`, `timeout`, `options`) from plugin state when omitted by caller params.

### AoT Plugin Handoff (`reasoning.aot.run`)

```elixir
defmodule MyApp.AoTPluginAgent do
  use Jido.AI.Agent,
    name: "aot_plugin_agent",
    plugins: [
      {Jido.AI.Plugins.Reasoning.AlgorithmOfThoughts,
       %{
         default_model: :reasoning,
         timeout: 30_000,
         options: %{profile: :standard, search_style: :dfs, llm_timeout_ms: 20_000}
       }}
    ]
end

signal =
  Jido.Signal.new!(
    "reasoning.aot.run",
    %{
      prompt: "Solve this with algorithmic steps and one fallback.",
      strategy: :cot,
      options: %{profile: :long, require_explicit_answer: true}
    },
    source: "/cli"
  )
```

Execution handoff:

- Route dispatch maps `reasoning.aot.run` to `Jido.AI.Actions.Reasoning.RunStrategy`.
- `Jido.AI.Plugins.Reasoning.AlgorithmOfThoughts` overrides payload strategy to `strategy: :aot`.
- `RunStrategy` applies plugin defaults (`default_model`, `timeout`, `options`) from plugin state when omitted by caller params.

### ToT Plugin Handoff (`reasoning.tot.run`)

```elixir
defmodule MyApp.ToTPluginAgent do
  use Jido.AI.Agent,
    name: "tot_plugin_agent",
    plugins: [
      {Jido.AI.Plugins.Reasoning.TreeOfThoughts,
       %{
         default_model: :reasoning,
         timeout: 30_000,
         options: %{branching_factor: 3, max_depth: 4, traversal_strategy: :best_first}
       }}
    ]
end

signal =
  Jido.Signal.new!(
    "reasoning.tot.run",
    %{
      prompt: "Explore three weather-safe plans with tradeoffs.",
      strategy: :cot,
      options: %{branching_factor: 4, max_depth: 5}
    },
    source: "/cli"
  )
```

Execution handoff:

- Route dispatch maps `reasoning.tot.run` to `Jido.AI.Actions.Reasoning.RunStrategy`.
- `Jido.AI.Plugins.Reasoning.TreeOfThoughts` overrides payload strategy to `strategy: :tot`.
- `RunStrategy` applies plugin defaults (`default_model`, `timeout`, `options`) from plugin state when omitted by caller params.
- ToT option keys include `branching_factor`, `max_depth`, `traversal_strategy`, `generation_prompt`, and `evaluation_prompt`.

### GoT Plugin Handoff (`reasoning.got.run`)

```elixir
defmodule MyApp.GoTPluginAgent do
  use Jido.AI.Agent,
    name: "got_plugin_agent",
    plugins: [
      {Jido.AI.Plugins.Reasoning.GraphOfThoughts,
       %{
         default_model: :reasoning,
         timeout: 30_000,
         options: %{max_nodes: 20, max_depth: 5, aggregation_strategy: :synthesis}
       }}
    ]
end

signal =
  Jido.Signal.new!(
    "reasoning.got.run",
    %{
      prompt: "Compare three weather scenarios and synthesize one recommendation.",
      strategy: :cot,
      options: %{max_nodes: 25, aggregation_strategy: :weighted}
    },
    source: "/cli"
  )
```

Execution handoff:

- Route dispatch maps `reasoning.got.run` to `Jido.AI.Actions.Reasoning.RunStrategy`.
- `Jido.AI.Plugins.Reasoning.GraphOfThoughts` overrides payload strategy to `strategy: :got`.
- `RunStrategy` applies plugin defaults (`default_model`, `timeout`, `options`) from plugin state when omitted by caller params.
- GoT option keys include `max_nodes`, `max_depth`, `aggregation_strategy`, `generation_prompt`, `connection_prompt`, and `aggregation_prompt`.

### TRM Plugin Handoff (`reasoning.trm.run`)

```elixir
defmodule MyApp.TRMPluginAgent do
  use Jido.AI.Agent,
    name: "trm_plugin_agent",
    plugins: [
      {Jido.AI.Plugins.Reasoning.TRM,
       %{
         default_model: :reasoning,
         timeout: 30_000,
         options: %{max_supervision_steps: 6, act_threshold: 0.92}
       }}
    ]
end

signal =
  Jido.Signal.new!(
    "reasoning.trm.run",
    %{
      prompt: "Recursively improve this emergency plan and stop when confidence is high.",
      strategy: :cot,
      options: %{max_supervision_steps: 7, act_threshold: 0.95}
    },
    source: "/cli"
  )
```

Execution handoff:

- Route dispatch maps `reasoning.trm.run` to `Jido.AI.Actions.Reasoning.RunStrategy`.
- `Jido.AI.Plugins.Reasoning.TRM` overrides payload strategy to `strategy: :trm`.
- `RunStrategy` applies plugin defaults (`default_model`, `timeout`, `options`) from plugin state when omitted by caller params.
- TRM option keys include `max_supervision_steps` and `act_threshold`.

### Adaptive Plugin Handoff (`reasoning.adaptive.run`)

```elixir
defmodule MyApp.AdaptivePluginAgent do
  use Jido.AI.Agent,
    name: "adaptive_plugin_agent",
    plugins: [
      {Jido.AI.Plugins.Reasoning.Adaptive,
       %{
         default_model: :reasoning,
         timeout: 30_000,
         options: %{
           default_strategy: :react,
           available_strategies: [:cod, :cot, :react, :tot, :got, :trm, :aot],
           complexity_thresholds: %{simple: 0.3, complex: 0.7}
         }
       }}
    ]
end

signal =
  Jido.Signal.new!(
    "reasoning.adaptive.run",
    %{
      prompt: "Pick the best strategy and produce a weather-safe commute with one backup.",
      strategy: :cot,
      options: %{default_strategy: :tot}
    },
    source: "/cli"
  )
```

Execution handoff:

- Route dispatch maps `reasoning.adaptive.run` to `Jido.AI.Actions.Reasoning.RunStrategy`.
- `Jido.AI.Plugins.Reasoning.Adaptive` overrides payload strategy to `strategy: :adaptive`.
- `RunStrategy` applies plugin defaults (`default_model`, `timeout`, `options`) from plugin state when omitted by caller params.
- Adaptive option keys include `default_strategy`, `available_strategies`, and `complexity_thresholds`.

## Chat Plugin Defaults Contract

`Jido.AI.Plugins.Chat` mounts the following defaults unless overridden in plugin config:

- `default_model: :capable`
- `default_max_tokens: 4096`
- `default_temperature: 0.7`
- `default_system_prompt: nil`
- `auto_execute: true`
- `max_turns: 10`
- `tool_policy: :allow_all`
- `tools: %{}` (normalized from configured tool modules)
- `available_tools: []`

## Tool Registry Precedence Contract

Tool-calling actions (`CallWithTools`, `ExecuteTool`, `ListTools`) resolve tool maps with this precedence:

1. `context[:tools]`
2. `context[:tool_calling][:tools]`
3. `context[:chat][:tools]`
4. `context[:state][:tool_calling][:tools]`
5. `context[:state][:chat][:tools]`
6. `context[:agent][:state][:tool_calling][:tools]`
7. `context[:agent][:state][:chat][:tools]`
8. `context[:plugin_state][:tool_calling][:tools]`
9. `context[:plugin_state][:chat][:tools]`

First non-`nil` tool map wins. This keeps direct `Jido.Exec` action calls and plugin-routed calls deterministic.

`ListTools` security filtering defaults:

- sensitive names are excluded by default
- `include_sensitive: true` disables sensitive-name filtering
- `allowed_tools: [...]` applies an allowlist after sensitive filtering unless `include_sensitive: true` is set

## Planning Plugin Defaults Contract

`Jido.AI.Plugins.Planning` mounts the following defaults unless overridden in plugin config:

- `default_model: :planning`
- `default_max_tokens: 4096`
- `default_temperature: 0.7`

Planning actions consume these plugin defaults when the caller omits those params.
Action-specific fields remain action-owned:

- `Plan`: `goal`, optional `constraints`/`resources`, optional `max_steps`
- `Decompose`: `goal`, optional `max_depth`, optional `context`
- `Prioritize`: `tasks`, optional `criteria`, optional `context`

Planning selection guidance:

- Use `Plan` when you need a sequential execution plan from one goal.
- Use `Decompose` when the goal is too large and should be split into hierarchical sub-goals.
- Use `Prioritize` when you already have a task list and need ranked execution order.

## Model Routing Plugin Defaults Contract

`Jido.AI.Plugins.ModelRouting` mounts default routes unless overridden by plugin
config:

- `"chat.message" => :capable`
- `"chat.simple" => :fast`
- `"chat.complete" => :fast`
- `"chat.embed" => :embedding`
- `"chat.generate_object" => :thinking`
- `"reasoning.*.run" => :reasoning`

Exact routes take precedence over wildcard routes. Wildcards use a
single-segment `*` matcher between dots.

## Reasoning CoT Plugin Defaults Contract

`Jido.AI.Plugins.Reasoning.ChainOfThought` mounts the following defaults unless overridden in plugin config:

- `strategy: :cot`
- `default_model: :reasoning`
- `timeout: 30_000`
- `options: %{}`

## Reasoning AoT Plugin Defaults Contract

`Jido.AI.Plugins.Reasoning.AlgorithmOfThoughts` mounts the following defaults unless overridden in plugin config:

- `strategy: :aot`
- `default_model: :reasoning`
- `timeout: 30_000`
- `options: %{}`

## Reasoning ToT Plugin Defaults Contract

`Jido.AI.Plugins.Reasoning.TreeOfThoughts` mounts the following defaults unless overridden in plugin config:

- `strategy: :tot`
- `default_model: :reasoning`
- `timeout: 30_000`
- `options: %{}`

## Reasoning GoT Plugin Defaults Contract

`Jido.AI.Plugins.Reasoning.GraphOfThoughts` mounts the following defaults unless overridden in plugin config:

- `strategy: :got`
- `default_model: :reasoning`
- `timeout: 30_000`
- `options: %{}`

## Reasoning TRM Plugin Defaults Contract

`Jido.AI.Plugins.Reasoning.TRM` mounts the following defaults unless overridden in plugin config:

- `strategy: :trm`
- `default_model: :reasoning`
- `timeout: 30_000`
- `options: %{}`

## Reasoning Adaptive Plugin Defaults Contract

`Jido.AI.Plugins.Reasoning.Adaptive` mounts the following defaults unless overridden in plugin config:

- `strategy: :adaptive`
- `default_model: :reasoning`
- `timeout: 30_000`
- `options: %{}`

## Action Context Contract (Plugin -> Action)

When plugin-routed actions execute, the action context contract includes:

- `state`
- `agent`
- `plugin_state`
- `provided_params`

Actions should read defaults from explicit params first, then context/plugin state fallback.

## Strategy Runtime Compatibility

All built-in reasoning strategies now support module-action fallback execution for non-strategy commands. This means plugin-routed `Jido.Action` modules execute on strategy agents instead of silently no-oping.

## When To Use Plugins vs Actions

Use plugins when:

- capability should be mountable and reusable across many agents
- you need lifecycle hooks and capability-level defaults
- you want stable signal contracts for app/runtime integration

Use actions directly when:

- you are building one-off pipelines or background jobs
- you need low-level composition via `Jido.Exec`
- you do not need plugin lifecycle behavior

## Failure Mode: Defaults Not Being Applied

Symptom:

- execution succeeds but model/tool defaults are ignored

Fix:

- verify plugin state keys and `mount/2` shape match plugin schema and action fallback readers
- ensure caller does not override defaults with empty explicit params

## Next

- [Actions Catalog](actions_catalog.md)
- [Package Overview (Production Map)](../user/package_overview.md)
- [Migration Guide: Plugins And Signals (v2 -> v3)](../user/migration_plugins_and_signals_v3.md)
