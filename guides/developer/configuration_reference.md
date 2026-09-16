# Configuration Reference

## Model Aliases

Model aliases are global application configuration. `Jido.AI.Models` only
resolves these aliases and direct ReqLLM or LLMDB model values.

```elixir
config :jido_ai,
  model_aliases: %{
    fast: "provider:fast-model",
    capable: "provider:capable-model",
    reasoning: "provider:reasoning-model"
  }
```

Application aliases merge over the package baseline.

## Agent Configuration

Use `Jido.AI.Agent` and the Spark DSL. The `use` options include core Agent options,
such as `name`, `description`, `metadata`, and `extensions`. The AI wrapper also
accepts `max_state_size` as a positive byte limit on the complete Agent state,
including Plugin-owned fields. It works with keyword or block metadata.
Construction and state updates enforce the limit; failed updates do not commit.
AI configuration belongs in an `ai` block.

```elixir
defmodule MyApp.Assistant do
  use Jido.AI.Agent, name: "assistant"

  agent do
    schema Zoi.object(%{answer: Zoi.any() |> Zoi.default(nil)})

    ai :assistant do
      instructions("Answer accurately.")

      models do
        model :answer, :fast do
          generation(temperature: 0.2, max_tokens: 1024)
        end
      end

      reasoning :react do
        model(:answer)
        tool_concurrency(1)
      end

      controls do
        max_iterations(8)
        max_model_calls(12)
        max_tool_calls(16)
        timeout(60_000)
        steering true
        idle_timeout 0
        tool_heartbeat 0
      end

      result(nil, into: :answer)
    end
  end

  routes do
    route("ai.ask", ai(:assistant))
  end
end
```

Agent construction validates and lowers this data. It does not call a model or
a tool.

There is no `requests` block or Profile field. Steering and activity timers
belong in `controls`. `steering` defaults to `false`. Timer values are
nonnegative milliseconds: `idle_timeout: 0` selects the automatic inactivity
limit, and `tool_heartbeat: 0` disables tool heartbeats.

Streaming is selected for each call. `ask/3` and `ask_sync/3` default to
buffered model calls. `ask_stream/3` selects provider streaming and returns an
event enumerable. A `stream_to` sink also selects provider streaming unless
the caller sets `stream: false` to receive lifecycle events only. Use
`stream: true` to select provider streaming without an event sink.

## Host Request Retention

Configure retained request records on the host, not on each Profile:

```elixir
config :jido_ai, :max_retained_requests, 100
```

The limit must be a positive integer. Each Coordinator captures it at startup.
Changing application configuration does not change an existing Coordinator.
Pending records are kept; older terminal records are removed first. This limit
does not control concurrency or retained Session/Thread Context. Each Agent
accepts one active AI request and rejects a second request with `:busy`.

## Portable Models and Dynamic Tool Sources

Public `Jido.AI.export/3` supports model IDs and aliases. For a rich model record,
it returns a structured validation error. Rich-model export is out of scope.
Core `Jido.Agent.Codec` has no model-specific export format: it encodes a
registered struct as a value reference. The receiving host must supply the
actual record in its Registry. The document does not contain the model record.

Dynamic tool-source declarations can be authored and transported, but native
AI routes do not resolve them yet. Selecting a profile with these sources
returns a `tool_sources` validation error before model work starts.
Supply resolved static tools for native execution.
The runtime does not silently omit optional or required sources.

## Reasoning Methods

Supported method values are:

- `:react`
- `:chain_of_draft`
- `:chain_of_thought`
- `:algorithm_of_thoughts`
- `:tree_of_thoughts`
- `:graph_of_thoughts`
- `:trm`
- `:adaptive`

Method-specific settings belong in `options(...)` inside the reasoning block.
Adaptive settings include `available_strategies`, `complexity_thresholds`,
`strategy_override`, and `method_options`. Adaptive has no `default_strategy`
setting.

Only ReAct accepts steering. ReAct and Tree of Thoughts can execute tools.

## Request Overrides

A request can supply its model and provider resources through caller context.
Supported request options include `model`, `tools`, `allowed_tools`,
`request_transformer`, `max_iterations`, `stream_timeout_ms`,
`tool_heartbeat_ms`, `tool_context`, `req_http_options`, and `llm_opts`.

`max_iterations` and `max_model_calls` are independent controls.

The standalone ReAct adapter retains its own `Config.streaming` option. That
value configures an invocation of the adapter; it is not Profile policy.
