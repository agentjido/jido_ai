#!/usr/bin/env env elixir

# Adaptive Strategy Example
#
# Run this example with:
#   mix run examples/strategies/adaptive_strategy.exs
#
# This example demonstrates the Adaptive strategy which
# automatically selects the best reasoning strategy.

Application.ensure_all_started(:jido_ai)

IO.puts("\n=== Adaptive Strategy Example ===\n")

# Example 1: How Adaptive strategy works
IO.puts("Example 1: Adaptive strategy logic")
IO.puts("---------------------------------")

IO.puts("""
Adaptive analyzes the query and automatically selects the best strategy:

Query → Keyword Analysis → Strategy Selection → Execute

Keyword Detection:
  "use", "call", "execute", "tool"  → ReAct
  "combine", "synthesize", "merge"  → Graph-of-Thoughts
  "explore", "alternatives", "options"  → Tree-of-Thoughts
  "refine", "improve", "iterate"  → TRM
  (no keywords)  → Chain-of-Thought
""")

# Example 2: Adaptive agent definition
IO.puts("\n\nExample 2: Defining an Adaptive agent")
IO.puts("------------------------------------")

adaptive_agent = """
defmodule MyApp.SmartAgent do
  use Jido.Agent,
    name: "smart_agent",
    strategy: {
      Jido.AI.Strategies.Adaptive,
      strategies: [:react, :cot, :tot, :got],
      model: :fast,
      tools: [
        MyApp.Actions.Calculator,
        MyApp.Actions.Search
      ]
    }
end
"""

IO.puts(adaptive_agent)

# Example 3: Strategy selection examples
IO.puts("\n\nExample 3: Strategy selection in action")
IO.puts("-------------------------------------")

IO.puts("""
Query: "Use the calculator to find 15 * 23"
  → Keywords: "use", "calculator"
  → Selected: ReAct (needs tools)

Query: "Synthesize different perspectives on remote work"
  → Keywords: "synthesize", "perspectives"
  → Selected: Graph-of-Thoughts (multi-perspective)

Query: "Explore options for Tokyo trip planning"
  → Keywords: "explore", "options"
  → Selected: Tree-of-Thoughts (branching)

Query: "What is 15 * 23?"
  → Keywords: none
  → Selected: Chain-of-Thought (direct reasoning)
""")

# Example 4: Manual override
IO.puts("\n\nExample 4: Manual override")
IO.puts("-------------------------")

IO.puts("""
You can manually specify the strategy:

{:ok, agent} = MyApp.SmartAgent.ask(pid, query,
  strategy: :react  # Force ReAct
)

{:ok, agent} = MyApp.SmartAgent.ask(pid, query,
  strategy: :tot  # Force Tree-of-Thoughts
)
""")

# Example 5: Adding custom strategy detection
IO.puts("\n\nExample 5: Custom keyword mappings")
IO.puts("----------------------------------")

IO.puts("""
You can extend keyword detection for custom behavior:

defmodule MyApp.CustomAdaptive do
  def detect_strategy(query, available_strategies) do
    cond do
      String.contains?(query, ["code", "program"]) ->
        {:ok, :cot, "Use Chain-of-Thought for step-by-step coding"}

      String.contains?(query, ["design", "architecture"]) ->
        {:ok, :got, "Use Graph-of-Thoughts for synthesis"

      true ->
        # Fall back to default detection
        Jido.AI.Strategies.Adaptive.detect_strategy(query, available_strategies)
    end
  end
end
""")

# Example 6: Adaptive vs Fixed strategies
IO.puts("\n\nExample 6: Adaptive vs Fixed strategies")
IO.puts("--------------------------------------")

comparison = """
┌─────────────────────┬──────────────────┬──────────────────┐
│ Aspect              │ Fixed Strategy   │ Adaptive         │
├─────────────────────┼──────────────────┼──────────────────┤
│ Strategy selection  │ Manual           │ Automatic        │
│ Best for            │ Known task types │ Variable tasks   │
│ Overhead            │ None             │ Minimal          │
│ Flexibility         │ Low              │ High             │
│ Predictability      │ High             │ Medium           │
│ Learning curve      │ Steeper          │ Easier           │
└─────────────────────┴──────────────────┴──────────────────┘
"""

IO.puts(comparison)

# Summary
IO.puts("\n=== Summary ===")
IO.puts("-----------")
IO.puts("Adaptive strategy provides:")
IO.puts("  • Automatic strategy selection")
IO.puts("  • Reduced decision-making burden")
IO.puts("  • Good for variable workloads")
IO.puts("  • Easy to use for general-purpose agents")
IO.puts("\nBest practices:")
IO.puts("  1. Start with Adaptive for unknown workloads")
IO.puts("  2. Override manually when you know the best strategy")
IO.puts("  3. Provide clear tool descriptions for better ReAct selection")
IO.puts("  4. Monitor which strategies are selected for optimization")
IO.puts("\n")
