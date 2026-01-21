# Program-of-Thought Examples

This directory contains practical examples demonstrating Program-of-Thought (PoT) reasoning with Jido AI.

## What is Program-of-Thought?

Program-of-Thought is a powerful reasoning technique that separates natural language reasoning from precise computation. Instead of performing calculations within the LLM's reasoning, PoT generates executable code to handle computations, dramatically improving accuracy for mathematical and logical problems.

**Key Insight**: LLMs excel at reasoning but struggle with arithmetic. PoT leverages LLMs for problem understanding and code generation, then uses traditional computation for accurate results.

## Performance

Program-of-Thought delivers significant accuracy improvements for computational problems:

| Metric | Value |
|--------|-------|
| **Accuracy Improvement** | +8.5% on GSM8K (83.4% vs 74.9% with CoT) |
| **Cost** | 2-3× baseline (generation + execution) |
| **Latency** | 3-8 seconds (sequential pipeline) |
| **Best For** | Mathematical reasoning, financial calculations, scientific computations |
| **Error Rate** | Near-zero for arithmetic (executes real code) |

## Examples

### 1. Financial Calculator (`financial_calculator.ex`)

**Purpose**: Demonstrates basic Program-of-Thought workflow with financial calculations.

**Features**:
- Four-stage pipeline (Classify → Generate → Execute → Integrate)
- Problem classification (domain, complexity, operations)
- Safe code generation (compound interest, simple interest, percentage)
- Sandboxed execution with timeout protection
- Result integration with natural language explanations
- Comparison with pure CoT approach
- Comprehensive safety validation

**The Classic Problem**: Compound Interest
```
Calculate the final amount for $10,000 invested at 5% annual interest
compounded monthly for 3 years.

CoT might make rounding errors
PoT generates and executes: P * (1 + r/n)^(nt)
Result: $11,614.72 (exact)
```

**Usage**:
```elixir
# Run the example
Examples.ProgramOfThought.FinancialCalculator.run()

# Solve a custom problem
Examples.ProgramOfThought.FinancialCalculator.solve(
  "Calculate simple interest on $5000 at 3% for 2 years"
)

# Solve with options
Examples.ProgramOfThought.FinancialCalculator.solve(
  problem,
  timeout: 10_000,
  validate_safety: true,
  include_explanation: true
)

# Compare with CoT
Examples.ProgramOfThought.FinancialCalculator.compare_with_cot(problem)

# Batch solve
Examples.ProgramOfThought.FinancialCalculator.batch_solve([
  "Problem 1...",
  "Problem 2..."
])
```

**Example Output**:
```
🎯 Final Answer: $11,614.72

📊 Analysis:
   Domain: financial
   Computational: true
   Complexity: moderate

✓ Program Generated (32 lines)
✓ Safety Validated
✓ Execution Successful (12ms)

💡 Explanation:
This problem involves compound interest calculation. The principal amount of $10,000
is compounded monthly (12 times per year) at 5% annual rate for 3 years, resulting
in a final amount of $11,614.72.

⚡ Performance:
   • Execution time: 12ms
   • Lines of code: 32
   • Safety checks passed: 5/5
```

**Key Concepts**:
- Problem classification to identify computational needs
- Safe code generation with Elixir's defmodule pattern
- Sandboxed execution with timeout protection
- Result integration with explanations
- Safety validation (no File/System/network operations)

**Best For**:
- Learning PoT basics
- Financial and mathematical calculations
- Understanding the four-stage pipeline
- Comparing PoT with traditional CoT

---

### 2. Multi-Domain Solver (`multi_domain_solver.ex`)

**Purpose**: Demonstrates advanced Program-of-Thought patterns with multi-domain routing and sophisticated validation.

**Features**:
- Multi-domain routing (financial, scientific, statistical, mathematical, general)
- Advanced safety validation (syntax, structure, patterns)
- Execution monitoring (time, memory usage)
- Result validation with plausibility checks
- Domain comparison functionality
- Performance metrics and analytics
- Comprehensive error handling

**Domains Supported**:
- **Financial**: Compound interest, loans, investments, ROI
- **Scientific**: Physics calculations (velocity, acceleration, force, energy)
- **Statistical**: Mean, median, standard deviation, variance
- **Mathematical**: General computations, percentages, equations

**Usage**:
```elixir
# Run the example (scientific calculation)
Examples.ProgramOfThought.MultiDomainSolver.run()

# Solve with domain specification
Examples.ProgramOfThought.MultiDomainSolver.solve(
  problem,
  domain: :scientific,
  validate_result: true,
  timeout: 10_000
)

# Auto-detect domain
Examples.ProgramOfThought.MultiDomainSolver.solve(
  "Calculate compound interest on $5000 at 4% for 3 years"
  # Domain will be auto-detected as :financial
)

# Compare domains
Examples.ProgramOfThought.MultiDomainSolver.compare_domains()
```

**Example Output**:
```
🔍 Domain Detected: scientific
🔒 Safety: Enabled
⏱️  Timeout: 5000ms

⚙️  Generating scientific program...

✓ Execution successful
  Result: 80.46
  Duration: 18ms
  Memory: 2.3 KB

======================================================================

✅ Multi-Domain Solver Complete

🎯 Answer: 80.46
🏷️  Domain: scientific
⏱️  Duration: 18ms
💾 Memory: 2.3 KB

✓ Validation:
   Valid: true
   Confidence: 100.0%

   Checks:
     ✓ is_numeric
     ✓ is_finite
     ✓ is_positive
     ✓ reasonable_magnitude
     ✓ no_nan

📋 Steps:
   • Initial velocity (at rest)
   • Final velocity: 60 mph converted to m/s
   • Time to accelerate
   • Calculate constant acceleration: a = (v - v0) / t
   • Calculate distance with constant acceleration: d = v0*t + 0.5*a*t^2
   • Since v0 = 0, simplifies to: d = 0.5 * a * t^2
   • Round to 2 decimal places

======================================================================
```

**Advanced Features**:

1. **Domain Detection**:
```elixir
# Automatic domain detection based on keywords
"compound interest" → :financial
"acceleration" → :scientific
"standard deviation" → :statistical
"calculate percentage" → :mathematical
```

2. **Advanced Safety Validation**:
- Pattern matching for unsafe operations
- Syntax verification with Code.string_to_quoted!
- Structure validation (required defmodule and solve/0)
- No File I/O, System calls, or network operations
- No process spawning or manipulation

3. **Execution Monitoring**:
```elixir
%{
  result: 80.46,
  duration_ms: 18,
  memory_bytes: 2348
}
```

4. **Result Validation**:
- Numeric check
- Finite value check (no infinity)
- NaN detection
- Domain-specific magnitude validation
- Confidence scoring

5. **Domain Comparison**:
```
Solving problems across 4 domains:

financial: Calculate compound interest on $5000 at 4% for 3...
  ✓ 5624.32 (15ms)

scientific: A car accelerates from 0 to 60 mph in 6 seconds...
  ✓ 80.46 (18ms)

statistical: Find standard deviation of: 12, 15, 18, 22, 25
  ✓ 4.69 (12ms)

mathematical: What is 35% of 850?
  ✓ 297.50 (10ms)

Successfully solved 4/4 problems
Average execution time: 13.8ms
```

**Key Concepts**:
- Domain-specific program generation
- Multi-stage safety validation
- Resource monitoring (time and memory)
- Plausibility checking
- Error recovery strategies

**Best For**:
- Production-grade implementations
- Multi-domain problem solving
- Understanding advanced safety patterns
- Performance monitoring and optimization
- High-stakes computational tasks

---

## Quick Start

### Running Examples in IEx

```elixir
# Start IEx
iex -S mix

# Compile examples
c "examples/program-of-thought/financial_calculator.ex"
c "examples/program-of-thought/multi_domain_solver.ex"

# Run examples
Examples.ProgramOfThought.FinancialCalculator.run()
Examples.ProgramOfThought.MultiDomainSolver.run()
```

### Running from Mix Task

```bash
# Run financial calculator
mix run -e "Examples.ProgramOfThought.FinancialCalculator.run()"

# Run multi-domain solver
mix run -e "Examples.ProgramOfThought.MultiDomainSolver.run()"
```

## Comparison: Basic vs Advanced Examples

| Aspect | Financial Calculator | Multi-Domain Solver |
|--------|---------------------|---------------------|
| **Complexity** | Basic | Advanced |
| **Domains** | Financial only | 5 domains |
| **Safety Validation** | Basic patterns | Multi-stage validation |
| **Execution Monitoring** | Timeout only | Time + Memory |
| **Result Validation** | Basic checks | Plausibility analysis |
| **Error Handling** | Simple | Comprehensive |
| **Best For** | Learning | Production |

## Common Patterns

### Pattern 1: Four-Stage Pipeline

Used in: `financial_calculator.ex`

```elixir
def solve(problem, opts) do
  # Stage 1: Classify the problem
  {:ok, analysis} = classify_problem(problem)

  # Stage 2: Generate program
  {:ok, program} = generate_program(problem, analysis)

  # Stage 3: Execute program
  {:ok, exec_result} = execute_program(program, timeout: timeout)

  # Stage 4: Integrate result
  {:ok, final_result} = integrate_result(
    exec_result,
    program: program,
    analysis: analysis
  )

  {:ok, final_result}
end
```

### Pattern 2: Problem Classification

Used in: `financial_calculator.ex`

```elixir
defp classify_problem(problem) do
  problem_lower = String.downcase(problem)

  # Detect domain
  domain = cond do
    problem_lower =~ ~r/interest|invest|loan/ -> :financial
    problem_lower =~ ~r/velocity|acceleration/ -> :scientific
    true -> :general
  end

  # Detect computational needs
  computational = problem_lower =~ ~r/calculate|compute|solve/

  # Estimate complexity
  complexity = estimate_complexity(problem)

  {:ok, %{
    domain: domain,
    computational: computational,
    complexity: complexity
  }}
end
```

### Pattern 3: Safe Code Generation

Used in: Both examples

```elixir
defp generate_safe_program(problem, context) do
  """
  defmodule Solution do
    def solve do
      # Problem-specific computation
      principal = 10000
      rate = 0.05
      time = 3

      # Use safe mathematical operations
      amount = principal * :math.pow(1 + rate, time)

      # Return formatted result
      Float.round(amount, 2)
    end
  end
  """
end
```

### Pattern 4: Safety Validation

Used in: Both examples

```elixir
defp validate_program(program) do
  with :ok <- validate_safety(program),
       :ok <- validate_syntax(program),
       :ok <- validate_structure(program) do
    :ok
  end
end

defp validate_safety(code) do
  unsafe_patterns = [
    {~r/File\./, "File I/O operations not allowed"},
    {~r/System\./, "System calls not allowed"},
    {~r/Code\.eval/, "Code evaluation not allowed"},
    {~r/spawn\(|Task\.(async|start)/, "Process spawning not allowed"},
    {~r/:httpc|:http|HTTPoison|Req|HTTP/, "Network operations not allowed"}
  ]

  Enum.reduce_while(unsafe_patterns, :ok, fn {pattern, message}, _acc ->
    if Regex.match?(pattern, code) do
      {:halt, {:error, message}}
    else
      {:cont, :ok}
    end
  end)
end
```

### Pattern 5: Sandboxed Execution

Used in: Both examples

```elixir
defp execute_with_timeout(program, timeout) do
  task = Task.async(fn ->
    try do
      {result, _binding} = Code.eval_string(program)
      answer = result.solve()
      {:ok, answer}
    rescue
      error -> {:error, Exception.message(error)}
    end
  end)

  case Task.yield(task, timeout) || Task.shutdown(task) do
    {:ok, {:ok, result}} -> {:ok, result}
    {:ok, {:error, error}} -> {:error, error}
    nil -> {:error, :timeout}
  end
end
```

### Pattern 6: Result Integration

Used in: `financial_calculator.ex`

```elixir
defp integrate_result(exec_result, opts) do
  program = Keyword.fetch!(opts, :program)
  analysis = Keyword.fetch!(opts, :analysis)

  # Extract steps from program comments
  steps = extract_steps(program)

  # Generate explanation
  explanation = generate_explanation(exec_result, analysis, steps)

  %{
    answer: exec_result,
    program: program,
    analysis: analysis,
    steps: steps,
    explanation: explanation
  }
end
```

### Pattern 7: Execution Monitoring

Used in: `multi_domain_solver.ex`

```elixir
defp execute_and_monitor(program) do
  start_time = System.monotonic_time(:millisecond)
  start_memory = :erlang.memory(:total)

  {:ok, result} = execute_code(program)

  end_time = System.monotonic_time(:millisecond)
  end_memory = :erlang.memory(:total)

  {:ok, %{
    result: result,
    duration_ms: end_time - start_time,
    memory_bytes: end_memory - start_memory
  }}
end
```

### Pattern 8: Result Validation

Used in: `multi_domain_solver.ex`

```elixir
defp validate_result(exec_result, domain) do
  answer = exec_result.result

  checks = %{
    is_numeric: is_number(answer),
    is_finite: answer != :infinity and answer != :neg_infinity,
    is_positive: answer > 0,
    reasonable_magnitude: check_magnitude(answer, domain),
    no_nan: not is_nan?(answer)
  }

  all_valid = Enum.all?(checks, fn {_k, v} -> v end)
  confidence = calculate_confidence(checks)

  %{
    is_valid: all_valid,
    confidence: confidence,
    checks: checks
  }
end
```

## Tips for Using These Examples

1. **Always validate safety**: Use comprehensive pattern matching to block unsafe operations
2. **Set appropriate timeouts**: 5-10 seconds is reasonable for most problems
3. **Monitor execution**: Track time and memory for performance optimization
4. **Validate results**: Check for numeric validity, finite values, and plausibility
5. **Generate clear code**: Include comments in generated programs for transparency
6. **Handle errors gracefully**: Use try/rescue and provide meaningful error messages
7. **Extract steps**: Parse program comments to explain reasoning
8. **Integrate results**: Combine computational results with natural language explanations

## When to Use Program-of-Thought

### ✅ Use Program-of-Thought For:
- **Mathematical reasoning** (arithmetic, algebra, calculus)
- **Financial calculations** (interest, loans, investments, ROI)
- **Scientific computations** (physics, chemistry, engineering)
- **Statistical analysis** (mean, median, standard deviation)
- **Multi-step calculations** (complex formulas, iterative processes)
- **When arithmetic accuracy is critical** (zero tolerance for calculation errors)

### ❌ Skip Program-of-Thought For:
- **Simple factual questions** (no computation needed)
- **Creative tasks** (story writing, brainstorming)
- **Subjective decisions** (opinions, preferences)
- **Natural language tasks** (summarization, translation)
- **When code generation overhead isn't worth it** (trivial calculations)
- **Environments without code execution** (security-restricted contexts)

## Decision Framework

```
Does the problem involve numerical computation?
    No → Use standard CoT
    Yes ↓

Is arithmetic accuracy critical (zero tolerance for errors)?
    No → Consider if CoT is sufficient
    Yes ↓

Can you safely execute generated code?
    No → Use CoT with careful verification
    Yes ↓

Is the problem complex enough to justify code generation?
    No → Simple CoT may suffice
    Yes ↓

Do you have 2-3× cost budget vs baseline CoT?
    No → Use standard CoT
    Yes → ✅ Use Program-of-Thought
```

## Key Differences from Other Methods

| Aspect | Chain-of-Thought | Program-of-Thought | ReAct | Self-Consistency |
|--------|------------------|-------------------|-------|------------------|
| **Computation** | LLM performs | Code executes | LLM performs | LLM performs (×k) |
| **Accuracy** | Good | Excellent | Good | Very Good |
| **Arithmetic Errors** | Common | Near-zero | Common | Reduced by voting |
| **Cost** | 3-4× | 2-3× | 10-30× | 5-10× |
| **Latency** | 2-3s | 3-8s | 20-60s | 15-25s |
| **Best For** | General reasoning | Math/computation | Research + Action | Critical decisions |
| **Code Generation** | No | Yes | No | No |

## Four-Stage Pipeline Explained

### Stage 1: Classify the Problem
- **Purpose**: Understand what type of problem we're solving
- **Outputs**: Domain, complexity, computational needs
- **Example**: "compound interest" → financial, moderate, computational

### Stage 2: Generate Program
- **Purpose**: Create executable code to solve the problem
- **Outputs**: Safe Elixir program with Solution.solve/0
- **Example**: Generate compound interest formula as code

### Stage 3: Execute Program
- **Purpose**: Run the generated code safely
- **Outputs**: Computed result, execution metrics
- **Example**: Execute and get $11,614.72 in 12ms

### Stage 4: Integrate Result
- **Purpose**: Combine computational result with explanation
- **Outputs**: Final answer with context and reasoning
- **Example**: "The final amount is $11,614.72 because..."

## Cost Analysis

```
Typical Costs (GPT-4):

Program-of-Thought:
- Classification: 100-150 tokens
- Generation: 200-300 tokens
- Integration: 100-150 tokens
- Total tokens: 400-600
- Cost per query: $0.006-0.009
- Time: 3-8 seconds

Compare to CoT:
- Tokens: 300-400
- Cost: $0.003
- Time: 2-3 seconds

ROI Calculation:
- 2-3× cost for near-zero arithmetic errors
- Worth it when calculation accuracy is critical
- Especially valuable for financial, scientific, statistical domains
- Can be combined with Self-Consistency for even higher accuracy
```

## Combining with Other Techniques

### PoT + Self-Consistency
Generate multiple programs (k=3-5) and vote on results:
```elixir
# Generate 5 different programs
programs = generate_diverse_programs(problem, k: 5)

# Execute all programs
results = Enum.map(programs, &execute_program/1)

# Vote on most common result
final_answer = majority_vote(results)
```

### PoT + ReAct
Use PoT within ReAct's action phase:
```elixir
# Thought: This requires precise calculation
# Action: generate_and_execute_program
# Observation: Program returned 11614.72
# Thought: The calculation is complete
```

## Integration with Jido AI

These examples can be adapted to work with Jido AI's action system:

```elixir
defmodule MyPoTAgent do
  use Jido.Agent,
    name: "computational_solver",
    actions: [ClassifyAction, GenerateAction, ExecuteAction]

  def solve_computational_problem(agent, problem) do
    # Use Program-of-Thought for computational problems
    result = Examples.ProgramOfThought.MultiDomainSolver.solve(
      problem,
      domain: :auto,
      validate_result: true,
      timeout: 10_000
    )

    case result do
      {:ok, %{validation: %{is_valid: true}}} ->
        {:ok, result}
      {:ok, %{validation: %{is_valid: false}}} ->
        {:error, :invalid_result, result}
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

## Safety Considerations

### Critical Safety Rules:

1. **Never allow File I/O**: Block all File.* operations
2. **Block System calls**: No System.* or :os.* operations
3. **Prevent network access**: Block HTTP libraries and sockets
4. **No process spawning**: Block spawn, Task.async, etc.
5. **No code evaluation**: Block Code.eval_string in generated code
6. **Validate syntax**: Use Code.string_to_quoted! before execution
7. **Set timeouts**: Always use Task.yield with reasonable timeouts
8. **Monitor resources**: Track time and memory usage

### Security Checklist:

- [ ] Safety validation enabled
- [ ] All unsafe patterns blocked
- [ ] Syntax validation performed
- [ ] Structure validation passed
- [ ] Timeout configured
- [ ] Resource monitoring active
- [ ] Error handling in place
- [ ] Result validation configured

## Further Reading

- [Program-of-Thought Guide](../../guides/program_of_thought.md) - Complete documentation
- [Chain-of-Thought Guide](../../guides/chain_of_thought.md) - Basic reasoning
- [Self-Consistency Guide](../../guides/self_consistency.md) - Voting strategies
- [ReAct Guide](../../guides/react.md) - Reasoning with actions

## Contributing

To add new examples:

1. Create a new file in this directory
2. Follow the four-stage pipeline pattern (Classify → Generate → Execute → Integrate)
3. Implement comprehensive safety validation
4. Add domain-specific program generators if applicable
5. Include usage examples in module documentation
6. Update this README with the new example
7. Add tests if applicable

## Questions?

See the main [Program-of-Thought Guide](../../guides/program_of_thought.md) for detailed documentation on:
- Four-stage pipeline implementation
- Safe code generation techniques
- Domain-specific patterns
- Security and sandboxing
- Production deployment patterns
- Performance optimization strategies
