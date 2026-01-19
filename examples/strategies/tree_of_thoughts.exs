#!/usr/bin/env env elixir

# Tree-of-Thoughts Strategy Example
#
# Run this example with:
#   mix run examples/strategies/tree_of_thoughts.exs
#
# This example demonstrates the Tree-of-Thoughts strategy for
# branching exploration of reasoning paths.

Application.ensure_all_started(:jido_ai)

IO.puts("\n=== Tree-of-Thoughts Strategy Example ===\n")

# Example 1: Understanding Tree-of-Thoughts
IO.puts("Example 1: How Tree-of-Thoughts works")
IO.puts("-------------------------------------")

IO.puts("""
Tree-of-Thoughts explores multiple reasoning paths in parallel:

Question: "What's the best way to learn programming?"

                  Root
                   |
     ┌──────────────┼──────────────┐
     │              │              │
  Thought A      Thought B      Thought C
 "Take a      "Watch        "Build projects"
  course"     tutorials"
     │              │              │
  ┌──┴──┐      ┌────┴────┐    ┌───┴───┐
  A1   A2      B1        B2    C1     C2

Then evaluate all thoughts and select the best path!
""")

# Example 2: ToT agent definition
IO.puts("\n\nExample 2: Defining a Tree-of-Thoughts agent")
IO.puts("-------------------------------------------")

tot_agent = """
defmodule MyApp.PlanningAgent do
  use Jido.Agent,
    name: "planning_agent",
    strategy: {
      Jido.AI.Strategies.TreeOfThoughts,
      branching_factor: 3,    # Thoughts per step
      max_depth: 4,            # Maximum reasoning depth
      traversal_strategy: :best_first
    },
    model: :capable
end
"""

IO.puts(tot_agent)

# Example 3: Traversal strategies
IO.puts("\n\nExample 3: Traversal strategies")
IO.puts("----------------------------")

IO.puts("""
Traversal strategies determine how to explore the tree:

1. BFS (Breadth-First Search)
   Explores all thoughts at current depth before going deeper

   Best for: When thoroughness matters more than depth
   Use: "Thoroughly explore all options"

2. DFS (Depth-First Search)
   Explores each branch completely before backtracking

   Best for: When depth is more important than breadth
   Use: "Follow each thought to its conclusion"

3. Best-First (Recommended)
   Always explores the highest-scoring thought first

   Best for: Most problems (balanced approach)
   Use: "Find the best path quickly"
""")

# Example 4: Configuration parameters
IO.puts("\n\nExample 4: Configuration parameters")
IO.puts("---------------------------------")

IO.puts("""
Key parameters for Tree-of-Thoughts:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| :branching_factor | integer() | 3 | Thoughts generated per step |
| :max_depth | integer() | 4 | Maximum reasoning depth |
| :traversal_strategy | atom() | :best_first | How to traverse thoughts |
| :evaluation_method | atom() | :auto | How to score thoughts |
""")

# Example 5: When to use Tree-of-Thoughts
IO.puts("\n\nExample 5: When Tree-of-Thoughts excels")
IO.puts("--------------------------------------")

IO.puts("""
Excellent for:
  ✓ Problems with multiple valid approaches
  ✓ Planning tasks (trip planning, project planning)
  ✓ Creative tasks (brainstorming, idea generation)
  ✓ Puzzles with branching solutions
  ✓ When you want to explore alternatives

Less effective for:
  ✗ Simple factual questions (overkill)
  ✗ Questions with single correct answer
  ✗ Very constrained problems
""")

# Example 6: Example problems
IO.puts("\n\nExample 6: Example problems for ToT")
IO.puts("--------------------------------")

IO.puts("""
Planning Problem:
  "Plan a 3-day trip to Tokyo with a $1000 budget"

  Tree explores:
  - Accommodation options (hotel, hostel, Airbnb)
  - Food strategies (restaurants, convenience stores, mix)
  - Activities (temples, shopping, day trips)
  - Transportation (train, bus, walking)

Creative Problem:
  "Brainstorm innovative features for a productivity app"

  Tree explores:
  - Time management features
  - Collaboration features
  - AI-powered features
  - Integration features

Puzzle Problem:
  "Place 8 queens on a chessboard without attacking each other"

  Tree explores:
  - Different starting positions
  - Different placement strategies
  - Backtracking when conflicts found
""")

# Example 7: CoT vs ToT comparison
IO.puts("\n\nExample 7: Chain-of-Thought vs Tree-of-Thoughts")
IO.puts("-----------------------------------------------")

comparison = """
┌─────────────────────┬──────────────────┬──────────────────┐
│ Feature             │ Chain-of-Thought │ Tree-of-Thoughts │
├─────────────────────┼──────────────────┼──────────────────┤
│ Exploration         │ Single path      │ Multiple paths   │
│ Alternatives        │ No               │ Yes              │
│ Compute cost        │ Low              │ High             │
│ Best for            │ Math, logic      │ Planning, creative│
│ Depth vs breadth    │ Deep only        │ Both             │
│ Branching factor    │ 1                │ 3+               │
└─────────────────────┴──────────────────┴──────────────────┘
"""

IO.puts(comparison)

# Summary
IO.puts("\n=== Summary ===")
IO.puts("-----------")
IO.puts("Tree-of-Thoughts provides:")
IO.puts("  • Exploration of multiple reasoning paths")
IO.puts("  • Better answers for complex problems")
IO.puts("  • Creative solution discovery")
IO.puts("  • Configurable exploration strategies")
IO.puts("\nBest practices:")
IO.puts("  1. Use best_first traversal for most problems")
IO.puts("  2. Start with branching_factor=3, max_depth=4")
IO.puts("  3. Increase depth for harder problems")
IO.puts("  4. Consider compute cost (branching_factor × depth = total thoughts)")
IO.puts("\n")
