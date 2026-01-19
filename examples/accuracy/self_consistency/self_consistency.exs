#!/usr/bin/env env elixir

# Self-Consistency Example
#
# Run this example with:
#   mix run examples/accuracy/self_consistency/self_consistency.exs
#
# This example demonstrates self-consistency for improving LLM accuracy
# by generating multiple candidates and selecting the most consistent answer.

# Ensure we're running inside the application
Application.ensure_all_started(:jido_ai)

alias Jido.AI.Accuracy.SelfConsistency

IO.puts("\n=== Self-Consistency Example ===\n")

# Example 1: Basic self-consistency
IO.puts("Example 1: Basic self-consistency")
IO.puts("----------------------------------")

query = "What is 15 * 23?"

IO.puts("Query: #{query}")
IO.puts("Generating 5 candidates and selecting by majority vote...\n")

{:ok, best, metadata} = SelfConsistency.run(
  query,
  num_candidates: 5,
  aggregator: :majority_vote
)

IO.puts("Best Answer: #{best.content}")
IO.puts("Confidence: #{metadata.confidence}")
IO.puts("Num Candidates: #{metadata.num_candidates}")

# Example 2: Self-consistency with reasoning
IO.puts("\n\nExample 2: Self-consistency with step-by-step reasoning")
IO.puts("----------------------------------------------------------")

reasoning_query = "Solve step by step: A rectangle has perimeter 26 and area 40. What are its dimensions?"

IO.puts("Query: #{reasoning_query}")
IO.puts("Generating candidates with Chain-of-Thought prompting...\n")

{:ok, best_with_reasoning, _metadata} = SelfConsistency.run_with_reasoning(
  reasoning_query,
  num_candidates: 3,
  aggregator: :majority_vote
)

IO.puts("Best Answer: #{best_with_reasoning.content}")
if best_with_reasoning.reasoning do
  IO.puts("Reasoning: #{best_with_reasoning.reasoning}")
end

# Example 3: Self-consistency with different aggregators
IO.puts("\n\nExample 3: Comparing aggregation methods")
IO.puts("----------------------------------------")

math_query = "What is 247 * 13?"

IO.puts("Query: #{math_query}")
IO.puts("\n1. Majority Vote:")
{:ok, majority_best, m_meta} = SelfConsistency.run(
  math_query,
  num_candidates: 5,
  aggregator: :majority_vote
)
IO.puts("   Result: #{majority_best.content}")
IO.puts("   Confidence: #{m_meta.confidence}")

IO.puts("\n2. Best of N (with temperature sampling):")
{:ok, best_n_best, bn_meta} = SelfConsistency.run(
  math_query,
  num_candidates: 5,
  aggregator: :best_of_n,
  temperature_range: {0.5, 1.0}
)
IO.puts("   Result: #{best_n_best.content}")
IO.puts("   Temperature range: {0.5, 1.0}")

# Example 4: Multiple choice question
IO.puts("\n\nExample 4: Multiple choice with self-consistency")
IO.puts("------------------------------------------------")

mcq = """
Which sorting algorithm has the best average-case time complexity?

A) Bubble Sort - O(n²)
B) Quick Sort - O(n log n)
C) Merge Sort - O(n log n)
D) Insertion Sort - O(n²)
"""

IO.puts("Query: #{mcq}")
IO.puts("Selecting most consistent answer...\n")

{:ok, mc_best, mc_meta} = SelfConsistency.run(
  mcq,
  num_candidates: 7,
  aggregator: :majority_vote,
  temperature_range: {0.0, 0.3}
)

IO.puts("Best Answer: #{mc_best.content}")
IO.puts("Confidence: #{mc_meta.confidence}")

# Summary
IO.puts("\n\n=== Summary ===")
IO.puts("-----------")
IO.puts("Self-consistency improves accuracy by:")
IO.puts("1. Generating multiple candidate responses")
IO.puts("2. Selecting the most consistent answer")
IO.puts("3. Reducing errors from LLM randomness")
IO.puts("\nKey parameters:")
IO.puts("  - num_candidates: How many responses to generate")
IO.puts("  - aggregator: How to select the best answer")
IO.puts("  - temperature_range: Diversity of candidates")
IO.puts("\n")
