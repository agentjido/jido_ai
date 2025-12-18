# ReAct: Reasoning and Acting with Tool Integration

## Introduction

ReAct (Reasoning + Acting) is a powerful prompting framework that combines reasoning with action execution through an iterative loop of thinking, acting, and observing. Unlike traditional Chain-of-Thought that generates reasoning upfront, ReAct interleaves reasoning with real-world actions, allowing the model to gather information dynamically and adjust its strategy based on observations.

The key innovation is the **Thought-Action-Observation cycle**: the model reasons about what to do next, executes an action (like calling an API or tool), observes the result, and uses that observation to inform its next reasoning step. This creates a synergistic loop where reasoning guides action selection, and actions provide grounded observations that reduce hallucination.

### Why ReAct?

Research demonstrates that ReAct delivers **significant performance improvements** on multi-hop reasoning and information gathering tasks:

- **HotpotQA**: +27.4% accuracy improvement
- **Fever (Fact Verification)**: +19.5% accuracy improvement
- **Cost**: 10-30× baseline (depends on number of steps)
- **Best for**: Multi-source research, iterative investigation, tool-based problem solving

The framework is particularly effective because:
- Reasoning makes action selection more targeted than random exploration
- Actions provide concrete observations that ground the reasoning
- The iterative nature allows correction of mistakes
- Natural integration with tool/function calling systems

### Performance

ReAct excels on tasks requiring information gathering and multi-step investigation:

| Task Type | Baseline | With ReAct | Improvement |
|-----------|----------|------------|-------------|
| Multi-Hop QA (HotpotQA) | 45% | 72.4% | +27.4% |
| Fact Verification (Fever) | 60% | 79.5% | +19.5% |
| Multi-Source Research | 50% | 68% | +18% |
| Interactive Problem Solving | 55% | 72% | +17% |

**Cost**: Typically 10-30× the cost of direct prompting, depending on the number of reasoning steps (average: 5-10 steps per query).

> **💡 Practical Examples**: See the [ReAct examples directory](../examples/react/) for complete working implementations including a research assistant and a multi-step task solver.

---

## Core Concepts

### The ReAct Loop

ReAct follows a four-phase cycle that repeats until an answer is found or maximum steps are reached:

```
1. THOUGHT: Reason about what to do next based on current state
   ↓
2. ACTION: Select and execute a tool/action based on the thought
   ↓
3. OBSERVATION: Capture and process the result of the action
   ↓
4. REPEAT: Use observation to inform next thought
```

**Example**:

```
Question: "What is the capital of the country where the Eiffel Tower is located?"

Step 1:
  Thought: "I need to find where the Eiffel Tower is located."
  Action: search("Eiffel Tower location")
  Observation: "The Eiffel Tower is in Paris, France."

Step 2:
  Thought: "Now I know it's in France. I need to confirm France's capital."
  Action: search("capital of France")
  Observation: "The capital of France is Paris."

Step 3:
  Thought: "I have confirmed the answer from two sources."
  Final Answer: "Paris"
```

### How It Works

#### 1. Thought Generation

At each step, the model generates reasoning about:
- What information is still needed
- Which action would be most useful
- How to interpret previous observations
- Whether enough information has been gathered

#### 2. Action Selection

Based on the thought, the model selects an action from available tools:
- **Search**: Query external information sources
- **Calculate**: Perform computations
- **Lookup**: Retrieve specific details from previous observations
- **Custom Tools**: Any Jido Action can become a ReAct tool

#### 3. Observation Processing

Action results are processed and formatted as observations:
- Successful results become factual observations
- Errors become observations about what didn't work
- Observations are added to context for future reasoning

#### 4. Trajectory Management

The complete history of thoughts, actions, and observations forms a **trajectory** that:
- Provides context for future reasoning
- Enables backtracking if needed
- Supports debugging and explainability
- Allows analysis of the reasoning path

### Key Components

| Component | Purpose |
|-----------|---------|
| **ToolRegistry** | Manages available tools and their descriptions |
| **ActionSelector** | Parses thought output to identify intended action |
| **ObservationProcessor** | Formats action results into observations |
| **Trajectory** | Maintains complete history of the reasoning loop |
| **ThoughtGenerator** | Creates reasoning prompts with context |

### Integration with Jido AI

Jido AI implements ReAct as a standalone function that works with any Jido Actions:

```elixir
# Any Jido Action can become a ReAct tool
defmodule MyActions.SearchTool do
  use Jido.Action,
    name: "search",
    description: "Search for information online"

  def run(%{query: query}, _context) do
    # Perform search
    results = perform_search(query)
    {:ok, results}
  end
end

# Use actions with ReAct
{:ok, result} = Jido.AI.Runner.ReAct.run(
  question: "What year was Elixir created?",
  tools: [MyActions.SearchTool, MyActions.WikipediaTool],
  max_steps: 10
)

# Result includes complete trajectory
IO.inspect(result.trajectory)
```

The ReAct runner:
- Maintains the thought-action-observation loop
- Integrates seamlessly with Jido's action system
- Provides trajectory tracking and debugging
- Handles errors gracefully with observation messages
- Supports custom thought templates

---

## When to Use ReAct

### Ideal Use Cases

ReAct excels when tasks require:

**Multi-Hop Reasoning**
- Questions requiring information from multiple sources
- Queries where the answer depends on intermediate findings
- Research tasks with sequential dependencies

**Interactive Information Gathering**
- Web research and fact-finding
- Database queries with iterative refinement
- Document analysis across multiple files

**Dynamic Problem Solving**
- Troubleshooting where investigation reveals next steps
- Debugging where each observation guides the next action
- Exploratory data analysis

**Tool-Based Tasks**
- API orchestration with multiple services
- Code generation with iterative testing
- System administration with conditional actions

**Verification and Validation**
- Fact-checking across multiple sources
- Cross-referencing information
- Validating claims with evidence gathering

### When NOT to Use ReAct

Consider alternatives when:

- **Single-Source Answers**: Direct questions answerable from one source
- **No Tool Access Needed**: Pure reasoning tasks without external actions
- **Latency Critical**: The 10-30× cost/latency increase is unacceptable
- **Simple Lookups**: Direct database queries or API calls suffice
- **Budget Constrained**: Multiple LLM calls per query are too expensive

### Cost-Benefit Analysis

```
Without ReAct (Direct Answer):
- Latency: 1-2s
- Tokens: 100-200
- LLM Calls: 1
- Accuracy: 45% (multi-hop tasks)
- Cost: $0.001

With ReAct (5 steps average):
- Latency: 15-30s (10-15× increase)
- Tokens: 1000-2000 (10-20× increase)
- LLM Calls: 5-10 (one per step)
- Accuracy: 72% (+27%)
- Cost: $0.010-0.020 (10-20× increase)
```

**ROI**: ReAct is worth the cost when:
- Multi-hop reasoning is required
- Accuracy improvement justifies 10-20× cost
- Tool integration provides value
- Transparency in reasoning is important

---

## Getting Started

### Prerequisites

1. **Jido AI installed** with LLM provider configured
2. **API keys set** for your chosen provider
3. **Tools/Actions defined** for ReAct to use

### Basic Setup

```elixir
# Set your API key
Jido.AI.Keyring.set_env_value(:openai_api_key, "sk-...")

# Define tools for ReAct to use
defmodule MyTools.Search do
  use Jido.Action,
    name: "search",
    description: "Search for information online",
    schema: [query: [type: :string, required: true]]

  def run(%{query: query}, _context) do
    # Simulate search
    results = "Results for: #{query}"
    {:ok, results}
  end
end

defmodule MyTools.Calculate do
  use Jido.Action,
    name: "calculate",
    description: "Perform mathematical calculations",
    schema: [expression: [type: :string, required: true]]

  def run(%{expression: expr}, _context) do
    # Simulate calculation
    result = "Result of #{expr}"
    {:ok, result}
  end
end

# Run ReAct loop
{:ok, result} = Jido.AI.Runner.ReAct.run(
  question: "What is the population of the capital of Japan?",
  tools: [MyTools.Search],
  max_steps: 10
)

IO.puts("Answer: #{result.answer}")
IO.puts("Steps taken: #{result.steps}")
IO.inspect(result.trajectory)
```

### Simple Example

```elixir
defmodule Examples.BasicReAct do
  @moduledoc """
  Simple example demonstrating ReAct for multi-hop questions.
  """

  alias Jido.AI.Runner.ReAct

  # Define a simple search tool
  defmodule SearchTool do
    use Jido.Action,
      name: "search",
      description: "Search for information",
      schema: [query: [type: :string, required: true]]

    def run(%{query: query}, _context) do
      # Simulate search results
      case String.downcase(query) do
        q when q =~ "eiffel tower" ->
          {:ok, "The Eiffel Tower is located in Paris, France."}

        q when q =~ "capital" and q =~ "france" ->
          {:ok, "The capital of France is Paris."}

        _ ->
          {:ok, "No specific information found."}
      end
    end
  end

  def run_example do
    IO.puts("=== ReAct Multi-Hop Reasoning Example ===\n")

    question = "What is the capital of the country where the Eiffel Tower is located?"
    IO.puts("Question: #{question}\n")

    # Run ReAct
    {:ok, result} = ReAct.run(
      question: question,
      tools: [SearchTool],
      max_steps: 5
    )

    # Display results
    IO.puts("\n=== Results ===")
    IO.puts("Answer: #{result.answer}")
    IO.puts("Steps taken: #{result.steps}")
    IO.puts("Success: #{result.success}")

    # Display trajectory
    IO.puts("\n=== Reasoning Trajectory ===")

    Enum.each(result.trajectory, fn step ->
      IO.puts("\nStep #{step.step_number}:")
      IO.puts("  Thought: #{step.thought}")

      if step.action do
        IO.puts("  Action: #{step.action}")
        IO.puts("  Input: #{inspect(step.action_input)}")
        IO.puts("  Observation: #{step.observation}")
      end

      if step.final_answer do
        IO.puts("  Final Answer: #{step.final_answer}")
      end
    end)

    {:ok, result}
  end
end

# Run the example
Examples.BasicReAct.run_example()
```

### Configuration Options

```elixir
# Basic configuration
opts = [
  question: "Your question here",
  tools: [Tool1, Tool2],
  max_steps: 10,
  temperature: 0.7
]

# Advanced configuration
advanced_opts = [
  question: "Complex question",
  tools: [SearchTool, CalculatorTool, WikipediaTool],
  max_steps: 15,
  temperature: 0.7,
  thought_template: custom_template,
  context: %{additional: "metadata"}
]

{:ok, result} = ReAct.run(advanced_opts)
```

---

## Understanding ReAct Components

### Tools and Actions

ReAct tools are standard Jido Actions with specific requirements:

#### Tool Definition

```elixir
defmodule MyTools.WebSearch do
  use Jido.Action,
    name: "web_search",                          # Tool name (used in action selection)
    description: "Search the web for information", # Description (shown to LLM)
    schema: [
      query: [
        type: :string,
        required: true,
        doc: "Search query"
      ]
    ]

  def run(%{query: query}, context) do
    # Perform search
    results = external_search_api(query)

    # Return observation
    {:ok, format_results(results)}
  end

  defp format_results(results) do
    # Format results for readability
    results
    |> Enum.take(3)
    |> Enum.map_join("\n", fn r -> "- #{r.title}: #{r.snippet}" end)
  end
end
```

#### Tool Registry

The `ToolRegistry` manages tool descriptions and execution:

```elixir
# Format tool description for LLM
ToolRegistry.format_tool_description(MyTools.WebSearch)
# => "web_search: Search the web for information"

# Get tool name
ToolRegistry.tool_name(MyTools.WebSearch)
# => "web_search"

# Execute tool
ToolRegistry.execute_tool(MyTools.WebSearch, %{query: "elixir"}, context)
# => {:ok, "search results..."}
```

### Thought Generation

Each step generates a thought using an LLM with context:

#### Thought Prompt Template

```elixir
thought_template = """
You are solving the following question using a thought-action-observation loop.

Question: {question}

You have access to the following tools:
{tools}

Previous trajectory:
{trajectory}

Based on the above, what should you do next?

Respond in this format:
Thought: <your reasoning about what to do next>
Action: <tool_name>
Action Input: <input for the tool>

Or if you have the final answer:
Thought: <reasoning about why you have the answer>
Final Answer: <the answer>
"""
```

#### Custom Thought Templates

```elixir
# Customize the thought prompt
custom_template = """
Question: {question}

Available actions: {tools}

History: {trajectory}

Think step-by-step:
1. What do I know so far?
2. What do I still need to find out?
3. Which tool will help me most?

Thought: <your reasoning>
Action: <tool_name>
Action Input: <input>
"""

ReAct.run(
  question: "...",
  tools: [...],
  thought_template: custom_template
)
```

### Action Selection

The `ActionSelector` parses LLM output to extract actions:

```elixir
# Input: LLM thought output
thought_output = """
Thought: I need to find the population of Tokyo.
Action: search
Action Input: "population of Tokyo 2024"
"""

# Parse action
ActionSelector.parse(thought_output)
# => {:action, "I need to find...", "search", "population of Tokyo 2024"}

# Or for final answer
final_output = """
Thought: I now have all the information needed.
Final Answer: Tokyo has a population of 14 million.
"""

ActionSelector.parse(final_output)
# => {:final_answer, "I now have...", "Tokyo has a population of 14 million."}
```

### Observation Processing

The `ObservationProcessor` formats action results:

```elixir
# Successful action result
action_result = {:ok, "Tokyo is the capital of Japan with a population of 14 million."}
ObservationProcessor.process(action_result)
# => {:ok, "Tokyo is the capital of Japan with a population of 14 million."}

# Error handling
error_result = {:error, "API rate limit exceeded"}
ObservationProcessor.process(error_result)
# => {:ok, "Error: API rate limit exceeded"}

# Observations are always {:ok, string} for consistency
```

### Trajectory Structure

The trajectory maintains complete history:

```elixir
trajectory = [
  %{
    step_number: 1,
    thought: "I need to find where the Eiffel Tower is located.",
    action: "search",
    action_input: "Eiffel Tower location",
    observation: "The Eiffel Tower is in Paris, France.",
    final_answer: nil
  },
  %{
    step_number: 2,
    thought: "Now I know it's in France. I need the capital.",
    action: "search",
    action_input: "capital of France",
    observation: "The capital of France is Paris.",
    final_answer: nil
  },
  %{
    step_number: 3,
    thought: "I have confirmed the answer.",
    action: nil,
    action_input: nil,
    observation: nil,
    final_answer: "Paris"
  }
]

# Access trajectory in result
result.trajectory
# => [%{step_number: 1, ...}, %{step_number: 2, ...}, ...]

# Analyze trajectory
tools_used = extract_tools_used(result.trajectory)
# => %{"search" => 2, "calculate" => 1}
```

### Result Structure

ReAct returns a comprehensive result:

```elixir
result = %{
  answer: "Paris",                      # Final answer (or nil)
  steps: 3,                             # Number of steps taken
  trajectory: [...],                    # Complete step history
  success: true,                        # Whether answer was found
  reason: :answer_found,                # Why execution stopped
  metadata: %{
    max_steps: 10,
    temperature: 0.7,
    tools_used: %{"search" => 2}        # Tool usage statistics
  }
}

# Termination reasons
:answer_found        # Successfully found final answer
:max_steps_reached   # Reached max_steps limit
:error               # Encountered unrecoverable error
```

---

## Configuration Options

### Core Parameters

```elixir
config = [
  # Question to answer (required)
  question: "What is the capital of France?",

  # Available tools (required)
  tools: [SearchTool, CalculatorTool, WikipediaTool],

  # Maximum reasoning steps
  max_steps: 10,                        # Default: 10

  # LLM configuration
  temperature: 0.7,                     # Default: 0.7 (balanced)

  # Custom prompt template
  thought_template: custom_template,    # Optional

  # Additional context
  context: %{
    user_preferences: "...",
    session_data: "..."
  }
]
```

### Max Steps Configuration

```elixir
# Quick exploration (3-5 steps)
quick_config = [max_steps: 5]

# Standard reasoning (10-15 steps)
standard_config = [max_steps: 10]

# Deep investigation (15-20 steps)
deep_config = [max_steps: 20]

# Balance cost vs completeness
# More steps = more thorough but more expensive
```

### Temperature Settings

```elixir
# Deterministic reasoning
deterministic = [temperature: 0.0]    # Most consistent

# Balanced reasoning
balanced = [temperature: 0.7]         # Default, good balance

# Exploratory reasoning
exploratory = [temperature: 1.0]      # More creative actions
```

### Custom Thought Templates

```elixir
# Minimal template
minimal_template = """
Q: {question}
Tools: {tools}
History: {trajectory}

Next step:
Thought:
Action:
Input:
"""

# Detailed template
detailed_template = """
Question: {question}

Available Tools:
{tools}

Previous Steps:
{trajectory}

Analysis:
1. What information do I have?
2. What information do I need?
3. Which tool will help most?
4. What input should I provide?

Thought: <step-by-step reasoning>
Action: <tool_name>
Action Input: <specific input>

OR

Thought: <why I can answer now>
Final Answer: <the answer>
"""

ReAct.run(
  question: "...",
  tools: [...],
  thought_template: detailed_template
)
```

### Context Configuration

```elixir
# Pass additional context to tools
context = %{
  user_id: "user_123",
  session_id: "session_456",
  preferences: %{language: "en", format: "concise"},
  metadata: %{source: "web_app"}
}

ReAct.run(
  question: "...",
  tools: [...],
  context: context
)

# Tools receive context
defmodule MyTool do
  def run(params, context) do
    user_id = context.user_id
    # Use context in tool logic
  end
end
```

---

## Tool Development

### Creating ReAct Tools

Any Jido Action can be a ReAct tool:

```elixir
defmodule MyTools.DatabaseQuery do
  use Jido.Action,
    name: "database_query",
    description: "Query the database for information",
    schema: [
      query: [type: :string, required: true, doc: "SQL query to execute"],
      limit: [type: :integer, default: 10, doc: "Maximum results"]
    ]

  def run(%{query: query, limit: limit}, context) do
    # Execute database query
    case execute_sql(query, limit) do
      {:ok, results} ->
        # Format as observation
        formatted = format_db_results(results)
        {:ok, formatted}

      {:error, reason} ->
        {:error, "Database error: #{reason}"}
    end
  end

  defp format_db_results(results) do
    """
    Found #{length(results)} results:
    #{Enum.map_join(results, "\n", &format_row/1)}
    """
  end

  defp format_row(row) do
    "- #{inspect(row)}"
  end
end
```

### Tool Best Practices

#### 1. Clear Descriptions

```elixir
# Good: Specific description
description: "Search Wikipedia for factual information about a topic"

# Bad: Vague description
description: "Search for stuff"
```

#### 2. Descriptive Parameters

```elixir
# Good: Clear parameter documentation
schema: [
  query: [
    type: :string,
    required: true,
    doc: "The search query (e.g., 'capital of France')"
  ],
  max_results: [
    type: :integer,
    default: 5,
    doc: "Maximum number of results to return (1-10)"
  ]
]

# Bad: No documentation
schema: [
  query: [type: :string, required: true],
  max: [type: :integer, default: 5]
]
```

#### 3. Formatted Observations

```elixir
# Good: Readable, structured output
def run(%{query: query}, _context) do
  results = search(query)

  formatted = """
  Search results for "#{query}":

  1. #{results[0].title}
     #{results[0].snippet}

  2. #{results[1].title}
     #{results[1].snippet}
  """

  {:ok, formatted}
end

# Bad: Raw data dump
def run(%{query: query}, _context) do
  results = search(query)
  {:ok, inspect(results)}
end
```

#### 4. Error Handling

```elixir
def run(%{query: query}, _context) do
  case external_api_call(query) do
    {:ok, data} ->
      {:ok, format_data(data)}

    {:error, :rate_limit} ->
      {:error, "Rate limit exceeded. Please try again in 60 seconds."}

    {:error, :not_found} ->
      {:ok, "No results found for query: #{query}"}

    {:error, reason} ->
      {:error, "Search failed: #{inspect(reason)}"}
  end
end
```

### Tool Categories

#### Information Retrieval Tools

```elixir
defmodule Tools.WebSearch do
  use Jido.Action, name: "web_search", description: "Search the web"
end

defmodule Tools.Wikipedia do
  use Jido.Action, name: "wikipedia", description: "Search Wikipedia"
end

defmodule Tools.DatabaseLookup do
  use Jido.Action, name: "db_lookup", description: "Query database"
end
```

#### Computation Tools

```elixir
defmodule Tools.Calculator do
  use Jido.Action, name: "calculator", description: "Perform calculations"
end

defmodule Tools.DateCalculator do
  use Jido.Action, name: "date_calc", description: "Calculate dates and durations"
end
```

#### System Interaction Tools

```elixir
defmodule Tools.FileReader do
  use Jido.Action, name: "read_file", description: "Read file contents"
end

defmodule Tools.APICall do
  use Jido.Action, name: "api_call", description: "Call external APIs"
end
```

### Tool Testing

```elixir
defmodule MyToolsTest do
  use ExUnit.Case

  alias MyTools.SearchTool

  describe "SearchTool" do
    test "returns formatted results" do
      params = %{query: "elixir programming"}
      {:ok, result} = SearchTool.run(params, %{})

      assert is_binary(result)
      assert String.contains?(result, "elixir")
    end

    test "handles empty results" do
      params = %{query: "xyzabc123nonexistent"}
      {:ok, result} = SearchTool.run(params, %{})

      assert String.contains?(result, "No results")
    end

    test "handles errors gracefully" do
      params = %{query: nil}
      {:error, reason} = SearchTool.run(params, %{})

      assert is_binary(reason)
    end
  end
end
```

---

## Integration Patterns

### Pattern 1: Research Assistant

Use ReAct for multi-source information gathering:

```elixir
defmodule MyApp.ResearchAssistant do
  alias Jido.AI.Runner.ReAct

  defmodule Tools.WebSearch do
    use Jido.Action, name: "web_search", description: "Search the web"
    def run(%{query: query}, _ctx), do: {:ok, web_search(query)}
  end

  defmodule Tools.Wikipedia do
    use Jido.Action, name: "wikipedia", description: "Search Wikipedia"
    def run(%{topic: topic}, _ctx), do: {:ok, wikipedia_search(topic)}
  end

  defmodule Tools.Scholar do
    use Jido.Action, name: "scholar", description: "Search academic papers"
    def run(%{query: query}, _ctx), do: {:ok, scholar_search(query)}
  end

  def research(question, opts \\ []) do
    tools = [Tools.WebSearch, Tools.Wikipedia, Tools.Scholar]
    max_steps = Keyword.get(opts, :max_steps, 15)

    case ReAct.run(question: question, tools: tools, max_steps: max_steps) do
      {:ok, result} ->
        %{
          answer: result.answer,
          sources: extract_sources(result.trajectory),
          confidence: calculate_confidence(result.trajectory)
        }

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_sources(trajectory) do
    trajectory
    |> Enum.filter(fn step -> step.action != nil end)
    |> Enum.map(fn step -> %{tool: step.action, query: step.action_input} end)
  end

  defp calculate_confidence(trajectory) do
    # Higher confidence with more independent sources
    unique_tools = trajectory |> Enum.map(& &1.action) |> Enum.uniq() |> length()
    min(1.0, unique_tools / 3.0)
  end
end

# Use research assistant
{:ok, research} = MyApp.ResearchAssistant.research(
  "What are the benefits of functional programming?",
  max_steps: 10
)

IO.puts("Answer: #{research.answer}")
IO.puts("Confidence: #{research.confidence}")
IO.puts("Sources: #{length(research.sources)}")
```

### Pattern 2: Interactive Troubleshooting

Use ReAct for diagnostic tasks:

```elixir
defmodule MyApp.Troubleshooter do
  alias Jido.AI.Runner.ReAct

  defmodule Tools.CheckLogs do
    use Jido.Action, name: "check_logs", description: "Check system logs"
    def run(%{service: service}, _ctx), do: {:ok, read_logs(service)}
  end

  defmodule Tools.CheckMetrics do
    use Jido.Action, name: "check_metrics", description: "Check system metrics"
    def run(%{metric: metric}, _ctx), do: {:ok, get_metrics(metric)}
  end

  defmodule Tools.TestEndpoint do
    use Jido.Action, name: "test_endpoint", description: "Test API endpoint"
    def run(%{url: url}, _ctx), do: {:ok, test_api(url)}
  end

  def diagnose(problem, opts \\ []) do
    tools = [Tools.CheckLogs, Tools.CheckMetrics, Tools.TestEndpoint]

    case ReAct.run(question: problem, tools: tools, max_steps: 20) do
      {:ok, result} ->
        %{
          diagnosis: result.answer,
          investigation_path: format_trajectory(result.trajectory),
          steps_taken: result.steps
        }

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_trajectory(trajectory) do
    Enum.map(trajectory, fn step ->
      %{
        step: step.step_number,
        action: step.action,
        finding: step.observation
      }
    end)
  end
end

# Diagnose issue
{:ok, diagnosis} = MyApp.Troubleshooter.diagnose(
  "API endpoint is returning 500 errors"
)

IO.puts("Diagnosis: #{diagnosis.diagnosis}")
IO.puts("Investigation steps: #{diagnosis.steps_taken}")
```

### Pattern 3: Data Analysis Pipeline

Use ReAct for iterative data exploration:

```elixir
defmodule MyApp.DataAnalyst do
  alias Jido.AI.Runner.ReAct

  defmodule Tools.QueryDatabase do
    use Jido.Action, name: "query_db", description: "Query database"
    def run(%{sql: sql}, _ctx), do: {:ok, execute_query(sql)}
  end

  defmodule Tools.CalculateStats do
    use Jido.Action, name: "calculate_stats", description: "Calculate statistics"
    def run(%{data: data}, _ctx), do: {:ok, compute_stats(data)}
  end

  defmodule Tools.VisualizeData do
    use Jido.Action, name: "visualize", description: "Create visualization"
    def run(%{data: data, type: type}, _ctx), do: {:ok, create_chart(data, type)}
  end

  def analyze(question, dataset, opts \\ []) do
    tools = [Tools.QueryDatabase, Tools.CalculateStats, Tools.VisualizeData]

    context = %{dataset: dataset}

    case ReAct.run(question: question, tools: tools, context: context, max_steps: 12) do
      {:ok, result} ->
        %{
          answer: result.answer,
          analysis_steps: result.trajectory,
          queries_executed: count_queries(result.trajectory),
          visualizations: extract_visualizations(result.trajectory)
        }

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp count_queries(trajectory) do
    Enum.count(trajectory, fn step -> step.action == "query_db" end)
  end

  defp extract_visualizations(trajectory) do
    trajectory
    |> Enum.filter(fn step -> step.action == "visualize" end)
    |> Enum.map(fn step -> step.action_input end)
  end
end

# Analyze data
{:ok, analysis} = MyApp.DataAnalyst.analyze(
  "What are the top 3 products by revenue in Q4?",
  "sales_data"
)

IO.inspect(analysis)
```

### Pattern 4: Code Generation with Testing

Use ReAct for iterative code development:

```elixir
defmodule MyApp.CodeGenerator do
  alias Jido.AI.Runner.ReAct

  defmodule Tools.GenerateCode do
    use Jido.Action, name: "generate_code", description: "Generate code"
    def run(%{spec: spec}, _ctx), do: {:ok, generate(spec)}
  end

  defmodule Tools.RunTests do
    use Jido.Action, name: "run_tests", description: "Run tests on code"
    def run(%{code: code}, _ctx), do: {:ok, test_code(code)}
  end

  defmodule Tools.FixError do
    use Jido.Action, name: "fix_error", description: "Fix code error"
    def run(%{code: code, error: error}, _ctx), do: {:ok, fix(code, error)}
  end

  def generate(specification, opts \\ []) do
    tools = [Tools.GenerateCode, Tools.RunTests, Tools.FixError]

    question = """
    Generate code that meets this specification:
    #{specification}

    The code must pass all tests.
    """

    case ReAct.run(question: question, tools: tools, max_steps: 15) do
      {:ok, result} ->
        %{
          code: extract_code(result.trajectory),
          iterations: result.steps,
          test_results: extract_tests(result.trajectory)
        }

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_code(trajectory) do
    # Extract final code from trajectory
    trajectory
    |> Enum.reverse()
    |> Enum.find_value(fn step ->
      if step.action in ["generate_code", "fix_error"] do
        step.observation
      end
    end)
  end

  defp extract_tests(trajectory) do
    trajectory
    |> Enum.filter(fn step -> step.action == "run_tests" end)
    |> Enum.map(fn step -> step.observation end)
  end
end

# Generate code
{:ok, result} = MyApp.CodeGenerator.generate("""
  Create a function that calculates the factorial of a number.
  Handle edge cases for 0 and negative numbers.
""")

IO.puts("Generated code:")
IO.puts(result.code)
IO.puts("\nIterations: #{result.iterations}")
```

---

## Best Practices

### 1. Design Clear Tool Descriptions

```elixir
# Good: Clear, specific description
defmodule GoodTool do
  use Jido.Action,
    name: "search_wikipedia",
    description: "Search Wikipedia articles for factual information about a specific topic"
end

# Bad: Vague description
defmodule BadTool do
  use Jido.Action,
    name: "search",
    description: "Search stuff"
end
```

### 2. Set Appropriate Max Steps

```elixir
# Simple questions
simple_config = [max_steps: 5]    # Quick lookup

# Standard questions
standard_config = [max_steps: 10]  # Default, good balance

# Complex investigations
complex_config = [max_steps: 20]   # Deep research

# Match complexity to question type
def choose_max_steps(question) do
  cond do
    single_hop_question?(question) -> 5
    multi_hop_question?(question) -> 10
    research_question?(question) -> 20
  end
end
```

### 3. Format Observations Clearly

```elixir
# Good: Structured, readable
def run(%{query: query}, _ctx) do
  results = search(query)

  observation = """
  Found #{length(results)} results for "#{query}":

  Top result:
  Title: #{results[0].title}
  Summary: #{results[0].summary}
  Relevance: High
  """

  {:ok, observation}
end

# Bad: Raw dump
def run(%{query: query}, _ctx) do
  results = search(query)
  {:ok, inspect(results)}
end
```

### 4. Handle Errors Gracefully

```elixir
def run(params, _ctx) do
  case external_call(params) do
    {:ok, data} ->
      {:ok, format_data(data)}

    {:error, :timeout} ->
      # Return error as observation (not {:error, ...})
      {:ok, "Request timed out after 30 seconds. Try a simpler query."}

    {:error, :not_found} ->
      {:ok, "No results found. Try different search terms."}

    {:error, reason} ->
      {:ok, "Error occurred: #{inspect(reason)}"}
  end
end
```

### 5. Monitor Trajectory Length

```elixir
# Track steps and stop if inefficient
def research_with_monitoring(question) do
  {:ok, result} = ReAct.run(question: question, tools: [...], max_steps: 20)

  if result.steps >= 15 do
    Logger.warning("Question required #{result.steps} steps: #{question}")
  end

  if result.reason == :max_steps_reached do
    Logger.error("Max steps reached without answer: #{question}")
  end

  {:ok, result}
end
```

### 6. Use Appropriate Temperature

```elixir
# Factual research → Low temperature
factual_config = [temperature: 0.3]

# Balanced exploration → Medium temperature
balanced_config = [temperature: 0.7]  # Default

# Creative problem solving → Higher temperature
creative_config = [temperature: 0.9]
```

### 7. Validate Tool Outputs

```elixir
defmodule ToolWithValidation do
  use Jido.Action, name: "validated_tool", description: "..."

  def run(params, ctx) do
    case perform_action(params) do
      {:ok, result} ->
        # Validate result before returning
        case validate_result(result) do
          :ok -> {:ok, format_result(result)}
          {:error, reason} -> {:ok, "Invalid result: #{reason}"}
        end

      {:error, reason} ->
        {:ok, "Action failed: #{reason}"}
    end
  end

  defp validate_result(result) do
    cond do
      result == nil -> {:error, "null result"}
      result == "" -> {:error, "empty result"}
      true -> :ok
    end
  end
end
```

### 8. Test Tools Independently

```elixir
defmodule MyToolsTest do
  use ExUnit.Case

  test "tool returns formatted observation" do
    params = %{query: "test"}
    {:ok, observation} = MyTool.run(params, %{})

    assert is_binary(observation)
    refute observation == ""
  end

  test "tool handles errors" do
    params = %{query: "invalid"}
    result = MyTool.run(params, %{})

    # Errors should be returned as observations
    assert match?({:ok, "Error" <> _}, result)
  end
end
```

### 9. Log Trajectory for Debugging

```elixir
def research_with_logging(question) do
  {:ok, result} = ReAct.run(question: question, tools: [...])

  # Log trajectory for analysis
  Logger.info("""
  ReAct completed:
  Question: #{question}
  Answer: #{result.answer}
  Steps: #{result.steps}
  Success: #{result.success}
  """)

  Enum.each(result.trajectory, fn step ->
    Logger.debug("""
    Step #{step.step_number}:
      Thought: #{step.thought}
      Action: #{step.action}
      Observation: #{String.slice(step.observation || "", 0, 100)}...
    """)
  end)

  {:ok, result}
end
```

### 10. Optimize Tool Selection

```elixir
# Provide only relevant tools
def choose_tools(question_type) do
  case question_type do
    :factual ->
      [WikipediaTool, WebSearchTool]

    :mathematical ->
      [CalculatorTool, WolframAlphaTool]

    :data_analysis ->
      [DatabaseTool, StatisticsTool, VisualizationTool]

    :mixed ->
      # Provide all tools but with clear descriptions
      [WebSearchTool, WikipediaTool, CalculatorTool, DatabaseTool]
  end
end

# Use in ReAct
tools = choose_tools(classify_question(question))
ReAct.run(question: question, tools: tools)
```

---

## Troubleshooting

### Common Issues

#### Max Steps Reached Without Answer

**Problem**: `{:ok, %{success: false, reason: :max_steps_reached}}`

**Solutions**:

```elixir
# 1. Increase max_steps
config = [max_steps: 20]  # Was 10

# 2. Simplify the question
# Break complex questions into sub-questions

# 3. Add more specific tools
# Provide tools that directly address the question

# 4. Improve thought template
# Guide the model toward more efficient reasoning
```

#### Tool Not Found Errors

**Problem**: Observation contains "Tool not found: tool_name"

**Solutions**:

```elixir
# 1. Check tool name matches action name
defmodule MyTool do
  use Jido.Action,
    name: "my_tool",  # Name LLM will use
    description: "..."
end

# 2. Verify tool is in tools list
tools = [MyTool, OtherTool]  # Include all needed tools

# 3. Check tool description clarity
# LLM may be confused about which tool to use
```

#### Poor Tool Selection

**Problem**: LLM repeatedly selects wrong tools

**Solutions**:

```elixir
# 1. Improve tool descriptions
defmodule BetterTool do
  use Jido.Action,
    name: "wikipedia_search",
    description: "Search Wikipedia for factual, encyclopedic information about people, places, events, and concepts"
end

# 2. Use more specific tool names
# "web_search" vs "search" - be explicit

# 3. Reduce tool count
# Too many tools confuses the model
# Provide only relevant tools for the task

# 4. Adjust temperature
config = [temperature: 0.5]  # More deterministic
```

#### Trajectory Shows Loops

**Problem**: Repeating same actions without progress

**Solutions**:

```elixir
# 1. Improve thought template to discourage repetition
template = """
...
Previous steps: {trajectory}

IMPORTANT: Do not repeat actions you've already tried.
Consider what new information you need.
...
"""

# 2. Add observation about repetition
# Tools can detect and warn about repeated queries

# 3. Reduce max_steps
# Force more focused reasoning
config = [max_steps: 8]
```

#### Long Latency

**Problem**: Takes too long to complete

**Solutions**:

```elixir
# 1. Reduce max_steps
config = [max_steps: 5]

# 2. Optimize tool execution
# Cache results, use faster APIs

# 3. Use faster LLM
# GPT-3.5-turbo instead of GPT-4

# 4. Simplify thought template
# Shorter prompts = faster responses

# 5. Parallel tool execution (future enhancement)
# Execute multiple tools in parallel when possible
```

#### High Costs

**Problem**: ReAct is too expensive

**Solutions**:

```elixir
# 1. Reduce max_steps
config = [max_steps: 5]  # Fewer LLM calls

# 2. Use cheaper model
# GPT-3.5-turbo instead of GPT-4

# 3. Cache tool results
# Avoid redundant API calls

# 4. Pre-filter questions
# Use ReAct only for complex multi-hop questions

# 5. Monitor and optimize
:telemetry.execute(
  [:react, :completion],
  %{steps: result.steps, cost: estimate_cost(result)}
)
```

### Debugging Tips

1. **Inspect Trajectory**

```elixir
{:ok, result} = ReAct.run(...)

IO.puts("\n=== Trajectory ===")
Enum.each(result.trajectory, fn step ->
  IO.puts("\nStep #{step.step_number}:")
  IO.puts("Thought: #{step.thought}")
  if step.action, do: IO.puts("Action: #{step.action}(#{inspect(step.action_input)})")
  if step.observation, do: IO.puts("Observation: #{step.observation}")
end)
```

2. **Test Tools Independently**

```elixir
# Test each tool outside ReAct
{:ok, result} = MyTool.run(%{query: "test"}, %{})
IO.inspect(result)
```

3. **Use Custom Thought Function (Testing)**

```elixir
# Override thought generation for testing
thought_fn = fn state, _opts ->
  # Return predetermined thoughts
  predetermined_thoughts[state.step_number]
end

ReAct.run(
  question: "...",
  tools: [...],
  thought_fn: thought_fn
)
```

4. **Enable Debug Logging**

```elixir
# In config/dev.exs
config :logger, level: :debug

# Or in code
require Logger
Logger.configure(level: :debug)
```

### Getting Help

If issues persist:

1. Check [ReAct examples directory](../examples/react/) for working code
2. Review [API documentation](https://hexdocs.pm/jido_ai)
3. Search [GitHub issues](https://github.com/agentjido/jido_ai/issues)
4. Ask in [Elixir Forum](https://elixirforum.com/)

---

## Conclusion

ReAct (Reasoning + Acting) provides a powerful framework for tasks requiring iterative information gathering and tool use. By interleaving reasoning with action execution, ReAct achieves significant accuracy improvements on multi-hop reasoning tasks while maintaining transparency through trajectory tracking.

### Key Takeaways

- **Significant Gains**: +27.4% on multi-hop QA with 10-30× cost increase
- **Tool Integration**: Seamlessly uses Jido Actions as ReAct tools
- **Iterative Reasoning**: Thought → Action → Observation cycle enables dynamic adaptation
- **Transparency**: Complete trajectory provides explainability and debugging
- **Flexibility**: Works with any tools, customizable thought templates

### When to Use ReAct

**Use ReAct for:**
- Multi-hop reasoning requiring multiple information sources
- Iterative investigation where next steps depend on observations
- Tool-based problem solving (API orchestration, data analysis)
- Research tasks requiring cross-referencing
- Tasks where reasoning transparency is valuable

**Skip ReAct for:**
- Single-source direct answers
- Tasks not requiring tools
- Latency-critical operations (10-30× overhead)
- Simple lookups or pattern matching
- Budget-constrained scenarios

### Next Steps

1. **Define Tools**: Create Jido Actions for your use case
2. **Test Tools**: Verify tools work independently
3. **Start Simple**: Begin with 3-5 steps, simple questions
4. **Analyze Trajectories**: Review reasoning paths for patterns
5. **Optimize**: Adjust max_steps, temperature, tool descriptions

### Further Reading

- [Chain-of-Thought Guide](./chain_of_thought.md) - Pure reasoning without actions
- [Tree-of-Thoughts Guide](./tree_of_thoughts.md) - Multi-path exploration
- [Self-Consistency Guide](./self_consistency.md) - Multiple reasoning paths with voting
- [Actions Guide](./actions.md) - Creating Jido Actions
- [Prompt Engineering Guide](./prompt.md) - Prompt design best practices

### Examples

Explore complete working examples:

- [ReAct Examples Directory](../examples/react/) - Complete working implementations:
  - `research_assistant.ex` - Basic ReAct with tool integration and reasoning
  - `task_solver.ex` - Advanced ReAct with multi-step problem solving and trajectory tracking
  - `README.md` - Comprehensive documentation and usage patterns
- `lib/jido_ai/runner/react.ex` - Full ReAct implementation
- `test/jido_ai/runner/react_test.exs` - Comprehensive test suite

By mastering ReAct, you can build powerful agents that combine reasoning with real-world actions, achieving state-of-the-art performance on complex information gathering and problem-solving tasks.
