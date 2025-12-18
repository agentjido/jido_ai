# Chain-of-Thought: Step-by-Step Reasoning

## Introduction

Chain-of-Thought (CoT) is a prompting technique that dramatically improves Large Language Model (LLM) performance on complex reasoning tasks by encouraging the model to break down problems into intermediate steps. Instead of directly answering a question, CoT prompts the LLM to "think step by step," making its reasoning process explicit and transparent.

Research shows that CoT provides **8-15% accuracy improvements** on complex multi-step tasks with minimal overhead, and **15-25%** improvements on advanced reasoning challenges. The technique is particularly effective for mathematical reasoning, logical deduction, multi-step planning, and code generation.

### Why Chain-of-Thought?

Traditional prompting often fails on complex tasks because LLMs must perform all reasoning in a single forward pass. Chain-of-Thought addresses this by:

- **Decomposing Complex Problems**: Breaking multi-step tasks into manageable pieces
- **Making Reasoning Explicit**: Surfacing the model's thought process for validation
- **Enabling Self-Correction**: Allowing the model to catch and fix errors mid-reasoning
- **Improving Interpretability**: Providing insight into how the model reaches conclusions
- **Enhancing Reliability**: Reducing errors through structured thinking

### Performance

CoT delivers significant improvements across various domains:

- **Arithmetic Reasoning**: +15-25% accuracy on multi-step math problems (GSM8K)
- **Commonsense Reasoning**: +10-20% improvement on logical inference tasks
- **Symbolic Reasoning**: +20-40% on tasks requiring step-by-step manipulation
- **Code Generation**: +20-40% improvement on complex programming tasks
- **Multi-Hop QA**: +15-30% on questions requiring information synthesis

**Cost**: CoT adds 3-4× token overhead for single-shot reasoning, with latency increases of 2-3 seconds.

> **💡 Practical Examples**: See the [Chain-of-Thought examples directory](../examples/chain-of-thought/) for complete working implementations including a basic calculator and an advanced problem solver.

---

## Core Concepts

### The Chain-of-Thought Pattern

Traditional prompting:
```
Q: What is 15% of 80?
A: 12
```

Chain-of-Thought prompting:
```
Q: What is 15% of 80?
A: Let's think step by step.
   1. Convert 15% to decimal: 15/100 = 0.15
   2. Multiply by 80: 0.15 × 80 = 12
   Therefore, 15% of 80 is 12.
```

The key insight: Intermediate reasoning steps improve both accuracy and interpretability.

### How It Works

Chain-of-Thought reasoning follows a four-phase cycle:

1. **Analyze**: Examine the problem and identify what needs to be solved
2. **Plan**: Break the problem into intermediate steps
3. **Execute**: Work through each step sequentially
4. **Verify**: Check that the solution makes sense

### Key Components

| Component | Purpose |
|-----------|---------|
| **Reasoning Prompt** | Triggers step-by-step thinking |
| **Step Decomposition** | Breaks complex tasks into manageable pieces |
| **Intermediate Results** | Stores outputs from each reasoning step |
| **Outcome Validation** | Compares results against expectations |
| **Error Recovery** | Handles unexpected outcomes gracefully |

### Integration with Jido AI

Jido AI implements CoT through a custom **Runner** that intercepts instruction execution:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "reasoning_agent",
    runner: Jido.AI.Runner.ChainOfThought,
    actions: [MyAction]
end

# Reasoning is automatically applied to all instructions
{:ok, agent} = MyAgent.new()
agent = Jido.Agent.enqueue(agent, MyAction, %{task: "complex problem"})
{:ok, updated_agent, directives} = Jido.AI.Runner.ChainOfThought.run(agent)
```

The runner:
- Analyzes pending instructions
- Generates a reasoning plan
- Executes actions with enriched context
- Validates outcomes against predictions
- Provides graceful fallback on errors

---

## When to Use Chain-of-Thought

### Ideal Use Cases

CoT excels when tasks require:

**Multi-Step Reasoning**
- Mathematical calculations with multiple operations
- Logical deductions requiring intermediate conclusions
- Step-by-step transformations or manipulations

**Complex Problem Solving**
- Planning tasks with dependencies
- Troubleshooting and debugging
- Decision-making with multiple factors

**Code Generation**
- Writing functions that combine multiple operations
- Debugging code by reasoning about execution
- Designing algorithms with clear steps

**Information Synthesis**
- Combining facts from multiple sources
- Drawing conclusions from evidence
- Building arguments with supporting steps

**Validation and Verification**
- Checking complex calculations
- Verifying logical consistency
- Testing edge cases systematically

### When NOT to Use Chain-of-Thought

Consider alternatives when:

- **Simple, Direct Questions**: "What is the capital of France?" doesn't need reasoning
- **Single-Step Tasks**: Tasks solvable in one operation don't benefit from decomposition
- **Latency Critical**: The 2-3s reasoning overhead is unacceptable
- **Token Budget Constrained**: The 3-4× token increase is too expensive
- **Pattern Matching Sufficient**: Simple classification or retrieval tasks

### Cost-Benefit Analysis

```
Without CoT:
- Latency: 1s
- Tokens: 100
- Accuracy: 75%
- Cost: $0.001

With CoT:
- Latency: 3-4s (3-4× increase)
- Tokens: 300-400 (3-4× increase)
- Accuracy: 85-90% (+10-15%)
- Cost: $0.003-0.004 (3-4× increase)
```

**ROI**: CoT is worth the cost when accuracy improvement justifies the overhead.

---

## Getting Started

### Prerequisites

1. **Jido AI installed** with LLM provider configured
2. **API keys set** for your chosen provider
3. **Agent defined** with actions to execute

### Basic Setup

```elixir
# Set your API key
Jido.AI.Keyring.set_env_value(:openai_api_key, "sk-...")

# Define an agent with CoT runner
defmodule MyApp.ReasoningAgent do
  use Jido.Agent,
    name: "reasoning_agent",
    runner: Jido.AI.Runner.ChainOfThought,
    actions: [MyApp.Actions.SolveTask]
end

# Create and run the agent
{:ok, agent} = MyApp.ReasoningAgent.new()

# Enqueue a complex task
agent = Jido.Agent.enqueue(agent, MyApp.Actions.SolveTask, %{
  problem: "If a train travels 60 miles in 1.5 hours, then 40 miles in 1 hour, what is its average speed?"
})

# Execute with CoT reasoning
{:ok, updated_agent, directives} = Jido.AI.Runner.ChainOfThought.run(agent)

# The runner automatically generates and follows a reasoning plan
```

### Simple Example

```elixir
defmodule Examples.MathReasoning do
  @moduledoc """
  Simple example demonstrating Chain-of-Thought for math problems.
  """

  alias Jido.AI.Runner.ChainOfThought

  def solve_math_problem do
    # Define a simple math action
    defmodule MathAction do
      use Jido.Action,
        name: "solve_math",
        schema: [
          problem: [type: :string, required: true]
        ]

      def run(%{problem: problem}, context) do
        # The action receives enriched context with reasoning
        reasoning = context[:reasoning]

        IO.puts("Problem: #{problem}")

        if reasoning do
          IO.puts("\nReasoning Plan:")
          IO.puts(reasoning.analysis)
        end

        # Action performs its work
        # Result is validated against reasoning expectations
        {:ok, %{solution: "12", steps: ["15% = 0.15", "0.15 × 80 = 12"]}}
      end
    end

    # Create agent with CoT
    agent = %{
      name: "math_agent",
      state: %{},
      pending_instructions: :queue.from_list([
        %{action: MathAction, params: %{problem: "What is 15% of 80?"}}
      ])
    }

    # Run with CoT reasoning
    case ChainOfThought.run(agent) do
      {:ok, updated_agent, _directives} ->
        IO.puts("\n✓ Problem solved with reasoning!")
        {:ok, updated_agent}

      {:error, reason} ->
        IO.puts("✗ Error: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
```

### Configuration Options

```elixir
# Run with custom configuration
{:ok, agent, directives} = ChainOfThought.run(agent,
  mode: :structured,              # Reasoning mode
  max_iterations: 3,              # Refinement iterations
  model: "gpt-4o",                # LLM for reasoning
  temperature: 0.3,               # Higher than default for creativity
  enable_validation: true,        # Validate outcomes
  fallback_on_error: true         # Fallback to direct execution on error
)
```

---

## Understanding Chain-of-Thought Components

### Reasoning Modes

CoT supports three reasoning modes for different use cases:

#### 1. Zero-Shot CoT (Default)

Simple "Let's think step by step" prompting without examples.

```elixir
config = %{mode: :zero_shot}

# Generates reasoning like:
# "Let's think step by step.
#  1. First, identify the given information...
#  2. Next, determine what we need to find...
#  3. Then, apply the appropriate formula...
#  4. Finally, calculate the result..."
```

**Best for**: General-purpose reasoning, tasks without specific patterns

**Performance**: Fast, consistent, works well for most tasks

#### 2. Few-Shot CoT

Provides example reasoning chains to guide the model.

```elixir
config = %{
  mode: :few_shot,
  examples: [
    %{
      problem: "What is 20% of 150?",
      reasoning: """
      Let's break this down:
      1. Convert percentage: 20% = 20/100 = 0.20
      2. Multiply: 0.20 × 150 = 30
      Answer: 30
      """
    }
  ]
}

# Model follows the example pattern for new problems
```

**Best for**: Domain-specific reasoning, consistent formatting

**Performance**: Higher accuracy, but longer prompts (more tokens)

#### 3. Structured CoT

Task-specific reasoning templates with defined structure.

```elixir
config = %{
  mode: :structured,
  template: """
  Analysis: [Identify problem type and constraints]
  Plan: [List steps in order]
  Execution: [Work through each step]
  Verification: [Check result validity]
  """
}

# Forces reasoning into specific format
```

**Best for**: Complex workflows, when specific reasoning structure is needed

**Performance**: Most reliable for complex tasks, highest token cost

### Reasoning Plan Structure

The runner generates a structured reasoning plan:

```elixir
%ReasoningPlan{
  goal: "Calculate average speed for multi-segment journey",
  analysis: """
  The problem requires calculating average speed across two segments
  with different speeds. We need total distance and total time.
  """,
  steps: [
    %{
      number: 1,
      description: "Calculate total distance traveled",
      expected_outcome: "100 miles (60 + 40)"
    },
    %{
      number: 2,
      description: "Calculate total time taken",
      expected_outcome: "2.5 hours (1.5 + 1.0)"
    },
    %{
      number: 3,
      description: "Divide total distance by total time",
      expected_outcome: "40 mph (100 / 2.5)"
    }
  ],
  expected_results: "Average speed of 40 miles per hour",
  potential_issues: [
    "Confusing average speed with weighted average of speeds",
    "Incorrect time unit conversion"
  ]
}
```

### Execution Context Enrichment

The runner enriches action context with reasoning information:

```elixir
# Original context
context = %{agent: agent, state: %{}}

# Enriched with reasoning
enriched_context = %{
  agent: agent,
  state: %{},
  reasoning: %{
    current_step: 2,
    step_description: "Calculate total time taken",
    expected_outcome: "2.5 hours (1.5 + 1.0)",
    previous_results: [%{step: 1, result: "100 miles"}],
    remaining_steps: 1
  }
}

# Actions receive enriched context
MyAction.run(params, enriched_context)
```

Actions can use reasoning context to:
- Understand their role in the overall plan
- Access results from previous steps
- Know what output is expected
- Adjust behavior based on plan

### Outcome Validation

After each step, the runner validates outcomes against predictions:

```elixir
%ValidationResult{
  matches_expectation: true,        # Does result match plan?
  confidence: 0.95,                 # How confident are we?
  discrepancies: [],                # Any differences found?
  severity: :none                   # How serious are differences?
}

# If validation fails:
%ValidationResult{
  matches_expectation: false,
  confidence: 0.60,
  discrepancies: [
    "Expected '2.5 hours', got '150 minutes' (equivalent but different format)"
  ],
  severity: :minor                  # :minor, :major, or :critical
}
```

Validation triggers:
- **Minor discrepancies**: Log warning, continue execution
- **Major discrepancies**: Attempt self-correction
- **Critical discrepancies**: Fall back to direct execution (if enabled)

### Error Handling

The runner provides graceful error recovery:

```elixir
# Automatic retry on transient failures
ErrorHandler.with_retry(
  fn -> call_llm_for_reasoning(...) end,
  max_retries: 3,
  initial_delay_ms: 1000,
  backoff_factor: 2.0
)

# Fallback to direct execution
if config.fallback_on_error do
  case ChainOfThought.run(agent, config) do
    {:error, _reason} ->
      # Automatically falls back to simple runner
      Jido.AI.Runner.Simple.run(agent)

    success -> success
  end
end
```

---

## Configuration Options

### Core Parameters

```elixir
config = %{
  # Reasoning mode
  mode: :zero_shot,                 # :zero_shot, :few_shot, or :structured

  # Iteration settings
  max_iterations: 1,                # Number of reasoning refinement passes

  # LLM configuration
  model: "gpt-4o",                  # Model for reasoning (nil = default)
  temperature: 0.2,                 # Lower = more consistent reasoning

  # Validation settings
  enable_validation: true,          # Compare outcomes to expectations
  fallback_on_error: true,          # Fall back to direct execution on failure

  # Advanced options
  log_reasoning: true,              # Log reasoning plans
  store_reasoning_history: false,   # Keep history for analysis
  reasoning_timeout: 30_000         # Max time for reasoning generation (ms)
}
```

### Mode-Specific Options

#### Zero-Shot Configuration

```elixir
zero_shot_config = %{
  mode: :zero_shot,
  preamble: "Let's think step by step.",  # Custom preamble
  include_examples: false                  # Don't include any examples
}
```

#### Few-Shot Configuration

```elixir
few_shot_config = %{
  mode: :few_shot,
  examples: [
    %{problem: "...", reasoning: "...", answer: "..."},
    %{problem: "...", reasoning: "...", answer: "..."}
  ],
  max_examples: 3,                  # Limit examples to avoid long prompts
  example_selection: :most_similar  # How to choose examples
}
```

#### Structured Configuration

```elixir
structured_config = %{
  mode: :structured,
  template: """
  ## Problem Analysis
  [Describe the problem and constraints]

  ## Solution Plan
  [List the steps required]

  ## Step-by-Step Execution
  [Work through each step]

  ## Verification
  [Validate the solution]
  """,
  enforce_format: true              # Require template adherence
}
```

### LLM Parameters

Fine-tune reasoning quality:

```elixir
llm_config = %{
  model: "gpt-4o",                  # Reasoning model
  temperature: 0.2,                 # Low for consistency
  max_tokens: 2000,                 # Allow detailed reasoning
  top_p: 0.9,                       # Nucleus sampling
  presence_penalty: 0.0,            # Don't penalize thoroughness
  frequency_penalty: 0.0            # Allow repetition if needed
}
```

**Model Selection**:
- **GPT-4/4o**: Best reasoning quality, higher cost
- **GPT-3.5-turbo**: Good balance, lower cost
- **Claude 3 Sonnet**: Strong reasoning, good for long chains
- **Claude 3 Haiku**: Fast, cheap, decent quality

### Validation Options

```elixir
validation_config = %{
  enable_validation: true,

  # Validation strictness
  strictness: :moderate,            # :lenient, :moderate, :strict

  # What to validate
  validate_format: true,            # Check output format
  validate_logic: true,             # Check logical consistency
  validate_completeness: true,      # Check all steps completed

  # Response to failures
  on_minor_discrepancy: :log,       # :log, :warn, :error
  on_major_discrepancy: :retry,     # :retry, :fallback, :error
  on_critical_discrepancy: :fallback # :fallback or :error
}
```

### Persistent Configuration

Store configuration in agent state:

```elixir
# Define agent with default CoT config
defmodule MyApp.ReasoningAgent do
  use Jido.Agent,
    name: "reasoning_agent",
    runner: Jido.AI.Runner.ChainOfThought
end

# Create agent and set CoT configuration
{:ok, agent} = MyApp.ReasoningAgent.new()

agent = Jido.Agent.set(agent, :cot_config, %{
  mode: :structured,
  max_iterations: 3,
  model: "gpt-4o",
  enable_validation: true
})

# Configuration is used automatically
{:ok, updated_agent, directives} = Jido.AI.Runner.ChainOfThought.run(agent)

# Override specific options at runtime
{:ok, agent2, dirs2} = Jido.AI.Runner.ChainOfThought.run(agent,
  temperature: 0.5  # Override just temperature
)
```

---

## Integration Patterns

### Pattern 1: Transparent CoT Runner

The simplest pattern - CoT is applied automatically to all instructions:

```elixir
defmodule MyApp.SmartAgent do
  use Jido.Agent,
    name: "smart_agent",
    runner: Jido.AI.Runner.ChainOfThought,
    actions: [
      MyApp.Actions.AnalyzeData,
      MyApp.Actions.TransformData,
      MyApp.Actions.GenerateReport
    ]
end

# All actions automatically get CoT reasoning
{:ok, agent} = MyApp.SmartAgent.new()
agent = agent
  |> Jido.Agent.enqueue(MyApp.Actions.AnalyzeData, %{data: data})
  |> Jido.Agent.enqueue(MyApp.Actions.TransformData, %{format: :json})
  |> Jido.Agent.enqueue(MyApp.Actions.GenerateReport, %{template: "summary"})

{:ok, final_agent, results} = Jido.AI.Runner.ChainOfThought.run(agent)
```

**Benefits**: Zero code changes to actions, transparent integration
**Overhead**: Applied to all instructions, even simple ones

### Pattern 2: Selective CoT with Runner Switching

Use CoT only for complex tasks:

```elixir
defmodule MyApp.AdaptiveAgent do
  use Jido.Agent,
    name: "adaptive_agent",
    runner: Jido.AI.Runner.Simple,  # Default: simple runner
    actions: [MyApp.Actions.ComplexTask, MyApp.Actions.SimpleTask]
end

def process(agent, task_complexity) do
  case task_complexity do
    :simple ->
      # Use simple runner (no CoT overhead)
      Jido.AI.Runner.Simple.run(agent)

    :complex ->
      # Switch to CoT for complex tasks
      Jido.AI.Runner.ChainOfThought.run(agent, mode: :structured)

    :very_complex ->
      # Use advanced CoT with multiple iterations
      Jido.AI.Runner.ChainOfThought.run(agent,
        mode: :structured,
        max_iterations: 3,
        model: "gpt-4o"
      )
  end
end
```

**Benefits**: Optimize cost/performance for task complexity
**Overhead**: Requires complexity classification

### Pattern 3: Lifecycle Hook Integration

Inject CoT into specific lifecycle stages:

```elixir
defmodule MyApp.HookBasedAgent do
  use Jido.Agent,
    name: "hook_agent",
    actions: [MyApp.Actions.SomeAction]

  # Generate reasoning before planning
  def on_before_plan(agent, _context) do
    instructions = get_pending_instructions(agent)

    case generate_reasoning_plan(instructions, agent.state) do
      {:ok, plan} ->
        # Store reasoning in state for actions to use
        {:ok, Jido.Agent.set(agent, :reasoning_plan, plan)}

      {:error, _reason} ->
        # Continue without reasoning on error
        {:ok, agent}
    end
  end

  # Validate outcomes after execution
  def on_after_run(agent, result, _context) do
    plan = Jido.Agent.get(agent, :reasoning_plan)

    if plan do
      validation = validate_result_against_plan(result, plan)

      if validation.matches_expectation do
        {:ok, result}
      else
        {:error, "Result doesn't match reasoning: #{inspect(validation.discrepancies)}"}
      end
    else
      {:ok, result}
    end
  end

  defp generate_reasoning_plan(instructions, state) do
    # CoT reasoning generation logic
  end

  defp validate_result_against_plan(result, plan) do
    # Validation logic
  end
end
```

**Benefits**: Fine-grained control over when CoT is applied
**Overhead**: More implementation complexity

### Pattern 4: CoT as a Skill

Implement CoT reasoning as a reusable skill:

```elixir
defmodule MyApp.Skills.ReasoningSkill do
  @moduledoc """
  Skill that adds CoT reasoning capabilities to any agent.
  """

  def generate_reasoning(problem, context \\ %{}) do
    # CoT reasoning logic
    prompt = """
    Problem: #{problem}

    Let's think step by step to solve this problem.
    """

    # Call LLM and parse reasoning
    {:ok, reasoning_plan}
  end

  def validate_outcome(result, reasoning) do
    # Validation logic
    {:ok, validation_result}
  end
end

defmodule MyApp.FlexibleAgent do
  use Jido.Agent,
    name: "flexible_agent",
    skills: [MyApp.Skills.ReasoningSkill],
    actions: [MyApp.Actions.ComplexTask]
end

# Use skill explicitly when needed
def solve_with_reasoning(agent, problem) do
  {:ok, reasoning} = MyApp.Skills.ReasoningSkill.generate_reasoning(problem)

  agent = Jido.Agent.set(agent, :reasoning, reasoning)

  {:ok, updated_agent, result} = run_agent_with_reasoning(agent)

  {:ok, _validation} = MyApp.Skills.ReasoningSkill.validate_outcome(result, reasoning)

  {:ok, updated_agent, result}
end
```

**Benefits**: Flexible, composable, can combine with other skills
**Overhead**: Manual integration in action logic

---

## Best Practices

### 1. Choose the Right Mode

```elixir
# Simple tasks → Zero-shot
config = %{mode: :zero_shot}  # Fast, general-purpose

# Domain-specific → Few-shot
config = %{
  mode: :few_shot,
  examples: domain_examples
}  # Better accuracy for specialized tasks

# Complex workflows → Structured
config = %{
  mode: :structured,
  template: workflow_template
}  # Best for multi-step processes
```

### 2. Set Appropriate Temperature

```elixir
# Mathematical/logical reasoning
config = %{temperature: 0.1}  # Very deterministic

# General problem solving
config = %{temperature: 0.2}  # Default, good balance

# Creative reasoning
config = %{temperature: 0.5}  # Allow more exploration
```

### 3. Use Validation Strategically

```elixir
# Critical tasks → Strict validation
config = %{
  enable_validation: true,
  strictness: :strict,
  fallback_on_error: true
}

# Exploratory tasks → Lenient validation
config = %{
  enable_validation: true,
  strictness: :lenient,
  fallback_on_error: false
}
```

### 4. Optimize Token Usage

```elixir
# For cost optimization
config = %{
  mode: :zero_shot,           # Simplest prompts
  max_tokens: 1000,           # Limit reasoning length
  model: "gpt-3.5-turbo"      # Cheaper model
}

# For quality optimization
config = %{
  mode: :structured,          # Most thorough
  max_tokens: 2000,           # Allow detailed reasoning
  model: "gpt-4o"             # Best reasoning model
}
```

### 5. Handle Errors Gracefully

```elixir
# Always enable fallback for production
config = %{
  fallback_on_error: true,
  reasoning_timeout: 30_000
}

case ChainOfThought.run(agent, config) do
  {:ok, agent, results} ->
    # Success path
    handle_success(agent, results)

  {:error, %ErrorHandler.Error{type: :timeout}} ->
    # Reasoning timed out, try simpler approach
    ChainOfThought.run(agent, mode: :zero_shot, max_iterations: 1)

  {:error, reason} ->
    # Other error, log and continue
    Logger.error("CoT failed: #{inspect(reason)}")
    Jido.AI.Runner.Simple.run(agent)
end
```

### 6. Log Reasoning for Debugging

```elixir
# Enable detailed logging during development
config = %{
  log_reasoning: true,
  store_reasoning_history: true
}

# Check reasoning history after execution
reasoning_history = Jido.Agent.get(agent, :reasoning_history)
Enum.each(reasoning_history, fn entry ->
  IO.puts("Step #{entry.step}: #{entry.description}")
  IO.puts("Expected: #{entry.expected_outcome}")
  IO.puts("Actual: #{entry.actual_outcome}")
  IO.puts("---")
end)
```

### 7. Test with Representative Tasks

```elixir
# Build a test suite for CoT reasoning
defmodule MyApp.CoTTest do
  use ExUnit.Case

  test "CoT improves accuracy on multi-step math" do
    problems = load_math_problems()

    # Without CoT
    {:ok, baseline_results} = solve_without_cot(problems)
    baseline_accuracy = calculate_accuracy(baseline_results)

    # With CoT
    {:ok, cot_results} = solve_with_cot(problems)
    cot_accuracy = calculate_accuracy(cot_results)

    # CoT should improve accuracy
    assert cot_accuracy > baseline_accuracy
    assert cot_accuracy - baseline_accuracy >= 0.10  # At least 10% improvement
  end
end
```

### 8. Monitor Performance

```elixir
# Track CoT metrics
defmodule MyApp.CoTMetrics do
  def track_execution(agent, config) do
    start_time = System.monotonic_time(:millisecond)

    result = ChainOfThought.run(agent, config)

    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time

    # Log metrics
    :telemetry.execute(
      [:myapp, :cot, :execution],
      %{duration: duration},
      %{mode: config.mode, success: match?({:ok, _, _}, result)}
    )

    result
  end
end
```

### 9. Use Appropriate Models

```elixir
# Development/testing
dev_config = %{model: "gpt-3.5-turbo"}  # Fast, cheap

# Production - moderate complexity
prod_config = %{model: "gpt-4o"}  # Good balance

# Production - high complexity
complex_config = %{model: "gpt-4o"}  # Best reasoning

# Match reasoning model to production model
# Don't develop with GPT-3.5 if production uses GPT-4
```

### 10. Document Reasoning Patterns

```elixir
# Keep a library of effective reasoning templates
defmodule MyApp.ReasoningTemplates do
  def math_problem_template do
    """
    ## Problem Understanding
    [State the problem clearly]

    ## Known Information
    [List given values and constraints]

    ## Solution Strategy
    [Identify the approach]

    ## Step-by-Step Solution
    [Work through the calculation]

    ## Verification
    [Check the answer makes sense]
    """
  end

  def debugging_template do
    """
    ## Symptom Analysis
    [Describe the observed behavior]

    ## Hypothesis Generation
    [List possible causes]

    ## Testing Strategy
    [Plan how to test each hypothesis]

    ## Root Cause Identification
    [Determine the actual cause]

    ## Solution Implementation
    [Fix the issue]
    """
  end
end
```

---

## Example Workflow

Here's a complete workflow demonstrating Chain-of-Thought for a complex task:

```elixir
defmodule Examples.DataAnalysisWorkflow do
  @moduledoc """
  Complete workflow using Chain-of-Thought for multi-step data analysis.
  """

  alias Jido.AI.Runner.ChainOfThought
  alias Jido.AI.Keyring

  # Define analysis actions
  defmodule Actions.LoadData do
    use Jido.Action, name: "load_data", schema: [source: [type: :string, required: true]]

    def run(%{source: source}, context) do
      # Load data with reasoning context
      if reasoning = context[:reasoning] do
        IO.puts("Step #{reasoning.current_step}: #{reasoning.step_description}")
      end

      data = load_from_source(source)
      {:ok, %{data: data, rows: length(data)}}
    end

    defp load_from_source(_source), do: [%{value: 10}, %{value: 20}, %{value: 30}]
  end

  defmodule Actions.FilterData do
    use Jido.Action, name: "filter_data", schema: [condition: [type: :string, required: true]]

    def run(%{condition: condition}, context) do
      if reasoning = context[:reasoning] do
        IO.puts("Step #{reasoning.current_step}: #{reasoning.step_description}")
      end

      data = get_previous_result(context, :data) || []
      filtered = Enum.filter(data, fn row -> row.value > 15 end)
      {:ok, %{data: filtered, filtered_count: length(filtered)}}
    end

    defp get_previous_result(context, key) do
      context[:reasoning][:previous_results]
      |> List.last()
      |> case do
        nil -> nil
        result -> Map.get(result, key)
      end
    end
  end

  defmodule Actions.AggregateData do
    use Jido.Action, name: "aggregate_data", schema: [metric: [type: :string, required: true]]

    def run(%{metric: "average"}, context) do
      if reasoning = context[:reasoning] do
        IO.puts("Step #{reasoning.current_step}: #{reasoning.step_description}")
      end

      data = get_previous_result(context, :data) || []
      average = Enum.reduce(data, 0, fn row, acc -> acc + row.value end) / length(data)
      {:ok, %{metric: "average", value: average}}
    end

    defp get_previous_result(context, key) do
      context[:reasoning][:previous_results]
      |> List.last()
      |> case do
        nil -> nil
        result -> Map.get(result, key)
      end
    end
  end

  def run_analysis do
    IO.puts("=== Chain-of-Thought Data Analysis Workflow ===\n")

    # Step 1: Setup
    IO.puts("Step 1: Setup")
    setup_api_keys()

    # Step 2: Create agent with CoT runner
    IO.puts("\nStep 2: Create Agent with CoT Runner")

    defmodule AnalysisAgent do
      use Jido.Agent,
        name: "analysis_agent",
        runner: Jido.AI.Runner.ChainOfThought,
        actions: [
          Actions.LoadData,
          Actions.FilterData,
          Actions.AggregateData
        ]
    end

    {:ok, agent} = AnalysisAgent.new()

    # Step 3: Configure CoT
    IO.puts("\nStep 3: Configure Chain-of-Thought")

    cot_config = %{
      mode: :structured,
      template: """
      ## Analysis Plan
      [Understand the data flow]

      ## Execution Steps
      [Process data through pipeline]

      ## Validation
      [Verify results]
      """,
      enable_validation: true,
      fallback_on_error: true,
      log_reasoning: true
    }

    agent = Jido.Agent.set(agent, :cot_config, cot_config)

    # Step 4: Enqueue instructions
    IO.puts("\nStep 4: Enqueue Analysis Instructions")

    agent =
      agent
      |> Jido.Agent.enqueue(Actions.LoadData, %{source: "data.csv"})
      |> Jido.Agent.enqueue(Actions.FilterData, %{condition: "value > 15"})
      |> Jido.Agent.enqueue(Actions.AggregateData, %{metric: "average"})

    IO.puts("  ✓ 3 instructions enqueued")

    # Step 5: Execute with CoT reasoning
    IO.puts("\nStep 5: Execute with Chain-of-Thought Reasoning\n")

    case ChainOfThought.run(agent) do
      {:ok, updated_agent, directives} ->
        IO.puts("\n✓ Analysis completed successfully!\n")

        # Step 6: Review results
        IO.puts("Step 6: Review Results")
        print_results(updated_agent, directives)

        # Step 7: Analyze reasoning
        IO.puts("\nStep 7: Analyze Reasoning Quality")
        analyze_reasoning(updated_agent)

        {:ok, updated_agent}

      {:error, reason} ->
        IO.puts("\n✗ Analysis failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp setup_api_keys do
    case Keyring.get_env_value(:openai_api_key, nil) do
      nil ->
        IO.puts("  ⚠ Warning: OpenAI API key not set")
        IO.puts("  Set with: Jido.AI.Keyring.set_env_value(:openai_api_key, \"sk-...\")")

      key ->
        IO.puts("  ✓ API key configured: #{String.slice(key, 0, 7)}...")
    end
  end

  defp print_results(_agent, directives) do
    IO.puts("\nExecution Results:")

    Enum.with_index(directives, 1)
    |> Enum.each(fn {directive, idx} ->
      IO.puts("  Step #{idx}: #{inspect(directive)}")
    end)
  end

  defp analyze_reasoning(agent) do
    reasoning_history = Jido.Agent.get(agent, :reasoning_history, [])

    if length(reasoning_history) > 0 do
      IO.puts("\nReasoning Analysis:")
      IO.puts("  Total steps: #{length(reasoning_history)}")
      IO.puts("  All steps validated: #{all_validated?(reasoning_history)}")
      IO.puts("  Average confidence: #{calculate_avg_confidence(reasoning_history)}")
    else
      IO.puts("  No reasoning history available")
    end
  end

  defp all_validated?(history) do
    Enum.all?(history, fn step ->
      step[:validation][:matches_expectation] == true
    end)
  end

  defp calculate_avg_confidence(history) do
    confidences =
      Enum.map(history, fn step ->
        step[:validation][:confidence] || 0.0
      end)

    if length(confidences) > 0 do
      sum = Enum.sum(confidences)
      Float.round(sum / length(confidences), 2)
    else
      0.0
    end
  end
end

# Run the workflow
Examples.DataAnalysisWorkflow.run_analysis()
```

### Running the Workflow

```elixir
# In IEx
iex> c "data_analysis_workflow.ex"
iex> Examples.DataAnalysisWorkflow.run_analysis()

# Expected output:
# === Chain-of-Thought Data Analysis Workflow ===
#
# Step 1: Setup
#   ✓ API key configured: sk-proj...
#
# Step 2: Create Agent with CoT Runner
#
# Step 3: Configure Chain-of-Thought
#
# Step 4: Enqueue Analysis Instructions
#   ✓ 3 instructions enqueued
#
# Step 5: Execute with Chain-of-Thought Reasoning
#
# === Chain-of-Thought Reasoning Plan ===
# Goal: Process data through multi-step analysis pipeline
# ...
```

---

## Troubleshooting

### Common Issues

#### Reasoning Generation Fails

**Problem**: `{:error, "Failed to generate reasoning plan"}`

**Solutions**:

```elixir
# 1. Check API key
case Keyring.get_env_value(:openai_api_key, nil) do
  nil -> IO.puts("API key not set!")
  key -> IO.puts("Key: #{String.slice(key, 0, 7)}...")
end

# 2. Enable fallback
config = %{fallback_on_error: true}

# 3. Try simpler mode
config = %{mode: :zero_shot}  # Instead of :structured

# 4. Increase timeout
config = %{reasoning_timeout: 60_000}  # 60 seconds
```

#### Poor Reasoning Quality

**Problem**: Generated reasoning is superficial or incorrect

**Solutions**:

```elixir
# 1. Use better model
config = %{model: "gpt-4o"}  # Instead of gpt-3.5-turbo

# 2. Lower temperature
config = %{temperature: 0.1}  # More deterministic

# 3. Provide examples (few-shot)
config = %{
  mode: :few_shot,
  examples: [good_reasoning_examples]
}

# 4. Use structured mode with template
config = %{
  mode: :structured,
  template: detailed_template
}
```

#### Validation Always Fails

**Problem**: Outcomes never match reasoning expectations

**Solutions**:

```elixir
# 1. Reduce strictness
config = %{strictness: :lenient}

# 2. Check validation logic
# Review OutcomeValidator configuration

# 3. Disable validation temporarily
config = %{enable_validation: false}

# 4. Examine discrepancies
# Look at validation.discrepancies for patterns
```

#### High Latency

**Problem**: CoT adds too much overhead

**Solutions**:

```elixir
# 1. Use faster model
config = %{model: "gpt-3.5-turbo"}

# 2. Reduce max_tokens
config = %{max_tokens: 1000}  # Shorter reasoning

# 3. Use zero-shot only
config = %{mode: :zero_shot}

# 4. Apply selectively
# Only use CoT for complex tasks

# 5. Cache reasoning plans
# Store and reuse plans for similar tasks
```

#### Token Budget Exceeded

**Problem**: CoT uses too many tokens

**Solutions**:

```elixir
# 1. Limit reasoning length
config = %{max_tokens: 500}

# 2. Use simpler prompts
config = %{mode: :zero_shot}

# 3. Shorter templates
# Keep structured templates concise

# 4. Reduce iterations
config = %{max_iterations: 1}
```

#### Actions Don't Use Reasoning Context

**Problem**: Actions execute without leveraging reasoning

**Solutions**:

```elixir
# Ensure actions access reasoning context
defmodule MyAction do
  def run(params, context) do
    # Access reasoning information
    if reasoning = context[:reasoning] do
      IO.inspect(reasoning, label: "CoT Reasoning")

      # Use reasoning.current_step
      # Use reasoning.expected_outcome
      # Use reasoning.previous_results
    end

    # Action logic...
  end
end
```

### Debugging Tips

1. **Enable Verbose Logging**

```elixir
config = %{log_reasoning: true}

# Shows:
# - Generated reasoning plan
# - Each step execution
# - Validation results
# - Discrepancies
```

2. **Inspect Reasoning Plans**

```elixir
{:ok, agent, _directives} = ChainOfThought.run(agent)

plan = Jido.Agent.get(agent, :last_reasoning_plan)
IO.inspect(plan, pretty: true, limit: :infinity)
```

3. **Test Reasoning Separately**

```elixir
# Test reasoning generation in isolation
alias Jido.AI.Runner.ChainOfThought.ReasoningPrompt

instructions = [...]
prompt = ReasoningPrompt.zero_shot(instructions, %{})

# Call LLM directly
{:ok, %{content: reasoning}} = call_llm(prompt)
IO.puts(reasoning)
```

4. **Compare With and Without CoT**

```elixir
# Without CoT
{:ok, baseline_agent, baseline_results} = Jido.AI.Runner.Simple.run(agent)

# With CoT
{:ok, cot_agent, cot_results} = ChainOfThought.run(agent)

# Compare results
compare_results(baseline_results, cot_results)
```

### Getting Help

If issues persist:

1. Check [examples directory](../examples/chain-of-thought/)
2. Review [API documentation](https://hexdocs.pm/jido_ai)
3. Search [GitHub issues](https://github.com/agentjido/jido_ai/issues)
4. Ask in [Elixir Forum](https://elixirforum.com/)

---

## Conclusion

Chain-of-Thought reasoning is a powerful technique for improving LLM performance on complex tasks through structured, step-by-step thinking. Jido AI's CoT runner provides transparent integration that enhances instruction execution without requiring changes to existing actions.

### Key Takeaways

- **Accuracy Improvement**: 8-15% gain on complex reasoning with 3-4× token overhead
- **Transparent Integration**: Works with existing actions via custom runner
- **Flexible Modes**: Zero-shot, few-shot, and structured reasoning patterns
- **Validation & Recovery**: Automatic outcome validation with graceful fallback
- **Production Ready**: Error handling, retry logic, and comprehensive logging

### When to Use Chain-of-Thought

**Use CoT for:**
- Multi-step reasoning and calculations
- Complex problem solving and planning
- Code generation and debugging
- Tasks requiring intermediate verification
- Situations where accuracy justifies 3-4× cost

**Skip CoT for:**
- Simple, direct questions
- Single-step tasks
- Latency-critical operations
- Tight token budgets
- Pattern matching/classification

### Next Steps

1. **Start Simple**: Begin with zero-shot mode on representative tasks
2. **Measure Impact**: Compare accuracy with and without CoT
3. **Optimize Configuration**: Tune mode, temperature, and validation settings
4. **Scale Selectively**: Apply CoT to complex tasks, skip for simple ones
5. **Monitor Performance**: Track latency, tokens, and accuracy

### Further Reading

- [Self-Consistency Guide](./self_consistency.md) - Multiple reasoning paths with voting
- [Tree-of-Thoughts Guide](./tree_of_thoughts.md) - Multi-path exploration with backtracking
- [ReAct Guide](./react.md) - Reasoning + Acting for tool use
- [Prompt Engineering Guide](./prompt.md) - Prompt design best practices
- [Actions Guide](./actions.md) - Building custom actions

### Examples

Explore complete working examples:

- [Chain-of-Thought Examples Directory](../examples/chain-of-thought/) - Complete working implementations:
  - `calculator.ex` - Basic CoT with step-by-step mathematical reasoning
  - `problem_solver.ex` - Advanced CoT with self-correction and verification
  - `README.md` - Comprehensive documentation and usage patterns
- `lib/jido_ai/runner/chain_of_thought.ex` - Full implementation
- `test/jido_ai/runner/chain_of_thought_test.exs` - Test suite

By mastering Chain-of-Thought reasoning, you can dramatically improve your LLM-powered applications' ability to handle complex, multi-step tasks while maintaining transparency and interpretability in the reasoning process.
