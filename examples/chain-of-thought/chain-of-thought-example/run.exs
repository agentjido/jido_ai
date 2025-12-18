#!/usr/bin/env elixir

# Comprehensive Chain-of-Thought Example
# Run this example with: mix run run.exs

IO.puts("\n=== Comprehensive Chain-of-Thought Example ===\n")

# Example 1: Solve with reasoning
IO.puts("Example 1: Problem Solving with Reasoning")
{:ok, result} = Examples.ChainOfThoughtExample.solve_with_reasoning(
  problem: "If a train travels 120 km in 2 hours, how far will it travel in 5 hours at the same speed?",
  use_cot: true
)
IO.puts("Answer: #{result.answer}")
IO.puts("Confidence: #{result.confidence}%\n")

# Example 2: Compare with and without CoT
IO.puts("\nExample 2: Comparing with and without CoT")
{:ok, comparison} = Examples.ChainOfThoughtExample.compare_with_without_cot(
  problem: "What is 15% of 240?"
)
IO.puts("With CoT answer: #{comparison.with_cot.answer}")
IO.puts("Without CoT answer: #{comparison.without_cot.answer}\n")
