# ReAct Examples

This directory contains practical examples demonstrating ReAct (Reasoning + Acting) with Jido AI.

## What is ReAct?

ReAct is a prompting technique that combines reasoning and acting in an interleaved manner. It uses a **Thought-Action-Observation** loop where:
- **Thought**: The agent reasons about what to do next
- **Action**: The agent executes a tool/action
- **Observation**: The agent receives the result and incorporates it into reasoning

This approach improves both reasoning transparency and task success rates by grounding the agent's reasoning in external information.

## Examples

### 1. Basic Multi-Hop Reasoning (`basic_multi_hop.ex`)

**Purpose**: Demonstrates fundamental ReAct reasoning with multi-hop question answering.

**Features**:
- Thought-Action-Observation loop
- Multi-hop reasoning (questions requiring multiple steps)
- Tool-based information gathering
- Complete trajectory tracking
- Reasoning trace display

**Available Tools**:
- `SearchTool` - Search for information about a topic
- `LookupTool` - Extract specific details from previous results

**Usage**:
```elixir
# Run the example
Examples.ReAct.BasicMultiHop.run()

# Solve a custom question
Examples.ReAct.BasicMultiHop.solve_question(
  "What is the capital of the country where the Eiffel Tower is located?"
)

# Compare with and without ReAct
Examples.ReAct.BasicMultiHop.compare_with_without_react()

# Batch solve multiple questions
Examples.ReAct.BasicMultiHop.batch_solve([
  "What is the capital of the country where the Eiffel Tower is located?",
  "What is the population of Tokyo?",
  "How tall is Mount Everest?"
])
```

**Example Output**:
```
🤔 Step 1:
   Thought: I need to find where the Eiffel Tower is located first.
   Action: search("Eiffel Tower location")
   Observation: The Eiffel Tower is located in Paris, France...

🤔 Step 2:
   Thought: I found that the Eiffel Tower is in Paris, France. Now I need to confirm that Paris is the capital of France.
   Action: search("capital of France")
   Observation: The capital of France is Paris...

🤔 Step 3:
   Thought: I have confirmed that Paris is the capital of France, and the Eiffel Tower is in Paris. I can now provide the final answer.
   ✅ Final Answer: Paris
```

**Key Concepts**:
- Step-by-step reasoning with external tools
- Information gathering from multiple sources
- Transparent reasoning trail
- Verifiable tool usage

**Best For**:
- Learning ReAct basics
- Multi-hop question answering
- Understanding the Thought-Action-Observation pattern
- Simple tool integration

---

### 2. Advanced Research Agent (`advanced_research_agent.ex`)

**Purpose**: Demonstrates sophisticated ReAct reasoning with multiple specialized tools and error handling.

**Features**:
- Multiple specialized tools (4 types)
- Error handling and retry logic
- Adaptive reasoning based on findings
- Complex research workflows
- Finding extraction and synthesis
- Confidence scoring
- Result verification

**Available Tools**:
- `SearchTool` - Web search for general information
- `CalculatorTool` - Mathematical calculations
- `DatabaseTool` - Structured data queries
- `FactCheckTool` - Verify accuracy of claims

**Usage**:
```elixir
# Run the complete example
Examples.ReAct.AdvancedResearchAgent.run()

# Conduct custom research
Examples.ReAct.AdvancedResearchAgent.conduct_research(
  "Compare the GDP per capita of France and Germany"
)

# Research with custom max steps
Examples.ReAct.AdvancedResearchAgent.conduct_research(
  "What is the square root of 144?",
  max_steps: 5
)

# Compare approaches
Examples.ReAct.AdvancedResearchAgent.compare_with_without_react()

# Batch research multiple topics
Examples.ReAct.AdvancedResearchAgent.batch_research([
  "What is the population of Tokyo?",
  "Calculate 25% of 200"
])
```

**Research Workflow**:
1. **Initial Analysis** - Understand the research question
2. **Information Gathering** - Use appropriate tools to collect data
3. **Verification** - Fact-check critical claims
4. **Synthesis** - Combine findings into coherent answer
5. **Confidence Assessment** - Evaluate result reliability

**Example Output**:
```
🔬 Step 1:
   Thought: I need to find France's GDP and population first.
   Action: search("France GDP 2024")
   Observation: France's GDP is approximately $2.96 trillion...

🔬 Step 2:
   Thought: Now I need Germany's data for comparison.
   Action: search("Germany GDP 2024")
   Observation: Germany's GDP is approximately $4.31 trillion...

🔬 Step 3:
   Thought: I should calculate GDP per capita for both countries.
   Action: calculate("2.96 trillion / 67.8 million")
   Observation: 43,659

🔬 Step 4:
   Thought: Let me verify these figures are accurate.
   Action: fact_check("France GDP $2.96 trillion 2024")
   Observation: Verified: France's GDP is confirmed at $2.96 trillion for 2024

📊 Results:
   Answer: Germany has higher GDP per capita ($51,761) than France ($43,659)
   Confidence: 95%
   Verification Status: ✓ Verified
```

**Advanced Features**:
- **Error Recovery**: Automatic retry on tool failures (up to 3 attempts)
- **Finding Extraction**: Structured extraction of key facts
- **Confidence Calculation**: Based on verification and source quality
- **Adaptive Reasoning**: Changes strategy based on observations
- **Result Synthesis**: Aggregates multiple data points

**Key Concepts**:
- Multi-tool orchestration
- Error handling and resilience
- Complex reasoning workflows
- Finding aggregation
- Confidence metrics
- Result verification

**Best For**:
- Complex research tasks
- Multi-source data gathering
- Production-grade implementations
- Understanding error handling
- Learning verification patterns

---

## Quick Start

### Running Examples in IEx

```elixir
# Start IEx
iex -S mix

# Compile examples
c "examples/react/basic_multi_hop.ex"
c "examples/react/advanced_research_agent.ex"

# Run examples
Examples.ReAct.BasicMultiHop.run()
Examples.ReAct.AdvancedResearchAgent.run()
```

### Running from Mix Task

```bash
# Run basic multi-hop example
mix run -e "Examples.ReAct.BasicMultiHop.run()"

# Run advanced research agent
mix run -e "Examples.ReAct.AdvancedResearchAgent.run()"
```

## Comparison: Basic vs Advanced Examples

| Aspect | Basic Multi-Hop | Advanced Research |
|--------|-----------------|-------------------|
| **Complexity** | Low | High |
| **Tools** | 2 tools | 4 specialized tools |
| **Error Handling** | Basic | Retry logic + recovery |
| **Verification** | None | Fact-checking tool |
| **Confidence** | Implicit | Explicit scoring |
| **Best For** | Learning | Production patterns |

## Common Patterns

### Pattern 1: Basic ReAct Loop

Used in: `basic_multi_hop.ex`

```elixir
defp run_react_loop(state, tools) do
  cond do
    state.answer != nil ->
      # Found answer, stop
      {:ok, finalize_result(state)}

    state.current_step >= state.max_steps ->
      # Reached max steps
      {:ok, finalize_result(state)}

    true ->
      # Continue reasoning
      case execute_step(state, tools) do
        {:ok, new_state} -> run_react_loop(new_state, tools)
        {:error, reason} -> {:error, reason}
      end
  end
end
```

### Pattern 2: Tool Execution with Error Handling

Used in: `advanced_research_agent.ex`

```elixir
defp execute_action_with_retry(action_name, action_input, tools, attempts \\ 0) do
  max_attempts = 3

  case execute_action(action_name, action_input, tools) do
    {:ok, observation} ->
      {:ok, observation}

    {:error, reason} when attempts < max_attempts ->
      # Retry with exponential backoff
      :timer.sleep(100 * :math.pow(2, attempts))
      execute_action_with_retry(action_name, action_input, tools, attempts + 1)

    {:error, reason} ->
      {:error, "Failed after #{max_attempts} attempts: #{reason}"}
  end
end
```

### Pattern 3: Adaptive Reasoning

Used in: `advanced_research_agent.ex`

```elixir
defp generate_thought(state, tools) do
  last_step = List.last(state.trajectory)

  cond do
    # Initial step - analyze question
    state.current_step == 0 ->
      analyze_research_question(state.research_question)

    # After observation - adapt based on findings
    last_step && last_step.observation ->
      adapt_based_on_observation(last_step, state)

    # Error occurred - try different approach
    last_step && String.starts_with?(last_step.observation, "Error:") ->
      generate_alternative_approach(state)

    true ->
      continue_research(state)
  end
end
```

### Pattern 4: Finding Extraction and Synthesis

Used in: `advanced_research_agent.ex`

```elixir
defp extract_findings(trajectory) do
  trajectory
  |> Enum.filter(fn step -> step.action == "search" || step.action == "database" end)
  |> Enum.reduce(%{}, fn step, findings ->
    # Extract structured data from observations
    case parse_observation(step.observation) do
      {:ok, data} -> Map.merge(findings, data)
      {:error, _} -> findings
    end
  end)
end

defp synthesize_answer(findings, question) do
  # Combine multiple findings into coherent answer
  findings
  |> aggregate_relevant_data(question)
  |> format_answer()
  |> add_confidence_score()
end
```

## Tips for Using These Examples

1. **Start Simple**: Begin with `basic_multi_hop.ex` to understand the Thought-Action-Observation loop
2. **Progress to Advanced**: Move to `advanced_research_agent.ex` for production patterns
3. **Customize Tools**: Modify tool implementations for your specific use cases
4. **Experiment**: Try different questions and observe reasoning patterns
5. **Add Real Tools**: Replace simulated tools with actual API calls or database queries

## Integration with Jido AI

These examples are designed to work with Jido AI's action system:

```elixir
defmodule MyReActAgent do
  use Jido.Agent,
    name: "research_agent",
    actions: [
      SearchAction,
      CalculatorAction,
      DatabaseAction
    ]

  def conduct_research(agent, question) do
    # Use Jido Actions as ReAct tools
    tools = build_tools_from_actions(agent.actions)

    # Run ReAct loop
    state = %{
      question: question,
      trajectory: [],
      current_step: 0,
      max_steps: 10
    }

    run_react_loop(state, tools)
  end

  defp build_tools_from_actions(actions) do
    Enum.map(actions, fn action ->
      %{
        name: action.name,
        description: action.description,
        execute: &action.run/1
      }
    end)
  end
end
```

## Key Differences from Chain-of-Thought

| Aspect | Chain-of-Thought | ReAct |
|--------|------------------|-------|
| **External Tools** | No | Yes |
| **Observation Loop** | No | Yes (Action-Observation) |
| **Information Grounding** | Internal only | External sources |
| **Best For** | Reasoning problems | Research + action tasks |
| **Accuracy Improvement** | +8-15% | +27.4% (on multi-hop) |

## When to Use ReAct

Use ReAct when:
- ✅ You need to gather external information
- ✅ The task requires multiple steps with different tools
- ✅ You want transparent, verifiable reasoning
- ✅ The problem involves multi-hop questions
- ✅ You need to combine reasoning with actions

Consider Chain-of-Thought instead when:
- ❌ No external tools are needed
- ❌ The problem is purely logical/mathematical
- ❌ You want simpler, faster reasoning
- ❌ Cost is a primary concern

## Further Reading

- [ReAct Guide](../../guides/react.md) - Complete documentation
- [Chain-of-Thought Guide](../../guides/chain_of_thought.md) - Alternative reasoning approach
- [Tree-of-Thoughts Guide](../../guides/tree_of_thoughts.md) - Tree-based exploration
- [Jido Actions](../../guides/jido_actions.md) - Building ReAct-compatible tools

## Contributing

To add new examples:

1. Create a new file in this directory
2. Follow the existing pattern (module docs, public functions, helpers)
3. Include usage examples in module documentation
4. Include both basic and error-handling cases
5. Update this README with the new example
6. Add tests if applicable

## Questions?

See the main [ReAct Guide](../../guides/react.md) for detailed documentation.
