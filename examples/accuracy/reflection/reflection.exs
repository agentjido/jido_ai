#!/usr/bin/env env elixir

# Reflection Example
#
# Run this example with:
#   mix run examples/accuracy/reflection/reflection.exs
#
# This example demonstrates reflection and self-refine for
# iteratively improving candidate responses.

Application.ensure_all_started(:jido_ai)

alias Jido.AI.Accuracy.{ReflectionStage, Critique}

IO.puts("\n=== Reflection and Self-Refine Example ===\n")

# Example 1: Understanding reflection
IO.puts("Example 1: How reflection works")
IO.puts("--------------------------------")

IO.puts("""
Reflection improves candidates through iterative critique-revise:

Original Candidate → Critique → Revise → Improved Candidate

Iteration 1:
  Original: "The answer is 350."
  Critique: "Incorrect calculation. Check: 15 * 23 = ?"
  Revised: "Let me recalculate: 15 * 23 = 345."

Iteration 2:
  Critique: "Answer is now correct."
  Done! (converged)
""")

# Example 2: Self-refine (single pass)
IO.puts("\n\nExample 2: Self-refine (single improvement)")
IO.puts("-------------------------------------------")

IO.puts("Use self-refine for quick improvements:\n")

self_refine_example = """
strategy = SelfRefine.new!(%{
  model: "anthropic:claude-3-5-sonnet-20241022",
  temperature: 0.7
})

{:ok, result} = SelfRefine.run(
  "Explain the causes of World War I",
  strategy: strategy
)

# result.original - Initial candidate
# result.refined_candidate - Improved version
# result.improvement - Score increase
"""

IO.puts(self_refine_example)

# Example 3: Reflection stage configuration
IO.puts("\n\nExample 3: Reflection stage configuration")
IO.puts("----------------------------------------")

IO.puts("Key parameters:\n")

reflection_config = """
stage = ReflectionStage.new(%{
  min_score_threshold: 0.7,      # Skip reflection if score >= 0.7
  max_iterations: 3,              # Maximum refinement iterations
  convergence_threshold: 0.1      # Stop if improvement < 0.1
})
"""

IO.puts(reflection_config)

IO.puts("""
Parameter meanings:

min_score_threshold
  → Candidates scoring >= this skip reflection
  → Lower = more reflection (higher cost)
  → Higher = less reflection (lower cost)

max_iterations
  → Maximum critique-revise cycles
  → Higher = more improvement attempts (higher cost)

convergence_threshold
  → Minimum improvement to continue reflecting
  → Higher = stops sooner (lower cost)
  → Lower = keeps trying to improve (higher cost)
""")

# Example 4: Reflection flow diagram
IO.puts("\n\nExample 4: Reflection decision flow")
IO.puts("-----------------------------------")

IO.puts("""
candidate → score >= threshold?
                │
     ┌─────────┴─────────┐
     │                   │
    Yes                  No
     │                   │
  Return          Generate critique
     │                   │
                     Generate revision
                     │
                   score revised
                     │
           improvement >= threshold?
                     │
          ┌────────────┴────────────┐
          │                         │
         Yes                       No
          │                         │
     Continue                  Return improved
     (up to max)
          │
       Return
""")

# Example 5: Cost-optimized reflection
IO.puts("\n\nExample 5: Cost-optimized configuration")
IO.puts("--------------------------------------")

IO.puts("For cost-sensitive applications:\n")

cost_optimized = """
# Only reflect on poor candidates
stage = ReflectionStage.new(%{
  min_score_threshold: 0.5,  # Only reflect on scores < 0.5
  max_iterations: 1,           # Single improvement attempt
  convergence_threshold: 0.05  # Easy to stop
})
"""

IO.puts(cost_optimized)

# Example 6: Quality-optimized reflection
IO.puts("\n\nExample 6: Quality-optimized configuration")
IO.puts("---------------------------------------")

IO.puts("For accuracy-critical applications:\n")

quality_optimized = """
# Reflect on most candidates, iterate to improve
stage = ReflectionStage.new(%{
  min_score_threshold: 0.8,  # Reflect on most candidates
  max_iterations: 3,           # Multiple improvement attempts
  convergence_threshold: 0.05  # Keep trying to improve
})
"""

IO.puts(quality_optimized)

# Example 7: When to use reflection
IO.puts("\n\nExample 7: When reflection helps most")
IO.puts("--------------------------------------")

IO.puts("""
┌───────────────────┬─────────────────┬────────────────┐
│ Candidate Quality │ Reflection Help│ Recommendation│
├───────────────────┼─────────────────┼────────────────┤
│ High (0.8+)      │ Minimal         │ Skip reflection│
│ Medium (0.5-0.8)  │ Moderate        │ 1-2 iterations│
│ Low (<0.5)       │ Significant     │ 2-3 iterations│
└───────────────────┴─────────────────┴────────────────┘
""")

# Example 8: Combining with self-consistency
IO.puts("\n\nExample 8: Reflection with self-consistency")
IO.puts("-------------------------------------------")

combined_example = """
# Reflect candidates before aggregation
{:ok, best, meta} = SelfConsistency.run(
  query,
  num_candidates: 3,
  generator: fn q ->
    {:ok, initial} = generate(q)
    {:ok, reflected} = ReflectionStage.reflect(stage, initial,
      scorer: &score_candidate/1,
      generator: &generate_refinement/2
    )
    {:ok, reflected.final_answer}
  end
)
"""

IO.puts(combined_example)

# Summary
IO.puts("\n=== Summary ===")
IO.puts("-----------")
IO.puts("Reflection provides:")
IO.puts("  • Iterative improvement of candidates")
IO.puts("  • Targeted fixes based on critique")
IO.puts("  • Better final answers")
IO.puts("\nTrade-offs:")
IO.puts("  • Pros: Higher quality, error correction")
IO.puts("  • Cons: Additional latency and cost")
IO.puts("\nBest practices:")
IO.puts("  1. Set appropriate thresholds (don't reflect on good candidates)")
IO.puts("  2. Limit iterations to avoid infinite loops")
IO.puts("  3. Track improvement to measure value")
IO.puts("  4. Use for low-scoring candidates only")
IO.puts("\n")
