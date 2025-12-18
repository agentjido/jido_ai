# GEPA: Genetic-Pareto Prompt Optimization

## Introduction

GEPA (Genetic-Pareto) is an evolutionary optimization system for automatically improving prompts and other text-based components of AI systems. Unlike traditional methods that require thousands of trial runs, GEPA uses the LLM itself as a reflective coach to efficiently evolve high-quality prompts through natural language feedback.

The key innovation is treating prompt optimization as an **evolutionary search problem** guided by the AI's own feedback. GEPA maintains a diverse set of high-performing prompts along a **Pareto frontier**, meaning it considers multiple objectives simultaneously and keeps prompts that excel in different aspects.

### Why GEPA?

- **Sample Efficient**: Achieves large performance gains with far fewer trials than reinforcement learning (up to 35× fewer rollouts)
- **Multi-Objective**: Optimizes for multiple competing goals simultaneously (accuracy, speed, cost, robustness)
- **Task-Specific**: Specialized evaluation strategies for different task types (code generation, reasoning, classification, etc.)
- **Language-Driven**: Uses natural language reflection to propose targeted improvements
- **Diverse Solutions**: Maintains multiple high-quality prompts for different trade-offs
- **Elixir Native**: Leverages Elixir's concurrency to evaluate prompts in parallel

### Performance

In experiments, GEPA outperformed reinforcement learning baselines by ~10% on average (up to 19% on certain benchmarks) while using significantly fewer evaluations. It also surpassed prior prompt optimizers like MIPROv2, more than doubling the quality improvement achieved.

---

## Core Concepts

### Multi-Objective Optimization

Traditional optimization seeks a single "best" solution. GEPA uses **multi-objective optimization** to find multiple solutions that represent different trade-offs:

```elixir
# Example: Optimize for multiple objectives
objectives = [:accuracy, :latency, :cost, :robustness]

# Result: A Pareto frontier of solutions
# - Prompt A: High accuracy, slower, more expensive
# - Prompt B: Lower accuracy, faster, cheaper
# - Prompt C: Balanced across all objectives
```

### The Pareto Frontier

A solution is **Pareto optimal** if you cannot improve one objective without making another worse. GEPA maintains a population of Pareto optimal prompts:

```
Cost ↓
  │     ◆ High accuracy, high cost
  │   ◆   Medium accuracy, medium cost
  │ ◆     Low accuracy, low cost
  └─────────────────────────► Speed
```

Each point (◆) represents a different prompt variant optimized for different trade-offs.

### Evolutionary Loop

GEPA follows a four-step cycle:

1. **Sample**: Evaluate prompt variants on test inputs
2. **Reflect**: Use the LLM to analyze what went wrong or could improve
3. **Mutate**: Generate new prompt variations based on reflection
4. **Select**: Choose the best candidates for the next generation using Pareto dominance

### Key Components

| Component | Purpose |
|-----------|---------|
| **Population** | Set of prompt candidates being optimized |
| **Evaluation** | Measures prompt quality across multiple objectives with task-specific strategies |
| **Selection** | Chooses parents for breeding based on NSGA-II Pareto dominance |
| **Mutation** | Makes small changes to prompts (word changes, instruction tweaks) |
| **Crossover** | Combines elements from multiple parent prompts |
| **Convergence Detection** | Determines when optimization has plateaued |

---

## Task-Specific Evaluation

GEPA provides specialized evaluation strategies for different types of LLM tasks. Each strategy includes domain-specific metrics and validation appropriate for the task type.

### Supported Task Types

#### Code Generation (`:code_generation`)

Evaluates prompts for code generation tasks with syntax validation and functionality scoring.

**Configuration:**
```elixir
task = %{
  type: :code_generation,
  language: :elixir,  # :elixir, :python, :javascript
  problem: "Write a function to calculate fibonacci numbers",
  test_cases: [
    %{input: 0, expected: 0},
    %{input: 5, expected: 5},
    %{input: 10, expected: 55}
  ]
}
```

**Evaluation Process:**
1. Generate code using the LLM with the prompt
2. Validate syntax using AST parsing
3. Run test cases (currently heuristic-based)
4. Calculate code-specific fitness:
   - 50% functionality (test pass rate)
   - 30% generic quality
   - 20% syntax validity

**Supported Languages:**
- **Elixir**: Full AST-based syntax validation
- **Python**: Placeholder (coming soon)
- **JavaScript**: Placeholder (coming soon)

#### Reasoning (`:reasoning`)

Evaluates prompts for mathematical and logical reasoning tasks.

**Configuration:**
```elixir
task = %{
  type: :reasoning,
  problem: "What is 15 × 12? Think step by step.",
  expected_answer: "180",  # optional
  reasoning_steps_required: true  # optional
}
```

**Evaluation Process:**
1. Generate answer using the LLM with the prompt
2. Extract answer from response (handles multiple formats)
3. Check answer correctness (exact match, numeric similarity, partial match)
4. Assess reasoning steps (looks for "because", "first", "step", etc.)
5. Evaluate explanation clarity
6. Calculate reasoning-specific fitness:
   - 60% answer correctness
   - 25% reasoning steps present
   - 15% explanation clarity

**Key Features:**
- Multi-pattern answer extraction (supports "answer:", "therefore", numeric-only, yes/no)
- Numeric similarity checking (handles floats vs integers)
- Reasoning step detection
- Clarity scoring based on length and structure

#### Classification (`:classification`)

Evaluates prompts for text classification tasks with confidence calibration.

**Configuration:**
```elixir
task = %{
  type: :classification,
  expected_label: "positive",  # optional
  classes: ["positive", "negative", "neutral"],  # optional
  expected_confidence: 0.95  # optional
}
```

**Evaluation Process:**
1. Generate classification using the LLM with the prompt
2. Extract predicted label and confidence
3. Check label accuracy (with semantic equivalents like "pos" ↔ "positive")
4. Assess confidence calibration (penalizes over/under confidence)
5. Evaluate classification consistency
6. Calculate classification-specific fitness:
   - 70% label accuracy
   - 20% confidence calibration
   - 10% classification consistency

**Key Features:**
- Label and confidence extraction from multiple formats
- Semantic equivalents dictionary
- Confidence calibration scoring
- Multi-format confidence parsing (percentages, decimals, integers)

#### Question Answering (`:question_answering`)

Evaluates prompts for QA and information retrieval tasks.

**Configuration:**
```elixir
task = %{
  type: :question_answering,
  question: "What is the capital of France?",
  expected_answer: "Paris",  # optional
  context: "France is a country in Europe...",  # optional, for hallucination detection
  question_type: :what  # optional, :who, :what, :when, :where, :why, :how
}
```

**Evaluation Process:**
1. Generate answer using the LLM with the prompt
2. Auto-detect question type if not provided
3. Assess answer accuracy (exact match, partial match, context grounding)
4. Evaluate relevance to the question
5. Check completeness (type-specific length expectations)
6. Verify question type match (ensures "when" answers have dates/times, etc.)
7. Detect hallucinations (if context provided)
8. Calculate QA-specific fitness:
   - 60% answer accuracy
   - 25% relevance score
   - 15% completeness score
   - 0.5× penalty if hallucination detected

**Key Features:**
- Auto-detection of question types
- Question type validation
- Hallucination detection using context grounding
- Completeness assessment with type-specific length expectations

#### Summarization (`:summarization`)

Evaluates prompts for text summarization tasks.

**Configuration:**
```elixir
task = %{
  type: :summarization,
  source_text: "Long article or document to summarize...",
  expected_summary: "Reference summary for comparison",  # optional
  max_length: 100,  # optional, maximum words in summary
  min_length: 20,   # optional, minimum words in summary
  key_points: ["point 1", "point 2"]  # optional, important points to cover
}
```

**Evaluation Process:**
1. Generate summary using the LLM with the prompt
2. Calculate length metrics and compression ratio
3. Assess factual consistency with source (content word overlap)
4. Evaluate conciseness (optimal: 5-25% of source)
5. Check coherence (sentence structure, connectors, proper endings)
6. Verify key points coverage
7. Detect truncation (identifies lazy copy-paste)
8. Calculate summarization-specific fitness:
   - 40% factual consistency
   - 30% conciseness
   - 20% coherence
   - 10% key points coverage
   - 0.5× penalty if truncation detected

**Key Features:**
- Content word overlap for factual checking
- Stop word filtering for better analysis
- Compression ratio assessment
- Truncation detection
- Coherence scoring
- Key points coverage tracking

#### Generic Tasks (`:generic` or unspecified)

Default evaluation for tasks without specialized evaluators. Uses generic quality metrics based on LLM responses.

**Configuration:**
```elixir
task = %{
  type: :generic  # or omit for default
}
```

### How Task-Specific Evaluation Works

GEPA uses a strategy pattern dispatcher that routes evaluation to the appropriate evaluator based on task type:

```
TaskEvaluator (dispatcher)
  ├─> CodeEvaluator (for :code_generation)
  ├─> ReasoningEvaluator (for :reasoning)
  ├─> ClassificationEvaluator (for :classification)
  ├─> QuestionAnsweringEvaluator (for :question_answering)
  ├─> SummarizationEvaluator (for :summarization)
  └─> Generic Evaluator (fallback for all others)
```

Each evaluator:
1. Generates outputs using the LLM with the candidate prompt
2. Applies task-specific validation and metrics
3. Calculates domain-appropriate fitness scores
4. Returns enhanced evaluation results with task-specific metadata

---

## When to Use GEPA

### Ideal Use Cases

GEPA excels when:

- **Multiple Objectives Matter**: You need to balance accuracy, speed, cost, or other metrics
- **Quality is Critical**: The cost of optimization is justified by improved prompt quality
- **Complex Tasks**: Multi-step reasoning, code generation, classification, QA, summarization, or other nuanced tasks
- **Trade-off Analysis**: You need to understand trade-offs between competing goals
- **Task-Specific Optimization**: You're working with specialized tasks (code generation, reasoning, classification, QA, or summarization)

### When NOT to Use GEPA

Consider alternatives when:

- **Single Simple Prompt**: Basic tasks with obvious prompts don't need optimization
- **Time Constraints**: Optimization requires multiple LLM calls and takes time
- **Budget Limits**: Each optimization run costs money (see Cost Management)
- **Static Requirements**: Prompts won't change or don't need improvement
- **No Evaluation Metrics**: You can't define clear objectives to optimize

### Cost Considerations

⚠️ **GEPA MAKES REAL API CALLS AND INCURS COSTS**

- Each generation evaluates 10-20 prompts
- Each evaluation typically requires 1-5 LLM calls
- Default 10 generations = 100-1000 API calls
- Estimated cost: $0.50 - $10+ per optimization run

Always start with small population sizes and cheaper models for testing.

---

## Getting Started

### Prerequisites

Before running GEPA optimization, ensure you have:

1. **Jido AI Library**: The library must be available in your project
2. **LLM Provider Access**: An account with at least one LLM provider (OpenAI, Anthropic, Groq, etc.)
3. **API Credentials**: Valid API keys for your chosen provider(s)
4. **Test Data**: Example inputs to evaluate prompt performance

### Configuration

#### Step 1: Set API Keys

GEPA uses `Jido.AI.Keyring` for secure credential management. The API key name must match the provider in your model string.

**Provider → API Key Mapping:**

| Model Provider | API Key Name | Example |
|---------------|--------------|---------|
| `"openai:..."` | `:openai_api_key` | `"sk-..."` |
| `"anthropic:..."` | `:anthropic_api_key` | `"sk-ant-..."` |
| `"groq:..."` | `:groq_api_key` | `"gsk_..."` |

**Setting Keys:**

```elixir
# OpenAI
Jido.AI.Keyring.set_env_value(:openai_api_key, "sk-...")

# Anthropic
Jido.AI.Keyring.set_env_value(:anthropic_api_key, "sk-ant-...")

# Groq
Jido.AI.Keyring.set_env_value(:groq_api_key, "gsk_...")

# Verify key is set
case Jido.AI.Keyring.get_env_value(:openai_api_key, nil) do
  nil -> IO.puts("⚠️  Key not set!")
  key -> IO.puts("✓ Key configured: #{String.slice(key, 0, 7)}...")
end
```

**Alternative: Environment Variables**

You can also use environment variables (useful for deployment):

```bash
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
export GROQ_API_KEY="gsk_..."
```

#### Step 2: Choose Your Model

Models **must** be specified in the format: **`"provider:model_name"`**

**Supported Providers** (via [ReqLLM](https://hexdocs.pm/req_llm)):

```elixir
# OpenAI
model: "openai:gpt-4"              # High accuracy, expensive
model: "openai:gpt-3.5-turbo"      # Fast, cost-effective

# Anthropic
model: "anthropic:claude-3-opus-20240229"    # Highest accuracy
model: "anthropic:claude-3-sonnet-20240229"  # Balanced
model: "anthropic:claude-3-haiku-20240307"   # Fast, cheap

# Groq
model: "groq:llama-3.1-8b-instant"     # Ultra-fast inference
model: "groq:mixtral-8x7b-32768"       # Good reasoning

# And 50+ more providers via ReqLLM
```

**Model Selection Guide:**

| Use Case | Recommended Model | Why |
|----------|------------------|-----|
| **Testing/Development** | `openai:gpt-3.5-turbo` | Cheap, fast iterations |
| **Production Quality** | `openai:gpt-4` or `anthropic:claude-3-sonnet` | Best accuracy |
| **Budget Conscious** | `anthropic:claude-3-haiku` | Good quality, low cost |
| **Speed Critical** | `groq:llama-3.1-8b-instant` | Ultra-fast responses |

### Basic Setup

Now that configuration is complete, here's a complete example:

```elixir
# 1. Set API key (if not already done)
Jido.AI.Keyring.set_env_value(:openai_api_key, "sk-...")

# 2. Create agent with GEPA runner
agent = %{
  id: "optimizer-agent",
  name: "My Prompt Optimizer",
  state: %{},
  pending_instructions: :queue.new(),
  actions: [],
  runner: Jido.AI.Runner.GEPA,
  result: nil
}

# 3. Define test inputs for evaluation
test_inputs = [
  "Classify sentiment: I love this product!",
  "Classify sentiment: This is terrible.",
  "Classify sentiment: It's okay, nothing special."
]

# 4. Run optimization
{:ok, updated_agent, directives} = Jido.AI.Runner.GEPA.run(
  agent,
  test_inputs: test_inputs,
  seed_prompts: ["Classify the sentiment of: {{input}}"],
  model: "openai:gpt-3.5-turbo",  # ← Provider and model
  population_size: 10,
  max_generations: 5,
  objectives: [:accuracy, :latency, :cost]
)

# 5. Access results from agent state
best_prompts = updated_agent.state.gepa_best_prompts
pareto_frontier = updated_agent.state.gepa_pareto_frontier
history = updated_agent.state.gepa_history

IO.puts("Best prompt: #{hd(best_prompts).prompt}")
IO.puts("Fitness: #{hd(best_prompts).fitness}")
```

### Simple Example

```elixir
defmodule MyPromptOptimizer do
  alias Jido.AI.Runner.GEPA

  def optimize_classification_prompt do
    # Create agent
    agent = build_agent()

    # Test data
    test_inputs = [
      "I love Elixir!",
      "This bug is frustrating.",
      "The documentation is adequate."
    ]

    # Initial prompt templates
    seed_prompts = [
      "Classify the sentiment of this text: {{input}}\nReturn only: positive, negative, or neutral"
    ]

    # Run GEPA optimization
    {:ok, updated_agent, directives} = GEPA.run(
      agent,
      test_inputs: test_inputs,
      seed_prompts: seed_prompts,
      population_size: 8,
      max_generations: 3,
      model: "openai:gpt-3.5-turbo"
    )

    # Extract results
    best_prompts = updated_agent.state.gepa_best_prompts
    IO.puts("Optimized prompt:")
    IO.puts(hd(best_prompts).prompt)

    IO.puts("\nFitness scores:")
    IO.inspect(hd(best_prompts).fitness)
  end

  defp build_agent do
    %{
      id: "optimizer-#{System.unique_integer([:positive])}",
      name: "Prompt Optimizer",
      state: %{},
      pending_instructions: :queue.new(),
      actions: [],
      runner: GEPA,
      result: nil
    }
  end
end
```

---

## Code Generation Example

When optimizing prompts for code generation tasks, use the `:code_generation` task type for specialized evaluation:

```elixir
defmodule CodePromptOptimizer do
  alias Jido.AI.Runner.GEPA

  def optimize_code_prompt do
    agent = build_agent()

    # Code generation task configuration
    task = %{
      type: :code_generation,
      language: :elixir,
      problem: "Write a function that calculates the nth Fibonacci number",
      test_cases: [
        %{input: 0, expected: 0},
        %{input: 1, expected: 1},
        %{input: 5, expected: 5},
        %{input: 10, expected: 55}
      ]
    }

    # Test inputs (problem variations)
    test_inputs = [
      "Calculate fibonacci(0)",
      "Calculate fibonacci(5)",
      "Calculate fibonacci(10)"
    ]

    # Seed prompts for code generation
    seed_prompts = [
      """
      Write an Elixir function to calculate the nth Fibonacci number.
      Use recursion and include proper error handling for negative inputs.
      """
    ]

    # Run optimization with code evaluation
    {:ok, updated_agent, _directives} = GEPA.run(
      agent,
      test_inputs: test_inputs,
      seed_prompts: seed_prompts,
      task: task,
      population_size: 10,
      max_generations: 5,
      objectives: [:accuracy, :cost],
      model: "openai:gpt-4"
    )

    # Get best code generation prompt
    best_prompts = updated_agent.state.gepa_best_prompts
    best = hd(best_prompts)

    IO.puts("Optimized Code Generation Prompt:")
    IO.puts(best.prompt)

    IO.puts("\nCode Metrics:")
    IO.inspect(best.objectives)
  end

  defp build_agent do
    %{
      id: "code-optimizer-#{System.unique_integer([:positive])}",
      name: "Code Prompt Optimizer",
      state: %{},
      pending_instructions: :queue.new(),
      actions: [],
      runner: GEPA,
      result: nil
    }
  end
end
```

---

## Additional Task Examples

### Reasoning Task Example

Optimize prompts for mathematical and logical reasoning:

```elixir
defmodule ReasoningPromptOptimizer do
  alias Jido.AI.Runner.GEPA

  def optimize_reasoning_prompt do
    agent = build_agent()

    # Reasoning task configuration
    task = %{
      type: :reasoning,
      problem: "What is 15 × 12?",
      expected_answer: "180",
      reasoning_steps_required: true
    }

    # Test inputs (reasoning problems)
    test_inputs = [
      "What is 15 × 12? Think step by step.",
      "Calculate 7 + 8 × 2. Show your work.",
      "If a train travels 60 mph for 2.5 hours, how far does it go?"
    ]

    # Seed prompts for reasoning
    seed_prompts = [
      """
      Solve the following problem step by step.
      Show your reasoning at each step.
      Provide the final answer clearly.
      """
    ]

    {:ok, updated_agent, _} = GEPA.run(
      agent,
      test_inputs: test_inputs,
      seed_prompts: seed_prompts,
      task: task,
      population_size: 10,
      max_generations: 5,
      model: "openai:gpt-4"
    )

    best = hd(updated_agent.state.gepa_best_prompts)
    IO.puts("Optimized Reasoning Prompt:")
    IO.puts(best.prompt)
  end

  defp build_agent do
    %{
      id: "reasoning-optimizer-#{System.unique_integer([:positive])}",
      name: "Reasoning Prompt Optimizer",
      state: %{},
      pending_instructions: :queue.new(),
      actions: [],
      runner: GEPA,
      result: nil
    }
  end
end
```

### Classification Task Example

Optimize prompts for text classification with confidence:

```elixir
defmodule ClassificationPromptOptimizer do
  alias Jido.AI.Runner.GEPA

  def optimize_classification_prompt do
    agent = build_agent()

    # Classification task configuration
    task = %{
      type: :classification,
      classes: ["positive", "negative", "neutral"],
      expected_label: "positive"
    }

    # Test inputs for sentiment classification
    test_inputs = [
      "I absolutely love this product! Best purchase ever.",
      "Terrible quality. Complete waste of money.",
      "It's okay, does what it's supposed to do."
    ]

    # Seed prompts
    seed_prompts = [
      """
      Classify the sentiment of the following text as positive, negative, or neutral.
      Provide a confidence score between 0 and 1.
      Format: Label: [label], Confidence: [score]
      """
    ]

    {:ok, updated_agent, _} = GEPA.run(
      agent,
      test_inputs: test_inputs,
      seed_prompts: seed_prompts,
      task: task,
      population_size: 10,
      max_generations: 5,
      model: "anthropic:claude-3-sonnet-20240229"
    )

    best = hd(updated_agent.state.gepa_best_prompts)
    IO.puts("Optimized Classification Prompt:")
    IO.puts(best.prompt)
    IO.puts("\nMetrics:")
    IO.inspect(best.objectives)
  end

  defp build_agent, do: # ... same as above
end
```

### Question Answering Task Example

Optimize prompts for QA with hallucination detection:

```elixir
defmodule QAPromptOptimizer do
  alias Jido.AI.Runner.GEPA

  def optimize_qa_prompt do
    agent = build_agent()

    # QA task configuration
    task = %{
      type: :question_answering,
      question: "What is the capital of France?",
      expected_answer: "Paris",
      context: "France is a country in Western Europe. Its capital city is Paris, located in the north-central part of the country.",
      question_type: :what
    }

    # Test QA inputs
    test_inputs = [
      "What is the capital of France?",
      "Where is the Eiffel Tower located?",
      "When was France founded as a republic?"
    ]

    # Seed prompts for QA
    seed_prompts = [
      """
      Answer the following question based on the provided context.
      Provide a clear, concise answer.
      Only use information from the context.

      Context: {{context}}
      Question: {{input}}
      """
    ]

    {:ok, updated_agent, _} = GEPA.run(
      agent,
      test_inputs: test_inputs,
      seed_prompts: seed_prompts,
      task: task,
      population_size: 10,
      max_generations: 5,
      objectives: [:accuracy, :cost],
      model: "openai:gpt-4"
    )

    best = hd(updated_agent.state.gepa_best_prompts)
    IO.puts("Optimized QA Prompt:")
    IO.puts(best.prompt)
  end

  defp build_agent, do: # ... same as above
end
```

### Summarization Task Example

Optimize prompts for text summarization:

```elixir
defmodule SummarizationPromptOptimizer do
  alias Jido.AI.Runner.GEPA

  def optimize_summarization_prompt do
    agent = build_agent()

    source_text = """
    Artificial Intelligence (AI) has revolutionized many industries over the past decade.
    From healthcare to finance, AI systems are being deployed to automate tasks, improve
    decision-making, and enhance user experiences. Machine learning, a subset of AI,
    enables systems to learn from data without explicit programming. Deep learning, using
    neural networks with multiple layers, has achieved remarkable results in image
    recognition, natural language processing, and game playing. However, challenges remain,
    including bias in AI systems, lack of interpretability, and concerns about job
    displacement. Researchers are working on explainable AI, fairness in algorithms, and
    ensuring AI systems benefit society as a whole.
    """

    # Summarization task configuration
    task = %{
      type: :summarization,
      source_text: source_text,
      max_length: 50,
      min_length: 20,
      key_points: ["AI", "machine learning", "challenges"]
    }

    # Test inputs (different summarization requests)
    test_inputs = [
      "Summarize the above text in 2-3 sentences.",
      "Provide a brief summary highlighting key points.",
      "Condense the main ideas into a short paragraph."
    ]

    # Seed prompts for summarization
    seed_prompts = [
      """
      Summarize the following text concisely.
      Focus on the main ideas and key points.
      Keep the summary between 20-50 words.

      Text: {{input}}
      """
    ]

    {:ok, updated_agent, _} = GEPA.run(
      agent,
      test_inputs: test_inputs,
      seed_prompts: seed_prompts,
      task: task,
      population_size: 10,
      max_generations: 5,
      model: "anthropic:claude-3-sonnet-20240229"
    )

    best = hd(updated_agent.state.gepa_best_prompts)
    IO.puts("Optimized Summarization Prompt:")
    IO.puts(best.prompt)
    IO.puts("\nMetrics:")
    IO.inspect(best.objectives)
  end

  defp build_agent, do: # ... same as above
end
```

---

## Understanding GEPA Components

### Agent State

After optimization, the agent state contains all results:

```elixir
agent.state = %{
  gepa_best_prompts: [
    %{
      prompt: "Your optimized prompt text...",
      fitness: 0.95,
      objectives: %{accuracy: 0.95, latency: 120, cost: 0.002},
      generation: 5,
      metadata: %{}
    },
    # ... more prompts
  ],
  gepa_pareto_frontier: [
    # Top 5 Pareto-optimal solutions
  ],
  gepa_history: [
    %{generation: 1, best_fitness: 0.75, avg_fitness: 0.60},
    %{generation: 2, best_fitness: 0.82, avg_fitness: 0.68},
    # ...
  ],
  gepa_config: %{
    # Configuration used for this run
  },
  gepa_last_run: %{
    timestamp: ~U[2024-01-01 12:00:00Z],
    final_generation: 5,
    total_evaluations: 50,
    convergence_reason: :max_generations_reached,
    duration_ms: 45000
  }
}
```

### Directives

The runner returns directives that describe what happened:

```elixir
directives = [
  {:optimization_complete, %{
    final_generation: 5,
    total_evaluations: 50,
    convergence_reason: :max_generations_reached
  }},
  {:best_prompt, %{
    prompt: "...",
    fitness: 0.95,
    objectives: %{...}
  }},
  {:pareto_frontier, [
    # List of Pareto-optimal solutions
  ]}
]
```

### Population Management

**Population Size**: Controls diversity vs. convergence speed
- Small (5-10): Faster convergence, less diversity
- Medium (10-20): Good balance (recommended)
- Large (20-50): More diversity, slower, more expensive

### Selection: NSGA-II Pareto Dominance

GEPA uses the NSGA-II algorithm for selection:

**Pareto Dominance**: Solution A dominates solution B if:
- A is better or equal on all objectives, AND
- A is strictly better on at least one objective

**Fast Non-Dominated Sorting**:
1. Classify population into Pareto fronts
2. Front 1 contains all non-dominated solutions (Pareto optimal)
3. Front 2 contains solutions dominated only by Front 1, etc.

**Crowding Distance**:
- When Front 1 has more than 5 solutions, use crowding distance for diversity
- Solutions in less-crowded regions are preferred
- Boundary solutions get infinite distance to preserve extremes

### Mutation Operators

Mutations introduce variation by modifying prompts:

| Mutation Type | Effect | Example |
|---------------|--------|---------|
| **Instruction Modifier** | Add/modify instructions | "Be concise" → "Be concise and specific" |
| **Wording Tweak** | Rephrase for clarity | "Analyze this" → "Carefully examine this" |
| **Format Adjuster** | Change output format | "Respond..." → "Respond in JSON format" |
| **Example Addition** | Add few-shot examples | Add "Example: input → output" |
| **Constraint Addition** | Add guardrails | "Avoid technical jargon" |

**Mutation Rate**: Probability of applying each mutation (default: 0.3)

### Crossover Operators

Crossover combines elements from multiple parent prompts:

```elixir
# Parent prompts
parent1 = "Analyze the sentiment. Be concise."
parent2 = "Classify the emotion. Provide reasoning."

# Crossover result (combines elements)
offspring = "Analyze the sentiment. Provide reasoning."
```

**Crossover Rate**: Probability of breeding vs. mutation (default: 0.7)

### Convergence Detection

GEPA automatically detects when optimization has plateaued:

- **Max Generations**: Hard limit on generations
- **Evaluation Budget**: Stop when budget exhausted
- **Convergence Threshold**: Minimal improvement between generations

---

## Configuration Options

### Core Parameters

```elixir
# Required parameters
options = [
  test_inputs: ["input1", "input2", "input3"],  # Required: evaluation data

  # Optional parameters with defaults
  seed_prompts: [],                     # Initial prompt templates
  population_size: 10,                  # Candidates per generation
  max_generations: 20,                  # Maximum generations
  evaluation_budget: 200,               # Max evaluations (>= population_size)
  model: nil,                           # LLM model (provider:model format)

  # Evolutionary operators
  mutation_rate: 0.3,                   # Probability of mutation (0.0-1.0)
  crossover_rate: 0.7,                  # Probability of crossover (0.0-1.0)

  # Multi-objective settings
  objectives: [:accuracy, :cost, :latency, :robustness],
  objective_weights: %{},               # Optional custom weights

  # Advanced options
  enable_reflection: true,              # Use LLM reflection for improvements
  enable_crossover: true,               # Enable prompt crossover
  convergence_threshold: 0.001,         # Minimum fitness improvement
  parallelism: 5,                       # Max concurrent evaluations

  # Task-specific evaluation
  task: %{type: :generic}               # Task configuration (see Task-Specific Evaluation)
]
```

### Task-Specific Configuration

**Code Generation:**
```elixir
task: %{
  type: :code_generation,
  language: :elixir,
  problem: "Problem description",
  test_cases: [%{input: test_input, expected: expected_output}],
  starter_code: "optional",  # Optional
  timeout: 30_000            # Optional
}
```

**Reasoning:**
```elixir
task: %{
  type: :reasoning,
  problem: "What is 15 × 12?",
  expected_answer: "180",           # Optional
  reasoning_steps_required: true    # Optional
}
```

**Classification:**
```elixir
task: %{
  type: :classification,
  expected_label: "positive",       # Optional
  classes: ["positive", "negative", "neutral"],  # Optional
  expected_confidence: 0.95         # Optional
}
```

**Question Answering:**
```elixir
task: %{
  type: :question_answering,
  question: "What is the capital of France?",
  expected_answer: "Paris",         # Optional
  context: "Source text...",        # Optional
  question_type: :what              # Optional: :who, :what, :when, :where, :why, :how
}
```

**Summarization:**
```elixir
task: %{
  type: :summarization,
  source_text: "Text to summarize...",
  expected_summary: "Reference",    # Optional
  max_length: 100,                  # Optional
  min_length: 20,                   # Optional
  key_points: ["point1", "point2"]  # Optional
}
```

**Generic (default):**
```elixir
task: %{type: :generic}  # Or omit task entirely
```

---

## Cost Management

### ⚠️ CRITICAL: Understanding Costs

**GEPA MAKES REAL API CALLS AND INCURS ACTUAL COSTS**

Every optimization run involves:
- **Population size** × **Generations** = Total evaluations minimum
- Each evaluation = 1-5 LLM API calls
- Costs vary by provider, model, and prompt length

**Example Cost Calculation:**
```
Population: 15 prompts
Generations: 10
Total evaluations: 150 prompts minimum

At $0.002 per evaluation (GPT-3.5):
Estimated cost: $0.30

At $0.03 per evaluation (GPT-4):
Estimated cost: $4.50
```

### Budget Limits

The evaluation_budget parameter limits total evaluations:

```elixir
# Run with budget constraint
{:ok, agent, _} = GEPA.run(
  agent,
  test_inputs: inputs,
  population_size: 10,
  max_generations: 20,
  evaluation_budget: 100,  # Stop after 100 evaluations
  model: "openai:gpt-3.5-turbo"
)
```

### Cost Reduction Strategies

1. **Start Small**: Use small populations and few generations for testing

```elixir
# Development configuration
dev_options = [
  population_size: 5,
  max_generations: 3,
  evaluation_budget: 15
]
```

2. **Use Cheaper Models**: Start with GPT-3.5 or Claude Haiku

3. **Limit Test Inputs**: Use fewer evaluation examples during development

4. **Progressive Optimization**: Start cheap, then refine

```elixir
# Phase 1: Quick with cheap model
{:ok, agent1, _} = GEPA.run(agent, [
  model: "openai:gpt-3.5-turbo",
  population_size: 5,
  max_generations: 3
] ++ base_options)

# Phase 2: Refine with better model
best_prompt = hd(agent1.state.gepa_best_prompts).prompt
{:ok, agent2, _} = GEPA.run(agent, [
  seed_prompts: [best_prompt],
  model: "anthropic:claude-3-sonnet-20240229",
  population_size: 10,
  max_generations: 5
] ++ base_options)
```

---

## Best Practices

### 1. Define Clear Objectives

```elixir
# Good: Specific, measurable objectives
objectives = [:accuracy, :latency, :cost]

# Consider task-specific objectives for code
objectives = [:accuracy, :cost]  # Syntax validity is built into code evaluation
```

### 2. Use Representative Test Data

```elixir
# Good: Diverse, representative inputs
test_inputs = [
  "Simple case",
  "Complex scenario with multiple clauses",
  "Edge case: empty input",
  "Edge case: very long text...",
  "Ambiguous input"
]
```

### 3. Start with Simple Baselines

```elixir
# Start with a basic seed prompt
seed_prompts = ["Classify the sentiment: {{input}}"]

# Let GEPA evolve it
```

### 4. Choose Appropriate Task Types

```elixir
# For code generation
task = %{type: :code_generation, language: :elixir, ...}

# For mathematical/logical reasoning
task = %{type: :reasoning, problem: "What is...", ...}

# For text classification
task = %{type: :classification, classes: [...], ...}

# For question answering
task = %{type: :question_answering, question: "...", ...}

# For text summarization
task = %{type: :summarization, source_text: "...", ...}

# For general tasks
task = %{type: :generic}  # or omit
```

### 5. Monitor Agent State

```elixir
# Check progress
history = agent.state.gepa_history
last_gen = List.last(history)
IO.puts("Generation #{last_gen.generation}: fitness #{last_gen.best_fitness}")

# Examine Pareto frontier for trade-offs
agent.state.gepa_pareto_frontier
|> Enum.each(fn solution ->
  IO.inspect(solution.objectives)
end)
```

### 6. Save and Version Results

```elixir
# Save best prompt
best = hd(agent.state.gepa_best_prompts)
File.write!("prompts/optimized_v1.txt", best.prompt)

# Save metadata
metadata = %{
  version: "1.0",
  date: DateTime.utc_now(),
  fitness: best.fitness,
  objectives: best.objectives,
  config: agent.state.gepa_config
}
File.write!("prompts/optimized_v1_meta.json", Jason.encode!(metadata, pretty: true))
```

---

## API Reference

### Main Runner Function

```elixir
@spec run(agent(), keyword()) :: {:ok, agent(), list(directive())} | {:error, String.t()}

Jido.AI.Runner.GEPA.run(agent, options)
```

**Parameters:**
- `agent`: Jido agent struct
- `options`: Keyword list of configuration options

**Returns:**
- `{:ok, updated_agent, directives}` on success
- `{:error, reason}` on failure

**Required Options:**
- `:test_inputs` - List of test inputs for evaluation (must be non-empty)

**Optional Options:**
- `:seed_prompts` - Initial prompt templates (default: [])
- `:population_size` - Number of candidates per generation (default: 10, minimum: 2)
- `:max_generations` - Maximum generations (default: 20, minimum: 1)
- `:evaluation_budget` - Max evaluations (default: 200, must be >= population_size)
- `:model` - LLM model in "provider:model" format (default: nil)
- `:mutation_rate` - Probability 0.0-1.0 (default: 0.3)
- `:crossover_rate` - Probability 0.0-1.0 (default: 0.7)
- `:parallelism` - Max concurrent evaluations (default: 5, minimum: 1)
- `:objectives` - List of objective atoms (default: [:accuracy, :cost, :latency, :robustness])
- `:objective_weights` - Map of custom weights (default: %{})
- `:enable_reflection` - Use LLM reflection (default: true)
- `:enable_crossover` - Enable crossover (default: true)
- `:convergence_threshold` - Minimum improvement (default: 0.001)
- `:task` - Task configuration map (default: %{type: :generic})

**Agent State After Optimization:**
- `:gepa_best_prompts` - Top performing prompts
- `:gepa_pareto_frontier` - Pareto-optimal solutions (top 5)
- `:gepa_history` - Optimization history by generation
- `:gepa_config` - Configuration used
- `:gepa_last_run` - Metadata about the run

---

## Troubleshooting

### API Key Not Found

**Problem**: `{:error, "API key not found: OPENAI_API_KEY"}`

**Solution**: Set the API key that matches your model provider. See the [Configuration](#configuration) section for details.

```elixir
# Set the key for your provider (key name must match model provider)
Jido.AI.Keyring.set_env_value(:openai_api_key, "sk-...")

# Verify it's set
case Jido.AI.Keyring.get_env_value(:openai_api_key, nil) do
  nil -> IO.puts("⚠️  Key not set!")
  key -> IO.puts("✓ Key is set")
end
```

**Remember**: The API key name must match your model:
- `"openai:gpt-4"` requires `:openai_api_key`
- `"anthropic:claude-3-sonnet"` requires `:anthropic_api_key`
- `"groq:llama-3.1"` requires `:groq_api_key`

### Configuration Validation Errors

**Problem**: `{:error, "population_size must be at least 2"}`

**Solution**: Check all configuration constraints match the requirements in the API Reference section.

### No Test Inputs

**Problem**: `{:error, "test_inputs cannot be empty"}`

**Solution**: Provide at least one test input:
```elixir
test_inputs = ["test input"]
```

### Task-Specific Evaluation Failures

**Problem**: Code evaluation fails or produces low scores

**Solutions**:
```elixir
# 1. Verify task configuration
task = %{
  type: :code_generation,
  language: :elixir,  # Must match actual target language
  problem: "Clear problem description",
  test_cases: [
    %{input: valid_input, expected: correct_output}
  ]
}

# 2. Use appropriate model
model: "openai:gpt-4"  # Better for code generation than gpt-3.5-turbo

# 3. Provide good seed prompts
seed_prompts: [
  """
  Write clean, well-documented Elixir code.
  Include proper error handling.
  """
]
```

### Getting Help

If you encounter issues:

1. Check the agent state for error information
2. Review the [API documentation](https://hexdocs.pm/jido_ai)
3. Search [GitHub issues](https://github.com/agentjido/jido_ai/issues)
4. Ask in the [Elixir Forum](https://elixirforum.com/)

---

## Conclusion

GEPA brings powerful evolutionary optimization to prompt engineering through the Jido runner system. With specialized evaluation strategies for different task types and multi-objective Pareto dominance selection, GEPA helps you find prompts that balance accuracy, speed, cost, and other metrics according to your specific needs.

### Key Takeaways

- **Runner-Based**: GEPA integrates with the Jido agent system through the runner pattern
- **Task-Specific**: Specialized evaluation for code generation, reasoning, classification, question answering, and summarization
- **Multi-Objective**: Optimize for multiple competing goals using NSGA-II Pareto dominance
- **Sample Efficient**: Achieve results with far fewer evaluations than traditional methods
- **Pareto Frontier**: Maintain top 5 diverse solutions representing different trade-offs
- **Heuristic-Based**: Uses string analysis and pattern matching for task-specific metrics

### Next Steps

1. **Create an Agent**: Set up a Jido agent with the GEPA runner
2. **Define Test Inputs**: Prepare representative evaluation data
3. **Choose Task Type**: Use specialized evaluators (`:code_generation`, `:reasoning`, `:classification`, `:question_answering`, `:summarization`) or `:generic` for other tasks
4. **Run Optimization**: Call `GEPA.run/2` with your configuration
5. **Examine Results**: Review agent state for optimized prompts and Pareto frontier

### Further Reading

- [GEPA Research Paper](https://arxiv.org/abs/2507.19457)
- [ReqLLM Documentation](https://hexdocs.pm/req_llm)
- [Jido Documentation](https://hexdocs.pm/jido)
- [NSGA-II Algorithm](https://ieeexplore.ieee.org/document/996017)

By mastering GEPA, you can systematically improve your prompts, understand trade-offs between competing objectives, and build more effective AI-powered applications with confidence in your prompt quality.
