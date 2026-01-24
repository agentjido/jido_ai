#!/usr/bin/env env elixir

# Monte Carlo Tree Search Example
#
# Run this example with:
#   mix run examples/accuracy/search/mcts.exs
#
# This example demonstrates MCTS for systematic exploration
# of reasoning paths using intelligent selection.

Application.ensure_all_started(:jido_ai)

alias Jido.AI.Accuracy.Search.MCTS

IO.puts("\n=== Monte Carlo Tree Search (MCTS) Example ===\n")

# Example 1: Basic MCTS search
IO.puts("Example 1: Basic MCTS for math problem")
IO.puts("--------------------------------------")

query = "What is the square root of 144?"

IO.puts("Query: #{query}")
IO.puts("Running 50 MCTS simulations...\n")

# Note: This requires proper generator and verifier modules
# For demonstration, we show the structure:

IO.puts("MCTS performs 4 phases per simulation:")
IO.puts("1. Selection: Use UCB1 to find promising node")
IO.puts("2. Expansion: Add new child to tree")
IO.puts("3. Simulation: Rollout and score with verifier")
IO.puts("4. Backpropagation: Update values up the tree")
IO.puts("\nAfter all simulations, return best path.")

# Example 2: MCTS with different exploration constants
IO.puts("\n\nExample 2: Exploration constant impact")
IO.puts("---------------------------------------")

IO.puts("Exploration constant (C) controls exploration vs exploitation:\n")

IO.puts("C = 0.5 (Exploit-focused):")
IO.puts("  → Focuses on known good paths")
IO.puts("  → Good for well-understood problems")
IO.puts("  → Risk: local optima")

IO.puts("\nC = 1.414 (Balanced, √2):")
IO.puts("  → Good balance of exploration and exploitation")
IO.puts("  → Default and recommended for most problems")

IO.puts("\nC = 2.0+ (Explore-focused):")
IO.puts("  → Explores more diverse paths")
IO.puts("  → Good for uncertain problems")
IO.puts("  → Risk: slower convergence")

# Example 3: MCTS configuration
IO.puts("\n\nExample 3: MCTS configuration options")
IO.puts("-------------------------------------")

IO.puts("Key parameters:")
IO.puts("\n:simulations")
IO.puts("  Number of MCTS iterations (default: 100)")
IO.puts("  Higher → More thorough search, slower")
IO.puts("  Typical range: 50-200")

IO.puts("\n:exploration_constant")
IO.puts("  UCB1 exploration weight (default: 1.414)")
IO.puts("  Higher → More exploration")
IO.puts("  Typical range: 0.5-2.0")

IO.puts("\n:max_depth")
IO.puts("  Maximum reasoning depth (default: 10)")
IO.puts("  Limits tree size for very deep problems")
IO.puts("  Typical range: 5-20")

# Example 4: Usage pattern
IO.puts("\n\nExample 4: Usage pattern")
IO.puts("----------------------")

code_example = """
{:ok, best} = MCTS.search(
  query,
  generator: LLMGenerator,
  verifier: LLMOutcomeVerifier,
  simulations: 100,
  exploration_constant: 1.414
)
"""

IO.puts("Complete example:")
IO.puts(code_example)

# Summary
IO.puts("\n=== Summary ===")
IO.puts("-----------")
IO.puts("MCTS is best for:")
IO.puts("  • Complex reasoning with many branches")
IO.puts("  • Game-like scenarios with clear states")
IO.puts("  • When evaluation is expensive")
IO.puts("  • Problems requiring systematic exploration")
IO.puts("\nAlternatives:")
IO.puts("  • Beam Search - For memory-constrained environments")
IO.puts("  • Self-Consistency - For simpler problems")
IO.puts("  • Diverse Decoding - For creative exploration")
IO.puts("\n")
