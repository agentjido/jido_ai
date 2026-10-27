# Public API Reference

This page lists the Jido AI contract in one place: the Agent DSL, the
functions it generates, each built-in reasoning Flow's request schema and
defaults, the response map, Signal names, Thread entry kinds, and the public
modules. Read [Core Concepts](core-concepts.md) first for how the pieces fit.
Module documentation holds the full detail for each function.

## Agent DSL

```elixir
defmodule MyApp.SupportAgent do
  use Jido.AI.Agent,
    id: "my_app/support_agent",
    vsn: 1,
    name: "support_agent"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "openai:gpt-4o-mini"
      instructions "Answer customer support questions."

      limits do
        model_calls 6
        tool_rounds 3
      end
    end

    tools do
      action MyApp.LookupOrder
      action MyApp.IssueRefund
    end
  end
end
```

| Declaration | Rules |
| --- | --- |
| `use Jido.AI.Agent, opts` | Takes the `use Jido.Agent` options. `id` defaults to the module name and sets the Signal source to `"/" <> id`. Adds the `session` state field and the `jido.ai.request` route. |
| `ai do ... end` | One per Agent. Holds exactly one `reasoning` and at most one `tools` block. Anything else is a `CompileError`. |
| `reasoning Module` | Selects a compiled `Jido.Flow` module as the root Flow, with no defaults. |
| `reasoning Module do ... end` | Same, plus request defaults. Each line is `field literal` or `field do ... end` for a nested object. Values must be compile-time literals. The Flow schema validates them at compile time. `input` cannot be a default. |
| `reasoning do ... end` | Defines the root Flow inline with Flow `step` and `output` declarations. Its output must match `%{state: map(), response: map()}`. |
| `tools do action Module; flow Module end` | The ordered static tool allowlist. Each target must be a Jido Action or Flow with a unique name. |

`Jido.AI.Agent` also accepts the extension data directly when you build an
Agent from a JSON document. The document stores `reasoning`, `config`, and
`tools`, and its Flow and Action references must be registered. See
[Agent Authoring](agent-authoring.md).

## Generated Functions

| Function | Returns |
| --- | --- |
| `reasoning/0` | The root reasoning Flow module. |
| `explain/0` | `%{agent, reasoning, defaults, input_schema, output_schema, tools, flow}` |
| `preflight/1` | `{:ok, %{agent, reasoning, params, tools, flow, workflow}}` or `{:error, reason}`. Takes a map or keyword list. Validates the request against the Flow schema and compiles the Flow. It does not call a model. |
| `request_signal!/2` | A `jido.ai.request` `Jido.Signal` built from a request map. Raises on an invalid Signal. It does not validate the request fields. |
| `request_signal/2` | `{:ok, signal}` or `{:error, reason}`. |

The second argument of `request_signal!/2` takes Signal options: `source`,
`id`, `time`, `subject`, and `datacontenttype`. The generated functions call
`Jido.AI.Reasoning.root/1`, `Jido.AI.Reasoning.explain/1`, and
`Jido.AI.Reasoning.preflight/2`.

Core Jido generates the rest, including `instantiate!/1`, `cmd/3`, and
`definition/0`. See [Jido](https://hexdocs.pm/jido).

## Request Route

| Field | Value |
| --- | --- |
| Signal type | `jido.ai.request` |
| Route name | `:request` |
| Target | The root reasoning Flow |
| Defaults | The `reasoning` block values, merged under each request |
| State | The Flow output at `[:state]` replaces Agent state |
| Reply | A `jido.ai.response` Signal with the Flow output at `[:response]` |
| Agent state | `%{session: Jido.Session.t() \| nil}`, `nil` until the first request |

`cmd/3` returns `{:ok, agent, [%Jido.Agent.Directive.Reply{signal: reply}]}`
for completed, blocked, and failed requests. It returns `{:error, reason}`
for an invalid request. Request data merges over Agent defaults one level
deep: a request `limits` map replaces the whole default `limits` map, and
the Flow schema fills in the missing keys.

## Shared Flow Fields

Every built-in Flow rejects unknown keys. These fields appear in all of them
except Adaptive, which is covered below:

| Field | Type | Default |
| --- | --- | --- |
| `input` | string, or a list of content-part maps | required |
| `instructions` | string | Flow-specific; see below |
| `model` | ReqLLM model string | `"openai:gpt-4o-mini"` |
| `options` | map of ReqLLM options | Flow-specific; see below |
| `prompt_cache.enabled` | boolean | `false` |
| `prompt_cache.ttl` | string or integer `>= 0` | not set |
| `context.max_messages` | integer `1..512` | `64` |
| `context.max_bytes` | integer `1_024..2_000_000` | `200_000` |
| `limits.elapsed_ms` | integer `1..3_600_000` | `120_000` |
| `limits.input_tokens` | integer `>= 1` or `nil` | `nil` |
| `limits.output_tokens` | integer `>= 1` or `nil` | `nil` |
| `limits.total_tokens` | integer `>= 1` or `nil` | `nil` |
| `limits.total_cost` | number `>= 0` or `nil` | `nil` |

A request `options` map replaces the default `options` map. Include every
option you need, such as `max_tokens`.

## ReAct Fields

`Jido.AI.Reasoning.ReAct` adds model fallbacks, streaming, structured
output, and tools:

| Field | Type | Default |
| --- | --- | --- |
| `instructions` | string | `"Answer concisely. Use the available tools when they help. You can request multiple tools in one response."` |
| `options` | map | `%{max_tokens: 128, receive_timeout: 30_000, temperature: 0.0}` |
| `fallback_models` | list of model strings | `[]` |
| `stream` | boolean | `false` |
| `output_schema` | JSON Schema map or `nil` | `nil` |
| `review_tools` | boolean | `false` |
| `tool_policy.visible` | list of tool names | `[]` (all) |
| `tool_policy.hidden` | list of tool names | `[]` |
| `tool_policy.review` | list of tool names | `[]` |
| `tool_policy.requirement` | `:optional`, `:required`, `:per_turn`, `:disabled` | `:optional` |
| `tool_policy.reason` | string or `nil` | `nil` |
| `limits.model_calls` | integer `1..16` | `8` |
| `limits.tool_rounds` | integer `0..8` | `4` |
| `limits.tool_calls` | integer `1..16` | `8` |
| `limits.retries` | integer `0..4` | `1` |
| `limits.tool_output_bytes` | integer `256..1_000_000` | `16_384` |

A `tool_policy` name that is not one of the Agent's tools fails the request
with `{:unknown_tool, name}`.

## Single-Call and Staged

These Flows use only the shared fields. They differ in default instructions
and options:

| Flow | Calls | Default `options` |
| --- | --- | --- |
| `Jido.AI.Reasoning.ChainOfThought` | 1 | `%{max_tokens: 512, receive_timeout: 30_000, temperature: 0.0}` |
| `Jido.AI.Reasoning.ChainOfDraft` | 1 | `%{max_tokens: 256, temperature: 0.0}` |
| `Jido.AI.Reasoning.AlgorithmOfThoughts` | 1 | `%{max_tokens: 1024, temperature: 0.0}` |
| `Jido.AI.Reasoning.TreeOfThoughts` | Several | `%{max_tokens: 1536, temperature: 0.4}` |
| `Jido.AI.Reasoning.GraphOfThoughts` | Several | `%{max_tokens: 1536, temperature: 0.3}` |
| `Jido.AI.Reasoning.TRM` | Several | `%{max_tokens: 1536, temperature: 0.2}` |

Each of these modules exposes its default instructions through
`default_instructions/0`. None of them executes tools. See
[Single-Call Reasoning](single-call-reasoning.livemd) and
[Multi-Stage Reasoning](multi-stage-reasoning.livemd).

## Adaptive Fields

`Jido.AI.Reasoning.Adaptive` selects one of the other Flows and passes the
request to it. Its fields have no defaults, so the selected Flow applies its
own:

| Field | Type | Default |
| --- | --- | --- |
| `input` | string or list of maps | required |
| `strategy` | `:react`, `:chain_of_thought`, `:chain_of_draft`, `:algorithm_of_thoughts`, `:tree_of_thoughts`, `:graph_of_thoughts`, `:trm`, or `nil` | `nil` (select locally) |
| `instructions`, `model`, `options` | as above | not set |
| `prompt_cache`, `context`, `limits` | as above | not set |

Adaptive keeps unknown top-level and `limits` keys and passes every field
except `strategy` to the selected Flow, which validates them against its own
schema. A ReAct-only field such as `tool_policy` fails if Adaptive selects
another Flow. See [Adaptive Reasoning](adaptive-reasoning.livemd).

## Response Fields

Every built-in Flow ends with `Jido.AI.Reasoning.Actions.FinalizeTurn`,
which returns this map as the `jido.ai.response` data:

| Field | Value |
| --- | --- |
| `version` | `1` |
| `status` | `:completed`, `:blocked`, or `:failed` |
| `output` | Final text, a structured map, or `""` when not completed |
| `reason_code` | `:none` on success, or an atom such as `:input`, `:output`, `:model`, `:limits`, `:review` |
| `reason` | Human-readable reason, or `nil` |
| `reasoning` | Flow-specific result data, or `nil` for ReAct |
| `reasoning_steps` | `reasoning.steps_count` when present, else `nil` |
| `flow` | `%{id: flow_id, vsn: integer}` |
| `request_id`, `run_id` | Correlation IDs for this request |
| `session_id`, `thread_id`, `thread_rev` | The committed Session and Thread revision |
| `started_at_ms`, `completed_at_ms` | System time in milliseconds |
| `model_calls`, `retries` | Model calls made and retries used |
| `tool_rounds`, `tool_calls`, `tool_errors`, `tool_cycles` | Tool counters |
| `usage` | Normalized totals from `Jido.AI.Usage`: `input_tokens`, `output_tokens`, `total_tokens`, cache and cost fields |
| `budget` | `%{elapsed_ms: integer, limits: map}` from `Jido.AI.Budget.summary/2` |
| `model_attempts` | One map per model call; see below |
| `tool_attempts` | One map per executed tool call; see below |

Each `model_attempts` entry has `model_call`, `model`, `model_index`,
`model_attempt`, `status`, `outcome`, `output_allowed`, `output_reason`,
`req_llm_request_id`, `prompt_cache`, `tool_rounds`, `reasoning`, and
`context`. `context` is `%{format: "jido.ai.context.snapshot+json", before:
json, after: json}`; decode each with `Jido.AI.Context.Snapshot.decode!/1`.

Each `tool_attempts` entry has `tool_call_id`, `tool_name`, `tool`, `input`,
`output`, `content`, `error`, `status`, `metadata`, `result_metadata`,
`review`, `tool_round`, `started_at_ms`, `completed_at_ms`, `duration_ms`,
and `effects_count`. `input` and `output` use string keys.

An inline `reasoning do ... end` Flow replies with whatever its `response`
map holds.

## Signals

| Type | Direction | Data |
| --- | --- | --- |
| `jido.ai.request` | In | The Flow request fields |
| `jido.ai.response` | Reply | The response map above |
| `jido.ai.model.stream.started` | Out, when `stream: true` | Stream correlation |
| `jido.ai.model.stream.chunk` | Out | Correlation plus `chunk: %{type, text, name, arguments, metadata}` |
| `jido.ai.model.stream.completed` | Out | Correlation plus `response_id`, `outcome`, `finish_reason` |
| `jido.ai.model.stream.failed` | Out | Correlation plus `reason` |
| `jido.ai.review.requested` | Out, when a tool needs review | `review_id`, `session_id`, `thread_id`, `request_id`, `run_id`, `timestamp_ms`, `expires_at_ms`, `options`, `policy_reason`, `tool_calls` |
| `jido.ai.review.approved` | In, to the waiting Flow | Must match `review_id`, `request_id`, `run_id` |
| `jido.ai.review.denied` | In, to the waiting Flow | Must match `review_id`, `request_id`, `run_id` |

Stream correlation is `session_id`, `thread_id`, `request_id`, `run_id`,
`model`, `model_call`, `model_index`, `model_attempt`, `tool_rounds`,
`stream_id`, `sequence`, and `timestamp_ms`. `sequence` starts at `0` for
`started` and increases by one per Signal within one `stream_id`.

Outgoing stream and review Signals go to the dispatch configured by the
execution host. A review waits 300,000 ms before it expires. See
[Stream Model Output](stream-model-output.livemd) and
[Tool Review and Cycle Limits](tool-review-and-cycle-limits.livemd).

## Thread Entry Kinds

| Kind | Written when | Enters later prompts |
| --- | --- | --- |
| `:ai_message` | A user, assistant, or tool message is recorded | Yes, if its request completed and its tool exchange is complete |
| `:ai_model_attempt` | Each model call finishes | No |
| `:ai_tool_attempt` | Each tool call finishes | No |
| `:ai_review` | A review is requested or resolved | No |
| `:ai_request_outcome` | Each request ends | No |

`Jido.AI.Thread.Projection` decides which `:ai_message` entries enter a
model call. See [Project a Thread](project-a-thread.livemd).

## Telemetry Events

Jido AI emits these events:

| Event | Spans |
| --- | --- |
| `[:jido, :ai, :agent, :start \| :stop \| :exception]` | One AI request |
| `[:jido, :ai, :reasoning, :start \| :stop \| :exception]` | One reasoning Flow run |
| `[:jido, :ai, :tool, :start \| :stop \| :exception]` | One tool call |

`Jido.AI.Telemetry.events/0` adds the lower-layer Jido, Runic, and ReqLLM
events. See [Telemetry and Tracing](telemetry-and-tracing.livemd).

## Public Modules

### Core

| Module | Purpose |
| --- | --- |
| `Jido.AI` | Package overview |
| `Jido.AI.Agent` | `use Jido.AI.Agent` and the `ai` DSL |
| `Jido.AI.Reasoning` | `root/1`, `explain/1`, `preflight/2` |

### Context and Conversation

| Module | Purpose |
| --- | --- |
| `Jido.AI.Context` | Lifecycle of one ReqLLM call: `new/2`, `transform/3`, `prepare/2`, `complete/3`, `snapshot/2`, `diff/2` |
| `Jido.AI.Context.Snapshot` | Portable snapshot: `encode/1`, `decode/1`, `decode!/1`, `diff/2` |
| `Jido.Thread` | Immutable, ordered conversation entries |
| `Jido.Thread.Entry` | One portable Thread entry |
| `Jido.Session` | One portable Thread plus status and metadata |
| `Jido.AI.Thread.Projection` | `append/4`, `observe/5`, `messages/1`, `context/2`, `explain/2` |

### Tools and Model Calls

| Module | Purpose |
| --- | --- |
| `Jido.AI.Actions.Embed` | Action for one embedding or a batch; `model` defaults to `"openai:text-embedding-3-small"` |
| `Jido.AI.Toolset` | The Agent tool allowlist and request tool selection |
| `Jido.AI.ToolSource` | Behaviour for trusted dynamic tools: `list_tools/2`, `run_tool/3` |
| `Jido.AI.ToolResult` | Splits a local tool value from bounded model-visible content |

### Limits and Observability

| Module | Purpose |
| --- | --- |
| `Jido.AI.Budget` | Request budget checks and `summary/2` |
| `Jido.AI.Usage` | Normalized usage: `zero/0`, `normalize/1`, `add/2` |
| `Jido.AI.Telemetry` | `events/0`, `owned_events/0`, `metrics/0`, `attach/3`, `attach_open_telemetry/1` |

### Reasoning

| Flow | Recipe modules |
| --- | --- |
| `Jido.AI.Reasoning.ReAct` | `ModelRound`, `ToolReview`, `Actions.DecideNext`, `Actions.DetectToolCycle`, `Actions.ExecuteTool`, `Actions.ExpandNext`, `Actions.RecordToolResults`, `Actions.RequestToolReview`, `Actions.ResolveToolReview` |
| `Jido.AI.Reasoning.ChainOfThought` | `ModelRound`, `Actions.Complete`, `Actions.ExpandNext` |
| `Jido.AI.Reasoning.ChainOfDraft` | `ModelRound`, `Actions.Complete`, `Actions.ExpandNext` |
| `Jido.AI.Reasoning.AlgorithmOfThoughts` | `ModelRound`, `Actions.Complete`, `Actions.ExpandNext` |
| `Jido.AI.Reasoning.TreeOfThoughts` | `ModelRound`, `Actions.AcceptOutput`, `Actions.ExpandNext`, `Actions.PrepareCall`, `Actions.SelectThoughts` |
| `Jido.AI.Reasoning.GraphOfThoughts` | `ModelRound`, `Actions.Advance`, `Actions.ExpandNext`, `Actions.PrepareCall` |
| `Jido.AI.Reasoning.TRM` | `ModelRound`, `Actions.Advance`, `Actions.ExpandNext`, `Actions.PrepareCall` |
| `Jido.AI.Reasoning.Adaptive` | `Actions.Expand`, `Actions.Select` |

Shared building blocks live under `Jido.AI.Reasoning.Actions`:
`StartRequest`, `GuardInput`, `DecideInput`, `ProjectConversation`,
`CallModel`, `GuardOutput`, `RecordModelAttempt`, and `FinalizeTurn`.
`Jido.AI.Reasoning.Result` builds the terminal `status`, `output`,
`reason_code`, `reason`, and `reasoning` map. Use these modules to build your
own reasoning Flow.
