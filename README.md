# Jido.AI

**AI integration layer for the Jido ecosystem** - LLM orchestration and reasoning strategies for building intelligent agents in Elixir.

## Overview

Jido.AI provides a comprehensive toolkit for building intelligent agents with LLMs. It implements proven reasoning strategies for tool use, multi-step reasoning, and complex planning - all designed to get better results from language models.

```elixir
# Quick example: ReAct agent with tool use
defmodule MyApp.Agent do
  use Jido.AI.ReActAgent,
    name: "my_agent",
    tools: [MyApp.Actions.Calculator, MyApp.Actions.Search],
    model: :fast
end

{:ok, agent} = MyApp.Agent.start_link()
{:ok, response} = MyApp.Agent.chat(agent, "What is 15 * 23?")
```

## Installation

```elixir
def deps do
  [
    {:jido, "~> 2.0"},
    {:jido_ai, "~> 2.0"}
  ]
end
```

Configure your LLM provider (see [Configuration Guide](guides/developer/08_configuration.md)):

```elixir
# config/config.exs
config :jido_ai, :models,
  anthropic: [
    api_key: System.get_env("ANTHROPIC_API_KEY")
  ],
  openai: [
    api_key: System.get_env("OPENAI_API_KEY")
  ]
```

## Reasoning Strategies

Strategies are agent patterns that determine how an LLM approaches a problem. They are the foundation of building intelligent agents with Jido.AI.

| Strategy | Pattern | Best For | Guide |
|----------|---------|----------|-------|
| **ReAct** | Reason-Act loop | Tool-using agents | [Guide](guides/user/02_strategies.md#react-reason-act) |
| **Chain-of-Thought** | Sequential reasoning | Multi-step problems | [Guide](guides/user/02_strategies.md#chain-of-thought) |
| **Tree-of-Thoughts** | Explore multiple paths | Complex planning | [Guide](guides/user/02_strategies.md#tree-of-thoughts) |
| **Graph-of-Thoughts** | Networked reasoning | Interconnected concepts | [Guide](guides/user/02_strategies.md#graph-of-thoughts) |
| **Adaptive** | Strategy selection | Variable problem types | [Guide](guides/user/02_strategies.md#adaptive-strategy) |

**When to use which strategy:**
- **ReAct** - When your agent needs to use tools or APIs
- **Chain-of-Thought** - For multi-step reasoning and math problems
- **Tree-of-Thoughts** - When exploring multiple solution paths is beneficial
- **Graph-of-Thoughts** - For problems with interconnected concepts
- **Adaptive** - When you need dynamic strategy selection based on the problem

```elixir
# ReAct agent with tools
defmodule MyApp.Agent do
  use Jido.AI.ReActAgent,
    name: "my_agent",
    tools: [MyApp.Actions.Calculator, MyApp.Actions.Search],
    model: :fast
end

# Chain-of-Thought for step-by-step reasoning
{:ok, result} = Jido.AI.Strategies.ChainOfThought.run(
  "If 3 cats catch 3 mice in 3 minutes, how many cats are needed to catch 100 mice in 100 minutes?",
  model: :fast
)
```

---

## Documentation

### User Guides
- [Overview](guides/user/01_overview.md) - Library introduction and concepts
- [Strategies](guides/user/02_strategies.md) - Reasoning strategies

### Developer Guides
- [Architecture Overview](guides/developer/01_architecture_overview.md) - System design
- [Strategies](guides/developer/02_strategies.md) - Strategy implementation
- [State Machines](guides/developer/03_state_machines.md) - Pure state machine pattern
- [Directives](guides/developer/04_directives.md) - Declarative side effects
- [Signals](guides/developer/05_signals.md) - Event-driven communication
- [Tool System](guides/developer/06_tool_system.md) - Tool registry and execution
- [Skills](guides/developer/07_skills.md) - Modular agent capabilities
- [Configuration](guides/developer/08_configuration.md) - Model aliases and providers

### Examples
See the [`examples/`](examples/) directory for runnable code:
- [`examples/strategies/`](examples/strategies/) - Reasoning strategy examples

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

Apache-2.0 - See [LICENSE](LICENSE) for details.

---

**[Jido.AI Homepage](https://agentjido.xyz)** | **[GitHub](https://github.com/agentjido/jido_ai)** | **[Discord](https://agentjido.xyz/discord)**
