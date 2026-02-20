# Jido.AI

**AI integration layer for the Jido ecosystem** - LLM orchestration and reasoning strategies for building intelligent agents in Elixir.

## Overview

Jido.AI provides a comprehensive toolkit for building intelligent agents with LLMs. It implements proven reasoning strategies for tool use, multi-step reasoning, and complex planning - all designed to get better results from language models.

```elixir
# Quick example: `Jido.AI.Agent` with tool use
defmodule MyApp.Agent do
  use Jido.AI.Agent,
    name: "my_agent",
    tools: [MyApp.Actions.Calculator, MyApp.Actions.Search],
    model: :fast
end

{:ok, pid} = Jido.AgentServer.start(agent: MyApp.Agent)
{:ok, response} = MyApp.Agent.ask_sync(pid, "What is 15 * 23?")
```

## Installation

```elixir
def deps do
  [
    {:jido, "~> 2.0"},
    {:jido_ai, "~> 2.0.0-beta"}
  ]
end
```

Configure model aliases and LLM provider credentials (see [Configuration Reference](guides/developer/configuration_reference.md)):

```elixir
# config/config.exs
config :jido_ai,
  model_aliases: %{
    fast: "anthropic:claude-haiku-4-5",
    capable: "anthropic:claude-sonnet-4-20250514"
  }

config :req_llm,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  openai_api_key: System.get_env("OPENAI_API_KEY")
```

## Reasoning Strategies

Strategies are agent patterns that determine how an LLM approaches a problem. They are the foundation of building intelligent agents with Jido.AI.

| Strategy | Pattern | Best For |
|----------|---------|----------|
| **ReAct** | Reason-Act loop | Tool-using agents |
| **Chain-of-Thought** | Sequential reasoning | Multi-step problems |
| **Tree-of-Thoughts** | Explore multiple paths | Complex planning |
| **Graph-of-Thoughts** | Networked reasoning | Interconnected concepts |
| **Adaptive** | Strategy selection | Variable problem types |

**When to use which strategy:**
- **ReAct** - When your agent needs to use tools or APIs
- **Chain-of-Thought** - For multi-step reasoning and math problems
- **Tree-of-Thoughts** - When exploring multiple solution paths is beneficial
- **Graph-of-Thoughts** - For problems with interconnected concepts
- **Adaptive** - When you need dynamic strategy selection based on the problem

```elixir
# `Jido.AI.Agent` with tools
defmodule MyApp.Agent do
  use Jido.AI.Agent,
    name: "my_agent",
    tools: [MyApp.Actions.Calculator, MyApp.Actions.Search],
    model: :fast
end

# Chain-of-Thought agent for step-by-step reasoning
defmodule MyApp.Reasoner do
  use Jido.AI.CoTAgent,
    name: "reasoner",
    model: :fast
end

{:ok, pid} = Jido.AgentServer.start(agent: MyApp.Reasoner)
{:ok, result} = MyApp.Reasoner.think_sync(pid, "Solve: 3 cats catch 3 mice in 3 minutes...")
```

---

## Documentation

### Build With Jido.AI
- [Package Overview (Production Map)](guides/user/package_overview.md) - Prioritized feature map and runtime architecture
- [Migration Guide: Plugins And Signals (v2 -> v3)](guides/user/migration_plugins_and_signals_v3.md) - Breaking-change module/signal mapping
- [Getting Started](guides/user/getting_started.md) - First working agent in minutes
- [Strategy Selection Playbook](guides/user/strategy_selection_playbook.md) - Choose CoT/ReAct/ToT/GoT/TRM/Adaptive
- [First Agent](guides/user/first_react_agent.md) - Tool-using `Jido.AI.Agent` with request handles
- [Request Lifecycle And Concurrency](guides/user/request_lifecycle_and_concurrency.md) - `ask/await` and concurrent safety
- [Thread Context And Message Projection](guides/user/thread_context_and_message_projection.md) - Multi-turn context management
- [Tool Calling With Actions](guides/user/tool_calling_with_actions.md) - Adapt `Jido.Action` modules as tools
- [Observability Basics](guides/user/observability_basics.md) - Telemetry events and normalization
- [CLI Workflows](guides/user/cli_workflows.md) - Interactive, one-shot, and batch CLI usage

### Extend Jido.AI
- [Architecture And Runtime Flow](guides/developer/architecture_and_runtime_flow.md) - Query to runtime lifecycle
- [Strategy Internals](guides/developer/strategy_internals.md) - Extending strategy adapters safely
- [Directives Runtime Contract](guides/developer/directives_runtime_contract.md) - Runtime side-effect semantics
- [Signals, Namespaces, Contracts](guides/developer/signals_namespaces_contracts.md) - Canonical event contracts
- [Plugins And Actions Composition](guides/developer/plugins_and_actions_composition.md) - Lifecycle and action composition
- [Skills System](guides/developer/skills_system.md) - Load/register/use skills
- [Security And Validation](guides/developer/security_and_validation.md) - Input and error hardening
- [Error Model And Recovery](guides/developer/error_model_and_recovery.md) - Retry and failure policy

### Reference
- [Actions Catalog](guides/developer/actions_catalog.md) - Built-in action inventory
- [Configuration Reference](guides/developer/configuration_reference.md) - Defaults and config keys

### Examples
- [`examples/strategies/react_agent.md`](examples/strategies/react_agent.md) - ReAct strategy example
- [`examples/strategies/chain_of_thought.md`](examples/strategies/chain_of_thought.md) - Chain-of-Thought example
- [`examples/strategies/tree_of_thoughts.md`](examples/strategies/tree_of_thoughts.md) - Tree-of-Thoughts example
- [`examples/strategies/adaptive_strategy.md`](examples/strategies/adaptive_strategy.md) - Adaptive strategy example

## ReAct Production Defaults

Use these references as the production baseline for ReAct:
- [`lib/jido_ai/agents/examples/weather_agent.ex`](lib/jido_ai/agents/examples/weather_agent.ex)
- [`examples/strategies/react_agent.md`](examples/strategies/react_agent.md)

## Quick Decision Guide

Not sure which technique to use? Start here:

```
Building an agent?
├─ Need to use tools/APIs?
│  └─ Use ReAct Strategy
├─ Multi-step reasoning?
│  └─ Use Chain-of-Thought
└─ Complex planning?
   └─ Use Tree-of-Thoughts
```

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

Apache-2.0 - See [LICENSE.md](LICENSE.md) for details.

---

**[Jido.AI Homepage](https://agentjido.xyz)** | **[GitHub](https://github.com/agentjido/jido_ai)** | **[Discord](https://agentjido.xyz/discord)**
