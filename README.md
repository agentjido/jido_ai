# Jido.AI

**AI integration layer for the Jido ecosystem** - LLM orchestration, accuracy improvement techniques, and reasoning strategies for building intelligent agents in Elixir.

## Overview

Jido.AI provides a comprehensive toolkit for improving LLM output quality through proven accuracy enhancement techniques. It implements research-backed algorithms for self-consistency, search, verification, reflection, and more - all designed to get better results from language models.

```elixir
# Quick example: ReAct agent with tool use
defmodule MyApp.Agent do
  use Jido.AI.ReActAgent,
    name: "my_agent",
    tools: [MyApp.Actions.Calculator, MyApp.Actions.Search],
    model: :fast
end

{:ok, agent} = MyApp.Agent.start_link()
{:ok, response} = MyApp.Agent.chat(agent, "What is 15 * 23?")
```

## Installation

```elixir
def deps do
  [
    {:jido, "~> 2.0"},
    {:jido_ai, "~> 2.0"}
  ]
end
```

Configure your LLM provider (see [Configuration Guide](guides/developer/08_configuration.md)):

```elixir
# config/config.exs
config :jido_ai, :models,
  anthropic: [
    api_key: System.get_env("ANTHROPIC_API_KEY")
  ],
  openai: [
    api_key: System.get_env("OPENAI_API_KEY")
  ]
```

## Reasoning Strategies

Strategies are agent patterns that determine how an LLM approaches a problem. They are the foundation of building intelligent agents with Jido.AI.

| Strategy | Pattern | Best For | Guide |
|----------|---------|----------|-------|
| **ReAct** | Reason-Act loop | Tool-using agents | [Guide](guides/user/02_strategies.md#react-reason-act) |
| **Chain-of-Thought** | Sequential reasoning | Multi-step problems | [Guide](guides/user/02_strategies.md#chain-of-thought) |
| **Tree-of-Thoughts** | Explore multiple paths | Complex planning | [Guide](guides/user/02_strategies.md#tree-of-thoughts) |
| **Graph-of-Thoughts** | Networked reasoning | Interconnected concepts | [Guide](guides/user/02_strategies.md#graph-of-thoughts) |
| **Adaptive** | Strategy selection | Variable problem types | [Guide](guides/user/02_strategies.md#adaptive-strategy) |

**When to use which strategy:**
- **ReAct** - When your agent needs to use tools or APIs
- **Chain-of-Thought** - For multi-step reasoning and math problems
- **Tree-of-Thoughts** - When exploring multiple solution paths is beneficial
- **Graph-of-Thoughts** - For problems with interconnected concepts
- **Adaptive** - When you need dynamic strategy selection based on the problem

```elixir
# ReAct agent with tools
defmodule MyApp.Agent do
  use Jido.AI.ReActAgent,
    name: "my_agent",
    tools: [MyApp.Actions.Calculator, MyApp.Actions.Search],
    model: :fast
end

# Chain-of-Thought for step-by-step reasoning
{:ok, result} = Jido.AI.Strategies.ChainOfThought.run(
  "If 3 cats catch 3 mice in 3 minutes, how many cats are needed to catch 100 mice in 100 minutes?",
  model: :fast
)
```

---

## Accuracy Improvement Techniques

Beyond strategies, Jido.AI provides research-backed techniques to improve LLM output quality. These are organized by how they enhance results:

### Consensus-Based Methods

Generate multiple candidates and aggregate results for more reliable answers.

| Technique | Best For | Guide |
|-----------|----------|-------|
| **Self-Consistency** | Multi-step reasoning, math problems | [Guide](guides/user/03_self_consistency.md) |
| **Adaptive Self-Consistency** | Dynamic resource allocation | [Guide](guides/user/04_adaptive_self_consistency.md) |

**When to use consensus methods:**
- Problems with definite answers (math, logic, factual)
- When you can afford multiple LLM calls
- When majority voting improves reliability

```elixir
# Generate 5 candidates, use majority vote
{:ok, best, _meta} = Jido.AI.Accuracy.SelfConsistency.run(
  "If 3 cats catch 3 mice in 3 minutes, how long for 100 cats?",
  num_candidates: 5,
  aggregator: :majority_vote
)
```

---

### Search Algorithms

Systematically explore the reasoning space to find optimal solutions.

| Algorithm | Best For | Guide |
|-----------|----------|-------|
| **Beam Search** | Focused exploration, limited depth | [Guide](guides/user/05_search_algorithms.md#beam-search) |
| **MCTS** | Complex reasoning, game-like scenarios | [Guide](guides/user/05_search_algorithms.md#monte-carlo-tree-search-mcts) |
| **Diverse Decoding** | Creative brainstorming | [Guide](guides/user/05_search_algorithms.md#diverse-decoding) |

**When to use search algorithms:**
- Problems with clear branching structure
- When systematic exploration beats single-shot
- Game-like or planning scenarios

```elixir
# MCTS for complex reasoning
{:ok, best} = Jido.AI.Accuracy.Search.MCTS.search(
  "Solve: x^2 + 5x + 6 = 0 for x",
  llm_generator,
  llm_verifier,
  simulations: 100
)
```

---

### Verification

Validate outputs before accepting them, catching hallucinations and errors.

| Verifier Type | Best For | Guide |
|---------------|----------|-------|
| **LLM Verifier** | General purpose checking | [Guide](guides/user/06_verification.md) |
| **Code Execution** | Code generation, math | [Guide](guides/user/06_verification.md#code-execution-verifier) |
| **Deterministic** | Known answers, test cases | [Guide](guides/user/06_verification.md#deterministic-verifier) |
| **Static Analysis** | Code quality checks | [Guide](guides/user/06_verification.md#static-analysis-verifier) |
| **Unit Test** | Test-driven validation | [Guide](guides/user/06_verification.md#unit-test-verifier) |

**When to use verification:**
- When hallucinations are costly
- For code generation or mathematical outputs
- When you have reference answers or tests

```elixir
# Create a code execution verifier
verifier = Jido.AI.Accuracy.Verifiers.CodeExecutionVerifier.new!(%{
  language: :elixir,
  timeout: 5000
})

# Verify code outputs
{:ok, result} = Jido.AI.Accuracy.Verifiers.CodeExecutionVerifier.verify(
  verifier,
  candidate,
  %{}
)
```

---

### Reflection & Improvement

Iteratively refine outputs through self-critique and revision.

| Technique | Best For | Guide |
|-----------|----------|-------|
| **Self-Refine** | Improving draft outputs | [Guide](guides/user/07_reflection.md) |
| **Reflection Stages** | Multi-stage refinement | [Guide](guides/user/07_reflection.md#reflection-stages) |
| **Critique & Revision** | Structured improvement cycles | [Guide](guides/user/08_critique_revision.md) |

**When to use reflection:**
- When initial drafts need refinement
- For writing, code, or complex explanations
- When you have time for iteration

```elixir
# Self-refine for better outputs
strategy = Jido.AI.Accuracy.SelfRefine.new!(%{})
{:ok, result} = Jido.AI.Accuracy.SelfRefine.run(strategy, "Write a function to sort a list")

result.refined_candidate  # The improved response
```

---

### Quality Estimation

Estimate confidence and difficulty to allocate resources appropriately.

| Technique | Best For | Guide |
|-----------|----------|-------|
| **Confidence Calibration** | Reliability scoring | [Guide](guides/user/10_confidence_calibration.md) |
| **Difficulty Estimation** | Resource allocation | [Guide](guides/user/11_difficulty_estimation.md) |
| **Process Reward Models** | Step-by-step quality | [Guide](guides/user/09_prm.md) |

**When to use quality estimation:**
- Variable-difficulty workloads
- Cost-sensitive applications
- When you need confidence scores

```elixir
# Estimate difficulty to allocate resources
estimator = Jido.AI.Accuracy.Estimators.HeuristicDifficulty.new!(%{})

{:ok, estimate} = Jido.AI.Accuracy.Estimators.HeuristicDifficulty.estimate(
  estimator,
  "What is the square root of 144 multiplied by the sum of the first 10 primes?",
  %{}
)

case estimate.level do
  :easy -> use_fast_model()
  :hard -> use_full_pipeline()
end
```

---

## Pipeline Orchestration

Combine multiple techniques into powerful pipelines that adapt to your needs.

[**Pipeline Guide &rarr;](guides/user/12_pipeline.md)**

```elixir
# Build a pipeline that adapts based on difficulty
{:ok, pipeline} = Jido.AI.Accuracy.Pipeline.new(%{})

generator = fn query, _context ->
  # Your LLM generation logic here
  {:ok, "Answer to: #{query}"}
end

{:ok, result} = Jido.AI.Accuracy.Pipeline.run(pipeline, "Solve this complex problem...", generator: generator)

result.answer  # The final answer
result.confidence  # Confidence score [0-1]
```

**When to use pipelines:**
- Complex problems requiring multiple techniques
- When you need adaptive processing
- Production workflows with quality requirements

---

## Documentation

### User Guides
- [Overview](guides/user/01_overview.md) - Library introduction and concepts
- [Strategies](guides/user/02_strategies.md) - Reasoning strategies
- [Self-Consistency](guides/user/03_self_consistency.md) - Consensus-based improvement
- [Adaptive Self-Consistency](guides/user/04_adaptive_self_consistency.md) - Dynamic resource allocation
- [Search Algorithms](guides/user/05_search_algorithms.md) - Beam search, MCTS, diverse decoding
- [Verification](guides/user/06_verification.md) - Output validation techniques
- [Reflection](guides/user/07_reflection.md) - Self-refine and reflection stages
- [Critique & Revision](guides/user/08_critique_revision.md) - Structured improvement cycles
- [Process Reward Models](guides/user/09_prm.md) - Step-by-step quality scoring
- [Confidence Calibration](guides/user/10_confidence_calibration.md) - Reliability estimation
- [Difficulty Estimation](guides/user/11_difficulty_estimation.md) - Resource-aware processing
- [Pipeline](guides/user/12_pipeline.md) - Combining techniques into workflows

### Developer Guides
- [Architecture Overview](guides/developer/01_architecture_overview.md) - System design
- [Strategies](guides/developer/02_strategies.md) - Strategy implementation
- [State Machines](guides/developer/03_state_machines.md) - Pure state machine pattern
- [Directives](guides/developer/04_directives.md) - Declarative side effects
- [Signals](guides/developer/05_signals.md) - Event-driven communication
- [Tool System](guides/developer/06_tool_system.md) - Tool registry and execution
- [Skills](guides/developer/07_skills.md) - Modular agent capabilities
- [Configuration](guides/developer/08_configuration.md) - Model aliases and providers

### Examples
See the `examples/` directory for runnable code:
- `examples/accuracy/` - Accuracy improvement examples
- `examples/strategies/` - Reasoning strategy examples

## Quick Decision Guide

Not sure which technique to use? Start here:

```
Building an agent?
├─ Need to use tools/APIs?
│  └─ Use ReAct Strategy
├─ Multi-step reasoning?
│  └─ Use Chain-of-Thought
└─ Complex planning?
   └─ Use Tree-of-Thoughts

Improving accuracy?
├─ Problem has definite answer?
│  └─ Use Self-Consistency
│
├─ Requires exploration/planning?
│  ├─ Shallow depth → Beam Search
│  └─ Deep/complex → MCTS
│
├─ Output needs validation?
│  └─ Add Verification
│
├─ Initial draft acceptable?
│  └─ Use Self-Refine
│
└─ Variable difficulty?
   └─ Use Pipeline with difficulty estimation
```

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

Apache-2.0 - See [LICENSE.md](LICENSE.md) for details.

---

**[Jido.AI Homepage](https://agentjido.xyz)** | **[GitHub](https://github.com/agentjido/jido_ai)** | **[Discord](https://agentjido.xyz/discord)**
