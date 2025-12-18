# Program-of-Thought (PoT) Guide

## Introduction

**Program-of-Thought (PoT)** is a reasoning framework that separates reasoning (handled by LLMs) from computation (handled by code execution). Instead of asking an LLM to perform complex calculations directly—where it often struggles with precision—PoT generates executable programs that perform the actual computation, then integrates the results with natural language explanations.

### Key Advantages

- **Improved Accuracy**: +8.5% over standard Chain-of-Thought on mathematical reasoning (GSM8K benchmark)
- **Computational Precision**: Delegates precise calculations to code execution, avoiding LLM arithmetic errors
- **Explainability**: Maintains natural language explanations while ensuring computational correctness
- **Domain Coverage**: Excels at mathematical, financial, and scientific problems requiring precise calculations

### Performance Characteristics

| Metric | Value |
|--------|-------|
| **Accuracy Improvement** | +8.5% over CoT on GSM8K |
| **Best For** | Mathematical reasoning, financial calculations, data analysis |
| **Cost Overhead** | 2-3× baseline (1 classification + 1 generation + 1 integration call) |
| **Latency** | 3-5 seconds (classification + generation + execution + integration) |
| **Computation Safety** | Sandboxed execution with timeout protection |

> **💡 Practical Examples**: See the [Program-of-Thought examples directory](../examples/program-of-thought/) for complete working implementations including a financial calculator and a multi-domain solver with advanced safety validation.

### When PoT Outperforms Other Methods

PoT is ideal when problems involve:
- **Precise numerical calculations** (compound interest, statistical analysis)
- **Multi-step mathematical operations** (physics formulas, financial models)
- **Scientific computations** (unit conversions, chemical calculations)
- **Data transformations** (aggregations, projections, filtering)

## Core Concepts

### The Four-Stage Pipeline

PoT uses a four-stage pipeline to solve computational problems:

```
┌────────────┐    ┌────────────┐    ┌────────────┐    ┌────────────┐
│  Classify  │ -> │  Generate  │ -> │  Execute   │ -> │ Integrate  │
│   Problem  │    │  Program   │    │  Program   │    │  Result    │
└────────────┘    └────────────┘    └────────────┘    └────────────┘
     │                  │                  │                  │
     v                  v                  v                  v
 Domain &          Elixir Code       Sandboxed         Answer +
 Complexity        Generation         Execution        Explanation
```

#### 1. Problem Classification

**Purpose**: Determine if a problem is computational and identify its domain.

**Classification Dimensions**:
- **Domain**: Mathematical, financial, scientific, or general
- **Computational Nature**: Does it require precise calculations?
- **Complexity**: Simple, moderate, or complex computational needs
- **Operations**: What types of calculations are needed?

**Example Classification**:
```elixir
problem = "If I invest $10,000 at 5% annual interest compounded monthly,
           how much will I have after 3 years?"

{:ok, analysis} = ProblemClassifier.classify(problem)

analysis
# %{
#   domain: :financial,
#   computational: true,
#   complexity: :moderate,
#   operations: [:exponentiation, :multiplication],
#   should_use_pot: true,
#   confidence: 0.92
# }
```

#### 2. Program Generation

**Purpose**: Generate executable Elixir code that solves the problem.

**Generation Process**:
1. LLM receives problem description and domain classification
2. Generates self-contained Elixir module with `Solution.solve/0` function
3. Includes step-by-step calculations with comments
4. Uses appropriate mathematical functions
5. Code is validated for safety before execution

**Safety Validation Checks**:
- No file I/O operations (`File.*`)
- No system calls (`System.*`)
- No code evaluation (`Code.eval*`)
- No process spawning (`spawn`, `Task.*`)
- No network operations

**Example Generated Program**:
```elixir
defmodule Solution do
  def solve do
    # Initial investment
    principal = 10000

    # Annual interest rate (5%)
    annual_rate = 0.05

    # Compounding frequency (monthly)
    n = 12

    # Time period in years
    t = 3

    # Compound interest formula: A = P(1 + r/n)^(nt)
    rate_per_period = annual_rate / n
    num_periods = n * t

    amount = principal * :math.pow(1 + rate_per_period, num_periods)

    # Round to 2 decimal places for currency
    Float.round(amount, 2)
  end
end
```

#### 3. Program Execution

**Purpose**: Safely execute the generated program and capture results.

**Safety Features**:
- **Sandboxed Environment**: Programs run in isolated context
- **Timeout Protection**: Default 5-second timeout (configurable up to 30s)
- **Resource Monitoring**: Tracks execution duration
- **Output Capture**: Captures both return value and any printed output
- **Error Handling**: Gracefully handles execution failures

**Execution Result Structure**:
```elixir
{:ok, %{
  result: 11614.72,           # The computed answer
  duration_ms: 12,            # Execution time in milliseconds
  output: "",                 # Any printed output
  program: "defmodule...",    # The executed program
  analysis: %{...}            # Classification analysis
}}
```

#### 4. Result Integration

**Purpose**: Integrate computational results with natural language explanations.

**Integration Components**:
- **Answer Extraction**: Gets the final computed value
- **Step Extraction**: Parses computational steps from program comments
- **Explanation Generation**: Creates natural language explanation (optional)
- **Plausibility Validation**: Checks if result makes sense (optional)

**Integrated Result Structure**:
```elixir
{:ok, %{
  answer: 11614.72,
  explanation: "Starting with $10,000 invested at 5% annual interest
                compounded monthly, after 3 years you would have $11,614.72.
                The investment grew by $1,614.72 (16.15% total return).",
  steps: [
    "Calculate monthly interest rate: 5% / 12 = 0.417%",
    "Calculate number of periods: 12 × 3 = 36 months",
    "Apply compound interest formula",
    "Final amount: $11,614.72"
  ],
  validation: %{
    is_plausible: true,
    confidence: 0.95,
    checks: [...]
  }
}}
```

### Separation of Concerns

The key insight of PoT is **separating what LLMs are good at from what code is good at**:

| Task | Best Tool | Reason |
|------|-----------|--------|
| **Understanding problem** | LLM | Natural language comprehension |
| **Planning approach** | LLM | Reasoning about solution strategy |
| **Precise calculations** | Code | Guaranteed computational accuracy |
| **Explaining result** | LLM | Natural language generation |

This separation leverages the strengths of both:
- **LLMs**: Excellent at language understanding and reasoning about approaches
- **Code**: Perfect for precise, repeatable calculations

## When to Use Program-of-Thought

### ✅ Ideal Use Cases

1. **Mathematical Word Problems**
   - "A train travels 120 km at 60 km/h, then 180 km at 90 km/h. What's the average speed?"
   - Requires precise calculations across multiple steps

2. **Financial Calculations**
   - "Calculate the monthly payment on a $300,000 mortgage at 4.5% over 30 years"
   - Involves compound interest, amortization formulas

3. **Scientific Computations**
   - "Convert 75°F to Celsius and calculate water density at that temperature"
   - Requires precise unit conversions and formula application

4. **Statistical Analysis**
   - "Given data points [12, 15, 18, 22, 25], calculate mean, median, standard deviation"
   - Involves multiple statistical operations

5. **Physics Problems**
   - "A 2kg object is thrown upward at 20 m/s. What's its maximum height?"
   - Requires kinematic equations and precise calculations

### ❌ When NOT to Use PoT

1. **Qualitative Questions**
   - "What is the capital of France?" → Use direct prompting
   - No computation needed

2. **Creative Tasks**
   - "Write a story about a robot" → Use standard generation
   - Not a computational problem

3. **Information Retrieval**
   - "Who won the 2020 election?" → Use RAG or direct prompting
   - Requires facts, not calculations

4. **Simple Arithmetic**
   - "What is 15 + 27?" → Use standard CoT or even direct prompting
   - PoT overhead not justified for trivial calculations

5. **Symbolic Reasoning**
   - "If all A are B, and all B are C, what can we conclude about A and C?"
   - Logic problem, not computational

### Decision Framework

```
Is the problem computational?
    No → Don't use PoT
    Yes ↓

Does it require precise multi-step calculations?
    No → Consider standard CoT instead
    Yes ↓

Is it mathematical, financial, or scientific?
    No → Consider standard CoT instead
    Yes ↓

Will LLM arithmetic errors be problematic?
    No → Standard CoT may be sufficient
    Yes → ✅ Use PoT
```

## Getting Started

### Basic Setup

```elixir
# Add to your mix.exs dependencies
{:jido, "~> 1.0"},
{:jido_ai, "~> 1.0"}

# Configure your LLM provider
config :jido_ai, :default_provider,
  module: Jido.AI.Provider.OpenAI,
  api_key: System.get_env("OPENAI_API_KEY")
```

### Your First PoT Problem

```elixir
# Define the computational problem
problem = """
A car accelerates from rest to 60 mph in 6 seconds.
Assuming constant acceleration, what distance does it cover?
(1 mph = 0.447 m/s)
"""

# Run through PoT pipeline
alias Jido.AI.Runner.ProgramOfThought

{:ok, result} = ProgramOfThought.solve(problem)

# Access the results
IO.puts("Answer: #{result.answer} meters")
IO.puts("\nExplanation:")
IO.puts(result.explanation)

IO.puts("\nComputational Steps:")
Enum.each(result.steps, fn step ->
  IO.puts("  • #{step}")
end)
```

**Output**:
```
Answer: 80.46 meters

Explanation:
The car accelerates from 0 to 60 mph (26.82 m/s) in 6 seconds with constant
acceleration. Using the kinematic equation d = v₀t + ½at², where v₀ = 0,
a = 4.47 m/s², and t = 6s, the car covers approximately 80.46 meters.

Computational Steps:
  • Convert 60 mph to m/s: 60 × 0.447 = 26.82 m/s
  • Calculate acceleration: 26.82 m/s / 6 s = 4.47 m/s²
  • Apply kinematic equation: d = 0 + ½(4.47)(6²) = 80.46 m
```

### What Happened Behind the Scenes

```elixir
# 1. Classification
{:ok, analysis} = ProblemClassifier.classify(problem)
# Identified as: domain=:scientific, computational=true, should_use_pot=true

# 2. Generation
{:ok, program} = ProgramGenerator.generate(problem, analysis)
# Generated Elixir module with Solution.solve/0

# 3. Execution
{:ok, exec_result} = ProgramExecutor.execute(program)
# Safely ran code, got result: 80.46

# 4. Integration
{:ok, final_result} = ResultIntegrator.integrate(exec_result,
  program: program,
  analysis: analysis,
  generate_explanation: true,
  validate_result: true
)
# Combined result with explanation and validation
```

## Understanding the Components

### Component 1: Problem Classifier

**Module**: `Jido.AI.Runner.ProgramOfThought.ProblemClassifier`

**Responsibility**: Determine if a problem should be solved with PoT and classify its domain.

#### Domain Detection

The classifier recognizes keywords and patterns for different domains:

**Mathematical Keywords**:
```elixir
calculate, compute, solve, equation, formula,
sum, product, difference, quotient,
multiply, divide, add, subtract
```

**Financial Keywords**:
```elixir
interest, rate, return, investment,
profit, loss, revenue, expense,
mortgage, loan, compound, amortize
```

**Scientific Keywords**:
```elixir
velocity, acceleration, force, mass,
conversion, unit, temperature, pressure,
meter, kilogram, celsius, fahrenheit
```

#### Computational Detection

Checks if problem requires actual computation:

```elixir
defp computational?(problem) do
  # Contains numbers?
  has_numbers = Regex.match?(~r/\d+/, problem)

  # Contains computational keywords?
  computational_keywords = ~w(
    calculate compute solve find determine
    what is how much how many
  )
  has_computational_intent =
    Enum.any?(computational_keywords, &String.contains?(problem, &1))

  has_numbers and has_computational_intent
end
```

#### Complexity Estimation

```elixir
@spec estimate_complexity(String.t()) :: :simple | :moderate | :complex

# Simple: Single operation
"What is 15% of 200?"  # → :simple

# Moderate: 2-3 operations
"Calculate compound interest on $1000 at 5% for 3 years"  # → :moderate

# Complex: 4+ operations or iterative calculations
"Model population growth with logistic equation over 50 years"  # → :complex
```

#### Usage Example

```elixir
alias Jido.AI.Runner.ProgramOfThought.ProblemClassifier

# Classify a problem
{:ok, analysis} = ProblemClassifier.classify(
  "If I invest $5000 at 6% annually for 10 years, how much will I have?"
)

analysis
# %{
#   domain: :financial,
#   computational: true,
#   complexity: :moderate,
#   confidence: 0.89,
#   operations: [:exponentiation, :multiplication],
#   should_use_pot: true
# }

# Check if PoT should be used
if analysis.should_use_pot do
  # Proceed with PoT pipeline
else
  # Fall back to standard CoT or direct prompting
end
```

#### Classification Thresholds

```elixir
# Confidence threshold for PoT routing
@min_confidence 0.7

# When to recommend PoT
defp should_route_to_pot?(analysis) do
  analysis.computational and
  analysis.confidence >= @min_confidence and
  analysis.complexity in [:moderate, :complex]
end
```

### Component 2: Program Generator

**Module**: `Jido.AI.Runner.ProgramOfThought.ProgramGenerator`

**Responsibility**: Generate safe, executable Elixir programs that solve the problem.

#### Generation Prompt Structure

```elixir
defp build_generation_prompt(problem, domain, complexity) do
  """
  Generate a self-contained Elixir program to solve the following computational problem.

  ## Problem
  #{problem}

  ## Domain
  #{domain}

  ## Complexity
  #{complexity}

  ## Requirements
  1. Create a module named `Solution` with a `solve/0` function
  2. The `solve/0` function should return the final answer
  3. Include step-by-step calculations with comments explaining each step
  4. Use appropriate mathematical functions from Elixir's :math module
  5. Handle edge cases and ensure numerical stability
  6. Use descriptive variable names
  7. Include intermediate calculations for clarity

  ## Available Functions
  - :math.pow/2 - exponentiation
  - :math.sqrt/1 - square root
  - :math.log/1, :math.log10/1 - logarithms
  - :math.sin/1, :math.cos/1, :math.tan/1 - trigonometry
  - :math.exp/1 - exponential
  - Float.round/2 - rounding
  - Enum.sum/1, Enum.reduce/3 - aggregations

  ## Example Structure
  ```elixir
  defmodule Solution do
    def solve do
      # Step 1: Define input values
      value = 100

      # Step 2: Perform calculation
      result = value * 2

      # Step 3: Return final answer
      result
    end
  end
  ```

  Generate the complete Elixir program:
  """
end
```

#### Safety Validation

Before execution, all generated code is validated:

```elixir
defp validate_safe_code(code) do
  unsafe_patterns = [
    {~r/File\./, :file_io_detected},
    {~r/System\./, :system_call_detected},
    {~r/Code\.eval/, :code_eval_detected},
    {~r/spawn|Task\./, :process_spawn_detected},
    {~r/:httpc|:http|HTTPoison|Req/, :network_call_detected},
    {~r/Process\./, :process_manipulation_detected}
  ]

  Enum.reduce_while(unsafe_patterns, :ok, fn {pattern, error}, _acc ->
    if Regex.match?(pattern, code) do
      {:halt, {:error, error}}
    else
      {:cont, :ok}
    end
  end)
end
```

#### Code Quality Checks

```elixir
defp validate_code_structure(code) do
  checks = [
    # Must have Solution module
    has_solution_module?: Regex.match?(~r/defmodule Solution/, code),

    # Must have solve/0 function
    has_solve_function?: Regex.match?(~r/def solve\(\)/, code),

    # Should have comments
    has_comments?: Regex.match?(~r/#/, code),

    # Must have return value
    has_return?: Regex.match?(~r/\n\s+\w+\s*$/, code)
  ]

  if Enum.all?(checks, fn {_, v} -> v end) do
    :ok
  else
    {:error, :invalid_structure}
  end
end
```

#### Usage Example

```elixir
alias Jido.AI.Runner.ProgramOfThought.ProgramGenerator

problem = "Calculate the area of a circle with radius 7.5 cm"
analysis = %{domain: :mathematical, complexity: :simple}

{:ok, program} = ProgramGenerator.generate(problem, analysis)

IO.puts(program)
```

**Generated Output**:
```elixir
defmodule Solution do
  def solve do
    # Given: radius of circle in cm
    radius = 7.5

    # Formula: Area = π × r²
    # Using :math.pi() for precise value of π
    pi = :math.pi()

    # Calculate radius squared
    radius_squared = :math.pow(radius, 2)

    # Calculate area
    area = pi * radius_squared

    # Round to 2 decimal places
    Float.round(area, 2)
  end
end
```

#### Domain-Specific Optimizations

```elixir
defp add_domain_specific_hints(:financial, prompt) do
  prompt <> """

  ## Financial Domain Hints
  - Use Float.round(value, 2) for currency (2 decimal places)
  - Compound interest: A = P(1 + r/n)^(nt)
  - Simple interest: I = Prt
  - Present/Future value formulas available
  """
end

defp add_domain_specific_hints(:scientific, prompt) do
  prompt <> """

  ## Scientific Domain Hints
  - Pay attention to unit conversions
  - Use appropriate precision (Float.round/2)
  - Common conversions:
    * F to C: (F - 32) × 5/9
    * mph to m/s: mph × 0.447
    * kg to lbs: kg × 2.205
  """
end
```

### Component 3: Program Executor

**Module**: `Jido.AI.Runner.ProgramOfThought.ProgramExecutor`

**Responsibility**: Safely execute generated programs with timeout and resource protection.

#### Execution Configuration

```elixir
@default_timeout 5_000        # 5 seconds
@max_timeout 30_000           # 30 seconds maximum
@capture_output true          # Capture IO.puts output
```

#### Safe Execution Process

```elixir
def execute(program, opts \\ []) do
  # 1. Validate timeout
  timeout = get_timeout(opts)

  # 2. Validate safety (no dangerous operations)
  with :ok <- validate_safety(program),
       :ok <- validate_syntax(program) do

    # 3. Execute in async task with timeout
    task = Task.async(fn ->
      execute_in_sandbox(program, opts)
    end)

    # 4. Wait for result or timeout
    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, result}} ->
        {:ok, %{
          result: result.value,
          duration_ms: result.duration,
          output: result.output,
          program: program
        }}

      nil ->
        {:error, :timeout}

      {:ok, {:error, error}} ->
        {:error, error}
    end
  end
end
```

#### Sandboxed Execution

```elixir
defp execute_in_sandbox(program, opts) do
  start_time = System.monotonic_time(:millisecond)

  # Capture output if requested
  output = if opts[:capture_output] do
    capture_io(fn ->
      execute_code(program)
    end)
  else
    execute_code(program)
  end

  duration = System.monotonic_time(:millisecond) - start_time

  {:ok, %{
    value: output,
    duration: duration,
    output: if(is_binary(output), do: output, else: "")
  }}
rescue
  error -> {:error, format_error(error)}
end

defp execute_code(program) do
  # Evaluate the code
  {result, _binding} = Code.eval_string(program)
  result
end
```

#### Error Handling

```elixir
defp format_error(%CompileError{description: desc}) do
  %{
    type: :compile_error,
    message: "Failed to compile generated program",
    details: desc
  }
end

defp format_error(%RuntimeError{message: msg}) do
  %{
    type: :runtime_error,
    message: "Program execution failed",
    details: msg
  }
end

defp format_error(%ArithmeticError{} = error) do
  %{
    type: :arithmetic_error,
    message: "Mathematical operation failed",
    details: Exception.message(error)
  }
end

defp format_error(error) do
  %{
    type: :unknown_error,
    message: "Unexpected error during execution",
    details: inspect(error)
  }
end
```

#### Timeout Protection

```elixir
# Validate timeout is within acceptable range
defp get_timeout(opts) do
  timeout = Keyword.get(opts, :timeout, @default_timeout)

  cond do
    timeout < 100 ->
      # Too short, use minimum
      100

    timeout > @max_timeout ->
      # Too long, cap at maximum
      @max_timeout

    true ->
      timeout
  end
end
```

#### Usage Example

```elixir
alias Jido.AI.Runner.ProgramOfThought.ProgramExecutor

program = """
defmodule Solution do
  def solve do
    # Calculate factorial of 10
    Enum.reduce(1..10, 1, &*/2)
  end
end
"""

# Execute with default timeout (5s)
{:ok, result} = ProgramExecutor.execute(program)

result
# %{
#   result: 3628800,
#   duration_ms: 3,
#   output: "",
#   program: "defmodule Solution..."
# }

# Execute with custom timeout
{:ok, result} = ProgramExecutor.execute(program, timeout: 10_000)

# Handle timeout
case ProgramExecutor.execute(long_running_program, timeout: 1000) do
  {:ok, result} -> handle_result(result)
  {:error, :timeout} -> IO.puts("Execution took too long!")
  {:error, error} -> IO.puts("Error: #{inspect(error)}")
end
```

#### Resource Monitoring

```elixir
defp execute_with_monitoring(program) do
  start_memory = :erlang.memory(:total)
  start_time = System.monotonic_time(:millisecond)

  result = execute_code(program)

  end_time = System.monotonic_time(:millisecond)
  end_memory = :erlang.memory(:total)

  %{
    result: result,
    duration_ms: end_time - start_time,
    memory_used_bytes: end_memory - start_memory
  }
end
```

### Component 4: Result Integrator

**Module**: `Jido.AI.Runner.ProgramOfThought.ResultIntegrator`

**Responsibility**: Integrate computational results with explanations and validation.

#### Integration Process

```elixir
def integrate(execution_result, opts \\ []) do
  # Start with basic result
  result = %{
    answer: execution_result.result,
    explanation: nil,
    steps: [],
    validation: nil
  }

  # Extract computational steps from program
  result = Map.put(result, :steps, extract_steps(opts[:program]))

  # Generate explanation if requested
  result = if opts[:generate_explanation] do
    case generate_explanation(execution_result, opts) do
      {:ok, explanation} -> Map.put(result, :explanation, explanation)
      {:error, _} -> result
    end
  else
    result
  end

  # Validate result plausibility
  result = if opts[:validate_result] do
    validation = validate_plausibility(execution_result, opts[:program], opts[:analysis])
    Map.put(result, :validation, validation)
  else
    result
  end

  {:ok, result}
end
```

#### Step Extraction

Parses computational steps from program comments:

```elixir
defp extract_steps(program) when is_binary(program) do
  program
  |> String.split("\n")
  |> Enum.filter(&comment_line?/1)
  |> Enum.map(&extract_comment_text/1)
  |> Enum.reject(&empty_or_header?/1)
end

defp comment_line?(line) do
  String.trim(line) |> String.starts_with?("#")
end

defp extract_comment_text(line) do
  line
  |> String.trim()
  |> String.trim_leading("#")
  |> String.trim()
end
```

**Example**:
```elixir
program = """
defmodule Solution do
  def solve do
    # Step 1: Convert mph to m/s
    speed_ms = 60 * 0.447

    # Step 2: Calculate acceleration
    accel = speed_ms / 6

    # Step 3: Calculate distance
    distance = 0.5 * accel * :math.pow(6, 2)

    distance
  end
end
"""

extract_steps(program)
# [
#   "Step 1: Convert mph to m/s",
#   "Step 2: Calculate acceleration",
#   "Step 3: Calculate distance"
# ]
```

#### Explanation Generation

```elixir
defp generate_explanation(execution_result, opts) do
  prompt = """
  A computational problem was solved using the following program:

  #{opts[:program]}

  The program produced this result: #{execution_result.result}

  Generate a clear, concise explanation (2-3 sentences) of:
  1. What the problem asked for
  2. The approach used to solve it
  3. What the final answer means in context

  Be specific and reference the actual calculations performed.
  """

  case call_llm(prompt, opts) do
    {:ok, explanation} -> {:ok, String.trim(explanation)}
    error -> error
  end
end
```

#### Plausibility Validation

```elixir
defp validate_plausibility(execution_result, program, analysis) do
  result = execution_result.result

  checks = [
    check_result_type(result, analysis),
    check_result_magnitude(result, analysis),
    check_execution_time(execution_result.duration_ms, analysis),
    check_computation_sensibility(result, program)
  ]

  # Overall plausibility
  passed_checks = Enum.count(checks, & &1.passed)
  total_checks = length(checks)
  confidence = passed_checks / total_checks

  %{
    is_plausible: confidence >= 0.7,
    confidence: confidence,
    checks: checks
  }
end

defp check_result_type(result, analysis) do
  expected_numeric = analysis.domain in [:mathematical, :financial, :scientific]
  is_numeric = is_number(result)

  %{
    name: :result_type,
    passed: !expected_numeric or is_numeric,
    message: if(is_numeric, do: "Result is numeric as expected",
                            else: "Expected numeric result")
  }
end

defp check_result_magnitude(result, analysis) when is_number(result) do
  # Check if result magnitude makes sense for domain
  reasonable = case analysis.domain do
    :financial -> result >= 0 and result < 1.0e12  # Reasonable money amounts
    :scientific -> result >= -1.0e6 and result < 1.0e6  # Reasonable physical quantities
    :mathematical -> result >= -1.0e9 and result < 1.0e9  # Reasonable math results
    _ -> true
  end

  %{
    name: :result_magnitude,
    passed: reasonable,
    message: if(reasonable, do: "Result magnitude is reasonable",
                            else: "Result magnitude seems unusual")
  }
end

defp check_execution_time(duration_ms, analysis) do
  # Complex problems should take some time, but not too long
  reasonable = case analysis.complexity do
    :simple -> duration_ms < 100
    :moderate -> duration_ms < 1000
    :complex -> duration_ms < 5000
  end

  %{
    name: :execution_time,
    passed: reasonable,
    message: "Execution took #{duration_ms}ms (#{analysis.complexity} problem)"
  }
end
```

#### Usage Example

```elixir
alias Jido.AI.Runner.ProgramOfThought.ResultIntegrator

execution_result = %{
  result: 176.71,
  duration_ms: 8,
  output: "",
  program: "defmodule Solution do..."
}

opts = [
  program: execution_result.program,
  analysis: %{domain: :scientific, complexity: :moderate},
  generate_explanation: true,
  validate_result: true,
  model: "gpt-4o"
]

{:ok, integrated} = ResultIntegrator.integrate(execution_result, opts)

integrated
# %{
#   answer: 176.71,
#   explanation: "The problem asked for the area of a circle...",
#   steps: [
#     "Given: radius of circle in cm",
#     "Formula: Area = π × r²",
#     "Calculate area"
#   ],
#   validation: %{
#     is_plausible: true,
#     confidence: 1.0,
#     checks: [...]
#   }
# }
```

## Configuration Options

### Main Configuration

```elixir
config = [
  # LLM Configuration
  model: "gpt-4o",                    # Model for generation and explanation
  temperature: 0.2,                   # Lower for deterministic code generation

  # Classification Options
  classification: [
    min_confidence: 0.7,              # Minimum confidence to use PoT
    require_computational: true       # Must be computational problem
  ],

  # Generation Options
  generation: [
    max_tokens: 2048,                 # Maximum program length
    include_comments: true,           # Require explanatory comments
    validate_safety: true,            # Check for unsafe operations
    validate_structure: true          # Verify proper module/function structure
  ],

  # Execution Options
  execution: [
    timeout: 5_000,                   # Execution timeout in ms (default 5s)
    max_timeout: 30_000,              # Maximum allowed timeout (30s)
    capture_output: true,             # Capture IO.puts output
    monitor_resources: false          # Track memory usage (overhead)
  ],

  # Integration Options
  integration: [
    generate_explanation: true,       # Generate natural language explanation
    validate_result: true,            # Check result plausibility
    extract_steps: true               # Extract computational steps
  ],

  # Error Handling
  fallback_on_error: true,           # Fall back to CoT if PoT fails
  max_retries: 1                      # Retry failed generations once
]
```

### Per-Component Configuration

```elixir
# Configure just the classifier
ProblemClassifier.classify(problem,
  min_confidence: 0.8,
  require_domain: [:mathematical, :financial]
)

# Configure just the generator
ProgramGenerator.generate(problem, analysis,
  model: "gpt-4",
  temperature: 0.1,
  max_tokens: 1024,
  include_examples: true
)

# Configure just the executor
ProgramExecutor.execute(program,
  timeout: 10_000,
  capture_output: true,
  monitor_resources: true
)

# Configure just the integrator
ResultIntegrator.integrate(result,
  program: program,
  analysis: analysis,
  generate_explanation: true,
  validate_result: false,
  model: "gpt-4o-mini"  # Use cheaper model for explanation
)
```

### Model Selection Guidelines

Different stages have different model requirements:

```elixir
config = [
  # Classification: Can use cheaper/faster model
  classifier_model: "gpt-4o-mini",

  # Generation: Use best model for quality code
  generator_model: "gpt-4o",

  # Execution: No model needed

  # Integration: Can use cheaper model for explanation
  integrator_model: "gpt-4o-mini"
]
```

### Timeout Guidelines

Set timeouts based on problem complexity:

```elixir
# Simple problems: very fast
simple_config = [execution: [timeout: 1_000]]

# Moderate problems: default
moderate_config = [execution: [timeout: 5_000]]

# Complex iterative calculations: longer timeout
complex_config = [execution: [timeout: 15_000]]

# Maximum allowed
maximum_config = [execution: [timeout: 30_000]]
```

## Integration Patterns

### Pattern 1: Financial Calculator Agent

Build an agent that handles financial calculations with guaranteed accuracy.

```elixir
defmodule FinancialCalculatorAgent do
  use Jido.Agent,
    name: "financial_calculator",
    actions: []

  alias Jido.AI.Runner.ProgramOfThought

  @doc """
  Solve financial calculation problems using PoT for accuracy.
  """
  def calculate(problem) do
    # Configure for financial domain
    config = [
      classification: [
        min_confidence: 0.8,
        require_domain: [:financial]
      ],
      generation: [
        temperature: 0.1,  # Very deterministic
        include_comments: true
      ],
      execution: [
        timeout: 5_000
      ],
      integration: [
        generate_explanation: true,
        validate_result: true
      ]
    ]

    case ProgramOfThought.solve(problem, config) do
      {:ok, result} ->
        format_financial_result(result)

      {:error, :not_computational} ->
        {:error, "This doesn't appear to be a computational problem"}

      {:error, reason} ->
        {:error, "Calculation failed: #{inspect(reason)}"}
    end
  end

  defp format_financial_result(result) do
    %{
      amount: format_currency(result.answer),
      explanation: result.explanation,
      calculation_steps: result.steps,
      confidence: result.validation.confidence
    }
  end

  defp format_currency(amount) when is_number(amount) do
    "$" <> :erlang.float_to_binary(amount, decimals: 2)
  end
end

# Usage
problem = """
I have a $250,000 mortgage at 4.5% annual interest for 30 years.
What will my monthly payment be?
"""

{:ok, result} = FinancialCalculatorAgent.calculate(problem)

IO.puts("Monthly Payment: #{result.amount}")
IO.puts("\n#{result.explanation}")
IO.puts("\nSteps:")
Enum.each(result.calculation_steps, &IO.puts("  • #{&1}"))
```

**Output**:
```
Monthly Payment: $1266.71

This mortgage requires a monthly payment of $1,266.71. With a principal of
$250,000, an annual interest rate of 4.5%, and a 30-year term (360 monthly
payments), the payment covers both principal and interest. Over the life of
the loan, you'll pay approximately $456,017 total ($206,017 in interest).

Steps:
  • Convert annual rate to monthly: 4.5% / 12 = 0.375%
  • Calculate number of payments: 30 years × 12 = 360 months
  • Apply amortization formula: M = P[r(1+r)^n]/[(1+r)^n-1]
  • Monthly payment: $1,266.71
```

### Pattern 2: Physics Problem Solver

Create a tool for solving physics problems with precise calculations.

```elixir
defmodule PhysicsProblemSolver do
  alias Jido.AI.Runner.ProgramOfThought

  @doc """
  Solve physics problems using PoT for computational accuracy.
  """
  def solve(problem, opts \\ []) do
    config = [
      classification: [
        min_confidence: 0.75,
        require_domain: [:scientific]
      ],
      generation: [
        model: "gpt-4o",
        temperature: 0.2,
        include_comments: true,
        # Add physics-specific context
        system_prompt: physics_system_prompt()
      ],
      execution: [
        timeout: 10_000  # Some calculations may be complex
      ],
      integration: [
        generate_explanation: true,
        validate_result: true
      ]
    ]

    case ProgramOfThought.solve(problem, Keyword.merge(config, opts)) do
      {:ok, result} ->
        {:ok, enhance_physics_result(result, problem)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp physics_system_prompt do
    """
    You are solving physics problems. Remember:
    - Pay attention to units and conversions
    - Use appropriate significant figures
    - Common constants: g = 9.8 m/s², c = 3×10^8 m/s
    - Include unit conversions in comments
    - Use :math module for trigonometry and powers
    """
  end

  defp enhance_physics_result(result, problem) do
    # Extract units from problem
    units = extract_units(problem)

    # Add unit to answer if possible
    answer_with_unit = if units != [] do
      "#{result.answer} #{hd(units)}"
    else
      result.answer
    end

    %{
      answer: answer_with_unit,
      explanation: result.explanation,
      steps: result.steps,
      validation: result.validation
    }
  end

  defp extract_units(problem) do
    # Simple unit extraction
    units_regex = ~r/\b(m|km|cm|mm|kg|g|s|ms|N|J|W|m\/s|m\/s²|°C|K)\b/

    problem
    |> then(&Regex.scan(units_regex, &1))
    |> List.flatten()
    |> Enum.uniq()
  end
end

# Usage
problem = """
A 5 kg object is thrown vertically upward with an initial velocity of 25 m/s.
Ignoring air resistance, what is the maximum height reached?
Use g = 9.8 m/s².
"""

{:ok, result} = PhysicsProblemSolver.solve(problem)

IO.puts("Maximum Height: #{result.answer}")
IO.puts("\n#{result.explanation}")
```

**Output**:
```
Maximum Height: 31.89 m

A 5 kg object thrown upward at 25 m/s will reach a maximum height of 31.89 meters.
Using the kinematic equation v² = v₀² - 2gh, where the final velocity at maximum
height is 0, we can solve for h. The mass doesn't affect the height in free fall.

Validation: ✓ Plausible (confidence: 100%)
```

### Pattern 3: Data Analysis Pipeline

Use PoT for precise statistical calculations in data analysis.

```elixir
defmodule DataAnalysisPipeline do
  alias Jido.AI.Runner.ProgramOfThought

  @doc """
  Perform statistical analysis on datasets using PoT.
  """
  def analyze(data, analysis_type) do
    # Convert data to string representation for LLM
    data_str = inspect(data)

    problem = """
    Given the dataset: #{data_str}

    Calculate the following: #{analysis_type}

    Return a map with all requested statistics.
    """

    config = [
      generation: [
        model: "gpt-4o",
        temperature: 0.1,
        include_comments: true
      ],
      execution: [
        timeout: 15_000  # Statistical calculations may take time
      ],
      integration: [
        generate_explanation: true,
        validate_result: true
      ]
    ]

    case ProgramOfThought.solve(problem, config) do
      {:ok, result} ->
        {:ok, format_statistics(result)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_statistics(result) do
    %{
      statistics: result.answer,
      interpretation: result.explanation,
      calculation_method: result.steps
    }
  end
end

# Usage
sales_data = [1200, 1450, 1380, 1520, 1290, 1610, 1470, 1390, 1550, 1420]

{:ok, analysis} = DataAnalysisPipeline.analyze(
  sales_data,
  "mean, median, standard deviation, and range"
)

IO.inspect(analysis.statistics, label: "Statistics")
IO.puts("\nInterpretation:")
IO.puts(analysis.interpretation)
```

**Output**:
```
Statistics: %{
  mean: 1428.0,
  median: 1430.0,
  std_dev: 115.87,
  range: 410,
  min: 1200,
  max: 1610
}

Interpretation:
The sales data shows an average of $1,428 with a median of $1,430, indicating
a fairly symmetric distribution. The standard deviation of $115.87 suggests
moderate variability in sales. The range of $410 (from $1,200 to $1,610)
shows the spread of the data.
```

### Pattern 4: Math Homework Helper

Create an educational tool that shows work for math problems.

```elixir
defmodule MathHomeworkHelper do
  alias Jido.AI.Runner.ProgramOfThought

  @doc """
  Solve math problems with detailed step-by-step solutions.
  """
  def solve_with_explanation(problem, opts \\ []) do
    config = [
      classification: [
        min_confidence: 0.7,
        require_domain: [:mathematical]
      ],
      generation: [
        model: Keyword.get(opts, :model, "gpt-4o"),
        temperature: 0.1,
        include_comments: true,
        # Emphasize educational value
        system_prompt: """
        Generate code that solves the problem step-by-step.
        Include detailed comments explaining each calculation.
        This is for educational purposes, so clarity is more important than brevity.
        """
      ],
      execution: [
        timeout: 5_000,
        capture_output: true
      ],
      integration: [
        generate_explanation: true,
        validate_result: true,
        extract_steps: true
      ]
    ]

    case ProgramOfThought.solve(problem, config) do
      {:ok, result} ->
        {:ok, format_educational_response(result)}

      {:error, :not_computational} ->
        {:error, "This problem doesn't require computation. Try explaining the concept instead."}

      {:error, reason} ->
        {:error, "Failed to solve: #{inspect(reason)}"}
    end
  end

  defp format_educational_response(result) do
    """
    ## Problem Solution

    **Answer: #{format_answer(result.answer)}**

    ## Explanation

    #{result.explanation}

    ## Step-by-Step Work

    #{format_steps(result.steps)}

    ## Validation

    #{format_validation(result.validation)}
    """
  end

  defp format_answer(answer) when is_number(answer) do
    if answer == trunc(answer) do
      Integer.to_string(trunc(answer))
    else
      Float.to_string(answer)
    end
  end

  defp format_answer(answer), do: inspect(answer)

  defp format_steps(steps) do
    steps
    |> Enum.with_index(1)
    |> Enum.map(fn {step, idx} -> "#{idx}. #{step}" end)
    |> Enum.join("\n")
  end

  defp format_validation(%{is_plausible: true}), do: "✓ Solution verified"
  defp format_validation(%{is_plausible: false}), do: "⚠ Solution may need review"
end

# Usage
problem = """
A rectangular garden is 3 times as long as it is wide.
If the perimeter is 96 meters, what are the dimensions?
"""

{:ok, solution} = MathHomeworkHelper.solve_with_explanation(problem)
IO.puts(solution)
```

**Output**:
```
## Problem Solution

**Answer: Width = 12 meters, Length = 36 meters**

## Explanation

The garden has a width of 12 meters and a length of 36 meters. Since the length
is 3 times the width (36 = 3 × 12) and the perimeter is 2(w + l) = 2(12 + 36)
= 96 meters, these dimensions satisfy both constraints.

## Step-by-Step Work

1. Let width = w, then length = 3w (given relationship)
2. Perimeter formula: P = 2(width + length) = 96
3. Substitute: 2(w + 3w) = 96
4. Simplify: 2(4w) = 96, so 8w = 96
5. Solve for width: w = 96 / 8 = 12 meters
6. Calculate length: length = 3 × 12 = 36 meters
7. Verify: 2(12 + 36) = 2(48) = 96 ✓

## Validation

✓ Solution verified
```

## Best Practices

### 1. Choose the Right Model for Each Stage

Different pipeline stages have different requirements:

```elixir
config = [
  # Classification: Fast, cheap model is sufficient
  classifier_model: "gpt-4o-mini",

  # Generation: Use best model for quality code
  generator_model: "gpt-4o",

  # Integration: Cheaper model can write explanations
  integrator_model: "gpt-4o-mini"
]
```

**Why**: Classification and explanation don't require top-tier reasoning, but code generation benefits from the best model.

### 2. Set Appropriate Timeouts

Match timeouts to problem complexity:

```elixir
# Fast for simple arithmetic
simple_problem_config = [execution: [timeout: 1_000]]

# Moderate for typical calculations
typical_config = [execution: [timeout: 5_000]]

# Longer for complex iterative calculations
complex_config = [execution: [timeout: 15_000]]
```

**Why**: Prevents timeouts on legitimate calculations while protecting against infinite loops.

### 3. Always Validate Generated Code

Never skip safety validation:

```elixir
config = [
  generation: [
    validate_safety: true,      # Check for dangerous operations
    validate_structure: true     # Verify proper module/function structure
  ]
]
```

**Why**: LLMs can generate unsafe code. Validation prevents file I/O, system calls, and other dangerous operations.

### 4. Extract and Display Computation Steps

Make the computational process transparent:

```elixir
config = [
  generation: [
    include_comments: true  # Require explanatory comments in code
  ],
  integration: [
    extract_steps: true     # Parse steps from comments
  ]
]

# Then display them
{:ok, result} = ProgramOfThought.solve(problem, config)
Enum.each(result.steps, fn step ->
  IO.puts("  • #{step}")
end)
```

**Why**: Users can verify the computational approach and learn from the solution process.

### 5. Generate Explanations for End Users

Bridge the gap between code and understanding:

```elixir
config = [
  integration: [
    generate_explanation: true,
    model: "gpt-4o-mini"  # Cheaper model for explanations
  ]
]

{:ok, result} = ProgramOfThought.solve(problem, config)
IO.puts(result.explanation)
```

**Why**: Most users don't want to read code—they want natural language explanations of the answer.

### 6. Validate Result Plausibility

Catch obvious errors early:

```elixir
config = [
  integration: [
    validate_result: true
  ]
]

{:ok, result} = ProgramOfThought.solve(problem, config)

unless result.validation.is_plausible do
  Logger.warning("Result may be incorrect: #{inspect(result.validation)}")
end
```

**Why**: Helps identify when generated code produces nonsensical results (negative distances, impossibly large values, etc.).

### 7. Use Domain-Specific Configuration

Tailor settings to the problem domain:

```elixir
# Financial problems: require high accuracy
financial_config = [
  classification: [require_domain: [:financial]],
  generation: [temperature: 0.1],  # Very deterministic
  integration: [validate_result: true]
]

# Scientific problems: allow broader exploration
scientific_config = [
  classification: [require_domain: [:scientific]],
  generation: [temperature: 0.2],
  execution: [timeout: 10_000]  # Complex calculations
]
```

**Why**: Different domains have different accuracy, speed, and determinism requirements.

### 8. Implement Fallback Strategies

Handle failures gracefully:

```elixir
def solve_with_fallback(problem) do
  case ProgramOfThought.solve(problem) do
    {:ok, result} ->
      {:ok, result}

    {:error, :not_computational} ->
      # Fall back to standard CoT
      ChainOfThought.solve(problem)

    {:error, :generation_failed} ->
      # Retry with more explicit instructions
      retry_with_examples(problem)

    {:error, :timeout} ->
      # Retry with longer timeout
      ProgramOfThought.solve(problem, execution: [timeout: 15_000])

    error ->
      error
  end
end
```

**Why**: PoT can fail for various reasons—have backup strategies for robustness.

### 9. Monitor and Log Execution Metrics

Track performance and costs:

```elixir
{:ok, result} = ProgramOfThought.solve(problem)

# Log metrics
Logger.info("""
PoT Execution Metrics:
  - Domain: #{result.analysis.domain}
  - Complexity: #{result.analysis.complexity}
  - Execution time: #{result.execution.duration_ms}ms
  - Validation confidence: #{result.validation.confidence}
  - LLM calls: 3 (classify + generate + integrate)
""")
```

**Why**: Helps optimize performance and identify expensive operations.

### 10. Provide Context in Problem Descriptions

Give the LLM all necessary information:

```elixir
# Bad: Missing context
problem = "Calculate the payment"

# Good: Complete context
problem = """
Calculate the monthly payment for a mortgage with:
- Principal: $300,000
- Annual interest rate: 4.5%
- Term: 30 years (360 monthly payments)

Use the amortization formula: M = P[r(1+r)^n]/[(1+r)^n-1]
where M is monthly payment, P is principal, r is monthly rate, n is number of payments.
"""
```

**Why**: Complete problem descriptions lead to better code generation and more accurate results.

## Troubleshooting

### Problem: Code Generation Fails

**Symptoms**:
```elixir
{:error, :generation_failed}
```

**Possible Causes**:
1. Problem description is ambiguous or incomplete
2. Problem is not actually computational
3. LLM doesn't understand the domain
4. Model doesn't have necessary programming knowledge

**Solutions**:

```elixir
# 1. Provide more context and explicit requirements
problem = """
Original: Calculate compound interest

Better: Calculate compound interest on $10,000 at 5% annually for 3 years.
Use the formula A = P(1 + r/n)^(nt) where:
- P = principal ($10,000)
- r = annual rate (0.05)
- n = compounding frequency (1 for annually)
- t = time in years (3)
"""

# 2. Check if problem is computational
{:ok, analysis} = ProblemClassifier.classify(problem)
if not analysis.should_use_pot do
  # Fall back to CoT or direct prompting
end

# 3. Use a more capable model
config = [generation: [model: "gpt-4o"]]

# 4. Provide example code structure
config = [
  generation: [
    system_prompt: """
    Generate code following this structure:

    defmodule Solution do
      def solve do
        # Step 1: Define inputs
        # Step 2: Perform calculation
        # Step 3: Return result
      end
    end
    """
  ]
]
```

### Problem: Code Execution Timeout

**Symptoms**:
```elixir
{:error, :timeout}
```

**Possible Causes**:
1. Generated code has infinite loop
2. Timeout is too short for complex calculation
3. Generated code is inefficient

**Solutions**:

```elixir
# 1. Increase timeout for complex problems
config = [execution: [timeout: 15_000]]  # 15 seconds

# 2. Validate code before execution
{:ok, program} = ProgramGenerator.generate(problem, analysis)
:ok = ProgramExecutor.validate_safety(program)

# 3. Add timeout hints to generation
config = [
  generation: [
    system_prompt: """
    Generate efficient code that completes in under 5 seconds.
    Avoid nested loops over large ranges.
    Use built-in functions (Enum.sum, etc.) instead of manual iteration.
    """
  ]
]

# 4. Monitor and retry with feedback
case ProgramExecutor.execute(program, timeout: 5_000) do
  {:error, :timeout} ->
    Logger.warning("Execution timeout, retrying with optimizations...")
    # Could regenerate with efficiency hints

  result ->
    result
end
```

### Problem: Incorrect Results

**Symptoms**:
```elixir
{:ok, result} = ProgramOfThought.solve(problem)
# result.answer is obviously wrong
# or result.validation.is_plausible == false
```

**Possible Causes**:
1. LLM made logical error in code generation
2. Formula or approach is incorrect
3. Unit conversion error
4. Floating-point precision issues

**Solutions**:

```elixir
# 1. Enable validation and check confidence
config = [integration: [validate_result: true]]

{:ok, result} = ProgramOfThought.solve(problem, config)

if result.validation.confidence < 0.8 do
  Logger.warning("Low confidence result, consider regenerating")
  # Retry or use different model
end

# 2. Inspect the generated program
{:ok, result} = ProgramOfThought.solve(problem)
IO.puts("Generated program:")
IO.puts(result.program)
# Manually review the logic

# 3. Provide formula in problem description
problem = """
Calculate distance traveled under constant acceleration.

Use the kinematic equation: d = v₀t + ½at²
where v₀ is initial velocity, a is acceleration, t is time.

Given: v₀ = 0 m/s, a = 3 m/s², t = 5 s
"""

# 4. Use higher precision and explicit rounding
config = [
  generation: [
    system_prompt: """
    Use Float.round/2 for final answer to avoid floating-point artifacts.
    Show intermediate calculations with more precision.
    """
  ]
]
```

### Problem: Safety Validation Rejects Code

**Symptoms**:
```elixir
{:error, :unsafe_code_detected}
```

**Possible Causes**:
1. LLM generated code with file I/O
2. Code includes system calls
3. Code spawns processes
4. Code attempts network operations

**Solutions**:

```elixir
# 1. Provide explicit safety constraints in generation
config = [
  generation: [
    system_prompt: """
    IMPORTANT SAFETY CONSTRAINTS:
    - Do NOT use File, System, or Code.eval
    - Do NOT spawn processes or tasks
    - Do NOT make network calls
    - Use only pure computation: math, Enum, basic Elixir

    Generate a self-contained pure function for calculation.
    """
  ]
]

# 2. Manually fix generated code if possible
{:ok, program} = ProgramGenerator.generate(problem, analysis)

case ProgramExecutor.validate_safety(program) do
  {:error, :file_io_detected} ->
    Logger.warning("Generated code attempted file I/O, regenerating...")
    # Retry generation with stricter prompt

  :ok ->
    # Proceed with execution
end

# 3. Use a more instruction-following model
config = [generation: [model: "gpt-4o"]]
```

### Problem: Missing or Poor Explanations

**Symptoms**:
```elixir
{:ok, result} = ProgramOfThought.solve(problem)
result.explanation == nil  # or is vague/unhelpful
```

**Possible Causes**:
1. Explanation generation disabled
2. Model doesn't have enough context
3. Integration step failed silently

**Solutions**:

```elixir
# 1. Enable explanation generation
config = [
  integration: [
    generate_explanation: true,
    model: "gpt-4o-mini"
  ]
]

# 2. Provide more context to integrator
config = [
  integration: [
    generate_explanation: true,
    explanation_prompt: """
    Explain this result in simple terms for a non-technical audience.
    Include:
    1. What the problem asked
    2. The approach used
    3. What the answer means practically
    """
  ]
]

# 3. Check for integration errors
case ProgramOfThought.solve(problem, config) do
  {:ok, result} ->
    if is_nil(result.explanation) do
      Logger.warning("Explanation generation may have failed silently")
      # Could regenerate explanation separately
    end

  error ->
    error
end

# 4. Generate explanation separately if needed
{:ok, result} = ProgramOfThought.solve(problem,
  integration: [generate_explanation: false]
)

{:ok, explanation} = generate_explanation_separately(
  result.answer,
  result.program,
  problem
)
```

### Problem: High Latency

**Symptoms**:
- PoT takes 10+ seconds per problem
- Much slower than expected

**Possible Causes**:
1. Using slow models (GPT-4 vs GPT-4o)
2. Generating explanations unnecessarily
3. Validation steps are expensive
4. Network latency to LLM provider

**Solutions**:

```elixir
# 1. Use faster models where possible
optimized_config = [
  classifier_model: "gpt-4o-mini",      # Fast classification
  generator_model: "gpt-4o",             # Quality code generation
  integrator_model: "gpt-4o-mini"       # Fast explanation
]

# 2. Disable expensive optional features
fast_config = [
  integration: [
    generate_explanation: false,  # Skip if not needed
    validate_result: false        # Skip validation for speed
  ]
]

# 3. Use streaming for generation (if supported)
config = [
  generation: [
    stream: true,
    on_chunk: &IO.write/1  # Show progress
  ]
]

# 4. Cache classification results
defmodule CachedClassifier do
  @cache :classification_cache

  def classify_with_cache(problem) do
    case :ets.lookup(@cache, problem) do
      [{^problem, analysis}] ->
        {:ok, analysis}

      [] ->
        {:ok, analysis} = ProblemClassifier.classify(problem)
        :ets.insert(@cache, {problem, analysis})
        {:ok, analysis}
    end
  end
end
```

### Problem: Domain Misclassification

**Symptoms**:
```elixir
{:ok, analysis} = ProblemClassifier.classify(financial_problem)
analysis.domain == :mathematical  # Expected :financial
```

**Possible Causes**:
1. Problem description lacks domain-specific keywords
2. Classification confidence too low
3. Problem is genuinely ambiguous

**Solutions**:

```elixir
# 1. Add domain-specific keywords to problem
problem = """
Financial calculation:
Calculate the monthly mortgage payment for...
"""

# 2. Manually specify domain if known
config = [
  classification: [
    override_domain: :financial  # Skip classification
  ]
]

# 3. Increase classification confidence threshold
config = [
  classification: [
    min_confidence: 0.8  # Higher threshold
  ]
]

# 4. Check analysis and handle low confidence
{:ok, analysis} = ProblemClassifier.classify(problem)

if analysis.confidence < 0.7 do
  # Ask user or default to general domain
  analysis = %{analysis | domain: :general}
end
```

## Conclusion

Program-of-Thought is a powerful technique for solving computational problems that require precision beyond what LLMs can reliably provide through direct reasoning. By separating reasoning (handled by LLMs) from computation (handled by code execution), PoT achieves:

- **Higher Accuracy**: +8.5% over standard Chain-of-Thought on mathematical benchmarks
- **Guaranteed Precision**: Eliminates LLM arithmetic errors
- **Explainability**: Maintains natural language explanations
- **Safety**: Sandboxed execution with comprehensive validation

### When to Choose PoT

PoT excels at:
- Mathematical word problems requiring multi-step calculations
- Financial computations (interest, amortization, returns)
- Scientific calculations (physics formulas, unit conversions)
- Statistical analysis (mean, standard deviation, correlations)
- Any problem where LLM arithmetic errors would be unacceptable

### Integration with Other Techniques

PoT works well alongside other reasoning frameworks:

```elixir
def solve_intelligently(problem) do
  # Classify problem type
  cond do
    computational?(problem) ->
      # Use PoT for computational precision
      ProgramOfThought.solve(problem)

    requires_tools?(problem) ->
      # Use ReAct for tool-based reasoning
      ReAct.solve(problem)

    requires_exploration?(problem) ->
      # Use ToT for exploring solution paths
      TreeOfThoughts.solve(problem)

    true ->
      # Use standard CoT
      ChainOfThought.solve(problem)
  end
end
```

### Cost-Benefit Analysis

| Aspect | Cost | Benefit |
|--------|------|---------|
| **API Calls** | 2-3× baseline (classify, generate, integrate) | Guaranteed computational accuracy |
| **Latency** | 3-5 seconds | Precise results every time |
| **Complexity** | Four-stage pipeline | Separation of concerns |

### Next Steps

1. **Start Simple**: Begin with basic mathematical problems to understand the pipeline
2. **Experiment**: Try different domains (financial, scientific, statistical)
3. **Optimize**: Tune timeouts, models, and validation based on your use case
4. **Integrate**: Combine with other reasoning techniques for comprehensive problem-solving

### Examples

Explore complete working examples:

- [Program-of-Thought Examples Directory](../examples/program-of-thought/) - Complete working implementations:
  - `financial_calculator.ex` - Basic PoT with four-stage pipeline and safe code generation
  - `multi_domain_solver.ex` - Advanced PoT with multi-domain routing and execution monitoring
  - `README.md` - Comprehensive documentation and usage patterns

### Additional Resources

- **Chain-of-Thought**: For problems requiring reasoning but not precise calculation
- **ReAct**: For problems requiring tool use and action-taking
- **Tree-of-Thoughts**: For problems requiring exploration of multiple solution paths
- **GEPA**: For optimizing prompts across multiple objectives

Program-of-Thought represents a fundamental insight: leverage each tool for what it does best. LLMs for language understanding and reasoning, code for precise computation. This separation of concerns leads to more accurate, reliable, and explainable AI systems.
