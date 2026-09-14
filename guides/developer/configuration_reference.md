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

Use `Jido.AI.Agent` and the Spark DSL. The `use` options are core Agent options,
such as `name`, `description`, `metadata`, `max_state_size`, and `extensions`.
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
      end

      requests do
        mode(:session)
        on_busy(:reject)
        max_requests(100)
        streaming(true)
        steering(true)
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

## CLI Defaults

- `--type`: `react`
- supported values: `react | aot | cod | cot | tot | got | trm | adaptive`
- `--timeout`: `60_000`
- `--format`: `text`
