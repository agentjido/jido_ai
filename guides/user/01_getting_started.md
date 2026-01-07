# Getting Started with Jido.AI

Welcome to Jido.AI! This guide will help you understand what Jido.AI is and how to start using it.

## What is Jido.AI?

Jido.AI is an AI agent framework that lets you build intelligent agents capable of:
- **Reasoning** through complex problems using various algorithms
- **Using tools** to interact with the world (APIs, databases, calculations)
- **Planning** and executing multi-step tasks autonomously

### Key Concepts

| Concept | Description |
|---------|-------------|
| **Agent** | An autonomous AI entity that uses strategies to accomplish goals |
| **Strategy** | The thinking pattern the agent uses (ReAct, Chain-of-Thought, etc.) |
| **Actions** | Tools the agent can call (calculator, search, database queries) |
| **Model** | The LLM that powers the agent (Claude, GPT-4, etc.) |

---

## Installation

Add Jido.AI to your `mix.exs`:

```elixir
def deps do
  [
    {:jido_ai, "~> 0.1"},
    {:req_llm, "~> 0.1"}  # Required for LLM integration
  ]
end
```

Then run:

```bash
mix deps.get
```

---

## Quick Example

Here's a simple agent that can use a calculator:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    # Use the ReAct strategy (reasons then acts)
    strategy: {
      Jido.AI.Strategies.ReAct,
      model: "anthropic:claude-haiku-4-5",
      # Tools the agent can use
      tools: [
        CalculatorAction,
        SearchAction
      ],
      max_iterations: 10
    }
end
```

Then use it:

```elixir
# Start the agent
{:ok, agent} = MyAgent.start_link()

# Ask a question
{:ok, response} = MyAgent.chat(agent, "What is 123 multiplied by 456?")
```

---

## Choosing a Strategy

Jido.AI includes several built-in strategies. Choose one based on your task:

### ReAct (Reason-Act) - *Default*

**Best for:** General tasks requiring reasoning and tool use

```
Question → Think → Use Tool → Think → Use Tool → Answer
```

```elixir
strategy: {Jido.AI.Strategies.ReAct, [
  model: "anthropic:claude-sonnet-4-20250514",
  tools: [Calculator, Weather, Search],
  max_iterations: 10
]}
```

### Chain-of-Thought (CoT)

**Best for:** Complex reasoning that benefits from step-by-step thinking

```
Question → Step 1 → Step 2 → Step 3 → Answer
```

```elixir
strategy: {Jido.AI.Strategies.ChainOfThought, [
  model: "anthropic:claude-sonnet-4-20250514"
]}
```

### Tree-of-Thoughts (ToT)

**Best for:** Problems with multiple possible solutions requiring exploration

```
Question → Branch 1 ┐
           → Branch 2 ├→ Best Solution
           → Branch 3 ┘
```

```elixir
strategy: {Jido.AI.Strategies.TreeOfThoughts, [
  model: "anthropic:claude-sonnet-4-20250514",
  max_depth: 3,
  branches: 3
]}
```

### Graph-of-Thoughts (GoT)

**Best for:** Complex problems where thoughts can be improved by combining them

```
Question → Thought A ──┐
           → Thought B ──┼── Combined → Improved → Answer
           → Thought C ──┘
```

```elixir
strategy: {Jido.AI.Strategies.GraphOfThoughts, [
  model: "anthropic:claude-sonnet-4-20250514",
  max_iterations: 5
]}
```

### TRM (Task-Resource-Model)

**Best for:** Tasks with clear structure and available resources

```elixir
strategy: {Jido.AI.Strategies.TRM, [
  model: "anthropic:claude-sonnet-4-20250514",
  resources: [Database, API]
]}
```

### Adaptive

**Best for:** When you want the system to choose the best strategy automatically

```elixir
strategy: {Jido.AI.Strategies.Adaptive, [
  model: "anthropic:claude-sonnet-4-20250514",
  available_strategies: [:react, :cot, :tot],
  tools: [Calculator, Search]
]}
```

---

## Setting Up API Keys

Jido.AI uses the `req_llm` library to connect to LLM providers. Set your API key:

```bash
# For Anthropic (Claude)
export ANTHROPIC_API_KEY="your_key_here"

# For OpenAI
export OPENAI_API_KEY="your_key_here"

# For Google
export GOOGLE_API_KEY="your_key_here"
```

Or configure in your application:

```elixir
# config/config.exs
config :jido_ai, :models,
  anthropic: [
    api_key: System.get_env("ANTHROPIC_API_KEY")
  ]
```

---

## Available Models

| Provider | Model String |
|----------|--------------|
| Anthropic | `anthropic:claude-haiku-4-5` |
| Anthropic | `anthropic:claude-sonnet-4-20250514` |
| OpenAI | `openai:gpt-4o` |
| OpenAI | `openai:gpt-4o-mini` |
| Google | `google:gemini-2.0-flash-exp` |

---

## Next Steps

- [Quick Start Guide](./02_quick_start.md) - Build your first useful agent
- [Strategies Guide](./03_strategies.md) - Deep dive into each strategy
- [Tools & Actions Guide](./04_tools_actions.md) - Creating and using tools
- [Examples](./05_examples.md) - Real-world agent examples
- [GEPA Guide](./06_gepa.md) - Optimize your prompts automatically

---

## Common Issues

### "API key not found"

Make sure your API key is set in the environment or config:

```bash
echo $ANTHROPIC_API_KEY  # Should show your key
```

### "Tool not found"

Ensure your tools are registered and available:

```elixir
Jido.AI.Tools.Registry.list_all()
# Should show your registered tools
```

### Agent stops after one iteration

Check your `max_iterations` setting:

```elixir
strategy: {Jido.AI.Strategies.ReAct, [
  max_iterations: 10  # Increase if needed
]}
```

---

## Getting Help

- Check the [Developer Guides](../developer/01_architecture_overview.md) for technical details
- See [Examples](./05_examples.md) for working code samples
- Review the [Strategies Guide](./03_strategies.md) for algorithm details
