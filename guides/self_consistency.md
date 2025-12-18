# Self-Consistency Guide

## Introduction

**Self-Consistency** is a reasoning technique that dramatically improves accuracy by generating multiple independent reasoning paths and selecting the most reliable answer through voting. Instead of relying on a single Chain-of-Thought reasoning path, Self-Consistency samples diverse reasoning approaches and leverages the "wisdom of the crowd" principle to identify the correct answer.

### Key Advantages

- **Significant Accuracy Boost**: +17.9% improvement on GSM8K mathematical reasoning benchmark
- **Error Resilience**: Reduces impact of occasional reasoning mistakes by any single path
- **Confidence Calibration**: Provides quantitative measure of answer reliability through consensus
- **Diversity Exploration**: Discovers multiple valid approaches to the same problem

### Performance Characteristics

| Metric | Value |
|--------|-------|
| **Accuracy Improvement** | +17.9% on GSM8K (GPT-4: 92% vs 74.9% with CoT alone) |
| **Cost Overhead** | 5-10× baseline (k=5-10 parallel samples) |
| **Latency** | 15-25 seconds (parallel generation with k=5-10) |
| **Best For** | Mission-critical decisions, mathematical reasoning, ambiguous problems |
| **Optimal Sample Count** | k=5-10 (diminishing returns beyond k=10) |

> **💡 Practical Examples**: See the [Self-Consistency examples directory](../examples/self-consistency/) for complete working implementations including a math reasoning solver and a multi-domain solver with advanced voting strategies.

### How Self-Consistency Differs from Standard CoT

| Aspect | Chain-of-Thought | Self-Consistency |
|--------|------------------|------------------|
| **Reasoning Paths** | 1 deterministic path | k diverse paths (5-10) |
| **Temperature** | Low (0.0-0.3) | Higher (0.7-0.9) for diversity |
| **Answer Selection** | Direct output | Voting across paths |
| **Error Tolerance** | One mistake = wrong answer | Majority voting mitigates errors |
| **Cost** | 1× | k× (5-10×) |
| **Use Case** | Standard problems | Critical accuracy needs |

## Core Concepts

### The Self-Consistency Process

```
┌──────────────────────────────────────────────────────────────┐
│                    Problem/Question                           │
└────────────────┬─────────────────────────────────────────────┘
                 │
                 v
┌────────────────────────────────────────────────────────────────┐
│  Generate k Diverse Reasoning Paths (Parallel, temp=0.7)      │
│                                                                 │
│  Path 1: "Step 1... Step 2... Answer: X"                      │
│  Path 2: "First... Then... Therefore: X"                      │
│  Path 3: "Given... Calculate... Result: Y"                    │
│  Path 4: "Let's... Next... Answer: X"                         │
│  Path 5: "Consider... Thus... Answer: X"                      │
└────────────────┬───────────────────────────────────────────────┘
                 │
                 v
┌────────────────────────────────────────────────────────────────┐
│  Extract & Normalize Answers                                   │
│  • Parse final answer from each path                           │
│  • Normalize formats ("42" → 42, "forty-two" → 42)           │
│  • Handle semantic equivalence ("yes" ≈ true)                 │
└────────────────┬───────────────────────────────────────────────┘
                 │
                 v
┌────────────────────────────────────────────────────────────────┐
│  Analyze Path Quality                                          │
│  • Score coherence (logical flow)                             │
│  • Score completeness (all steps present)                     │
│  • Score confidence (certainty in conclusion)                 │
│  • Detect outliers (unusually short/long, low quality)        │
└────────────────┬───────────────────────────────────────────────┘
                 │
                 v
┌────────────────────────────────────────────────────────────────┐
│  Vote & Select Answer                                          │
│  • Group equivalent answers                                    │
│  • Apply voting strategy (majority/weighted)                   │
│  • Calculate consensus (% agreement)                           │
│  • Return winner with confidence                               │
│                                                                 │
│  Result: X (4 votes), Y (1 vote) → Winner: X                  │
│  Consensus: 80%, Confidence: 0.85                              │
└────────────────────────────────────────────────────────────────┘
```

### Why Self-Consistency Works

**The Fundamental Insight**: Complex reasoning problems often have multiple valid solution paths, but incorrect reasoning paths rarely lead to the same wrong answer. By sampling multiple diverse paths:

1. **Correct reasoning converges**: Different correct approaches lead to the same answer
2. **Errors diverge**: Mistakes lead to scattered incorrect answers
3. **Majority voting wins**: The correct answer appears most frequently

**Example**:

```
Problem: "If 5 machines make 5 widgets in 5 minutes, how long for 100 machines to make 100 widgets?"

Path 1 (correct): "Each machine makes 1 widget in 5 min → 100 machines make 100 in 5 min"
Path 2 (correct): "Rate = 1 widget/machine/5min → 100 widgets at same rate = 5 min"
Path 3 (error):   "100 machines is 20× more, so 5 × 20 = 100 minutes"
Path 4 (correct): "Parallel production → same time regardless of scale = 5 min"
Path 5 (correct): "100 machines make 100 widgets in same 5 minutes"

Vote: "5 minutes" (4 votes) vs "100 minutes" (1 vote)
Winner: "5 minutes" with 80% consensus
```

### Key Components

#### 1. Path Generation

Generates k independent reasoning paths with increased temperature for diversity:

```elixir
# Generate 5 diverse paths in parallel
{:ok, paths} = SelfConsistency.generate_reasoning_paths(
  problem,
  sample_count: 5,
  temperature: 0.7,
  parallel: true
)

# paths = [
#   "Step 1: ... Step 2: ... Answer: 42",
#   "First, ... Then... Result: 42",
#   "Consider... Calculate... Therefore: 42",
#   "Given... Apply... Answer: 41",
#   "Let's... Thus... Answer: 42"
# ]
```

**Diversity Mechanisms**:
- **Temperature**: Higher temperature (0.7-0.9) encourages varied approaches
- **Prompt Variation**: Optional prompt modifications for each path
- **Parallel Generation**: Each path is independent

#### 2. Answer Extraction & Normalization

Extracts answers from diverse formats and normalizes to canonical forms:

```elixir
# Different expressions of the same answer
answers = [
  "The answer is 42",        # → 42
  "Therefore: forty-two",    # → 42
  "Result = 42.0",          # → 42
  "42 is the solution",     # → 42
  "Answer: 41"              # → 41
]

# After extraction and normalization
normalized = [42, 42, 42, 42, 41]
```

**Semantic Equivalence**:
```elixir
# These are considered equivalent
equivalent?(42, "42")              # → true
equivalent?("yes", true)           # → true
equivalent?("5 minutes", "5 min")  # → true
```

#### 3. Quality Analysis

Scores each path on multiple dimensions:

```elixir
quality_factors = %{
  coherence: 0.8,      # Logical flow (30% weight)
  completeness: 0.9,   # All steps present (25% weight)
  confidence: 0.85,    # Expressed certainty (20% weight)
  length: 0.7,         # Appropriate length (15% weight)
  structure: 0.75      # Clear organization (10% weight)
}

quality_score = 0.8 * 0.3 + 0.9 * 0.25 + 0.85 * 0.2 + 0.7 * 0.15 + 0.75 * 0.1
# = 0.8125
```

**Outlier Detection**:
- Unusually short or long compared to other paths
- Very low confidence compared to average
- Poor coherence (< 0.3)

#### 4. Voting Mechanisms

Four voting strategies:

**Majority Voting** (default):
```elixir
votes = %{"42" => 4, "41" => 1}
winner = "42"  # Most frequent
consensus = 4/5 = 0.8  # 80% agreement
```

**Confidence-Weighted Voting**:
```elixir
# Answer 42: paths with confidence [0.8, 0.9, 0.7, 0.85]
# Answer 41: path with confidence [0.6]
weight_42 = 0.8 + 0.9 + 0.7 + 0.85 = 3.25
weight_41 = 0.6
winner = "42"  # Higher weighted vote
```

**Quality-Weighted Voting**:
```elixir
# Answer 42: paths with quality [0.9, 0.85, 0.8, 0.88]
# Answer 41: path with quality [0.5]
weight_42 = 0.9 + 0.85 + 0.8 + 0.88 = 3.43
weight_41 = 0.5
winner = "42"
```

**Hybrid Voting**:
```elixir
# Combines count (40%), confidence (30%), and quality (30%)
score_42 = 4 * 0.4 + (3.25/4) * 4 * 0.3 + (3.43/4) * 4 * 0.3
score_41 = 1 * 0.4 + 0.6 * 1 * 0.3 + 0.5 * 1 * 0.3
winner = "42"  # Higher hybrid score
```

## When to Use Self-Consistency

### ✅ Ideal Use Cases

1. **Mission-Critical Decisions**
   - Financial calculations with high-stakes consequences
   - Medical diagnosis support where accuracy is paramount
   - Legal reasoning requiring high confidence
   - Safety-critical systems

2. **Mathematical & Logical Reasoning**
   - Complex word problems with multiple solution approaches
   - Statistical calculations requiring precision
   - Logic puzzles with non-obvious solutions
   - Scientific calculations

3. **Ambiguous or Tricky Problems**
   - Questions with potential misinterpretation
   - Problems with common misconceptions
   - Scenarios where intuition might mislead

4. **High-Value Decisions**
   - Strategic business decisions
   - Investment analysis
   - Risk assessment
   - Critical path planning

5. **When Single Errors Are Costly**
   - Scenarios where a wrong answer has significant consequences
   - When accuracy matters more than speed or cost
   - Production systems with strict SLAs

### ❌ When NOT to Use Self-Consistency

1. **Simple Factual Questions**
   - "What is the capital of France?" → Use direct prompting
   - Single CoT path is sufficient and much cheaper

2. **Creative Tasks**
   - Story writing, brainstorming, ideation
   - Multiple answers are all valid, voting doesn't apply

3. **Subjective Decisions**
   - "What color should we use?" → No objectively correct answer
   - Personal preferences and opinions

4. **High-Frequency, Low-Stakes Queries**
   - Chatbot responses where 5-10× cost isn't justified
   - Real-time systems requiring sub-second response

5. **Budget-Constrained Applications**
   - Development/testing environments with limited API budgets
   - Applications where cost optimization is priority

6. **When Latency Matters**
   - Real-time applications (Self-Consistency adds 15-25s even with parallel generation)
   - Interactive systems requiring immediate responses

### Decision Framework

```
Is the decision mission-critical or high-value?
    No → Don't use Self-Consistency
    Yes ↓

Would a wrong answer have significant consequences?
    No → Standard CoT is likely sufficient
    Yes ↓

Is the problem mathematical, logical, or potentially ambiguous?
    No → Consider if Self-Consistency applies
    Yes ↓

Can you afford 5-10× cost and 15-25s latency?
    No → Use standard CoT with validation
    Yes ↓

Is accuracy improvement worth the additional cost?
    No → Use standard CoT
    Yes → ✅ Use Self-Consistency
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

### Your First Self-Consistency Problem

```elixir
alias Jido.AI.Runner.SelfConsistency

# Pose a mathematical reasoning problem
problem = """
A bat and a ball together cost $1.10.
The bat costs $1.00 more than the ball.
How much does the ball cost?
"""

# Run with Self-Consistency
{:ok, result} = SelfConsistency.run(
  problem: problem,
  sample_count: 5,
  temperature: 0.7
)

# Examine the result
IO.puts("Answer: #{result.answer}")
IO.puts("Consensus: #{Float.round(result.consensus * 100, 1)}%")
IO.puts("Confidence: #{Float.round(result.confidence, 2)}")

IO.puts("\nVote Distribution:")
Enum.each(result.votes, fn {answer, count} ->
  IO.puts("  #{answer}: #{count} votes")
end)

IO.puts("\nAll reasoning paths:")
Enum.with_index(result.paths, 1) do |path, idx|
  IO.puts("\nPath #{idx}:")
  IO.puts(path.reasoning)
  IO.puts("→ Answer: #{path.answer} (quality: #{Float.round(path.quality_score, 2)})")
end
```

**Output**:
```
Answer: $0.05
Consensus: 80.0%
Confidence: 0.88

Vote Distribution:
  $0.05: 4 votes
  $0.10: 1 vote

All reasoning paths:

Path 1:
Let x be the cost of the ball.
Then the bat costs x + $1.00.
Together: x + (x + $1.00) = $1.10
2x + $1.00 = $1.10
2x = $0.10
x = $0.05
→ Answer: $0.05 (quality: 0.92)

Path 2:
Ball = b, Bat = b + 1.00
b + (b + 1.00) = 1.10
2b = 0.10
b = 0.05
The ball costs $0.05.
→ Answer: $0.05 (quality: 0.87)

Path 3:
Bat is $1 more than ball.
If ball is $0.10, bat would be $1.10, total $1.20 ✗
If ball is $0.05, bat is $1.05, total $1.10 ✓
→ Answer: $0.05 (quality: 0.79)

Path 4:
Total is $1.10, bat is $1 more.
Bat = $1.00, Ball = $0.10
Check: $1.00 + $0.10 = $1.10 ✓
→ Answer: $0.10 (quality: 0.65)

Path 5:
Let's solve: x + (x + 1) = 1.10
2x = 0.10
x = 0.05
Ball costs 5 cents.
→ Answer: $0.05 (quality: 0.90)
```

### What Happened Behind the Scenes

```elixir
# 1. Generate 5 diverse reasoning paths (parallel)
{:ok, paths} = generate_reasoning_paths(problem, 5, 0.7, nil, true)
# [path1, path2, path3, path4, path5]

# 2. Extract answers from each path
{:ok, paths_with_answers} = extract_answers(paths)
# [%{reasoning: "...", answer: 0.05}, ...]

# 3. Analyze quality of each path
{:ok, quality_paths} = analyze_and_filter_quality(paths_with_answers, 0.5)
# Scores each path on coherence, completeness, etc.

# 4. Ensure diversity (filter near-duplicates)
{:ok, diverse_paths} = ensure_diversity(quality_paths, 0.3)
# Keeps paths that are sufficiently different

# 5. Vote and select winner
{:ok, result} = vote_and_select(diverse_paths, :majority, 0.4)
# Votes: {0.05: 4, 0.10: 1} → Winner: 0.05
```

## Understanding the Components

### Component 1: Path Generation

**Module**: `Jido.AI.Runner.SelfConsistency`
**Function**: `generate_reasoning_paths/5`

**Responsibility**: Generate k independent reasoning paths with diversity.

#### Parallel Generation

```elixir
def generate_reasoning_paths(problem, sample_count, temperature, reasoning_fn, parallel) do
  generator = reasoning_fn || fn _i -> generate_single_path(problem, temperature) end

  paths = if parallel do
    # Generate in parallel using Tasks
    1..sample_count
    |> Enum.map(fn i -> Task.async(fn -> generator.(i) end) end)
    |> Task.await_many(30_000)
  else
    # Sequential generation
    Enum.map(1..sample_count, generator)
  end

  # Filter failures (need at least 50% success)
  {valid_paths, errors} = partition_results(paths)

  if length(valid_paths) >= div(sample_count, 2) do
    {:ok, valid_paths}
  else
    {:error, :insufficient_valid_paths}
  end
end
```

**Key Features**:
- **Parallel Execution**: Uses Elixir Tasks for concurrent generation
- **Failure Tolerance**: Requires only 50% of paths to succeed
- **Timeout Protection**: 30-second timeout per path
- **Error Logging**: Logs failures for observability

#### Temperature for Diversity

```elixir
# Low temperature (deterministic)
temperature: 0.2
# → Similar reasoning paths, less diversity

# High temperature (exploratory)
temperature: 0.7
# → Diverse approaches, creative solutions

# Very high temperature (risky)
temperature: 1.0
# → Maximum diversity but may include nonsense
```

**Recommended Settings**:
```elixir
# Standard Self-Consistency
sample_count: 5, temperature: 0.7

# High-stakes decisions
sample_count: 10, temperature: 0.8

# Quick/cheap version
sample_count: 3, temperature: 0.6
```

#### Custom Reasoning Function

```elixir
# Use custom reasoning logic
custom_reasoning = fn _seed ->
  # Your custom implementation
  # Could use different prompts, models, or strategies per path
  generate_custom_reasoning(problem)
end

{:ok, result} = SelfConsistency.run(
  problem: problem,
  sample_count: 5,
  reasoning_fn: custom_reasoning
)
```

### Component 2: Answer Extraction

**Module**: `Jido.AI.Runner.SelfConsistency.AnswerExtractor`

**Responsibility**: Extract and normalize answers from diverse reasoning formats.

#### Pattern-Based Extraction

```elixir
# Supports multiple answer formats
patterns = [
  ~r/(?:the\s+)?answer\s+is\s+[:\-]?\s*(.+?)(?:\.|$)/i,
  ~r/(?:therefore|thus|hence)[:\-]?\s*(.+?)(?:\.|$)/i,
  ~r/(?:result|solution|conclusion)[:\-]?\s*(.+?)(?:\.|$)/i
]

# Examples
extract("The answer is 42")          # → {:ok, "42"}
extract("Therefore: forty-two")      # → {:ok, "forty-two"}
extract("Result = 3.14")            # → {:ok, "3.14"}
```

#### Domain-Specific Extraction

```elixir
# Mathematical domain: prioritize numbers
{:ok, answer} = AnswerExtractor.extract(
  "Step 1... Step 2... Therefore x = 42",
  domain: :math
)
# → {:ok, 42}

# Code domain: extract code blocks
{:ok, answer} = AnswerExtractor.extract(
  "The solution is: ```elixir\ndef solve, do: 42\n```",
  domain: :code
)
# → {:ok, "def solve, do: 42"}

# Text domain: extract conclusions
{:ok, answer} = AnswerExtractor.extract(
  "In conclusion, the best approach is to prioritize quality.",
  domain: :text
)
# → {:ok, "the best approach is to prioritize quality"}
```

#### Normalization

```elixir
# Normalize to canonical forms
normalize("  HELLO  ")              # → {:ok, "hello"}
normalize("forty-two", domain: :math)  # → {:ok, 42}
normalize("yes", format: :boolean)   # → {:ok, true}
normalize("3.14159", format: :number) # → {:ok, 3.14159}

# Word-to-number conversion
normalize("twenty-three")            # → {:ok, 23}
normalize("one hundred")             # → {:ok, 100}
```

#### Semantic Equivalence

```elixir
# Check if answers are equivalent despite different representations
equivalent?(42, "42")                    # → true
equivalent?("yes", true)                 # → true
equivalent?("5 minutes", "5 min")        # → true
equivalent?("Hello", "hello")            # → true
equivalent?(3.14, "3.14")               # → true

# Case-insensitive, whitespace-normalized
equivalent?("  New York  ", "new york") # → true

# Not equivalent
equivalent?(42, 43)                     # → false
equivalent?("yes", false)               # → false
```

#### Usage Example

```elixir
alias Jido.AI.Runner.SelfConsistency.AnswerExtractor

reasoning_paths = [
  "Step 1... Step 2... The answer is 42",
  "Therefore: forty-two",
  "Result = 42.0",
  "Answer: 41",
  "Thus, 42 is the solution"
]

# Extract and normalize
answers = Enum.map(reasoning_paths, fn path ->
  {:ok, answer} = AnswerExtractor.extract(path, domain: :math, normalize: true)
  answer
end)

# → [42, 42, 42, 41, 42]

# Group equivalent answers
grouped = Enum.group_by(answers, & &1)
# → %{42 => [42, 42, 42, 42], 41 => [41]}

# Winner: 42 (4 out of 5 votes)
```

### Component 3: Path Quality Analyzer

**Module**: `Jido.AI.Runner.SelfConsistency.PathQualityAnalyzer`

**Responsibility**: Score reasoning paths on multiple quality dimensions.

#### Quality Factors

```elixir
@default_coherence_weight 0.3      # Logical flow
@default_completeness_weight 0.25  # All steps present
@default_confidence_weight 0.2     # Expressed certainty
@default_length_weight 0.15        # Appropriate length
@default_structure_weight 0.1      # Clear organization

# Analyze a path
path = %{
  reasoning: "Step 1: ... Step 2: ... Therefore, the answer is 42.",
  answer: 42,
  confidence: 0.85
}

score = PathQualityAnalyzer.analyze(path)
# → 0.82 (high quality)
```

#### Coherence Analysis

```elixir
defp analyze_coherence(path) do
  reasoning = path.reasoning

  # Positive indicators
  has_therefore = contains?(reasoning, ["therefore", "thus", "hence"])
  has_because = contains?(reasoning, ["because", "since", "as"])
  has_steps = contains?(reasoning, ["step", "first", "then", "next"])

  # Negative indicators
  has_contradiction = contains?(reasoning, ["but", "however"]) and
                      contains?(reasoning, ["not", "impossible"])

  connector_count = count_connectors(has_therefore, has_because, has_steps)
  base_score = min(1.0, connector_count / 3.0 * 1.2)

  if has_contradiction, do: base_score * 0.7, else: base_score
end
```

**High Coherence Example** (score: 0.9):
```
"First, let's identify the variables. Then, we set up the equation.
Because we have two unknowns, we need two equations. Therefore,
solving the system yields x = 5."
```

**Low Coherence Example** (score: 0.3):
```
"The answer might be 5. Or maybe 6. I'm not sure but let's say 5."
```

#### Completeness Analysis

```elixir
defp analyze_completeness(path) do
  reasoning = path.reasoning

  has_answer = path.answer != nil
  has_conclusion = contains?(reasoning, ["answer", "result", "therefore"])
  has_reasoning_steps = String.length(reasoning) > 50
  excessive_questions = count_questions(reasoning) > 2

  score = if(has_answer, do: 0.4, else: 0.0) +
          if(has_conclusion, do: 0.3, else: 0.0) +
          if(has_reasoning_steps, do: 0.3, else: 0.0)

  if excessive_questions, do: score * 0.8, else: score
end
```

**Complete Path** (score: 1.0):
```
"Given: x + y = 10, x - y = 2
Step 1: Add equations: 2x = 12
Step 2: Solve: x = 6
Step 3: Substitute: 6 + y = 10, so y = 4
Therefore, x = 6 and y = 4."
```

**Incomplete Path** (score: 0.4):
```
"x = 6"
```

#### Length Analysis

```elixir
defp analyze_length(path, opts) do
  length = String.length(path.reasoning)
  min_length = Keyword.get(opts, :min_length, 50)
  max_length = Keyword.get(opts, :max_length, 2000)
  ideal_length = (min_length + max_length) / 2

  cond do
    length < min_length -> length / min_length  # Too short
    length > max_length -> 1.0 - (length - max_length) / max_length  # Too long
    true -> 1.0 - abs(length - ideal_length) / ideal_length * 0.3  # Just right
  end
end
```

#### Structure Analysis

```elixir
defp analyze_structure(path) do
  reasoning = path.reasoning

  has_paragraphs = String.contains?(reasoning, "\n\n")
  has_numbered_steps = Regex.match?(~r/\d+[.):]\s/, reasoning)
  has_sections = contains?(reasoning, ["Step", "Given", "Solution"])

  score = if(has_paragraphs, do: 0.3, else: 0.0) +
          if(has_numbered_steps, do: 0.4, else: 0.0) +
          if(has_sections, do: 0.3, else: 0.0)

  max(0.3, score)  # Minimum score for unstructured but coherent
end
```

**Well-Structured** (score: 1.0):
```
Given:
- Variable x represents the unknown
- Constraint: x + 5 = 12

Solution:
1. Isolate x: x = 12 - 5
2. Simplify: x = 7

Therefore, x = 7.
```

#### Outlier Detection

```elixir
# Detect paths that are statistical outliers
{:ok, analysis} = PathQualityAnalyzer.detailed_analysis(path,
  context: other_paths
)

analysis
# %{
#   score: 0.65,
#   factors: %{coherence: 0.7, completeness: 0.6, ...},
#   outlier: true,
#   reasons: [
#     "Unusually short reasoning (45 chars vs avg 230)",
#     "Very low confidence (0.3 vs avg 0.8)"
#   ]
# }
```

**Outlier Criteria**:
- Length: More than 2 standard deviations from mean
- Confidence: Less than 50% of average confidence
- Coherence: Score below 0.3

#### Confidence Calibration

```elixir
# Adjust confidence based on quality
original_confidence = 0.8
quality_score = 0.9

calibrated = PathQualityAnalyzer.calibrate_confidence(path)
# → 0.85 (boosted due to high quality)

# Low quality path
original_confidence = 0.8
quality_score = 0.3

calibrated = PathQualityAnalyzer.calibrate_confidence(path)
# → 0.6 (reduced due to low quality)
```

### Component 4: Voting Mechanism

**Module**: `Jido.AI.Runner.SelfConsistency.VotingMechanism`

**Responsibility**: Select the most reliable answer through voting.

#### Voting Strategies

**Strategy 1: Majority Voting** (default):

```elixir
paths = [
  %{answer: 42, confidence: 0.8, quality_score: 0.9},
  %{answer: 42, confidence: 0.7, quality_score: 0.8},
  %{answer: 42, confidence: 0.9, quality_score: 0.85},
  %{answer: 43, confidence: 0.85, quality_score: 0.9},
  %{answer: 42, confidence: 0.75, quality_score: 0.8}
]

{:ok, result} = VotingMechanism.vote(paths, strategy: :majority)

result
# %{
#   answer: 42,
#   confidence: 0.8,  # Average confidence of winning paths
#   consensus: 0.8,   # 4 out of 5 paths agree
#   votes: %{42 => 4, 43 => 1},
#   paths: [4 paths that voted for 42],
#   metadata: %{total_paths: 5, unique_answers: 2, ...}
# }
```

**Strategy 2: Confidence-Weighted Voting**:

```elixir
# Weight votes by confidence scores
paths = [
  %{answer: 42, confidence: 0.7, quality_score: 0.8},  # Weight: 0.7
  %{answer: 42, confidence: 0.6, quality_score: 0.7},  # Weight: 0.6
  %{answer: 43, confidence: 0.9, quality_score: 0.95}, # Weight: 0.9
  %{answer: 42, confidence: 0.8, quality_score: 0.85}  # Weight: 0.8
]

# Answer 42: Total weight = 0.7 + 0.6 + 0.8 = 2.1
# Answer 43: Total weight = 0.9

{:ok, result} = VotingMechanism.vote(paths, strategy: :confidence_weighted)
# Winner: 42 (higher weighted vote despite 43 having highest individual confidence)
```

**Strategy 3: Quality-Weighted Voting**:

```elixir
# Weight votes by path quality scores
paths = [
  %{answer: 42, confidence: 0.8, quality_score: 0.9},  # Weight: 0.9
  %{answer: 43, confidence: 0.9, quality_score: 0.6},  # Weight: 0.6
  %{answer: 42, confidence: 0.7, quality_score: 0.85}, # Weight: 0.85
  %{answer: 42, confidence: 0.75, quality_score: 0.8}  # Weight: 0.8
]

# Answer 42: Total quality = 0.9 + 0.85 + 0.8 = 2.55
# Answer 43: Total quality = 0.6

{:ok, result} = VotingMechanism.vote(paths, strategy: :quality_weighted)
# Winner: 42 (higher quality reasoning)
```

**Strategy 4: Hybrid Voting**:

```elixir
# Combine count (40%), confidence (30%), and quality (30%)
paths = [
  %{answer: 42, confidence: 0.7, quality_score: 0.8},
  %{answer: 42, confidence: 0.8, quality_score: 0.85},
  %{answer: 43, confidence: 0.95, quality_score: 0.95}
]

# Answer 42:
# - Count: 2, avg_conf: 0.75, avg_quality: 0.825
# - Score: 2 * 0.4 + 0.75 * 2 * 0.3 + 0.825 * 2 * 0.3 = 1.745

# Answer 43:
# - Count: 1, avg_conf: 0.95, avg_quality: 0.95
# - Score: 1 * 0.4 + 0.95 * 1 * 0.3 + 0.95 * 1 * 0.3 = 0.97

{:ok, result} = VotingMechanism.vote(paths, strategy: :hybrid)
# Winner: 42 (balanced consideration of all factors)
```

#### Tie-Breaking

```elixir
# When multiple answers have equal votes
paths = [
  %{answer: 42, confidence: 0.9, quality_score: 0.85},
  %{answer: 43, confidence: 0.7, quality_score: 0.9}
]

# Both have 1 vote - tie!

# Tie-breaker: :highest_confidence
{:ok, result} = VotingMechanism.vote(paths,
  strategy: :majority,
  tie_breaker: :highest_confidence
)
# Winner: 42 (0.9 > 0.7)

# Tie-breaker: :highest_quality
{:ok, result} = VotingMechanism.vote(paths,
  strategy: :majority,
  tie_breaker: :highest_quality
)
# Winner: 43 (0.9 > 0.85)

# Other tie-breakers: :first, :random
```

#### Semantic Equivalence Grouping

```elixir
# Group semantically equivalent answers
paths = [
  %{answer: 42, ...},
  %{answer: "42", ...},
  %{answer: "forty-two", ...},
  %{answer: 43, ...}
]

{:ok, result} = VotingMechanism.vote(paths,
  semantic_equivalence: true,
  domain: :math
)

# Groups: {42 => 3 votes, 43 => 1 vote}
# Winner: 42 (equivalent forms grouped together)
```

#### Consensus Calculation

```elixir
# Consensus = proportion of paths agreeing with winner
paths = [
  %{answer: 42, ...},
  %{answer: 42, ...},
  %{answer: 42, ...},
  %{answer: 43, ...},
  %{answer: 42, ...}
]

consensus = VotingMechanism.calculate_consensus(paths, 42)
# → 0.8 (4 out of 5 paths agree on 42)

# High consensus = high confidence in answer
consensus >= 0.8  # → Strong agreement
consensus >= 0.6  # → Moderate agreement
consensus < 0.6   # → Weak agreement, may need more samples
```

## Configuration Options

### Main Configuration

```elixir
config = [
  # Sample Generation
  sample_count: 5,              # Number of reasoning paths (default: 5)
  temperature: 0.7,             # Temperature for diversity (default: 0.7)
  parallel: true,               # Parallel generation (default: true)

  # Quality Filtering
  quality_threshold: 0.5,       # Minimum quality to include path (default: 0.5)
  diversity_threshold: 0.3,     # Minimum diversity between paths (default: 0.3)

  # Voting
  voting_strategy: :majority,   # :majority, :confidence_weighted, :quality_weighted, :hybrid
  tie_breaker: :highest_confidence,  # :highest_confidence, :highest_quality, :first, :random
  semantic_equivalence: true,   # Group equivalent answers (default: true)
  min_consensus: 0.4,           # Minimum agreement required (default: 0.4)

  # LLM
  model: "gpt-4o",              # Model to use
  max_tokens: 1024,             # Tokens per path

  # Custom Functions
  reasoning_fn: nil             # Custom reasoning function (optional)
]

{:ok, result} = SelfConsistency.run(Keyword.merge(config, [problem: problem]))
```

### Sample Count Guidelines

```elixir
# Quick/cheap (acceptable for moderate importance)
sample_count: 3

# Standard Self-Consistency (recommended)
sample_count: 5

# High-stakes decisions
sample_count: 10

# Extreme accuracy needs (rarely justified)
sample_count: 15-20

# Research shows diminishing returns after k=10
```

### Temperature Guidelines

```elixir
# Low diversity (similar approaches)
temperature: 0.5

# Standard diversity (recommended)
temperature: 0.7

# High diversity (creative/exploratory)
temperature: 0.9

# Maximum diversity (may include low-quality paths)
temperature: 1.0
```

### Quality Threshold

```elixir
# Lenient (include more paths, even lower quality)
quality_threshold: 0.3

# Standard (filter obviously poor paths)
quality_threshold: 0.5

# Strict (only high-quality paths)
quality_threshold: 0.7

# Very strict (may filter out too many paths)
quality_threshold: 0.8
```

### Voting Strategy Selection

```elixir
# When votes are clear and quality is consistent
voting_strategy: :majority

# When some paths are more confident than others
voting_strategy: :confidence_weighted

# When reasoning quality varies significantly
voting_strategy: :quality_weighted

# For balanced consideration of all factors
voting_strategy: :hybrid
```

## Integration Patterns

### Pattern 1: Critical Financial Decision System

```elixir
defmodule FinancialAdvisor do
  alias Jido.AI.Runner.SelfConsistency

  @doc """
  Make high-stakes financial calculations with Self-Consistency.
  """
  def calculate_investment(scenario) do
    problem = """
    Investment Scenario:
    #{scenario}

    Calculate:
    1. Expected return over the investment period
    2. Risk assessment (conservative estimate)
    3. Recommended action
    """

    # High-stakes: use more samples and stricter quality
    config = [
      sample_count: 10,
      temperature: 0.7,
      quality_threshold: 0.7,
      voting_strategy: :hybrid,
      min_consensus: 0.6,
      model: "gpt-4o"
    ]

    case SelfConsistency.run(Keyword.merge(config, [problem: problem])) do
      {:ok, result} ->
        if result.consensus >= 0.6 do
          {:ok, format_financial_advice(result)}
        else
          {:error, :insufficient_consensus, result}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_financial_advice(result) do
    %{
      recommendation: result.answer,
      confidence: result.confidence,
      consensus: result.consensus,
      vote_distribution: result.votes,
      reasoning_paths: result.paths,
      decision_quality: assess_decision_quality(result)
    }
  end

  defp assess_decision_quality(result) do
    cond do
      result.consensus >= 0.8 and result.confidence >= 0.85 ->
        :very_high

      result.consensus >= 0.6 and result.confidence >= 0.7 ->
        :high

      result.consensus >= 0.5 ->
        :moderate

      true ->
        :low
    end
  end
end

# Usage
scenario = """
$100,000 investment for 5 years.
Options:
A) 7% annual return, moderate risk
B) 4% annual return, low risk
Current age: 35, retirement goal: 65
Risk tolerance: Moderate
"""

{:ok, advice} = FinancialAdvisor.calculate_investment(scenario)

IO.puts("Recommendation: #{advice.recommendation}")
IO.puts("Confidence: #{Float.round(advice.confidence * 100, 1)}%")
IO.puts("Consensus: #{Float.round(advice.consensus * 100, 1)}%")
IO.puts("Decision Quality: #{advice.decision_quality}")
```

### Pattern 2: Mathematical Problem Solver with Verification

```elixir
defmodule MathSolver do
  alias Jido.AI.Runner.SelfConsistency

  @doc """
  Solve mathematical problems with high accuracy using Self-Consistency.
  """
  def solve(problem, opts \\ []) do
    difficulty = assess_difficulty(problem)

    # Adjust sample count based on difficulty
    sample_count = case difficulty do
      :easy -> 3
      :medium -> 5
      :hard -> 10
    end

    config = [
      sample_count: sample_count,
      temperature: 0.7,
      quality_threshold: 0.6,
      voting_strategy: :quality_weighted,
      model: Keyword.get(opts, :model, "gpt-4o")
    ]

    case SelfConsistency.run(Keyword.merge(config, [problem: problem])) do
      {:ok, result} ->
        verified_result = verify_mathematical_answer(result, problem)
        {:ok, verified_result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp assess_difficulty(problem) do
    word_count = length(String.split(problem))
    has_multiple_steps = String.contains?(problem, ["then", "after", "next"])
    has_complex_ops = String.contains?(problem, ["exponential", "logarithm", "derivative"])

    cond do
      has_complex_ops or word_count > 100 -> :hard
      has_multiple_steps or word_count > 50 -> :medium
      true -> :easy
    end
  end

  defp verify_mathematical_answer(result, problem) do
    # Additional verification logic
    %{
      answer: result.answer,
      consensus: result.consensus,
      confidence: result.confidence,
      verification: %{
        quality_avg: calculate_avg_quality(result.paths),
        coherence_check: check_reasoning_coherence(result.paths),
        answer_plausibility: check_answer_plausibility(result.answer, problem)
      },
      all_paths: result.paths
    }
  end

  defp calculate_avg_quality(paths) do
    Enum.reduce(paths, 0.0, fn path, acc -> acc + path.quality_score end) / length(paths)
  end

  defp check_reasoning_coherence(paths) do
    # Check if paths used similar approaches
    approaches = Enum.map(paths, &extract_approach/1)
    unique_approaches = Enum.uniq(approaches)

    %{
      total_paths: length(paths),
      unique_approaches: length(unique_approaches),
      convergence: length(paths) / length(unique_approaches)
    }
  end

  defp extract_approach(path) do
    # Simple heuristic: check for key methods
    cond do
      String.contains?(path.reasoning, ["algebra", "equation"]) -> :algebraic
      String.contains?(path.reasoning, ["geometric", "visual"]) -> :geometric
      String.contains?(path.reasoning, ["trial", "test"]) -> :trial_and_error
      true -> :other
    end
  end

  defp check_answer_plausibility(answer, problem) do
    # Domain-specific plausibility checks
    %{
      is_numeric: is_number(answer),
      is_positive: is_number(answer) and answer > 0,
      reasonable_magnitude: is_number(answer) and answer < 1_000_000
    }
  end
end

# Usage
problem = """
A rectangular garden is 3 times as long as it is wide.
If the perimeter is 96 meters, what is the area of the garden?
"""

{:ok, solution} = MathSolver.solve(problem)

IO.puts("Answer: #{solution.answer}")
IO.puts("Consensus: #{Float.round(solution.consensus * 100)}%")
IO.puts("Average Quality: #{Float.round(solution.verification.quality_avg, 2)}")
IO.puts("Convergence: #{Float.round(solution.verification.coherence_check.convergence, 2)}x")
```

### Pattern 3: Medical Diagnosis Support

```elixir
defmodule MedicalDiagnosisSupport do
  alias Jido.AI.Runner.SelfConsistency

  @doc """
  Provide diagnostic suggestions using Self-Consistency.
  WARNING: For informational purposes only. Not a substitute for professional medical advice.
  """
  def analyze_symptoms(symptoms, patient_history) do
    problem = """
    Patient Symptoms:
    #{format_symptoms(symptoms)}

    Patient History:
    #{format_history(patient_history)}

    Based on the symptoms and history, what are the most likely diagnoses?
    Provide top 3 differential diagnoses with reasoning.
    """

    # Medical decisions require highest accuracy
    config = [
      sample_count: 10,
      temperature: 0.6,  # Lower temperature for medical reasoning
      quality_threshold: 0.7,
      voting_strategy: :hybrid,
      min_consensus: 0.7,  # Require high consensus
      model: "gpt-4o"
    ]

    case SelfConsistency.run(Keyword.merge(config, [problem: problem])) do
      {:ok, result} ->
        if result.consensus >= 0.7 do
          {:ok, format_diagnosis_report(result)}
        else
          {:warning, :low_consensus, format_diagnosis_report(result)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_symptoms(symptoms) do
    Enum.map_join(symptoms, "\n", fn symptom ->
      "- #{symptom}"
    end)
  end

  defp format_history(history) do
    Enum.map_join(history, "\n", fn item ->
      "- #{item}"
    end)
  end

  defp format_diagnosis_report(result) do
    %{
      suggested_diagnoses: result.answer,
      confidence_level: categorize_confidence(result),
      consensus: result.consensus,
      reasoning_paths_count: length(result.paths),
      vote_distribution: result.votes,
      recommendation: generate_recommendation(result),
      all_reasoning_paths: result.paths,
      disclaimer: "This is AI-assisted analysis. Always consult a qualified healthcare professional."
    }
  end

  defp categorize_confidence(result) do
    cond do
      result.consensus >= 0.9 and result.confidence >= 0.9 -> :very_high
      result.consensus >= 0.8 and result.confidence >= 0.8 -> :high
      result.consensus >= 0.7 and result.confidence >= 0.7 -> :moderate
      result.consensus >= 0.6 -> :low
      true -> :very_low
    end
  end

  defp generate_recommendation(result) do
    case categorize_confidence(result) do
      :very_high ->
        "Strong agreement across reasoning paths. Recommendation: Proceed with suggested diagnostic workup."

      :high ->
        "Good agreement across reasoning paths. Recommendation: Consider suggested diagnoses with clinical correlation."

      :moderate ->
        "Moderate agreement. Recommendation: Consider broader differential diagnosis."

      _ ->
        "Low agreement. Recommendation: Requires additional clinical information and expert consultation."
    end
  end
end

# Usage
symptoms = [
  "Fever (101.5°F) for 3 days",
  "Productive cough",
  "Shortness of breath",
  "Fatigue"
]

history = [
  "Age: 45",
  "Non-smoker",
  "No chronic conditions",
  "Recent travel to conference (1 week ago)"
]

{:ok, diagnosis} = MedicalDiagnosisSupport.analyze_symptoms(symptoms, history)

IO.puts("Confidence Level: #{diagnosis.confidence_level}")
IO.puts("Consensus: #{Float.round(diagnosis.consensus * 100)}%")
IO.puts("\n#{diagnosis.recommendation}")
IO.puts("\n#{diagnosis.disclaimer}")
```

### Pattern 4: Automated Fact-Checking System

```elixir
defmodule FactChecker do
  alias Jido.AI.Runner.SelfConsistency

  @doc """
  Verify claims using Self-Consistency across multiple reasoning paths.
  """
  def verify_claim(claim, context \\ nil) do
    problem = build_verification_prompt(claim, context)

    config = [
      sample_count: 7,
      temperature: 0.8,  # Higher diversity for fact-checking
      quality_threshold: 0.6,
      voting_strategy: :confidence_weighted,
      semantic_equivalence: true,
      domain: :text
    ]

    case SelfConsistency.run(Keyword.merge(config, [problem: problem])) do
      {:ok, result} ->
        {:ok, format_fact_check_result(result, claim)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_verification_prompt(claim, context) do
    base = """
    Claim to verify: "#{claim}"

    Please analyze this claim and determine:
    1. Is it TRUE, FALSE, or PARTIALLY TRUE?
    2. What evidence supports or contradicts it?
    3. What is your confidence level?
    """

    if context do
      base <> "\nAdditional context: #{context}"
    else
      base
    end
  end

  defp format_fact_check_result(result, claim) do
    verdict = normalize_verdict(result.answer)

    %{
      claim: claim,
      verdict: verdict,
      confidence: result.confidence,
      consensus: result.consensus,
      agreement_strength: assess_agreement(result),
      reasoning_summary: summarize_reasoning(result.paths),
      vote_breakdown: result.votes,
      all_paths: result.paths
    }
  end

  defp normalize_verdict(answer) do
    answer_lower = String.downcase(to_string(answer))

    cond do
      String.contains?(answer_lower, "true") and not String.contains?(answer_lower, "false") ->
        :true

      String.contains?(answer_lower, "false") ->
        :false

      String.contains?(answer_lower, ["partial", "mostly", "somewhat"]) ->
        :partially_true

      true ->
        :unclear
    end
  end

  defp assess_agreement(result) do
    cond do
      result.consensus >= 0.85 -> :strong_agreement
      result.consensus >= 0.7 -> :moderate_agreement
      result.consensus >= 0.5 -> :weak_agreement
      true -> :no_consensus
    end
  end

  defp summarize_reasoning(paths) do
    # Extract key points from each path
    Enum.map(paths, fn path ->
      %{
        conclusion: path.answer,
        quality: path.quality_score,
        key_point: extract_key_point(path.reasoning)
      }
    end)
  end

  defp extract_key_point(reasoning) do
    # Extract first sentence or key conclusion
    reasoning
    |> String.split(".")
    |> Enum.filter(fn s -> String.length(String.trim(s)) > 10 end)
    |> List.first()
    |> String.trim()
  end
end

# Usage
claim = "The Great Wall of China is visible from space with the naked eye."

{:ok, result} = FactChecker.verify_claim(claim)

IO.puts("Claim: #{result.claim}")
IO.puts("Verdict: #{result.verdict}")
IO.puts("Confidence: #{Float.round(result.confidence * 100)}%")
IO.puts("Agreement: #{result.agreement_strength}")
IO.puts("\nVote Breakdown:")
Enum.each(result.vote_breakdown, fn {verdict, count} ->
  IO.puts("  #{verdict}: #{count}")
end)
```

## Best Practices

### 1. Choose Appropriate Sample Counts

Match sample count to decision importance:

```elixir
# Low-stakes decisions
sample_count: 3  # Minimal Self-Consistency

# Standard applications
sample_count: 5  # Recommended default

# High-stakes decisions
sample_count: 10  # Maximum practical benefit

# Avoid excessive sampling
sample_count: 20  # Diminishing returns, unnecessary cost
```

**Why**: Research shows accuracy plateaus around k=10. Beyond that, you're paying more without significant accuracy gains.

### 2. Tune Temperature for Optimal Diversity

Balance diversity and quality:

```elixir
# Too low (insufficient diversity)
temperature: 0.3  # Paths will be too similar

# Optimal range
temperature: 0.7  # Recommended starting point
temperature: 0.8  # For more creative exploration

# Too high (poor quality)
temperature: 1.2  # May generate nonsense
```

**Why**: Too low = similar paths (defeats purpose), too high = low-quality paths (hurt voting accuracy).

### 3. Filter Low-Quality Paths

Use quality thresholds to maintain reliability:

```elixir
config = [
  quality_threshold: 0.5,  # Filter paths with quality < 0.5
  diversity_threshold: 0.3  # Ensure paths are sufficiently different
]

# Check quality distribution
{:ok, result} = SelfConsistency.run(config ++ [problem: problem])

avg_quality = Enum.reduce(result.paths, 0.0, fn p, acc ->
  acc + p.quality_score
end) / length(result.paths)

if avg_quality < 0.6 do
  Logger.warning("Low average path quality: #{avg_quality}")
end
```

**Why**: Low-quality paths add noise to voting without contributing valid reasoning.

### 4. Require Sufficient Consensus

Set minimum consensus thresholds:

```elixir
config = [
  min_consensus: 0.6  # Require 60% agreement
]

case SelfConsistency.run(config ++ [problem: problem]) do
  {:ok, result} ->
    case result.consensus do
      c when c >= 0.8 -> handle_high_confidence(result)
      c when c >= 0.6 -> handle_moderate_confidence(result)
      c when c < 0.6 -> handle_low_confidence(result)
    end

  {:error, {:insufficient_consensus, actual_consensus}} ->
    # Not enough paths agreed
    handle_no_consensus(actual_consensus)
end
```

**Why**: Low consensus indicates ambiguity or difficulty—you may need more samples or a different approach.

### 5. Select Appropriate Voting Strategy

Match strategy to your use case:

```elixir
# When all paths have similar quality
voting_strategy: :majority

# When confidence varies significantly
voting_strategy: :confidence_weighted

# When reasoning quality varies
voting_strategy: :quality_weighted

# For balanced decision-making
voting_strategy: :hybrid
```

**Why**: Different strategies emphasize different aspects of the reasoning paths.

### 6. Enable Semantic Equivalence

Group equivalent answers together:

```elixir
config = [
  semantic_equivalence: true,
  domain: :math  # or :text, :code, :general
]

# Without semantic equivalence:
# Votes: {42 => 2, "42" => 2, "forty-two" => 1}  # Split!

# With semantic equivalence:
# Votes: {42 => 5}  # Grouped correctly
```

**Why**: Prevents vote splitting across equivalent representations of the same answer.

### 7. Monitor and Log Results

Track Self-Consistency performance:

```elixir
defmodule SelfConsistencyMonitor do
  def run_and_log(problem, config) do
    start_time = System.monotonic_time(:millisecond)

    result = SelfConsistency.run(config ++ [problem: problem])

    duration = System.monotonic_time(:millisecond) - start_time

    log_result(result, duration, config)

    result
  end

  defp log_result({:ok, result}, duration, config) do
    Logger.info("""
    Self-Consistency Completed:
      Sample Count: #{config[:sample_count]}
      Consensus: #{Float.round(result.consensus * 100, 1)}%
      Confidence: #{Float.round(result.confidence, 2)}
      Duration: #{duration}ms
      Unique Answers: #{map_size(result.votes)}
      Winner: #{result.answer}
    """)
  end

  defp log_result({:error, reason}, duration, config) do
    Logger.error("Self-Consistency Failed: #{inspect(reason)} (#{duration}ms)")
  end
end
```

**Why**: Monitoring helps identify issues, optimize performance, and track costs.

### 8. Implement Fallback Strategies

Handle failures gracefully:

```elixir
def solve_with_fallback(problem) do
  case SelfConsistency.run(problem: problem, sample_count: 5) do
    {:ok, result} when result.consensus >= 0.6 ->
      {:ok, result}

    {:ok, result} ->
      # Low consensus - try with more samples
      Logger.info("Low consensus (#{result.consensus}), retrying with 10 samples")
      SelfConsistency.run(problem: problem, sample_count: 10)

    {:error, :insufficient_valid_paths} ->
      # Fall back to standard CoT
      Logger.warning("Self-Consistency failed, falling back to CoT")
      ChainOfThought.run(problem: problem)

    {:error, reason} ->
      {:error, reason}
  end
end
```

**Why**: Self-Consistency can fail (LLM errors, low consensus)—have backup strategies.

### 9. Cost Management

Control costs effectively:

```elixir
# Estimate cost before running
def estimate_cost(sample_count, avg_tokens_per_path) do
  # Rough estimate (adjust for your model pricing)
  cost_per_1k_tokens = 0.01  # $0.01 per 1K tokens for GPT-4o

  total_tokens = sample_count * avg_tokens_per_path
  estimated_cost = (total_tokens / 1000) * cost_per_1k_tokens

  %{
    sample_count: sample_count,
    tokens_per_path: avg_tokens_per_path,
    total_tokens: total_tokens,
    estimated_cost_usd: estimated_cost
  }
end

# Example
estimate_cost(5, 500)
# %{sample_count: 5, tokens_per_path: 500, total_tokens: 2500, estimated_cost_usd: 0.025}

estimate_cost(10, 500)
# %{sample_count: 10, tokens_per_path: 500, total_tokens: 5000, estimated_cost_usd: 0.05}

# Use cheaper models for non-critical tasks
config = [
  sample_count: 5,
  model: "gpt-4o-mini"  # Cheaper alternative
]
```

**Why**: Self-Consistency is expensive—estimate and control costs proactively.

### 10. Domain-Specific Customization

Tailor to your domain:

```elixir
# Mathematical domain
math_config = [
  sample_count: 5,
  temperature: 0.7,
  domain: :math,
  quality_threshold: 0.6,
  voting_strategy: :quality_weighted
]

# Medical domain (higher accuracy needs)
medical_config = [
  sample_count: 10,
  temperature: 0.6,  # Lower for medical reasoning
  quality_threshold: 0.7,
  voting_strategy: :hybrid,
  min_consensus: 0.7
]

# Creative domain (more diversity)
creative_config = [
  sample_count: 7,
  temperature: 0.9,
  quality_threshold: 0.4,  # More lenient
  voting_strategy: :confidence_weighted
]
```

**Why**: Different domains have different requirements for accuracy, diversity, and quality.

## Troubleshooting

### Problem: Low Consensus

**Symptoms**:
```elixir
{:ok, result} = SelfConsistency.run(problem: problem)
result.consensus  # → 0.3 (only 30% agreement)
```

**Possible Causes**:
1. Problem is genuinely ambiguous
2. Not enough samples
3. Temperature too high (excessive diversity)
4. Problem is too difficult for the model

**Solutions**:

```elixir
# 1. Increase sample count
config = [sample_count: 10]  # More samples for consensus

# 2. Lower temperature
config = [temperature: 0.6]  # Less randomness

# 3. Check if problem is ambiguous
IO.inspect(result.votes)
# %{"answer_A" => 3, "answer_B" => 2, "answer_C" => 2}
# → Multiple plausible answers, problem may be ambiguous

# 4. Rephrase problem for clarity
clearer_problem = """
Original: #{problem}

Clarification: Please focus on [specific aspect] and provide a single clear answer.
"""

# 5. Fall back to other methods
if result.consensus < 0.5 do
  # Try standard CoT or ask for clarification
  ChainOfThought.run(problem: problem)
end
```

### Problem: All Paths Give Same Answer (No Diversity)

**Symptoms**:
```elixir
{:ok, result} = SelfConsistency.run(problem: problem)
result.votes  # → %{42 => 5}  # All paths identical
map_size(result.votes)  # → 1 (only one unique answer)
```

**Possible Causes**:
1. Temperature too low
2. Problem has obvious answer
3. Paths are not truly independent

**Solutions**:

```elixir
# 1. Increase temperature
config = [temperature: 0.8]

# 2. Verify paths are actually different
Enum.each(result.paths, fn path ->
  IO.puts("\n#{String.slice(path.reasoning, 0..100)}...")
end)
# If reasoning is identical, temperature is too low

# 3. Check if problem is too simple
# For simple problems, Self-Consistency may be overkill
if is_simple_problem?(problem) do
  # Use cheaper standard CoT
  ChainOfThought.run(problem: problem)
else
  # Use Self-Consistency with higher temperature
  SelfConsistency.run(problem: problem, temperature: 0.8)
end
```

### Problem: Insufficient Valid Paths

**Symptoms**:
```elixir
{:error, :insufficient_valid_paths}
```

**Possible Causes**:
1. LLM API failures
2. Problem is malformed
3. Timeout too short
4. Answer extraction failing

**Solutions**:

```elixir
# 1. Retry with error handling
defmodule RobustSelfConsistency do
  def run_with_retry(config, max_retries \\ 2) do
    case SelfConsistency.run(config) do
      {:ok, result} ->
        {:ok, result}

      {:error, :insufficient_valid_paths} when max_retries > 0 ->
        Logger.info("Retrying Self-Consistency (#{max_retries} attempts remaining)")
        :timer.sleep(1000)  # Brief delay
        run_with_retry(config, max_retries - 1)

      error ->
        error
    end
  end
end

# 2. Check individual path failures
config = [
  sample_count: 5,
  parallel: false  # Sequential for debugging
]

# Look at logs for specific errors

# 3. Simplify problem
simplified_problem = simplify_language(problem)

# 4. Check answer extraction
{:ok, paths} = SelfConsistency.generate_reasoning_paths(problem, 5, 0.7, nil, false)

Enum.each(paths, fn path ->
  case AnswerExtractor.extract(path) do
    {:ok, answer} -> IO.puts("Extracted: #{answer}")
    {:error, reason} -> IO.puts("Failed: #{reason}\nPath: #{path}")
  end
end)
```

### Problem: High Cost

**Symptoms**:
- API bills higher than expected
- Self-Consistency is too expensive for use case

**Solutions**:

```elixir
# 1. Reduce sample count
config = [sample_count: 3]  # Minimum viable

# 2. Use cheaper model
config = [model: "gpt-4o-mini"]  # More economical

# 3. Route intelligently
def solve_intelligently(problem) do
  if is_critical_decision?(problem) do
    # Use Self-Consistency for important decisions
    SelfConsistency.run(problem: problem, sample_count: 5)
  else
    # Use standard CoT for routine problems
    ChainOfThought.run(problem: problem)
  end
end

# 4. Cache results for similar problems
defmodule CachedSelfConsistency do
  def run_cached(problem, config) do
    cache_key = :crypto.hash(:sha256, problem) |> Base.encode16()

    case get_cached_result(cache_key) do
      nil ->
        {:ok, result} = SelfConsistency.run(config ++ [problem: problem])
        cache_result(cache_key, result)
        {:ok, result}

      cached_result ->
        {:ok, cached_result, from_cache: true}
    end
  end
end

# 5. Monitor and set budgets
defmodule BudgetControlled do
  @max_monthly_spend_usd 100

  def run_if_within_budget(problem, config) do
    if current_month_spend() < @max_monthly_spend_usd do
      SelfConsistency.run(config ++ [problem: problem])
    else
      {:error, :budget_exceeded}
    end
  end
end
```

### Problem: Slow Performance

**Symptoms**:
- Takes 30+ seconds per query
- Timeout errors

**Solutions**:

```elixir
# 1. Ensure parallel execution is enabled
config = [parallel: true]  # Default, but verify

# 2. Reduce sample count
config = [sample_count: 3]  # Faster but less accurate

# 3. Use faster model
config = [model: "gpt-4o-mini"]  # Faster inference

# 4. Optimize path length
config = [max_tokens: 512]  # Shorter paths, faster generation

# 5. Implement timeout handling
task = Task.async(fn ->
  SelfConsistency.run(problem: problem, sample_count: 5)
end)

case Task.yield(task, 20_000) || Task.shutdown(task) do
  {:ok, result} ->
    result

  nil ->
    Logger.warning("Self-Consistency timeout")
    {:error, :timeout}
end
```

### Problem: Poor Answer Extraction

**Symptoms**:
```elixir
{:error, :no_valid_answers_extracted}
```

**Possible Causes**:
1. Reasoning paths don't contain explicit answers
2. Answer format doesn't match extraction patterns
3. Domain mismatch

**Solutions**:

```elixir
# 1. Improve prompting
problem = """
#{original_problem}

IMPORTANT: End your reasoning with a clear statement: "The answer is: [your answer]"
"""

# 2. Specify domain explicitly
config = [domain: :math]  # or :text, :code

# 3. Add custom extraction patterns
custom_patterns = [
  ~r/final answer:\s*(.+?)(?:\.|$)/i,
  ~r/conclusion:\s*(.+?)(?:\.|$)/i
]

config = [patterns: custom_patterns]

# 4. Debug extraction
{:ok, paths} = SelfConsistency.generate_reasoning_paths(problem, 3, 0.7, nil, false)

Enum.each(paths, fn path ->
  IO.puts("\n=== Path ===")
  IO.puts(path)

  {:ok, answer} = AnswerExtractor.extract(path, domain: :math)
  IO.puts("\n=== Extracted Answer ===")
  IO.puts(answer)
end)
```

### Problem: Tied Votes

**Symptoms**:
```elixir
{:ok, result} = SelfConsistency.run(problem: problem)
result.votes  # → %{42 => 2, 43 => 2, 44 => 1}
# Two answers tied at 2 votes
```

**Solutions**:

```elixir
# 1. Use tie-breaker strategy
config = [
  tie_breaker: :highest_confidence  # Select based on confidence
]

# 2. Use weighted voting
config = [
  voting_strategy: :confidence_weighted  # Breaks ties naturally
]

# 3. Increase sample count (odd number prevents ties)
config = [sample_count: 5]  # or 7, 9

# 4. Handle ties explicitly
case result do
  %{votes: votes} when map_size(votes) > 1 ->
    # Check if top two are tied
    sorted_votes = Enum.sort_by(votes, fn {_, count} -> -count end)

    case sorted_votes do
      [{_, c1}, {_, c2} | _] when c1 == c2 ->
        # Tie detected - handle specially
        handle_tie(result)

      _ ->
        # Clear winner
        {:ok, result}
    end
end
```

## Conclusion

Self-Consistency is a powerful technique for improving accuracy on mission-critical reasoning tasks. By generating multiple independent reasoning paths and selecting answers through voting, it achieves significant accuracy improvements (+17.9% on GSM8K) while providing quantitative measures of answer reliability through consensus scores.

### Key Takeaways

1. **When to Use**: Mission-critical decisions, mathematical reasoning, ambiguous problems where accuracy justifies 5-10× cost
2. **Sample Count**: k=5-10 optimal (diminishing returns beyond 10)
3. **Temperature**: 0.7-0.8 for good diversity without sacrificing quality
4. **Voting Strategy**: Majority for simple cases, hybrid for complex decisions
5. **Consensus Threshold**: Require 60%+ agreement for reliable results

### Cost-Benefit Analysis

| Metric | Standard CoT | Self-Consistency (k=5) |
|--------|--------------|------------------------|
| **API Calls** | 1 | 5 |
| **Cost** | 1× | 5× |
| **Latency** | 2-3s | 15-20s (parallel) |
| **Accuracy** | Baseline | +17.9% |
| **Confidence Measure** | No | Yes (consensus) |

### Integration Strategy

```elixir
# Smart routing based on importance
def solve_problem(problem, importance) do
  case importance do
    :critical ->
      # Use Self-Consistency with high sample count
      SelfConsistency.run(problem: problem, sample_count: 10)

    :high ->
      # Use Self-Consistency with standard settings
      SelfConsistency.run(problem: problem, sample_count: 5)

    :medium ->
      # Use standard CoT
      ChainOfThought.run(problem: problem)

    :low ->
      # Use direct prompting
      DirectPrompt.run(problem: problem)
  end
end
```

### Production Checklist

- [ ] Set appropriate sample counts based on decision criticality
- [ ] Configure quality and consensus thresholds
- [ ] Enable semantic equivalence for answer grouping
- [ ] Implement fallback strategies for failures
- [ ] Monitor consensus and confidence metrics
- [ ] Set up cost tracking and budgets
- [ ] Log results for analysis and debugging
- [ ] Cache results for similar problems
- [ ] Route intelligently (not everything needs Self-Consistency)
- [ ] Test on representative problems before production

### Combining with Other Techniques

Self-Consistency works well with other reasoning frameworks:

```elixir
# Self-Consistency + Chain-of-Thought
# Already built in (Self-Consistency uses CoT for each path)

# Self-Consistency + ReAct (for tool use)
# Generate multiple ReAct trajectories and vote on final answers

# Self-Consistency + Tree-of-Thoughts
# Explore multiple trees and vote on solutions

# Self-Consistency + Program-of-Thought
# Generate multiple programs, execute all, vote on results
```

### Next Steps

1. **Start Small**: Test with sample_count=3 on non-critical problems
2. **Measure Impact**: Compare accuracy with and without Self-Consistency
3. **Optimize**: Tune sample count, temperature, and thresholds for your domain
4. **Scale**: Gradually expand to more use cases based on demonstrated value
5. **Monitor**: Track consensus, confidence, and costs in production

### Examples

Explore complete working examples:

- [Self-Consistency Examples Directory](../examples/self-consistency/) - Complete working implementations:
  - `math_reasoning.ex` - Basic Self-Consistency with majority voting and quality scoring
  - `multi_domain_solver.ex` - Advanced Self-Consistency with multiple voting strategies and outlier detection
  - `README.md` - Comprehensive documentation and usage patterns

### Additional Resources

- **Chain-of-Thought Guide**: For understanding the base reasoning technique
- **ReAct Guide**: For combining Self-Consistency with tool use
- **Tree-of-Thoughts Guide**: For even more exhaustive exploration
- **GEPA Guide**: For optimizing prompts across multiple objectives

Self-Consistency represents a practical approach to improving LLM reliability: leverage diversity, use voting to surface consensus, and provide quantitative confidence measures. When accuracy matters more than cost or speed, Self-Consistency delivers measurable improvements while maintaining explainability through multiple reasoning paths.
