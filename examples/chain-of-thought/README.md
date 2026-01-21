# Chain-of-Thought Examples

This directory contains practical examples demonstrating Chain-of-Thought (CoT) reasoning with Jido AI.

## Examples

### 1. Simple Math Reasoning (`simple_math_reasoning.ex`)

**Purpose**: Demonstrates basic CoT reasoning for mathematical problems.

**Features**:
- Zero-shot Chain-of-Thought prompting
- Step-by-step problem breakdown
- Automatic answer extraction
- Confidence scoring
- Reasoning trace display

**Usage**:
```elixir
# Run the example
Examples.ChainOfThought.SimpleMathReasoning.run()

# Solve a custom problem
Examples.ChainOfThought.SimpleMathReasoning.solve_math_problem(
  "What is 25% of 200?"
)

# Compare with and without CoT
Examples.ChainOfThought.SimpleMathReasoning.compare_with_without_cot()

# Batch solve multiple problems
Examples.ChainOfThought.SimpleMathReasoning.batch_solve([
  "What is 15% of 80?",
  "What is 25% of 200?"
])
```

**Key Concepts**:
- Step-by-step reasoning breakdown
- Answer extraction from reasoning text
- Confidence calculation
- Verification steps

**Best For**:
- Learning CoT basics
- Mathematical reasoning
- Understanding reasoning traces

---

### 2. Data Analysis Workflow (`data_analysis_workflow.ex`)

**Purpose**: Demonstrates CoT orchestration of a multi-step data pipeline.

**Features**:
- Multi-stage data processing
- Reasoning plan generation
- Step-by-step validation
- Dependency tracking
- Comprehensive reporting

**Usage**:
```elixir
# Run the complete workflow
Examples.ChainOfThought.DataAnalysisWorkflow.run()

# Run with custom data
Examples.ChainOfThought.DataAnalysisWorkflow.run_analysis([
  %{id: 1, value: 10, category: "A"},
  %{id: 2, value: 20, category: "B"}
])

# Compare approaches
Examples.ChainOfThought.DataAnalysisWorkflow.compare_with_without_cot()
```

**Workflow Steps**:
1. **Load Data** - Import and validate raw data
2. **Filter Data** - Apply filtering conditions
3. **Aggregate Data** - Calculate metrics and summaries
4. **Generate Report** - Create insights and recommendations

**Key Concepts**:
- Reasoning plan generation
- Step dependencies
- Validation between steps
- Result aggregation
- Insight generation

**Best For**:
- Complex multi-step workflows
- Data pipeline orchestration
- Understanding step validation
- Learning workflow patterns

---

### 3. Chain-of-Thought Example (`chain_of_thought_example.ex`)

**Purpose**: Comprehensive example showing multiple CoT patterns and use cases.

**Features**:
- Problem solving with reasoning
- Complex task planning
- Decision analysis
- Reasoning verification
- Performance comparison

**Usage**:
```elixir
# Solve with reasoning
{:ok, result} = Examples.ChainOfThoughtExample.solve_with_reasoning(
  problem: "If a train travels 120 km in 2 hours, how far will it travel in 5 hours?",
  use_cot: true
)

# Plan a complex task
{:ok, plan} = Examples.ChainOfThoughtExample.plan_complex_task(
  task: "Build a REST API",
  requirements: ["authentication", "CRUD operations", "persistence"]
)

# Analyze a decision
{:ok, analysis} = Examples.ChainOfThoughtExample.analyze_decision(
  decision: "Choose a database",
  options: ["PostgreSQL", "MongoDB", "DynamoDB"],
  criteria: ["performance", "scalability", "cost"]
)

# Verify reasoning
{:ok, verification} = Examples.ChainOfThoughtExample.verify_reasoning(
  reasoning: result.reasoning,
  problem: "...",
  answer: result.answer
)

# Compare with and without CoT
{:ok, comparison} = Examples.ChainOfThoughtExample.compare_with_without_cot(
  problem: "..."
)
```

**Key Concepts**:
- Multiple reasoning modes
- Task decomposition
- Decision frameworks
- Reasoning verification
- Performance comparison

**Best For**:
- Exploring advanced CoT patterns
- Complex planning tasks
- Decision-making scenarios
- Learning verification techniques

---

## Quick Start

### Running Examples in IEx

```elixir
# Start IEx
iex -S mix

# Compile examples
c "examples/chain-of-thought/simple_math_reasoning.ex"
c "examples/chain-of-thought/data_analysis_workflow.ex"
c "examples/chain-of-thought/chain_of_thought_example.ex"

# Run examples
Examples.ChainOfThought.SimpleMathReasoning.run()
Examples.ChainOfThought.DataAnalysisWorkflow.run()
```

### Running from Mix Task

```bash
# Run simple math reasoning
mix run -e "Examples.ChainOfThought.SimpleMathReasoning.run()"

# Run data analysis workflow
mix run -e "Examples.ChainOfThought.DataAnalysisWorkflow.run()"
```

## Comparison: Simple vs Complex Examples

| Aspect | Simple Math | Data Workflow | Full Example |
|--------|-------------|---------------|--------------|
| **Complexity** | Low | Medium | High |
| **Steps** | Single | 4 steps | Variable |
| **Dependencies** | None | Sequential | Variable |
| **Validation** | Basic | Per-step | Comprehensive |
| **Best For** | Learning | Pipelines | Production patterns |

## Common Patterns

### Pattern 1: Single-Step Reasoning

Used in: `simple_math_reasoning.ex`

```elixir
# Generate prompt with CoT trigger
prompt = "Problem: #{problem}\n\nLet's solve this step by step:"

# Execute and parse
{:ok, response} = execute_llm(prompt)
result = parse_response(response)
```

### Pattern 2: Multi-Step Pipeline

Used in: `data_analysis_workflow.ex`

```elixir
# Generate reasoning plan
{:ok, plan} = generate_reasoning_plan()

# Execute steps sequentially with validation
with {:ok, state} <- execute_step(:step1, state, plan),
     {:ok, state} <- execute_step(:step2, state, plan),
     {:ok, state} <- execute_step(:step3, state, plan) do
  {:ok, state}
end
```

### Pattern 3: Reasoning Verification

Used in: `chain_of_thought_example.ex`

```elixir
# Get initial reasoning
{:ok, result} = solve_with_reasoning(problem: problem)

# Verify reasoning quality
{:ok, verification} = verify_reasoning(
  reasoning: result.reasoning,
  problem: problem,
  answer: result.answer
)
```

## Tips for Using These Examples

1. **Start Simple**: Begin with `simple_math_reasoning.ex` to understand basics
2. **Progress to Workflows**: Move to `data_analysis_workflow.ex` for complex scenarios
3. **Explore Patterns**: Use `chain_of_thought_example.ex` for advanced techniques
4. **Customize**: Modify examples for your specific use cases
5. **Experiment**: Try different problems and observe reasoning patterns

## Integration with Jido AI

These examples are designed to work with Jido AI's CoT runner:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    runner: Jido.AI.Runner.ChainOfThought,
    actions: [MyAction]
end

# The runner automatically applies CoT reasoning
{:ok, agent} = MyAgent.new()
{:ok, agent, results} = Jido.AI.Runner.ChainOfThought.run(agent)
```

## Further Reading

- [Chain-of-Thought Guide](../../guides/chain_of_thought.md) - Complete documentation
- [Self-Consistency Guide](../../guides/self_consistency.md) - Multiple reasoning paths
- [Tree-of-Thoughts Guide](../../guides/tree_of_thoughts.md) - Tree-based exploration
- [ReAct Guide](../../guides/react.md) - Reasoning + Acting

## Contributing

To add new examples:

1. Create a new file in this directory
2. Follow the existing pattern (module docs, public functions, helpers)
3. Include usage examples in module documentation
4. Update this README with the new example
5. Add tests if applicable

## Questions?

See the main [Chain-of-Thought Guide](../../guides/chain_of_thought.md) for detailed documentation.
