# Jido.AI

[![Hex.pm](https://img.shields.io/hexpm/v/jido_ai.svg)](https://hex.pm/packages/jido_ai)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/jido_ai/)
[![CI](https://github.com/agentjido/jido_ai/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/jido_ai/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/jido_ai.svg)](https://github.com/agentjido/jido_ai/blob/main/LICENSE)
[![Website](https://img.shields.io/badge/website-jido.run-0f172a.svg)](https://jido.run)
[![Ecosystem](https://img.shields.io/badge/ecosystem-jido.run-0ea5e9.svg)](https://jido.run/ecosystem)
[![Discord](https://img.shields.io/badge/discord-join-5865F2.svg?logo=discord&logoColor=white)](https://jido.run/discord)

Build tool-using Elixir agents with explicit reasoning strategies and request orchestration.

This `v3-spike` branch has a working V3 implementation with automated authoring
and example tests. It is not yet a verified stable V3 release. See the
[conversation architecture guide](guides/user/thread_context_and_message_projection.md) and
[example capabilities](examples/README.md#what-the-examples-can-do).

[Hex](https://hex.pm/packages/jido_ai) | [HexDocs](https://hexdocs.pm/jido_ai) | [Jido Ecosystem](https://jido.run/ecosystem) | [Discord](https://jido.run/discord)

`jido_ai` is the AI runtime layer for Jido. You define tools and agents as Elixir modules, then run synchronous or asynchronous requests with built-in model routing, retries, and observability.

```elixir
defmodule MyApp.Actions.AddNumbers do
  use Jido.Action,
    name: "add_numbers",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()}),
    description: "Add two numbers."

  @impl true
  def run(%{a: a, b: b}, _context), do: {:ok, %{sum: a + b}}
end

defmodule MyApp.MathAgent do
  use Jido.AI.Agent, name: "math_agent"

  agent do
    schema Zoi.object(%{answer: Zoi.any() |> Zoi.default(nil)})

    ai :assistant do
      instructions("Solve accurately. Use tools for arithmetic.")

      models do
        model(:answer, :fast)
      end

      reasoning :react do
        model(:answer)
      end

      tools do
        action(MyApp.Actions.AddNumbers, as: :add_numbers)
      end

      requests do
        mode(:session)
        streaming(true)
      end

      result(nil, into: :answer)
    end
  end

  routes do
    route("ai.ask", ai(:assistant))
  end
end

{:ok, pid} = Jido.AgentServer.start(agent: MyApp.MathAgent)
{:ok, answer} = MyApp.MathAgent.ask_sync(pid, "What is 19 + 23?")
```

## Where This Package Fits

`jido_ai` is a **core package** in the Jido ecosystem:

- [jido](https://hex.pm/packages/jido): agent runtime, process model, and signal lifecycle
- [jido_action](https://hex.pm/packages/jido_action): typed tool/action contract used by `jido_ai`
- [req_llm](https://hex.pm/packages/req_llm): provider abstraction for Anthropic, OpenAI, Google, and others

Use `jido_ai` when you need long-lived agents, tool-calling loops, or explicit reasoning strategies. For direct model calls, resolve an optional application alias with `Jido.AI.Models.resolve/1`, then use ReqLLM. You can also use `Jido.Exec.run/3` with any action module.
For cross-package tutorials and the package map, see [jido.run/ecosystem](https://jido.run/ecosystem).

In `jido_ai`, tool actions are allowed to be effectful. They often perform HTTP, LLM, database, or file I/O because the model needs the result back in the same ReAct loop.

The purity boundary lives around agent strategy decisions and runtime orchestration, not necessarily inside each tool action. Use a tool action when the next reasoning step needs the result now. Use directives, signals, or runtime integrations when an outbound effect has already been decided and the runtime should own delivery, retry, and observability.

## Installation

### Igniter Installation (Recommended)

The fastest way to get started is with [Igniter](https://hex.pm/packages/igniter):

```bash
mix igniter.install jido_ai
```

This automatically:
- Adds `jido_ai` to your dependencies
- Configures default model aliases
- Reminds you to set up API keys

### Manual Installation

Add `jido_ai` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido, "~> 3.0"},
    {:jido_ai, "~> 3.0"}
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
  use Jido.AI.Agent, name: "my_agent"

  agent do
    schema Zoi.object(%{answer: Zoi.any() |> Zoi.default(nil)})

    ai :assistant do
      models do
        model(:answer, :fast)
      end

      reasoning :react do
        model(:answer)
      end

      tools do
        action(MyApp.Actions.Multiply, as: :multiply)
      end

      requests do
        mode(:session)
      end

      result(nil, into: :answer)
    end
  end

  routes do
    route("ai.ask", ai(:assistant))
  end
end

{:ok, pid} = Jido.AgentServer.start(agent: MyApp.Agent)

# Sync convenience path
{:ok, result} = MyApp.Agent.ask_sync(pid, "What is 15 * 23?")

# Async path with explicit request handle
{:ok, request} = MyApp.Agent.ask(pid, "What is 144 * 12?")
{:ok, result2} = MyApp.Agent.await(request, timeout: 15_000)
```

## Request-Scoped ReAct Controls

`ask/3` and `ask_sync/3` can narrow or override the active tool registry for a single run:

```elixir
{:ok, result} =
  MyApp.Agent.ask_sync(pid, "Multiply 15 by 23",
    allowed_tools: ["multiply"],
    tool_context: %{tenant_id: "acme"},
    llm_opts: [reasoning_effort: :medium]
  )
```

- `allowed_tools:` filters the agent's configured tools by name for one request.
- `tools:` replaces the tool registry for one request.
- `request_transformer:` lets you reshape each LLM turn, including dynamic tool gating and structured-output schemas.

After a ReAct run, `snapshot.result` is the final assistant answer. Completed
tool outputs are available separately through
`snapshot.details[:tool_results]`, so callers do not need to parse conversation
messages or request traces to recover structured tool data.

For retrieval or classification flows, prefer having tools write `StateOp.SetState` updates and let a `request_transformer` read `context[:state]` to constrain the next turn. That keeps tool exposure, runtime state, and output schemas aligned without scraping message history. See [Standalone ReAct Runtime](guides/user/standalone_react_runtime.md) for the pattern.

Need one-shot text generation without an agent process?

```elixir
model = Jido.AI.Models.resolve(:fast)
{:ok, response} = ReqLLM.generate_text(model, "Summarize Phoenix PubSub in one paragraph.")
text = ReqLLM.Response.text(response)
```

## Choose Your Integration Surface

| If you need | Use | Why |
|---|---|---|
| Tool-using agent loops | `Jido.AI.Agent` with `reasoning :react` | Request tracking and tool orchestration |
| Fixed reasoning method | `Jido.AI.Agent` with a declared `reasoning` method | One authoring form for all reasoning behavior |
| AI inside existing workflows/jobs | `Jido.AI.Actions.*` | Run via `Jido.Exec.run/3` without defining an agent module |
| Streaming + checkpoint/resume | `Jido.AI.Reasoning.ReAct` | Standalone ReAct runtime with event streams and checkpoint tokens |
| Direct model calls | `Jido.AI.Models.resolve/1` and ReqLLM | Optional application aliases with the native model API |

## Strategy Quick Pick

- **ReAct (`:react`)**: default for tool and API calls.
- **CoD (`:chain_of_draft`)**: concise reasoning with lower latency and cost.
- **CoT (`:chain_of_thought`)**: linear, multi-step reasoning.
- **AoT (`:algorithm_of_thoughts`)**: one-pass algorithmic exploration.
- **ToT / GoT (`:tree_of_thoughts`, `:graph_of_thoughts`)**: branching or graph exploration.
- **TRM (`:trm`)**: iterative recursive refinement.
- **Adaptive (`:adaptive`)**: per-request method selection.

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
- [Jido Ecosystem](https://jido.run/ecosystem) — Ecosystem overview and cross-package tutorials
- [Discord](https://jido.run/discord) — Community discussion

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
- [Context And Message Projection](guides/user/thread_context_and_message_projection.md)
- [Turn And Tool Results](guides/user/turn_and_tool_results.md)
- [Request Lifecycle And Concurrency](guides/user/request_lifecycle_and_concurrency.md)
- [Retrieval And Quota](guides/user/retrieval_and_quota.md)
- [Observability Basics](guides/user/observability_basics.md)
- [Standalone ReAct Runtime](guides/user/standalone_react_runtime.md)

Upgrading:
- [Migration: Plugins And Signals v3](guides/user/migration_plugins_and_signals_v3.md)

Deep reference:
- [Actions Catalog](guides/developer/actions_catalog.md)
- [Configuration Reference](guides/developer/configuration_reference.md)
- [Architecture And Runtime Flow](guides/developer/architecture_and_runtime_flow.md)
- [Thread-Context Projection Model](guides/developer/thread_context_projection_model.md)
- [HexDocs](https://hexdocs.pm/jido_ai)

## Runnable Examples

The checked [example catalog](examples/README.md) uses real Jido AI features
with a deterministic local model server. Example tests are skipped by default.

```bash
mix test
mix examples --seed 0
```

Production builds compile `lib/` only. Development and test builds also compile
the checked example modules.

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

Apache-2.0. See [LICENSE](LICENSE).
