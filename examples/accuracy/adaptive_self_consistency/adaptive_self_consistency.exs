#!/usr/bin/env env elixir

# Adaptive Self-Consistency Example
#
# Run this example with:
#   mix run examples/accuracy/adaptive_self_consistency/adaptive_self_consistency.exs
#
# This example demonstrates adaptive self-consistency which dynamically
# adjusts the number of candidates based on query difficulty and stops
# early when consensus is reached.

Application.ensure_all_started(:jido_ai)

alias Jido.AI.Accuracy.AdaptiveSelfConsistency

IO.puts("\n=== Adaptive Self-Consistency Example ===\n")

# Example 1: Easy question with early stopping
IO.puts("Example 1: Easy question (should stop early)")
IO.puts("-------------------------------------------")

easy_query = "What is 2 + 2?"

IO.puts("Query: #{easy_query}")
IO.puts("Config: min=3, max=20, threshold=0.8\n")

adapter = AdaptiveSelfConsistency.new!(%{
  min_candidates: 3,
  max_candidates: 20,
  batch_size: 3,
  early_stop_threshold: 0.8
})

{:ok, result, metadata} = AdaptiveSelfConsistency.run(
  adapter,
  easy_query,
  generator: fn prompt ->
    # Mock generator for demonstration
    # In production, use actual LLM calls
    {:ok, %{
      content: case prompt do
        "What is 2 + 2?" -> "4"
        _ -> "I don't know"
      end
    }}
  end
)

IO.puts("Answer: #{result.content}")
IO.puts("Candidates generated: #{metadata.num_candidates}")
IO.puts("Stopped early: #{metadata.stopped_early}")
IO.puts("Consensus: #{metadata.consensus}")

# Example 2: Hard question requiring more candidates
IO.puts("\n\nExample 2: Hard question (generates more candidates)")
IO.puts("----------------------------------------------------")

hard_query = "Explain the implications of quantum entanglement for quantum computing."

IO.puts("Query: #{hard_query}")
IO.puts("This would generate more candidates due to lower consensus.\n")

# Example 3: Demonstrating the adaptive behavior
IO.puts("\n\nExample 3: Adaptive behavior demonstration")
IO.puts("------------------------------------------")

IO.puts("Adaptive self-consistency adjusts based on:")
IO.puts("1. Difficulty estimation")
IO.puts("2. Consensus after each batch")
IO.puts("3. Early stopping threshold\n")

# Show configuration for different scenarios
IO.puts("Configurations for different scenarios:")
IO.puts("\nCost-optimized:")
IO.puts("  min_candidates: 3")
IO.puts("  max_candidates: 10")
IO.puts("  early_stop_threshold: 0.7")
IO.puts("  → Generates 3-10 candidates, stops easily")

IO.puts("\nBalanced (recommended):")
IO.puts("  min_candidates: 3")
IO.puts("  max_candidates: 20")
IO.puts("  early_stop_threshold: 0.8")
IO.puts("  → Generates 3-20 candidates, balanced stopping")

IO.puts("\nQuality-optimized:")
IO.puts("  min_candidates: 5")
IO.puts("  max_candidates: 30")
IO.puts("  early_stop_threshold: 0.9")
IO.puts("  → Generates 5-30 candidates, stops only with high consensus")

# Example 4: Using with difficulty estimation
IO.puts("\n\nExample 4: With difficulty-based configuration")
IO.puts("------------------------------------------------")

IO.puts("Configure adaptive SC based on estimated difficulty:\n")

difficulty_configs = %{
  easy: %{min_candidates: 3, max_candidates: 5, early_stop_threshold: 0.7},
  medium: %{min_candidates: 5, max_candidates: 10, early_stop_threshold: 0.8},
  hard: %{min_candidates: 10, max_candidates: 20, early_stop_threshold: 0.9}
}

IO.puts("Easy questions: #{inspect(difficulty_configs.easy)}")
IO.puts("Medium questions: #{inspect(difficulty_configs.medium)}")
IO.puts("Hard questions: #{inspect(difficulty_configs.hard)}")

# Summary
IO.puts("\n\n=== Summary ===")
IO.puts("-----------")
IO.puts("Adaptive self-consistency optimizes compute by:")
IO.puts("1. Starting with minimum candidates")
IO.puts("2. Checking consensus after each batch")
IO.puts("3. Stopping early when consensus is high")
IO.puts("4. Generating more candidates for low consensus")
IO.puts("\nBenefits:")
IO.puts("  - Reduces average compute cost by ~40-50%")
IO.puts("  - Maintains accuracy through adaptive generation")
IO.puts("  - Ideal for variable-difficulty workloads")
IO.puts("\n")
