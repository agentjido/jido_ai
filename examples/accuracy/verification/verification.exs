#!/usr/bin/env env elixir

# Verification Example
#
# Run this example with:
#   mix run examples/accuracy/verification/verification.exs
#
# This example demonstrates different verification methods for
# validating LLM responses.

Application.ensure_all_started(:jido_ai)

alias Jido.AI.Accuracy.VerificationResult

IO.puts("\n=== Verification Example ===\n")

# Example 1: Deterministic verification
IO.puts("Example 1: Deterministic (exact match) verification")
IO.puts("---------------------------------------------------")

IO.puts("Best for: Math problems, factual questions, multiple choice\n")

IO.puts("Configuration:")
verification_config = """
verifier = DeterministicVerifier.new!(%{
  check_type: :exact_match,
  expected: "Paris"
})
"""

IO.puts(verification_config)

IO.puts("Result: Scores 1.0 for exact match, 0.0 otherwise")
IO.puts("Fastest verification method with no LLM calls needed.")

# Example 2: LLM outcome verification
IO.puts("\n\nExample 2: LLM-based verification")
IO.puts("----------------------------------")

IO.puts("Best for: Nuanced questions, explanations, open-ended reasoning\n")

IO.puts("Configuration:")
llm_verification_config = """
verifier = LLMOutcomeVerifier.new!(%{
  model: "anthropic:claude-haiku-4-5",
  score_range: {0, 100},
  temperature: 0.2
})
"""

IO.puts(llm_verification_config)

IO.puts("Result: Returns score 0-100 with reasoning:")
IO.puts("  {")
IO.puts("    score: 85,")
IO.puts("    passed?: true,")
IO.puts("    reasoning: \"Answer is correct but lacks detail...\"")
IO.puts("  }")

# Example 3: Code execution verification
IO.puts("\n\nExample 3: Code execution verification")
IO.puts("--------------------------------------")

IO.puts("Best for: Programming problems, algorithm verification\n")

IO.puts("Configuration:")
code_verification_config = """
verifier = CodeExecutionVerifier.new!(%{
  sandbox: :docker,  # or :none (unsafe)
  timeout: 5000
})
"""

IO.puts(code_verification_config)

IO.puts("How it works:")
IO.puts("  1. Receives code candidate")
IO.puts("  2. Executes code in sandbox")
IO.puts("  3. Compares output to expected")
IO.puts("  4. Returns score based on correctness")

IO.puts("\nSafety levels:")
IO.puts("  • docker: High isolation (recommended)")
IO.puts("  • podman: High isolation")
IO.puts("  • none: No isolation (trusted only)")

# Example 4: Unit test verification
IO.puts("\n\nExample 4: Unit test verification")
IO.puts("----------------------------------")

IO.puts("Best for: Function correctness, API testing\n")

IO.puts("Configuration:")
test_verification_config = """
verifier = UnitTestVerifier.new!(%{
  test_framework: :exunit,
  timeout: 5000
})

{:ok, result} = UnitTestVerifier.verify(verifier, code, %{
  tests: [
    ~s(test "add/2 returns sum" do),
    ~s(assert Calculator.add(2, 3) == 5)
  ]
})
"""

IO.puts(test_verification_config)

# Example 5: Choosing a verifier
IO.puts("\n\nExample 5: Verifier selection guide")
IO.puts("-----------------------------------")

IO.puts("""
┌────────────────────────┬──────────────────┬─────────┬────────┐
│ Verifier              │ Best For          │ Speed   │ Cost   │
├────────────────────────┼──────────────────┼─────────┼────────┤
│ Deterministic         │ Facts, math       │ Fastest │ Free   │
│ LLM Outcome           │ Complex answers   │ Slow    │ $$     │
│ Code Execution        │ Code problems     │ Medium  │ $      │
│ Static Analysis        │ Code review       │ Fast    │ Free   │
│ Unit Test             │ Functions         │ Medium  │ $      │
└────────────────────────┴──────────────────┴─────────┴────────┘
""")

# Example 6: Combining verifiers
IO.puts("\n\nExample 6: Composite verification")
IO.puts("---------------------------------")

IO.puts("Combine multiple verifiers for robustness:\n")

composite_config = """
verifier = CompositeVerifier.new!(%{
  verifiers: [
    {DeterministicVerifier, %{check_type: :numeric_range, min: 40, max: 45}},
    {LLMOutcomeVerifier, %{model: :fast, score_range: {0, 1}}}
  ],
  aggregation: :average  # or :min, :max, :weighted
})
"""

IO.puts(composite_config)

IO.puts("Result: Aggregates scores from all verifiers")
IO.puts("  • average: Mean of all scores")
IO.puts("  • min: Most conservative (lowest score wins)")
IO.puts("  • max: Most optimistic (highest score wins)")

# Example 7: Verification with self-consistency
IO.puts("\n\nExample 7: Using verification with self-consistency")
IO.puts("----------------------------------------------------")

sc_with_verification = """
# Generate candidates and verify each
{:ok, best, metadata} = SelfConsistency.run(
  "What is 247 * 13?",
  num_candidates: 5,
  aggregator: :best_of_n,  # Use verifier scores
  scorer: fn candidate ->
    {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
    result.score
  end
)
"""

IO.puts(sc_with_verification)

# Summary
IO.puts("\n=== Summary ===")
IO.puts("-----------")
IO.puts("Verification provides:")
IO.puts("  • Quality assessment of candidates")
IO.puts("  • Guidance for search algorithms")
IO.puts("  • Confidence estimation")
IO.puts("  • Error detection")
IO.puts("\nBest practices:")
IO.puts("  1. Use deterministic when possible (fastest)")
IO.puts("  2. Combine multiple verifiers for robustness")
IO.puts("  3. Cache verification results for repeated candidates")
IO.puts("  4. Handle edge cases (malformed responses, timeouts)")
IO.puts("\n")
