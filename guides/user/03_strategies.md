# Strategies Guide

Jido.AI includes multiple reasoning strategies (algorithms) that determine how your agent thinks and solves problems. This guide explains each strategy and when to use it.

## Strategy Comparison

| Strategy | Best For | Tool Use | Complexity | Speed |
|----------|----------|----------|------------|-------|
| **ReAct** | General tasks | ✅ | Medium | Fast |
| **Chain-of-Thought** | Complex reasoning | ❌ | Low | Fastest |
| **Tree-of-Thoughts** | Multiple solutions | ✅ | High | Slow |
| **Graph-of-Thoughts** | Combining ideas | ✅ | High | Slowest |
| **TRM** | Structured tasks | ✅ | Medium | Medium |
| **Adaptive** | Auto-selection | ✅ | High | Variable |

---

## Decision Tree

```
Start
 │
 ├─ Need tools (API calls, calculations)?
 │  ├─ Yes → ReAct (most common)
 │  └─ No → Continue
 │
 ├─ Multiple possible solutions?
 │  ├─ Yes → Tree-of-Thoughts
 │  └─ No → Continue
 │
 ├─ Need to combine/improve ideas?
 │  ├─ Yes → Graph-of-Thoughts
 │  └─ No → Continue
 │
 ├─ Simple reasoning needed?
 │  ├─ Yes → Chain-of-Thought
 │  └─ No → Continue
 │
 └─ Not sure which to pick?
    └─ Adaptive (lets AI decide)
```

---

## 1. ReAct (Reason-Act)

**The "Think, Then Act" Strategy**

ReAct is the most commonly used strategy. It alternates between:
1. **Thinking** about what to do
2. **Acting** by calling tools
3. **Observing** the results
4. Repeating until done

### When to Use

- ✅ General-purpose tasks
- ✅ Tasks requiring tools (APIs, databases)
- ✅ Multi-step problems
- ✅ When you need to see the agent's reasoning

### Example

```elixir
defmodule ResearchAgent do
  use Jido.Agent,
    name: "researcher",
    strategy: {
      Jido.AI.Strategies.ReAct,
      model: "anthropic:claude-sonnet-4-20250514",
      tools: [SearchAction, CalculatorAction, DatabaseAction],
      max_iterations: 10
    }

  @impl true
  def system_prompt do
    """
    You are a research assistant. Use the search tool to find information
    and the calculator to analyze data.
    """
  end
end
```

### Sample Execution

```
User: "What's the population of Tokyo plus the population of Delhi?"

Agent: "I need to find the populations of both cities."
        → Calls search tool for Tokyo
        → Observes: "Tokyo: 37 million"

Agent: "Now I need Delhi's population."
        → Calls search tool for Delhi
        → Observes: "Delhi: 32 million"

Agent: "I'll add these numbers."
        → Calls calculator: 37 + 32
        → Observes: 69

Agent: "The combined population is 69 million."
```

### Configuration Options

```elixir
strategy: {Jido.AI.Strategies.ReAct, [
  model: "anthropic:claude-sonnet-4-20250514",  # Required
  tools: [...],                                   # Required
  max_iterations: 10,                             # Default: 10
  temperature: 0.7,                               # Default: 0.7
  system_prompt: "Custom prompt..."              # Optional override
]}
```

---

## 2. Chain-of-Thought (CoT)

**The "Step-by-Step" Strategy**

CoT forces the model to think through problems step by step before answering. It doesn't use tools but excels at reasoning.

### When to Use

- ✅ Math problems
- ✅ Logic puzzles
- ✅ Multi-step reasoning without external data
- ❌ Tasks requiring API calls or tools

### Example

```elixir
defmodule LogicPuzzleAgent do
  use Jido.Agent,
    name: "logic_solver",
    strategy: {
      Jido.AI.Strategies.ChainOfThought,
      model: "anthropic:claude-sonnet-4-20250514"
    }

  @impl true
  def system_prompt do
    """
    You solve logic puzzles by thinking through them carefully.
    Show your work step by step.
    """
  end
end
```

### Sample Execution

```
User: "If all Bloops are Razzies and all Razzies are Lazzies,
       are all Bloops definitely Lazzies?"

Agent: "Let me think step by step:

        Step 1: All Bloops are Razzies (given)
        Step 2: All Razzies are Lazzies (given)
        Step 3: If B → R and R → L, then B → L (transitive property)
        Step 4: Therefore, all Bloops are Lazzies.

        Answer: YES"
```

---

## 3. Tree-of-Thoughts (ToT)

**The "Explore Possibilities" Strategy**

ToT explores multiple solution paths in parallel, like branches of a tree, then selects the best one.

### When to Use

- ✅ Problems with multiple valid approaches
- ✅ Creative tasks (writing, brainstorming)
- ✅ Decision making under uncertainty
- ✅ When you want to compare alternatives

### Example

```elixir
defmodule CreativeAgent do
  use Jido.Agent,
    name: "creative_writer",
    strategy: {
      Jido.AI.Strategies.TreeOfThoughts,
      model: "anthropic:claude-sonnet-4-20250514",
      max_depth: 3,      # How deep to explore
      branches: 3,       # How many options to consider
      selection: :best   # How to pick the final answer
    }

  @impl true
  def system_prompt do
    """
    You are a creative writer. Explore different approaches
    and pick the most compelling one.
    """
  end
end
```

### Sample Execution

```
User: "Write a slogan for a coffee shop"

Branch 1: "Wake Up to Perfection" → Score: 7/10
Branch 2: "Brewed for Brilliance" → Score: 8/10
Branch 3: "Your Daily Inspiration" → Score: 6/10

Best: "Brewed for Brilliance"
```

### Configuration Options

```elixir
strategy: {Jido.AI.Strategies.TreeOfThoughts, [
  model: "anthropic:claude-sonnet-4-20250514",
  max_depth: 3,           # Max levels of thinking (default: 3)
  branches: 3,            # Options to explore (default: 3)
  selection: :best,       # :best, :vote, or :random
  pruning: true,          # Eliminate bad paths early
  tools: [...]            # Optional: tools can be used
]}
```

---

## 4. Graph-of-Thoughts (GoT)

**The "Combine and Improve" Strategy**

GoT treats thoughts as nodes in a graph that can be generated, combined, and improved iteratively.

### When to Use

- ✅ Complex problems requiring synthesis
- ✅ Tasks where multiple approaches can be merged
- ✅ When you want iterative improvement
- ✅ Research and analysis tasks

### Example

```elixir
defmodule AnalystAgent do
  use Jido.Agent,
    name: "analyst",
    strategy: {
      Jido.AI.Strategies.GraphOfThoughts,
      model: "anthropic:claude-sonnet-4-20250514",
      max_iterations: 5,
      operations: [:generate, :combine, :improve]
    }

  @impl true
  def system_prompt do
    """
    You are an analyst. Generate insights, combine them,
    and improve the results.
    """
  end
end
```

### Sample Execution

```
User: "Analyze the pros and cons of remote work"

Generate: Thought A (productivity focus)
Generate: Thought B (collaboration focus)
Generate: Thought C (wellbeing focus)

Combine: A + B → "Balance async work with sync sessions"
Improve: → "Use async for deep work, schedule regular collaboration"

Combine: (A+B) + C → "Remote work requires intentional structure"
Improve: → Final recommendation...

Answer: "Successful remote work needs: 1) Clear async protocols,
        2) Regular collaboration time, 3) Wellness check-ins"
```

### Operations

| Operation | Description |
|-----------|-------------|
| `:generate` | Create new thoughts |
| `:combine` | Merge multiple thoughts |
| `:improve` | Refine an existing thought |
| `:aggregate` | Summarize multiple thoughts |
| `:score` | Evaluate and rank thoughts |

---

## 5. TRM (Task-Resource-Model)

**The "Structured Planning" Strategy**

TRM breaks tasks into clear steps using available resources.

### When to Use

- ✅ Well-defined tasks with clear steps
- ✅ When you have specific resources to leverage
- ✅ Enterprise/workflow automation
- ✅ Tasks requiring documentation

### Example

```elixir
defmodule WorkflowAgent do
  use Jido.Agent,
    name: "workflow_bot",
    strategy: {
      Jido.AI.Strategies.TRM,
      model: "anthropic:claude-sonnet-4-20250514",
      resources: [
        :database,
        :api_client,
        :notification_service
      ]
    }

  @impl true
  def system_prompt do
    """
    You automate workflows by planning tasks and using available resources.
    """
  end
end
```

---

## 6. Adaptive

**The "Automatic Selection" Strategy**

Adaptive evaluates your request and automatically chooses the best strategy.

### When to Use

- ✅ When you're unsure which strategy to pick
- ✅ For general-purpose assistants
- ✅ When task types vary widely
- ❌ When you need deterministic behavior

### Example

```elixir
defmodule SmartAssistant do
  use Jido.Agent,
    name: "smart_assistant",
    strategy: {
      Jido.AI.Strategies.Adaptive,
      model: "anthropic:claude-sonnet-4-20250514",
      available_strategies: [:react, :cot, :tot],
      tools: [Calculator, Search, Database],
      selection_criteria: :task_complexity
    }

  @impl true
  def system_prompt do
    """
    You are an intelligent assistant that adapts your approach
    to each task.
    """
  end
end
```

### How It Works

```
User: "What is 234 * 567?"
      → Adaptive detects: simple calculation
      → Selects: Chain-of-Thought (fast, no tools needed)

User: "What's the weather in Paris?"
      → Adaptive detects: requires API
      → Selects: ReAct with weather tool

User: "Write a poem about spring"
      → Adaptive detects: creative task
      → Selects: Tree-of-Thoughts (explore options)
```

---

## Strategy Tips

### 1. Start Simple

```elixir
# Begin with ReAct for most cases
strategy: {Jido.AI.Strategies.ReAct, [
  model: "anthropic:claude-sonnet-4-20250514",
  tools: [YourTools]
]}
```

### 2. Adjust Iterations

```elixir
# Quick tasks: fewer iterations
max_iterations: 3

# Complex tasks: more iterations
max_iterations: 20
```

### 3. Match Model to Task

```elixir
# Fast/cheap: Haiku
model: "anthropic:claude-haiku-4-5"

# Balanced: Sonnet
model: "anthropic:claude-sonnet-4-20250514"

# Complex reasoning: Opus
model: "anthropic:claude-opus-4-20250514"
```

### 4. Monitor Performance

```elixir
# Enable telemetry to see what's happening
:telemetry.attach("strategy_monitor", [:jido, :ai, :strategy, :*], &handle_event/4, nil)
```

---

## Comparison Examples

### Same Task, Different Strategies

**Task:** "Plan a 3-day trip to Paris"

| Strategy | Approach |
|----------|----------|
| ReAct | "Search for attractions → Book hotels → Calculate costs..." |
| CoT | "Day 1: Eiffel Tower. Day 2: Louvre. Day 3: Notre Dame..." |
| ToT | Explores budget vs luxury options, picks best balance |
| GoT | Generates ideas, combines them, refines the itinerary |
| TRM | Creates structured plan with resources (booking, maps) |

---

## Next Steps

- [Tools & Actions Guide](./04_tools_actions.md) - Build tools for your strategies
- [Examples](./05_examples.md) - See strategies in action
- [Getting Started](./01_getting_started.md) - New to Jido.AI?
