# Jido AI Examples

This directory contains standalone, runnable examples demonstrating various AI reasoning techniques using the Jido AI library.

## 🚀 Quick Start

Each example is a self-contained Mix project. To run any example:

```bash
cd examples/<category>/<example-name>
mix deps.get
mix run run.exs
```

**Example:**
```bash
cd examples/chain-of-thought/simple-math-reasoning
mix deps.get
mix run run.exs
```

## 📚 Available Examples (20 Total)

### Chain-of-Thought (3 examples)
Step-by-step reasoning for problem-solving.

1. **simple-math-reasoning** - Basic CoT for math problems
   ```bash
   cd examples/chain-of-thought/simple-math-reasoning && mix run run.exs
   ```

2. **data-analysis-workflow** - Multi-step data pipeline orchestration
   ```bash
   cd examples/chain-of-thought/data-analysis-workflow && mix run run.exs
   ```

3. **chain-of-thought-example** - Comprehensive CoT patterns
   ```bash
   cd examples/chain-of-thought/chain-of-thought-example && mix run run.exs
   ```

**Performance:** +8-15% accuracy | 3-4× cost

---

### Conversation Manager (2 examples)
Stateful multi-turn conversations with tool integration.

4. **basic-chat** - Simple conversational agent with tools
   ```bash
   cd examples/conversation-manager/basic-chat && mix run run.exs
   ```

5. **multi-tool-agent** - Production-grade agent with 3 tools
   ```bash
   cd examples/conversation-manager/multi-tool-agent && mix run run.exs
   ```

**Use Cases:** Chatbots, customer service, interactive assistants

---

### Program-of-Thought (2 examples)
Generate and execute code for computational accuracy.

6. **financial-calculator** - Financial calculations with code execution
   ```bash
   cd examples/program-of-thought/financial-calculator && mix run run.exs
   ```

7. **multi-domain-solver** - Advanced multi-domain problem solving
   ```bash
   cd examples/program-of-thought/multi-domain-solver && mix run run.exs
   ```

**Performance:** +8.5% accuracy on GSM8K | 2-3× cost | Near-zero arithmetic errors

---

### ReAct (2 examples)
Reasoning + Acting with external tools (Thought-Action-Observation loop).

8. **basic-multi-hop** - Multi-hop question answering
   ```bash
   cd examples/react/basic-multi-hop && mix run run.exs
   ```

9. **advanced-research-agent** - Complex research with 4 tools
   ```bash
   cd examples/react/advanced-research-agent && mix run run.exs
   ```

**Performance:** +27.4% accuracy on multi-hop QA | 10-30× cost

---

### Self-Consistency (2 examples)
Generate multiple reasoning paths and vote for best answer.

10. **math-reasoning** - Math problems with majority voting
    ```bash
    cd examples/self-consistency/math-reasoning && mix run run.exs
    ```

11. **multi-domain-solver** - Advanced with 4 voting strategies
    ```bash
    cd examples/self-consistency/multi-domain-solver && mix run run.exs
    ```

**Performance:** +17.9% accuracy on GSM8K (92% vs 74.9%) | 5-10× cost

---

### Tree-of-Thoughts (3 examples)
Tree-structured exploration with backtracking.

12. **game-of-24** - Classic Game of 24 puzzle
    ```bash
    cd examples/tree-of-thoughts/game-of-24 && mix run run.exs
    ```

13. **strategic-planner** - Multi-criteria project planning
    ```bash
    cd examples/tree-of-thoughts/strategic-planner && mix run run.exs
    ```

14. **tree-of-thought-example** - Comprehensive ToT patterns
    ```bash
    cd examples/tree-of-thoughts/tree-of-thought-example && mix run run.exs
    ```

**Performance:** +70% accuracy on Game of 24 (74% vs 4%) | 50-150× cost

---

### Hook Agents (4 examples)
Specialized agent patterns with lifecycle hooks.

15. **execution-hook** - Pre-execution analysis and validation
    ```bash
    cd examples/hook-agents/execution-hook && mix run run.exs
    ```

16. **planning-hook** - Planning-time instruction analysis
    ```bash
    cd examples/hook-agents/planning-hook && mix run run.exs
    ```

17. **validation-hook** - Post-execution result validation
    ```bash
    cd examples/hook-agents/validation-hook && mix run run.exs
    ```

18. **full-lifecycle-hook** - Complete lifecycle integration
    ```bash
    cd examples/hook-agents/full-lifecycle-hook && mix run run.exs
    ```

**Use Cases:** Production agents, workflow orchestration, quality assurance

---

### GEPA Optimization (2 examples)
Genetic-Pareto Prompt Optimization across multiple objectives.

19. **optimization-example** - Multi-objective prompt optimization
    ```bash
    cd examples/gepa/optimization-example && mix run run.exs
    ```

20. **working-example** - Working GEPA optimization example
    ```bash
    cd examples/gepa/working-example && mix run run.exs
    ```

**Use Cases:** Optimizing prompts for production, balancing accuracy/cost/latency

---

## 📊 Quick Comparison

| Technique | Accuracy Boost | Cost | Best For |
|-----------|----------------|------|----------|
| Chain-of-Thought | +8-15% | 3-4× | General reasoning |
| Program-of-Thought | +8.5% | 2-3× | Math/computation |
| ReAct | +27% | 10-30× | Research + Action |
| Self-Consistency | +17.9% | 5-10× | Critical decisions |
| Tree-of-Thoughts | +70% | 50-150× | Strategic planning |
| Conversation Manager | N/A | Variable | Multi-turn chat |
| Hook Agents | N/A | N/A | Production workflows |
| GEPA | Variable | High | Prompt optimization |

## 🎯 When to Use Each

- **Just starting?** → Chain-of-Thought examples
- **Need tools/actions?** → ReAct or Conversation Manager
- **Math accuracy critical?** → Program-of-Thought
- **Mission-critical decision?** → Self-Consistency
- **Strategic/planning problem?** → Tree-of-Thoughts
- **Building production agents?** → Hook examples
- **Optimizing for production?** → GEPA

## 📁 Project Structure

Each example follows this structure:

```
example-name/
├── mix.exs           # Project configuration
├── run.exs           # Executable script
└── lib/
    └── example.ex    # Example implementation
```

## 🔧 Common Commands

### Run an example
```bash
cd examples/<category>/<example-name>
mix run run.exs
```

### Get dependencies
```bash
mix deps.get
```

### Compile without running
```bash
mix compile
```

### Interactive shell with example loaded
```bash
iex -S mix
```

## 📖 Documentation

Each category has a detailed README:
- [Chain-of-Thought README](chain-of-thought/README.md)
- [Conversation Manager README](conversation-manager/README.md)
- [Program-of-Thought README](program-of-thought/README.md)
- [ReAct README](react/README.md)
- [Self-Consistency README](self-consistency/README.md)
- [Tree-of-Thoughts README](tree-of-thoughts/README.md)

## 🛠️ Requirements

- Elixir 1.14 or later
- Mix (comes with Elixir)
- Internet connection for dependency downloads

## 💡 Tips

1. **Start simple:** Begin with Chain-of-Thought examples
2. **Read the docs:** Each example includes inline documentation
3. **Experiment:** Modify parameters and observe behavior
4. **Check costs:** Higher accuracy techniques cost more
5. **Use appropriate technique:** Match the technique to your problem

## 🤝 Contributing

To add a new example:

1. Create a new directory: `examples/<category>/<example-name>/`
2. Add `mix.exs`, `run.exs`, and `lib/` directory
3. Implement your example in `lib/`
4. Update this README
5. Test with `mix run run.exs`

## 📚 Further Reading

- [Jido AI Documentation](https://hexdocs.pm/jido_ai)
- [Main Project README](../README.md)
- [Guides](../guides/)

## ❓ Questions?

- Check the category-specific READMEs for detailed information
- Review the inline documentation in each example
- See the main Jido AI documentation

---

**All examples are self-contained and ready to run!** 🚀
