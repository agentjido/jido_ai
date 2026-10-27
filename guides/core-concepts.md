# Core Concepts

A Jido AI request crosses a fixed set of boundaries: a Signal, a route, a
reasoning Flow, a conversation, one or more model calls, and tools. Each has
one owner. This guide names each part, what it holds, and which package owns
it. It uses `MyApp.SupportAgent` from [Getting Started](getting-started.livemd).

## The Request Path

One `jido.ai.request` runs these steps in order. The ReAct Flow is shown; other
Flows replace the model-and-tool loop with their own fixed stages.

| Step | Owner | What happens |
| --- | --- | --- |
| 1. Signal | Your code | `request_signal!/1` builds a `jido.ai.request` Signal. Its data is the Flow input. |
| 2. Route | Core Jido | The generated route merges the Agent's reasoning defaults with the Signal data. Signal data wins. |
| 3. Validate | Reasoning Flow | The Flow's Zoi input schema checks every field and fills defaults. Unknown keys fail. |
| 4. Start | Reasoning Flow | Loads the Session (or creates one), resolves tools, appends the user message to the Thread. |
| 5. Input guard | Reasoning Flow | Blocks empty input, text over 2,000 characters, and known prompt-injection phrases. |
| 6. Project | `Jido.AI.Thread.Projection` | Selects eligible Thread messages and builds a `ReqLLM.Context`. The Flow adds `instructions` as the system message. |
| 7. Model call | `Jido.AI.Context` + ReqLLM | Freezes the exact model, messages, tools, and options, calls ReqLLM, and records the result. |
| 8. Decide | Reasoning Flow | Final answer, tool calls, output repair, retry, fallback model, or a limit. |
| 9. Tools | Reasoning Flow + Actions | Runs the requested Actions in parallel, appends the results, and returns to step 6. |
| 10. Finalize | Reasoning Flow | Records the outcome in the Thread and returns `%{state: ..., response: ...}`. |
| 11. Commit, reply | Core Jido | Validates the new state and returns a `Reply` with a `jido.ai.response` Signal. A `Jido.AgentServer` commits the state. |

Steps 3 to 10 run inside one Flow. Jido AI adds no pipeline around it.

## Agent

`use Jido.AI.Agent` defines a normal `Jido.Agent` and adds three things:

| Addition | Value |
| --- | --- |
| State field | `session`, a nullable `Jido.Session`. It starts as `nil`. |
| Route | `jido.ai.request` to the root reasoning Flow, generated as `request_signal/2` and `request_signal!/2`. |
| Helpers | `reasoning/0`, `explain/0`, and `preflight/1`. |

The `ai` block takes exactly one `reasoning` declaration and at most one
`tools` block. The Agent's `signal_source` is `"/"` plus its `id`, such as
`"/my_app/support_agent"`.

Everything else, including `cmd/3`, `instantiate!/1`, and running under a
server, is core Jido. See the [Jido guides](https://hexdocs.pm/jido).

## Root Reasoning Flow

The root Flow is a `Jido.Flow` module. It is the direct target of the request
route. It owns:

- the request schema: which fields a request can set, their types, and their
  defaults;
- the control behavior: how many model calls, which stages, whether tools run;
- the output shape: `%{state: map(), response: map()}`.

Values in the `reasoning` block are partial defaults for that schema. They're
checked at compile time:

```elixir
ai do
  reasoning Jido.AI.Reasoning.ReAct do
    model "openai:gpt-4o-mini"

    limits do
      model_calls 4
    end
  end
end
```

A request can override any of them except tools. Jido AI ships eight Flows,
and you can write your own. See
[Choose a Reasoning Flow](choose-a-reasoning-flow.md).

## Request and Response

The built-in Flows return the same response map. It becomes the data of the
`jido.ai.response` reply:

| Field | Value |
| --- | --- |
| `status` | `:completed`, `:blocked`, or `:failed` |
| `output` | The answer: a string, or a map when you set `output_schema`. `""` when not completed. |
| `reason_code`, `reason` | `:none` and `nil` on success; otherwise the cause, such as `:limits` and `"maximum tool rounds reached"` |
| `reasoning` | Flow-specific data, such as Chain of Thought steps. `nil` for ReAct. |
| `model_calls`, `tool_rounds`, `tool_calls`, `retries` | Counters for this request |
| `usage` | Token and cost totals across all model calls |
| `budget` | The limits in force and `elapsed_ms` |
| `model_attempts`, `tool_attempts` | One record per model call and per tool call |
| `request_id`, `run_id`, `session_id`, `thread_id`, `thread_rev` | Correlation IDs. `request_id` is the request Signal's `id`. |

A blocked or failed request is still a normal reply: `cmd/3` returns
`{:ok, next_agent, [reply]}`, and the Thread records what happened. Request
data that fails the Flow schema returns `{:error, reason}` before any model
call.
[Errors and Recovery](errors-and-recovery.md) lists every reason code.

## Session and Thread

`Jido.Session` is the conversation. It holds one `Jido.Thread`, an append-only
log of entries. Both are immutable, portable values: no processes, no
callbacks, no provider clients. They encode to plain maps with
`Jido.Session.encode/1`.

The Agent stores the Session at `state.session`. The first request creates
one with the ID `"session:<agent id>"`. Each entry adds one revision to the
Thread.

| Entry kind | Written when |
| --- | --- |
| `:ai_message` | A user, assistant, or tool message is added |
| `:ai_model_attempt` | A model call finishes, with content-free Context snapshots |
| `:ai_tool_attempt` | A tool call finishes |
| `:ai_review` | A tool review is requested or resolved |
| `:ai_request_outcome` | The request ends, with the response summary |

The Agent owns the Session value. Core Jido owns when it is committed and
whether it is saved. [Sessions and Threads](sessions-and-threads.md) covers
entries and sources.

## Thread Projection

The Thread keeps everything. `Jido.AI.Thread.Projection` decides what a model
sees:

```elixir
{:ok, projection} =
  Jido.AI.Thread.Projection.context(next_agent.state.session, %{
    max_messages: 64,
    max_bytes: 200_000
  })

Enum.map(projection.context.messages, & &1.role)
# => [:user, :assistant, :tool, :assistant]
```

Projection includes only `:ai_message` entries. It drops messages from blocked
or failed requests, drops incomplete tool exchanges, and keeps the newest
complete turns that fit `max_messages` and `max_bytes`. `projection.decisions`
records why each message was kept or dropped. Projection never changes the
Session.

Every built-in Flow projects the Thread before each model call. Its `context`
input sets the limits; the defaults are 64 messages and 200,000 bytes.
[Project a Thread](project-a-thread.livemd) shows the rules.

## Context: One Model Call

`Jido.AI.Context` wraps exactly one ReqLLM call. It knows nothing about
Threads, tools, or Flows.

| Stage | Function | What it fixes |
| --- | --- | --- |
| `:open` | `Jido.AI.Context.new/2` | Wraps a `ReqLLM.Context` |
| `:open` | `Jido.AI.Context.transform/3` | Applies an idempotent change, keyed by an operation ID |
| `:prepared` | `Jido.AI.Context.prepare/2` | Freezes the model, messages, tools, and options sent to ReqLLM |
| `:completed` | `Jido.AI.Context.complete/3` | Attaches the exact ReqLLM result |

`Jido.AI.Context.snapshot/2` captures a portable view at any stage, with
content `:none`, `:redacted` (the default), or `:full`. Each built-in Flow
stores a `:none` snapshot before and after every call in
`reply.data.model_attempts`. Memory, retrieval, and skills belong outside
Context; they use `transform/3`.
[Context Lifecycle](context-lifecycle.md) covers each stage.

## Model Calls and ReqLLM

[ReqLLM](https://hexdocs.pm/req_llm) owns providers, model names, credentials,
and HTTP. A Flow passes it three values: the `model` string, such as
`"openai:gpt-4o-mini"`, the projected `ReqLLM.Context`, and the request
`options` map. Jido AI adds `tools`, `tool_choice`, and structured `output`
options when the Flow needs them.

Every built-in Flow defaults to `"openai:gpt-4o-mini"`. ReAct also accepts
`fallback_models`. After a retryable failure, it retries the current model up
to `limits.retries` times, then moves to the next fallback.
[Models and Options](models-and-options.md) lists the options.

## Tools

A tool is a `Jido.Action` or `Jido.Flow`. The model sees its `name`, `description`, and
parameter schema. The Agent's `tools` block is its protected allowlist:

```elixir
tools do
  action MyApp.LookupOrder
end
```

Three sources form the tool set for one request:

| Source | Set by | Can add tools |
| --- | --- | --- |
| `tools` block | Agent definition | Yes |
| `Jido.AI.ToolSource` | Trusted host, through `jido_ai_tool_sources` in the execution context | Yes |
| `tool_policy` | Request data | No. It can hide tools or require review. |

Request data can't add a tool or a tool source. Only ReAct, and Adaptive when
it selects ReAct, sends tools to the model. The other Flows ignore the Agent's
tools. [Action Tools](action-tools.livemd) and
[Dynamic Tool Sources](dynamic-tool-sources.md) cover both paths.

## Who Owns What

| Concern | Owner |
| --- | --- |
| Agent process, route execution, state validation, commit, reply, Directives | `jido` |
| Actions, Flows, and graph execution | `jido_action` |
| Signal envelope and dispatch | `jido_signal` |
| AI Agent DSL, reasoning Flows, limits, tool policy, Session, Thread, Projection, Context | `jido_ai` |
| Providers, model names, credentials, HTTP, streaming | `req_llm` |
| Schemas for input, output, and tool parameters | `zoi` |

When a question is about processes, persistence, or Directives, the answer is
in core Jido. When it's about what a model sees or how many calls it gets, the
answer is in the reasoning Flow and its input schema.
