#!/usr/bin/env env elixir

# Beam Search Example
#
# Run this example with:
#   mix run examples/accuracy/search/beam_search.exs
#
# This example demonstrates beam search for systematic
# exploration with controlled memory usage.

Application.ensure_all_started(:jido_ai)

alias Jido.AI.Accuracy.Search.BeamSearch

IO.puts("\n=== Beam Search Example ===\n")

# Example 1: Understanding beam search
IO.puts("Example 1: How beam search works")
IO.puts("-------------------------------")

query = "What is 17 * 19?"

IO.puts("Query: #{query}")
IO.puts("\nBeam search maintains top-N candidates at each depth:")

IO.puts("""
Depth 0: [Question]
         ↓
Depth 1: [Thought A, Thought B, Thought C]  # Keep top 3 (beam_width)
         ↓    ↓    ↓
Depth 2: Expand each to 2 candidates
         [A1, A2, B1, B2, C1, C2]
         ↓
         Keep top 3: [A2, B1, C2]  # beam_width = 3
         ↓
Depth 3: Continue until max_depth
         ↓
         Return best candidate
""")

# Example 2: Beam search parameters
IO.puts("\n\nExample 2: Configuration parameters")
IO.puts("----------------------------------")

IO.puts("Key parameters:")
IO.puts("\n:beam_width")
IO.puts("  Number of candidates to keep at each depth (default: 5)")
IO.puts("  Higher → More exploration, more memory")
IO.puts("  Typical range: 3-10")

IO.puts("\n:depth")
IO.puts("  Number of expansion rounds (default: 3)")
IO.puts("  Higher → Deeper reasoning")
IO.puts("  Typical range: 2-5")

IO.puts("\n:branching_factor")
IO.puts("  Candidates generated per beam position (default: 2)")
IO.puts("  Higher → More candidates considered")
IO.puts("  Typical range: 2-4")

# Example 3: Usage pattern
IO.puts("\n\nExample 3: Usage pattern")
IO.puts("----------------------")

code_example = """
{:ok, best} = BeamSearch.search(
  "What is 17 * 19?",
  generator: fn thought ->
    # Generate next reasoning step
    ReqLLM.Generation.generate_text(model, [
      %{role: :user, content: "Continue reasoning: #{thought}"}
    ])
  end,
  verifier: fn candidate ->
    # Score the candidate (0-1)
    cond do
      String.contains?(candidate, "323") -> 1.0
      String.contains?(candidate, "32") -> 0.5
      true -> 0.0
    end
  end,
  beam_width: 3,
  depth: 2,
  branching_factor: 2
)
"""

IO.puts("Complete example:")
IO.puts(code_example)

# Example 4: When to use beam search
IO.puts("\n\nExample 4: When to use beam search")
IO.puts("----------------------------------")

IO.puts("Use beam search when:")
IO.puts("  ✓ Problem has clear branching structure")
IO.puts("  ✓ Memory is constrained")
IO.puts("  ✓ Depth is limited and known")
IO.puts("  ✓ You need systematic exploration")

IO.puts("\nConsider alternatives:")
IO.puts("  • MCTS - For complex, variable-depth problems")
IO.puts("  • Self-Consistency - For single-shot answers")
IO.puts("  • Diverse Decoding - For creative exploration")

# Example 5: Trade-offs
IO.puts("\n\nExample 5: Resource trade-offs")
IO.puts("----------------------------")

IO.puts("""
Beam Width vs Resources:
┌─────────────┬─────────┬─────────┬──────────┐
│ Beam Width  │ Memory  │ Quality │ Speed    │
├─────────────┼─────────┼─────────┼──────────┤
│ 3           │ Low     │ Good    │ Fast     │
│ 5           │ Medium  │ Better  │ Medium   │
│ 10+         │ High    │ Best    │ Slow     │
└─────────────┴─────────┴─────────┴──────────┘

Depth vs Resources:
┌─────────┬──────────┬─────────┬──────────┐
│ Depth   │ Candidates │ Quality │ Speed   │
├─────────┼──────────┼─────────┼──────────┤
│ 2       │ beam²    │ Basic   │ Fast     │
│ 3       │ beam³    │ Good    │ Medium   │
│ 5+      │ beam⁵    │ Best    │ Slow     │
└─────────┴──────────┴─────────┴──────────┘
""")

# Summary
IO.puts("\n=== Summary ===")
IO.puts("-----------")
IO.puts("Beam search provides:")
IO.puts("  • Controlled memory usage (beam_width)")
IO.puts("  • Systematic exploration")
IO.puts("  • Good for problems with known depth")
IO.puts("  • Better than exhaustive search, faster than MCTS for shallow problems")
IO.puts("\n")
