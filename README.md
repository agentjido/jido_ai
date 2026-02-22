# Jido.AI

[![Hex.pm](https://img.shields.io/hexpm/v/jido_ai.svg)](https://hex.pm/packages/jido_ai)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/jido_ai/)
[![CI](https://github.com/agentjido/jido_ai/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/jido_ai/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/jido_ai.svg)](https://github.com/agentjido/jido_ai/blob/main/LICENSE.md)
[![Coverage Status](https://coveralls.io/repos/github/agentjido/jido_ai/badge.svg?branch=main)](https://coveralls.io/github/agentjido/jido_ai?branch=main)

Build tool-using Elixir agents with explicit reasoning strategies and production-ready request orchestration.

[Hex](https://hex.pm/packages/jido_ai) | [HexDocs](https://hexdocs.pm/jido_ai) | [Jido Ecosystem](https://agentjido.xyz) | [Discord](https://agentjido.xyz/discord)

`jido_ai` is the AI runtime layer for Jido. You define tools and agents as Elixir modules, then run synchronous or asynchronous requests with built-in model routing, retries, and observability.

```elixir
defmodule MyApp.Actions.AddNumbers do
  use Jido.Action,
    name: "add_numbers",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  @impl true
  def run(%{a: a, b: b}, _context), do: {:ok, %{sum: a + b}}
end

defmodule MyApp.MathAgent do
  use Jido.AI.Agent,
    name: "math_agent",
    model: :fast,
    tools: [MyApp.Actions.AddNumbers],
    system_prompt: "Solve accurately. Use tools for arithmetic."
end

{:ok, pid} = Jido.AgentServer.start(agent: MyApp.MathAgent)
{:ok, answer} = MyApp.MathAgent.ask_sync(pid, "What is 19 + 23?")
```

## Where This Package Fits

`jido_ai` is a **core package** in the Jido ecosystem:

- [jido](https://hex.pm/packages/jido): agent runtime, process model, and signal lifecycle
- [jido_action](https://hex.pm/packages/jido_action): typed tool/action contract used by `jido_ai`
- [req_llm](https://hex.pm/packages/req_llm): provider abstraction for Anthropic, OpenAI, Google, and others

Use `jido_ai` when you need long-lived agents, tool-calling loops, or explicit reasoning strategies. You can also use it without a running agent process via `Jido.AI.generate_text/2`, `Jido.AI.ask/2`, or `Jido.Exec.run/3` with any action module.  
For cross-package tutorials (for example `jido` + `jido_ai` + app packages), see [agentjido.xyz](https://agentjido.xyz).

## Installation

```elixir
def deps do
  [
    {:jido, "~> 2.0"},
    {:jido_ai, "~> 2.0.0-rc.0"}
  ]
end
```

```bash
mix deps.get
```

Configure model aliases and at least one provider credential:

```elixir
# config/config.exs
config :jido_ai,
  model_aliases: %{
    fast: "provider:fast-model",
    capable: "provider:capable-model"
  }

config :req_llm,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  openai_api_key: System.get_env("OPENAI_API_KEY")
```

## Quick Start

1. Define one `Jido.Action` tool.
2. Define one `Jido.AI.Agent` with that tool.
3. Start the agent and call `ask_sync/3` or `ask/3` + `await/2`.

```elixir
defmodule MyApp.Actions.Multiply do
  use Jido.Action,
    name: "multiply",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  @impl true
  def run(%{a: a, b: b}, _context), do: {:ok, %{product: a * b}}
end

defmodule MyApp.Agent do
  use Jido.AI.Agent,
    name: "my_agent",
    model: :fast,
    tools: [MyApp.Actions.Multiply]
end

{:ok, pid} = Jido.AgentServer.start(agent: MyApp.Agent)

# Sync convenience path
{:ok, result} = MyApp.Agent.ask_sync(pid, "What is 15 * 23?")

# Async path with explicit request handle
{:ok, request} = MyApp.Agent.ask(pid, "What is 144 * 12?")
{:ok, result2} = MyApp.Agent.await(request, timeout: 15_000)
```

Need one-shot text generation without an agent process?

```elixir
{:ok, text} = Jido.AI.ask("Summarize Phoenix PubSub in one paragraph.", model: :fast)
```

## Choose Your Integration Surface

| If you need | Use | Why |
|---|---|---|
| Tool-using agent loops | `Jido.AI.Agent` | ReAct strategy with request tracking and tool orchestration |
| Fixed reasoning strategy | `Jido.AI.CoDAgent`, `Jido.AI.CoTAgent`, `Jido.AI.AoTAgent`, `Jido.AI.ToTAgent`, `Jido.AI.GoTAgent`, `Jido.AI.TRMAgent`, `Jido.AI.AdaptiveAgent` | Strategy-specific control over reasoning behavior |
| AI inside existing workflows/jobs | `Jido.AI.Actions.*` | Run via `Jido.Exec.run/3` without defining an agent module |
| Streaming + checkpoint/resume | `Jido.AI.Reasoning.ReAct` | Standalone ReAct runtime with event streams and checkpoint tokens |
| Thin model facade helpers | `Jido.AI.generate_text/2`, `generate_object/3`, `stream_text/2`, `ask/2` | Fast path for direct LLM calls with alias/default support |

## Strategy Quick Pick

- **ReAct (`Jido.AI.Agent`)**: default for tool/API calls.
- **CoD (`Jido.AI.CoDAgent`)**: concise reasoning with lower latency/cost.
- **Chain-of-Thought (CoT) (`Jido.AI.CoTAgent`)**: asks the model to reason through a problem in explicit intermediate steps before the final answer; useful for math, logic, and other multi-step tasks.
- **AoT (`Jido.AI.AoTAgent`)**: one-pass algorithmic exploration with explicit final answer extraction.
- **ToT / GoT (`Jido.AI.ToTAgent`, `Jido.AI.GoTAgent`)**: branching or graph-style exploration for complex tasks.
- **TRM (`Jido.AI.TRMAgent`)**: iterative recursive refinement.
- **Adaptive (`Jido.AI.AdaptiveAgent`)**: mixed workloads where strategy selection varies per task.

Full tradeoff matrix: [Strategy Selection Playbook](guides/user/strategy_selection_playbook.md)

## Common First-Run Errors

**`Unknown model alias: :my_model`**
- Add the alias under `config :jido_ai, model_aliases: ...`
- Or pass a direct model string (for example `"provider:exact-model-id"`)

**`{:error, :not_a_tool}` when registering or calling tools**
- Ensure your tool module implements `name/0`, `schema/0`, and `run/2`
- Validate with `Jido.AI.register_tool(pid, MyToolModule)`

## Documentation

- [HexDocs](https://hexdocs.pm/jido_ai) — Full API reference and guides
- [agentjido.xyz](https://agentjido.xyz) — Ecosystem overview and cross-package tutorials

### Documentation Map

Start here:
- [Package Overview](guides/user/package_overview.md)
- [Getting Started](guides/user/getting_started.md)
- [First Agent](guides/user/first_react_agent.md)

Strategy guides:
- [Strategy Selection Playbook](guides/user/strategy_selection_playbook.md)
- [Strategy Recipes](guides/user/strategy_recipes.md)
- [Model Routing And Policy](guides/user/model_routing_and_policy.md)

Integration and runtime guides:
- [LLM Facade Quickstart](guides/user/llm_facade_quickstart.md)
- [Tool Calling With Actions](guides/user/tool_calling_with_actions.md)
- [Thread Context And Message Projection](guides/user/thread_context_and_message_projection.md)
- [Turn And Tool Results](guides/user/turn_and_tool_results.md)
- [Request Lifecycle And Concurrency](guides/user/request_lifecycle_and_concurrency.md)
- [Retrieval And Quota](guides/user/retrieval_and_quota.md)
- [Observability Basics](guides/user/observability_basics.md)
- [Standalone ReAct Runtime](guides/user/standalone_react_runtime.md)
- [CLI Workflows](guides/user/cli_workflows.md)

Upgrading:
- [Migration: Plugins And Signals v3](guides/user/migration_plugins_and_signals_v3.md)

Deep reference:
- [Actions Catalog](guides/developer/actions_catalog.md)
- [Configuration Reference](guides/developer/configuration_reference.md)
- [Architecture And Runtime Flow](guides/developer/architecture_and_runtime_flow.md)
- [HexDocs](https://hexdocs.pm/jido_ai)

## Runnable Examples

Run local demos from the repository root:

```bash
mix run lib/examples/scripts/demo/actions_llm_runtime_demo.exs
mix run lib/examples/scripts/demo/actions_tool_calling_runtime_demo.exs
mix run lib/examples/scripts/demo/actions_reasoning_runtime_demo.exs
mix run lib/examples/scripts/demo/weather_multi_turn_context_demo.exs
```

Additional examples:
- [`lib/examples/agents/weather_agent.ex`](https://github.com/agentjido/jido_ai/blob/main/lib/examples/agents/weather_agent.ex)
- [`lib/examples/agents/react_demo_agent.ex`](https://github.com/agentjido/jido_ai/blob/main/lib/examples/agents/react_demo_agent.ex)
- [`lib/examples/tools/weather_by_location.ex`](https://github.com/agentjido/jido_ai/blob/main/lib/examples/tools/weather_by_location.ex)

## Why Jido.AI

- ReAct-first agent runtime with explicit request handles — `ask/await` prevents concurrent result overwrites
- Eight built-in reasoning strategy families (ReAct, CoD, CoT, AoT, ToT, GoT, TRM, Adaptive)
- Unified tool contract via `Jido.Action` modules with compile-time safety
- Strategy-independent `Actions` API for direct integration with `Jido.Exec`
- Stable telemetry event names via `Jido.AI.Observe` for production dashboards
- Policy and quota plugins rewrite unsafe or over-budget requests deterministically

## Contributing

See [CONTRIBUTING.md](https://github.com/agentjido/jido_ai/blob/main/CONTRIBUTING.md).

## License

Apache-2.0. See [LICENSE.md](LICENSE.md).
