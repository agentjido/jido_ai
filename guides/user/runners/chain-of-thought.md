# Chain of Thought Runner

The `Jido.AI.Runner.ChainOfThought` runner enhances agent instruction execution with transparent step-by-step reasoning. It provides 8-15% accuracy improvement for complex multi-step tasks.

## Overview

Chain-of-Thought (CoT) prompting encourages the LLM to "think step by step" before providing a final answer. This runner automatically adds reasoning to instruction execution.

```mermaid
graph LR
    A[Instructions] --> B[Analyze]
    B --> C[Generate Reasoning]
    C --> D[Execute with Context]
    D --> E[Validate Outcomes]
    E --> F[Return Results]
```

## Basic Usage

### With Jido Agent

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "reasoning_agent",
    runner: Jido.AI.Runner.ChainOfThought,
    actions: [MyAction]
end

{:ok, agent} = MyAgent.new()
agent = Jido.Agent.enqueue(agent, MyAction, %{input: "complex task"})
{:ok, updated_agent, directives} = Jido.AI.Runner.ChainOfThought.run(agent)
```

### With Custom Configuration

```elixir
opts = [
  mode: :structured,
  max_iterations: 3,
  model: "gpt-4o",
  temperature: 0.3
]

{:ok, updated_agent, directives} = Jido.AI.Runner.ChainOfThought.run(agent, opts)
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `mode` | atom | `:zero_shot` | Reasoning mode |
| `max_iterations` | integer | 1 | Refinement iterations |
| `model` | string | nil | LLM model to use |
| `temperature` | float | 0.2 | Generation temperature |
| `enable_validation` | boolean | true | Validate outcomes |
| `fallback_on_error` | boolean | true | Fall back on failure |

### Reasoning Modes

#### Zero-Shot (`:zero_shot`)
Simple "Let's think step by step" reasoning:
```elixir
{:ok, agent, _} = ChainOfThought.run(agent, mode: :zero_shot)
```

#### Few-Shot (`:few_shot`)
Reasoning with examples:
```elixir
{:ok, agent, _} = ChainOfThought.run(agent, mode: :few_shot)
```

#### Structured (`:structured`)
Task-specific structured reasoning:
```elixir
{:ok, agent, _} = ChainOfThought.run(agent, mode: :structured)
```

## Configuration via Agent State

Store configuration in agent state for persistent settings:

```elixir
agent = MyAgent.new()
agent = Jido.Agent.set(agent, :cot_config, %{
  mode: :zero_shot,
  max_iterations: 2,
  model: "claude-3-5-sonnet-latest"
})

# Runner uses stored configuration
{:ok, updated_agent, directives} = ChainOfThought.run(agent)
```

## Execution Flow

1. **Analyze Instructions**: Examines pending instructions and agent state
2. **Generate Reasoning**: Creates step-by-step reasoning plan using LLM
3. **Execute with Context**: Runs actions with reasoning context
4. **Validate Outcomes**: Compares results to reasoning predictions
5. **Return Results**: Returns updated agent and directives

## Reasoning Output

The runner logs the reasoning plan:

```
=== Chain-of-Thought Reasoning Plan ===
Goal: Process the user's complex calculation request

Analysis:
  The task requires multiple mathematical operations
  in a specific sequence to arrive at the correct answer.

Execution Steps (3):
  1. Parse the input values → Extract numbers
  2. Apply operations in order → Intermediate results
  3. Format final result → Human-readable output

Expected Results:
  A correctly formatted numerical answer

Potential Issues:
  • Division by zero if input contains zeros
  • Overflow for very large numbers
======================================
```

## Error Handling

### Graceful Fallback

When reasoning fails, the runner can fall back to direct execution:

```elixir
{:ok, agent, _} = ChainOfThought.run(agent,
  fallback_on_error: true
)
```

### Disable Fallback

For strict reasoning requirements:

```elixir
case ChainOfThought.run(agent, fallback_on_error: false) do
  {:ok, agent, directives} ->
    # Success with reasoning

  {:error, reason} ->
    # Handle reasoning failure
    Logger.error("Reasoning failed: #{inspect(reason)}")
end
```

## Validation

Enable outcome validation to compare results against predictions:

```elixir
{:ok, agent, _} = ChainOfThought.run(agent,
  enable_validation: true
)
```

The runner logs validation results:

```
Step 1 completed ✓:
  Matches Expectation: true
  Confidence: 0.95
```

## Performance Characteristics

| Metric | Value |
|--------|-------|
| Latency overhead | 2-3 seconds |
| Token cost | 3-4x increase |
| Accuracy improvement | 8-15% |
| Fallback overhead | Zero |

## Best Practices

1. **Use for complex tasks**: CoT is most beneficial for multi-step reasoning
2. **Keep temperature low**: Use 0.2-0.3 for consistent reasoning
3. **Enable validation**: Helps catch reasoning errors
4. **Use fallback**: Ensures reliability in production
5. **Match mode to task**: Structured mode for domain-specific tasks

## Example: Math Problem

```elixir
defmodule MathSolver do
  use Jido.Agent,
    name: "math_solver",
    runner: Jido.AI.Runner.ChainOfThought,
    actions: [SolveEquation]
end

{:ok, agent} = MathSolver.new()
agent = Jido.Agent.set(agent, :cot_config, %{
  mode: :structured,
  temperature: 0.1  # Low for math
})

agent = Jido.Agent.enqueue(agent, SolveEquation, %{
  equation: "2x + 5 = 15"
})

{:ok, solved_agent, _} = ChainOfThought.run(agent)
```

## See Also

- [Runners Overview](overview.md)
- [ReAct Runner](react.md) - For tasks requiring tool use
- [Self-Consistency](self-consistency.md) - For higher accuracy
