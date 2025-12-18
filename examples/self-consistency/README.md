# Self-Consistency Examples

This directory contains practical examples demonstrating Self-Consistency reasoning with Jido AI.

## What is Self-Consistency?

Self-Consistency is a powerful reasoning technique that dramatically improves accuracy by generating multiple independent reasoning paths and selecting the most reliable answer through voting. Instead of relying on a single Chain-of-Thought path, Self-Consistency leverages the "wisdom of the crowd" principle.

**Key Insight**: Correct reasoning paths converge on the same answer, while errors diverge into scattered incorrect answers. Majority voting selects the correct answer.

## Performance

Self-Consistency delivers significant accuracy improvements:

| Metric | Value |
|--------|-------|
| **Accuracy Improvement** | +17.9% on GSM8K (GPT-4: 92% vs 74.9% with CoT) |
| **Cost** | 5-10× baseline (k=5-10 parallel samples) |
| **Latency** | 15-25 seconds (parallel generation) |
| **Best For** | Mission-critical decisions, math reasoning, ambiguous problems |
| **Optimal Sample Count** | k=5-10 (diminishing returns beyond k=10) |

## Examples

### 1. Math Reasoning (`math_reasoning.ex`)

**Purpose**: Demonstrates basic Self-Consistency workflow for mathematical problems.

**Features**:
- Multiple diverse reasoning paths (k=5)
- Answer extraction and normalization
- Quality scoring (coherence, completeness, confidence, length, structure)
- Majority voting with consensus measurement
- Path visualization and comparison
- CoT vs Self-Consistency comparison

**The Classic Problem**: "Bat and Ball"
```
A bat and a ball together cost $1.10.
The bat costs $1.00 more than the ball.
How much does the ball cost?

Common wrong answer: $0.10 (intuitive but incorrect)
Correct answer: $0.05
```

**Usage**:
```elixir
# Run the example
Examples.SelfConsistency.MathReasoning.run()

# Solve a custom problem
Examples.SelfConsistency.MathReasoning.solve(
  "If 5 machines make 5 widgets in 5 minutes, how long for 100 machines to make 100 widgets?"
)

# Solve with options
Examples.SelfConsistency.MathReasoning.solve(
  problem,
  sample_count: 7,
  temperature: 0.8,
  voting_strategy: :quality_weighted
)

# Compare with CoT
Examples.SelfConsistency.MathReasoning.compare_with_cot()

# Batch solve
Examples.SelfConsistency.MathReasoning.batch_solve([
  "Problem 1...",
  "Problem 2..."
])
```

**Example Output**:
```
🎯 Final Answer: $0.05
📊 Consensus: 80.0%
💯 Confidence: 88.3%
⭐ Quality: 0.82
🗳️  Strategy: majority

📈 Vote Distribution:
   • $0.05: 4 votes (80.0%)
   • $0.10: 1 vote (20.0%)

📝 All Reasoning Paths:
   Path 1 ✓:
   Answer: $0.05
   Quality: 0.92, Confidence: 0.90
   Reasoning:
   Let x be the cost of the ball.
   Then the bat costs x + $1.00...
```

**Key Concepts**:
- Generating diverse paths with higher temperature (0.7)
- Extracting answers with pattern matching
- Scoring path quality on multiple dimensions
- Majority voting to select reliable answer
- Measuring consensus for confidence

**Best For**:
- Learning Self-Consistency basics
- Mathematical reasoning problems
- Understanding voting mechanisms
- Comparing with single-path CoT

---

### 2. Multi-Domain Solver (`multi_domain_solver.ex`)

**Purpose**: Demonstrates advanced Self-Consistency patterns with domain-specific handling and sophisticated voting.

**Features**:
- Domain-specific answer extraction (math, code, text)
- Four voting strategies (majority, confidence-weighted, quality-weighted, hybrid)
- Quality threshold filtering and calibration
- Outlier detection using statistical methods (z-scores)
- Confidence calibration based on quality factors
- Progressive refinement (start small, expand if needed)
- Detailed analytics and diagnostics

**Domains Supported**:
- **Math**: Extract numerical answers, handle currency/units
- **Code**: Extract code blocks and syntax
- **Text**: Extract conclusions and summaries

**Usage**:
```elixir
# Run the example (financial calculation)
Examples.SelfConsistency.MultiDomainSolver.run()

# Solve with domain specification
Examples.SelfConsistency.MultiDomainSolver.solve(
  problem,
  domain: :math,
  voting_strategy: :hybrid,
  sample_count: 10,
  quality_threshold: 0.6,
  detect_outliers: true
)

# Compare voting strategies
Examples.SelfConsistency.MultiDomainSolver.compare_voting_strategies(problem)

# Progressive refinement (adaptive sampling)
Examples.SelfConsistency.MultiDomainSolver.solve_with_refinement(
  problem,
  target_consensus: 0.7,
  max_iterations: 3
)
```

**Example Output**:
```
🎯 Final Answer: $20,108.78
📊 Consensus: 85.7%
💯 Avg Confidence: 91.2%
⭐ Avg Quality: 0.89
🗳️  Strategy: hybrid

📈 Vote Distribution:
   • $20,108.78: 6 votes (85.7%)
   • $20,109.00: 1 vote (14.3%)

⚠️  Outliers Detected: 1
   • Path with answer $20,200.00
     - Quality is 2.3σ from mean
     - Very low quality score

📊 Analytics:
   • Total paths generated: 7
   • Quality paths used: 6
   • Outliers excluded: 1
   • Unique answers: 2
```

**Advanced Features**:

1. **Domain-Specific Extraction**:
```elixir
# Math domain: Extract $20,108.78
# Code domain: Extract ```elixir ... ```
# Text domain: Extract "Conclusion: ..."
```

2. **Four Voting Strategies**:
- **Majority**: Simple vote count (default)
- **Confidence-Weighted**: Weight by path confidence scores
- **Quality-Weighted**: Weight by path quality scores
- **Hybrid**: Balanced combination (40% count, 30% confidence, 30% quality)

3. **Outlier Detection**:
- Calculate z-scores for quality and length
- Flag paths > 2σ from mean
- Report outlier reasons
- Exclude from voting

4. **Progressive Refinement**:
```
Phase 1: 3 paths  → consensus 55% → Continue
Phase 2: 7 paths  → consensus 73% → Accept
```

**Key Concepts**:
- Domain-aware answer parsing
- Weighted voting mechanisms
- Statistical outlier detection
- Confidence calibration
- Adaptive sampling strategies

**Best For**:
- Production-grade implementations
- High-stakes decisions
- Multi-domain problems
- Understanding advanced patterns
- Cost optimization with progressive refinement

---

## Quick Start

### Running Examples in IEx

```elixir
# Start IEx
iex -S mix

# Compile examples
c "examples/self-consistency/math_reasoning.ex"
c "examples/self-consistency/multi_domain_solver.ex"

# Run examples
Examples.SelfConsistency.MathReasoning.run()
Examples.SelfConsistency.MultiDomainSolver.run()
```

### Running from Mix Task

```bash
# Run math reasoning
mix run -e "Examples.SelfConsistency.MathReasoning.run()"

# Run multi-domain solver
mix run -e "Examples.SelfConsistency.MultiDomainSolver.run()"
```

## Comparison: Basic vs Advanced Examples

| Aspect | Math Reasoning | Multi-Domain Solver |
|--------|----------------|---------------------|
| **Complexity** | Basic | Advanced |
| **Domains** | Math only | Math, Code, Text |
| **Voting Strategies** | Majority | 4 strategies with comparison |
| **Quality Analysis** | Basic scoring | Advanced with calibration |
| **Outlier Detection** | No | Yes (statistical) |
| **Progressive Refinement** | No | Yes (adaptive) |
| **Best For** | Learning | Production |

## Common Patterns

### Pattern 1: Basic Self-Consistency Workflow

Used in: `math_reasoning.ex`

```elixir
def solve(problem, opts) do
  # 1. Generate diverse paths
  {:ok, paths} = generate_reasoning_paths(problem, sample_count, temperature)

  # 2. Extract answers
  paths_with_answers = extract_answers(paths)

  # 3. Analyze quality
  analyzed_paths = analyze_quality(paths_with_answers)

  # 4. Filter by threshold
  quality_paths = Enum.filter(analyzed_paths, &(&1.quality_score >= threshold))

  # 5. Vote and select
  result = vote_and_select(quality_paths, voting_strategy)

  {:ok, result}
end
```

### Pattern 2: Quality Scoring

Used in: Both examples

```elixir
defp calculate_quality_score(path) do
  # Multiple quality dimensions
  coherence = score_coherence(path.reasoning)        # Logical flow
  completeness = score_completeness(path.reasoning)   # All steps present
  length = score_length(path.reasoning)              # Appropriate length
  structure = score_structure(path.reasoning)         # Clear organization

  # Weighted combination
  0.3 * coherence + 0.3 * completeness + 0.2 * length + 0.2 * structure
end
```

### Pattern 3: Voting Mechanisms

Used in: `multi_domain_solver.ex`

```elixir
defp select_hybrid(votes) do
  votes
  |> Enum.map(fn {answer, count, paths} ->
    avg_confidence = Enum.sum(Enum.map(paths, & &1.confidence)) / length(paths)
    avg_quality = Enum.sum(Enum.map(paths, & &1.quality_score)) / length(paths)

    # Hybrid score: balance count, confidence, and quality
    score = count * 0.4 + avg_confidence * count * 0.3 + avg_quality * count * 0.3

    {answer, score, paths}
  end)
  |> Enum.max_by(fn {_answer, score, _paths} -> score end)
end
```

### Pattern 4: Outlier Detection

Used in: `multi_domain_solver.ex`

```elixir
defp detect_outliers(paths) do
  # Calculate statistics
  avg_quality = Enum.sum(qualities) / length(qualities)
  std_quality = calculate_std_dev(qualities, avg_quality)

  # Flag outliers (>2σ from mean)
  Enum.map(paths, fn path ->
    z_score = abs(path.quality_score - avg_quality) / (std_quality + 0.01)

    is_outlier = z_score > 2.0 or path.quality_score < 0.3

    Map.put(path, :is_outlier, is_outlier)
  end)
end
```

### Pattern 5: Progressive Refinement

Used in: `multi_domain_solver.ex`

```elixir
defp solve_with_refinement(problem, target_consensus) do
  # Phase 1: Quick (3 paths)
  {:ok, result} = solve(problem, sample_count: 3)

  if result.consensus >= target_consensus do
    {:ok, result}
  else
    # Phase 2: Standard (7 paths)
    {:ok, result} = solve(problem, sample_count: 7)

    if result.consensus >= target_consensus do
      {:ok, result}
    else
      # Phase 3: Thorough (15 paths)
      solve(problem, sample_count: 15)
    end
  end
end
```

## Tips for Using These Examples

1. **Start with 5-7 samples**: Good balance of accuracy and cost
2. **Use temperature 0.7**: Encourages diversity without nonsense
3. **Set quality thresholds**: Filter out obviously poor paths (0.5 is reasonable)
4. **Choose voting strategy wisely**:
   - Majority for simple problems
   - Hybrid for production systems
5. **Monitor consensus**: < 60% means low agreement, consider more samples
6. **Use progressive refinement**: Save costs on easy problems
7. **Detect outliers**: Improves accuracy by excluding anomalies

## When to Use Self-Consistency

### ✅ Use Self-Consistency For:
- **Mission-critical decisions** (financial, medical, legal)
- **Mathematical reasoning** (complex word problems, calculations)
- **Ambiguous problems** (common misconceptions, tricky questions)
- **High-value decisions** (strategic planning, investment analysis)
- **When single errors are costly** (production systems, safety-critical)

### ❌ Skip Self-Consistency For:
- **Simple factual questions** ("What is the capital of France?")
- **Creative tasks** (story writing, brainstorming)
- **Subjective decisions** (personal preferences, opinions)
- **High-frequency, low-stakes** (chatbot responses, quick queries)
- **Budget-constrained** (development/testing environments)
- **Latency-critical** (real-time applications requiring < 5s response)

## Decision Framework

```
Is the decision mission-critical or high-value?
    No → Use standard CoT
    Yes ↓

Would a wrong answer have significant consequences?
    No → Standard CoT is sufficient
    Yes ↓

Is the problem mathematical, logical, or ambiguous?
    No → Consider if Self-Consistency applies
    Yes ↓

Can you afford 5-10× cost and 15-25s latency?
    No → Use CoT with verification
    Yes ↓

Is +17.9% accuracy improvement worth the cost?
    No → Use standard CoT
    Yes → ✅ Use Self-Consistency
```

## Key Differences from Other Methods

| Aspect | Chain-of-Thought | Self-Consistency | ReAct | Tree-of-Thoughts |
|--------|------------------|------------------|-------|------------------|
| **Paths** | 1 path | k diverse paths (5-10) | Iterative single | Multiple branches |
| **Temperature** | Low (0.2) | High (0.7-0.9) | Medium | Medium |
| **Answer Selection** | Direct | Voting | Direct | Tree search |
| **Error Tolerance** | Low | High | Medium | High |
| **Cost** | 3-4× | 5-10× | 10-30× | 50-150× |
| **Accuracy Boost** | +8-15% | +17.9% | +27% | +70% (Game of 24) |
| **Best For** | Standard reasoning | Critical accuracy | Research + Action | Strategic planning |

## Voting Strategies Explained

### Majority Voting (Default)
- **How**: Simple vote count
- **Best for**: Clear consensus expected
- **Example**: 4 votes for $0.05, 1 vote for $0.10 → Winner: $0.05

### Confidence-Weighted Voting
- **How**: Weight votes by path confidence scores
- **Best for**: Some paths more confident than others
- **Example**: High-confidence paths get more weight

### Quality-Weighted Voting
- **How**: Weight votes by path quality scores
- **Best for**: Reasoning quality varies significantly
- **Example**: Well-reasoned paths get more weight

### Hybrid Voting
- **How**: Balanced combination (40% count, 30% confidence, 30% quality)
- **Best for**: Production systems, balanced consideration
- **Example**: Best overall score considering all factors

## Cost Analysis

```
Typical Costs (k=5, GPT-4):
- Tokens per path: ~300-400
- Total tokens: 1,500-2,000
- Cost per query: $0.015-0.020
- Time: 15-20 seconds (parallel)

Compare to CoT:
- Tokens: 300-400
- Cost: $0.003
- Time: 2-3 seconds

ROI Calculation:
- Use Self-Consistency if problem value > $1
- Consider progressive refinement to optimize costs
- 5× cost for 17.9% accuracy improvement
- Worth it for mission-critical decisions
```

## Integration with Jido AI

These examples can be adapted to work with Jido AI's action system:

```elixir
defmodule MySelfConsistencyAgent do
  use Jido.Agent,
    name: "critical_calculator",
    actions: [CalculationAction, VerificationAction]

  def solve_critical_problem(agent, problem) do
    # Use Self-Consistency for high-stakes calculations
    result = Examples.SelfConsistency.MathReasoning.solve(
      problem,
      sample_count: 10,
      voting_strategy: :hybrid
    )

    if result.consensus >= 0.7 do
      {:ok, result}
    else
      {:error, :low_consensus, result}
    end
  end
end
```

## Further Reading

- [Self-Consistency Guide](../../guides/self_consistency.md) - Complete documentation
- [Chain-of-Thought Guide](../../guides/chain_of_thought.md) - Single-path reasoning
- [ReAct Guide](../../guides/react.md) - Reasoning with actions
- [Tree-of-Thoughts Guide](../../guides/tree_of_thoughts.md) - Tree-based exploration

## Contributing

To add new examples:

1. Create a new file in this directory
2. Follow the existing pattern (path generation, quality analysis, voting)
3. Include domain-specific handling if applicable
4. Add usage examples in module documentation
5. Update this README with the new example
6. Add tests if applicable

## Questions?

See the main [Self-Consistency Guide](../../guides/self_consistency.md) for detailed documentation on:
- Path generation strategies
- Answer extraction techniques
- Quality analysis methods
- Voting mechanisms
- Production deployment patterns
