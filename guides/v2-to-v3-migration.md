# Migrating from V2

This guide moves an application from Jido AI `2.x` (checked against `2.4.0`)
to `3.0.0-beta.1`. V3 keeps the `Jido.AI.Agent` name, but an AI Agent is now
a normal Jido V3 Agent with one root reasoning Flow. There is no
compatibility mode and no automatic conversion of stored V2 Agent state.
Port Jido core first with the
[Jido migration guide](https://hexdocs.pm/jido/v2-to-v3-migration.html), then
read [Core Concepts](core-concepts.md).

## The Short Version

| V2 | V3 |
| --- | --- |
| `use Jido.AI.Agent, tools: [...], model: :fast, system_prompt: "..."` | `use Jido.AI.Agent` plus an `ai do reasoning ... tools ... end` block |
| `Jido.AI.CoTAgent`, `ToTAgent`, and the other strategy Agents | `use Jido.AI.Agent` with `reasoning Jido.AI.Reasoning.ChainOfThought` and so on |
| `ask/3`, `ask_sync/3`, `await/2`, `think/3` | `request_signal!/1`, then `cmd/3` or `Jido.AgentServer.call/3` |
| `{:ok, answer}` | `reply.data.output` from the `jido.ai.response` reply, with `status` |
| `"ai.react.query"` Signal | `"jido.ai.request"` |
| `ai.request.completed` and `ai.request.failed` Signals | One `jido.ai.response` reply with `status: :completed`, `:blocked`, or `:failed` |
| Model aliases such as `:fast` | ReqLLM model strings such as `"openai:gpt-4o-mini"` |
| `Jido.AI.Context` (conversation history) | `Jido.Session`, `Jido.Thread`, and `Jido.AI.Thread.Projection` |
| V2 `Jido.AI.ask`, `generate_text`, and `stream_text` | Call ReqLLM directly, or use `Jido.AI.Context` for one call |
| `Jido.AI.Test`, `expect_react`, `Jido.AI.TestCase` | Mimic on `ReqLLM` or the ReqLLM HTTP mock |

The name `Jido.AI.Context` survives with a new meaning. In V2 it held
conversation history. In V3 it is the lifecycle of one ReqLLM call. Move
history code to `Jido.Session` and `Jido.AI.Thread.Projection`.

## Dependencies

V3 requires Elixir 1.18 and OTP 27 or later, and the V3 releases of `jido`,
`jido_action`, and `jido_signal`:

```elixir
def deps do
  [
    {:jido, "~> 3.0.0-beta.2"},
    {:jido_ai, "~> 3.0.0-beta.1"}
  ]
end
```

The Igniter installer and the `mix jido_ai.install`, `mix jido_ai.skill`, and
`mix jido_ai.quality` tasks are removed. Remove `config :jido_ai,
model_aliases:` and configure provider keys for ReqLLM only.

## Agent Modules

V2 configured the Agent through `use` options:

```elixir
# V2
defmodule MyApp.SupportAgent do
  use Jido.AI.Agent,
    name: "support_agent",
    model: :fast,
    tools: [MyApp.LookupOrder],
    system_prompt: "Answer customer support questions.",
    max_iterations: 6
end
```

V3 declares the root Flow, its defaults, and the tools:

```elixir
# V3
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
      end
    end

    tools do
      action MyApp.LookupOrder
    end
  end
end
```

The reasoning Flow schema owns every request field and default.
`MyApp.SupportAgent.preflight(%{input: "Where is A-1001?"})` checks a request
against it without a model call.

### Agent Options

| V2 option | V3 |
| --- | --- |
| `:name`, `:description`, `:tags` | `use Jido.AI.Agent` options, as in `use Jido.Agent` |
| `:tools` | `tools do action Module end` |
| `:system_prompt` | `instructions` |
| `:model` | `model`, a ReqLLM model string |
| `:max_iterations` | `limits.model_calls` and `limits.tool_rounds` |
| `:max_tokens` | `options.max_tokens`; the ReAct default is now `128` |
| `:streaming` (default `true`) | `stream` (default `false`) |
| `:llm_opts`, `:req_http_options` | `options`, a map passed to ReqLLM; `req_http_options` goes inside it |
| `:output` | `output_schema`, a JSON Schema map |
| `:tool_context` | Caller context: `cmd(agent, signal, context: %{tenant_id: "acme"})`; tool Actions receive it |
| `:tool_timeout_ms`, `:stream_timeout_ms` | `limits.elapsed_ms` bounds the whole request |
| `:tool_max_retries`, `:tool_retry_backoff_ms` | Removed; a failed tool becomes a tool result the model can act on |
| `:request_policy` | Removed; an AgentServer runs one Turn at a time |
| `:request_transformer` | Removed; use `tool_policy`, `output_schema`, or your own Flow |
| `:effect_policy`, `:strategy_effect_policy` | Removed; see [Security and Portability](security-and-portability.md) |
| `:skills`, `:agent_skills` | Removed |
| `:observability` | `Jido.AI.Telemetry` |
| `:runtime_adapter`, `:runtime_task_supervisor` | Removed; Jido core owns processes |
| `:signal_routes` | Removed from the AI options; port routes with the Jido migration guide |

### Strategy Agents

Each V2 strategy Agent maps to a reasoning Flow:

| V2 | V3 `reasoning` |
| --- | --- |
| `Jido.AI.Agent` (ReAct) | `Jido.AI.Reasoning.ReAct` |
| `Jido.AI.CoTAgent` | `Jido.AI.Reasoning.ChainOfThought` |
| `Jido.AI.CoDAgent` | `Jido.AI.Reasoning.ChainOfDraft` |
| `Jido.AI.AoTAgent` | `Jido.AI.Reasoning.AlgorithmOfThoughts` |
| `Jido.AI.ToTAgent` | `Jido.AI.Reasoning.TreeOfThoughts` |
| `Jido.AI.GoTAgent` | `Jido.AI.Reasoning.GraphOfThoughts` |
| `Jido.AI.TRMAgent` | `Jido.AI.Reasoning.TRM` |
| `Jido.AI.AdaptiveAgent` | `Jido.AI.Reasoning.Adaptive` |

Only ReAct executes tools, and Adaptive can select ReAct. See
[Choose a Reasoning Flow](choose-a-reasoning-flow.md).

## Requests and Results

V2 generated `ask/3`, `ask_sync/3`, and `await/2` around a running server.
V3 builds a Signal and runs it like any other Jido route:

```elixir
agent = MyApp.SupportAgent.instantiate!(id: "support-1")
signal = MyApp.SupportAgent.request_signal!(%{input: "Where is order A-1001?"})

{:ok, agent, [%Jido.Agent.Directive.Reply{signal: reply}]} =
  MyApp.SupportAgent.cmd(agent, signal)

reply.type
# => "jido.ai.response"

reply.data.status
# => :completed
```

With a live process, `Jido.AgentServer.call(server, signal)` returns
`{:ok, committed, directives}` with the same reply. See
[Pure or Live Execution](pure-or-live-execution.md).

| V2 | V3 |
| --- | --- |
| `{:ok, answer}` | `reply.data.output` |
| `{:error, reason}` from a failed run | `reply.data.status` is `:failed` or `:blocked`; read `reason_code` and `reason` |
| `%Jido.AI.Request{id: ...}` | `reply.data.request_id` and `run_id` |
| `snapshot.result` | `reply.data.output` |
| `snapshot.details[:tool_results]` | `reply.data.tool_attempts` |
| `Jido.AI.Turn` | `reply.data.model_attempts` |
| State `:last_answer`, `:last_query`, `:requests`, `:completed` | State `:session`, a `Jido.Session` |
| Usage Signals | `reply.data.usage` and `reply.data.budget` |

### Per-Request Options

| V2 `ask/3` option | V3 request field |
| --- | --- |
| `allowed_tools: ["multiply"]` | `tool_policy: %{visible: ["multiply"]}` |
| `tools: [...]` (replace registry) | Removed; request data cannot add tools |
| `tool_context: %{...}` | `cmd/3` `context:` option |
| `llm_opts: [...]` | `options: %{...}` |
| `timeout:` | `limits.elapsed_ms` |

V3 also adds `tool_policy.hidden`, `tool_policy.review`,
`tool_policy.requirement`, `fallback_models`, and token and cost limits. See
[Public API Reference](public-api-reference.md) for every field.

### Runtime Tool Changes

V2 `Jido.AI.register_tool`, `unregister_tool`, `set_system_prompt`, and
`list_tools` are removed. The `tools` block is a fixed allowlist. A trusted
execution host adds runtime tools with `Jido.AI.ToolSource`. Send new
`instructions` with a request to change them for that request.

## Signals

| V2 Signal | V3 |
| --- | --- |
| `ai.react.query` | `jido.ai.request` |
| `ai.request.started` | Removed; `[:jido, :ai, :agent, :start]` telemetry |
| `ai.request.completed`, `ai.request.failed`, `ai.request.error` | `jido.ai.response` reply |
| `ai.llm.delta` | `jido.ai.model.stream.chunk` |
| `ai.llm.response` | `jido.ai.model.stream.completed` when streaming; `model_attempts` otherwise |
| `ai.tool.started`, `ai.tool.result` | `[:jido, :ai, :tool, ...]` telemetry and `tool_attempts` |
| `ai.usage` | `reply.data.usage` |
| `ai.embed.result` | The `Jido.AI.Actions.Embed` result |
| `ai.react.cancel`, `ai.react.steer`, `ai.react.inject` | Removed |
| `ai.react.register_tool`, `ai.react.set_system_prompt`, and other control Signals | Removed |

Tool review is new in V3: `jido.ai.review.requested`, `approved`, and
`denied`. See [Tool Review and Cycle Limits](tool-review-and-cycle-limits.livemd).

## Conversation State

V2 `Jido.AI.Context` appended messages and projected them with the system
prompt. V3 splits that work:

| V2 | V3 |
| --- | --- |
| `Context.new(system_prompt: ...)` | `instructions` on the reasoning Flow |
| `Context.append_user/2`, `append_assistant/2` | The Flow appends to `agent.state.session`; `Jido.AI.Thread.Projection.append/4` for your own entries |
| `Context.to_messages/1` | `Jido.AI.Thread.Projection.context/2` returns a `ReqLLM.Context` |
| Checkpoint stripping with `Jido.AI.Checkpoint` | The Session is portable data; AgentServer persistence saves it |

Projection keeps failed requests and incomplete tool exchanges out of later
prompts. See [Sessions and Threads](sessions-and-threads.md).

## Plugins and Actions

V2 shipped capability Plugins and many standalone Actions. V3 keeps one
Action:

| V2 | V3 |
| --- | --- |
| `Jido.AI.Actions.LLM.Embed`, `chat.embed` | `Jido.AI.Actions.Embed` |
| `Jido.AI.Actions.LLM.Chat`, `Complete`, `GenerateObject` | Removed; use an AI Agent or ReqLLM |
| `Jido.AI.Actions.ToolCalling.*` | Removed; ReAct runs tools |
| `Jido.AI.Actions.Reasoning.*`, `RunStrategy` | Removed; select a reasoning Flow |
| `Jido.AI.Actions.Planning.*` | Removed |
| `Jido.AI.Plugins.Chat` | Removed; use an AI Agent |
| `Jido.AI.Plugins.Reasoning.*` | Removed; select a reasoning Flow |
| `Jido.AI.Plugins.ModelRouting` | `model` and `fallback_models` |
| `Jido.AI.Plugins.Quota` and `Jido.AI.Actions.Quota.*` | Removed; `limits` bound tokens, cost, and calls for one request. Keep rolling quotas in your application |
| `Jido.AI.Plugins.Policy` | Removed; each Flow runs a built-in input guard, and `tool_policy` narrows tools |
| `Jido.AI.Plugins.Retrieval`, `Jido.AI.Actions.Retrieval.*` | Removed; apply retrieval with `Jido.AI.Context.transform/3` |
| `Jido.AI.Plugins.Planning`, `TaskSupervisor` | Removed |
| `Jido.AI.Skill` and Agent Skills | Removed |

## Other Removed APIs

| V2 | Status |
| --- | --- |
| V2 `Jido.AI.Reasoning.ReAct.run`, `stream`, `start`, `continue`, and checkpoint tokens | Removed; `Jido.AI.Reasoning.ReAct` is now a Flow module |
| V2 `Jido.AI.resolve_model`, `model_aliases`, and `llm_defaults` | Removed |
| `Jido.AI.Effects`, `Jido.AI.Output`, `Jido.AI.Observe` | Removed; `output_schema` and `Jido.AI.Telemetry` replace the last two |
| `Jido.AI.Directive.*` (`LLMGenerate`, `LLMStream`, `ToolExec`) | Removed; the Flow calls ReqLLM and runs tools |
| `Jido.AI.Test`, `Jido.AI.TestCase` | Removed; see [Test AI Agents](test-ai-agents.livemd) |
| CLI adapters and `mix jido_ai` | Removed |

## Telemetry

V2 emitted `[:jido, :ai, :request | :llm | :tool | :strategy | :output, ...]`.
V3 emits `[:jido, :ai, :agent, ...]`, `[:jido, :ai, :reasoning, ...]`, and
`[:jido, :ai, :tool, ...]`. ReqLLM owns model request events under
`[:req_llm, :request, ...]`. Attach to `Jido.AI.Telemetry.events/0` for the
complete list. See [Telemetry and Tracing](telemetry-and-tracing.livemd).

## Tests

V2 `expect_react` scripted the model inside the ReAct runtime. In V3, mock
`ReqLLM.generate_text/3` with Mimic and run the Agent with `cmd/3`:

```elixir
expect(ReqLLM, :generate_text, fn model, context, _options ->
  {:ok,
   %ReqLLM.Response{
     id: "resp-1",
     model: model,
     context: context,
     finish_reason: :stop,
     message: ReqLLM.Context.assistant("Order A-1001 shipped.")
   }}
end)
```

See [Test AI Agents](test-ai-agents.livemd) and
[Mock Model Calls with ReqLLM](mock-model-calls-with-reqllm.livemd).

## Port Order

1. Port Jido core, Actions, and Signals to V3.
2. Replace each AI Agent's `use` options with an `ai` block. Run `preflight/1`
   on your request shapes.
3. Replace `ask` and `await` calls with `request_signal!/1` and `cmd/3` or
   `Jido.AgentServer.call/3`. Read `reply.data`.
4. Move conversation code to `Jido.Session` and `Jido.AI.Thread.Projection`.
5. Replace removed Plugins and Actions using the tables above.
6. Replace V2 test helpers with ReqLLM mocks.
