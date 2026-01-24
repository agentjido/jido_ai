#!/usr/bin/env env elixir

# Chain-of-Thought Strategy Example
#
# Run this example with:
#   mix run examples/strategies/chain_of_thought.exs
#
# This example demonstrates the Chain-of-Thought strategy for
# step-by-step sequential reasoning.

Application.ensure_all_started(:jido_ai)

IO.puts("\n=== Chain-of-Thought Strategy Example ===\n")

# Example 1: Understanding Chain-of-Thought
IO.puts("Example 1: How Chain-of-Thought works")
IO.puts("-------------------------------------")

IO.puts("""
Chain-of-Thought breaks problems into sequential steps:

Example: "Roger starts with 5 tennis balls. He buys 2 cans of
3 tennis balls each. How many tennis balls does he have?"

Step 1: Roger starts with 5 tennis balls
Step 2: He buys 2 cans of 3 tennis balls
Step 3: 2 cans × 3 balls = 6 balls from cans
Step 4: Total = 5 + 6 = 11 tennis balls
Answer: 11

This explicit reasoning reduces errors!
""")

# Example 2: CoT agent definition
IO.puts("\n\nExample 2: Defining a Chain-of-Thought agent")
IO.puts("--------------------------------------------")

cot_agent = """
defmodule MyApp.MathAgent do
  use Jido.Agent,
    name: "math_agent",
    strategy: {
      Jido.AI.Strategies.ChainOfThought,
      model: :fast
    },
    system_prompt: \"\"\"
    You are a math expert. Always think step by step and
    show your work clearly.
    \"\"\"
end
"""

IO.puts(cot_agent)

# Example 3: Types of problems for CoT
IO.puts("\n\nExample 3: When Chain-of-Thought excels")
IO.puts("----------------------------------------")

IO.puts("""
Excellent for:
  ✓ Arithmetic and word problems
  ✓ Logic puzzles
  ✓ Multi-step reasoning
  ✓ Mathematical proofs
  ✓ Common sense reasoning

Less effective for:
  ✗ Creative writing (no single "correct" path)
  ✗ Open-ended questions
  ✗ Tasks requiring divergent thinking
""")

# Example 4: Prompting techniques
IO.puts("\n\nExample 4: Effective CoT prompting")
IO.puts("---------------------------------")

prompting_examples = """
# Basic CoT prompt
"Let's think step by step to solve this problem."

# More detailed
"Think step by step:
1. Understand what's being asked
2. Identify the information given
3. Work through the calculations
4. Check your answer
5. State the final result clearly"

# For math specifically
"Solve this math problem step by step:
- First, identify what operation is needed
- Then, perform the calculation carefully
- Finally, verify your answer"
"""

IO.puts(prompting_examples)

# Example 5: Example problems
IO.puts("\n\nExample 5: Example problems for CoT")
IO.puts("-----------------------------------")

IO.puts("""
Math Problem:
  "If 3x + 7 = 22, what is x² + 2x?"

  CoT Response:
  Step 1: First, solve for x
  Step 2: 3x + 7 = 22
  Step 3: 3x = 22 - 7 = 15
  Step 4: x = 15 / 3 = 5
  Step 5: Now calculate x² + 2x
  Step 6: 5² + 2(5) = 25 + 10 = 35
  Answer: 35

Logic Problem:
  "If all Bloops are Razzles and all Razzles are Lazzles,
   then are all Bloops definitely Lazzles?"

  CoT Response:
  Step 1: All Bloops are Razzles (given)
  Step 2: All Razzles are Lazzles (given)
  Step 3: Bloop → Razzle → Lazzle
  Step 4: By transitivity, all Bloops are Lazzles
  Answer: Yes
""")

# Example 6: CoT vs ReAct comparison
IO.puts("\n\nExample 6: Chain-of-Thought vs ReAct")
IO.puts("-------------------------------------")

comparison = """
┌────────────────────┬──────────────────┬─────────────────┐
│ Feature            │ Chain-of-Thought │ ReAct           │
├────────────────────┼──────────────────┼─────────────────┤
│ Tool use           │ No               │ Yes             │
│ External info      │ No               │ Yes             │
│ Reasoning steps    │ Yes              │ Yes             │
│ Best for           │ Math, logic      │ Multi-step with │
│                    │                  │ tools           │
│ Complexity         │ Low-Medium       │ Medium-High     │
│ Cost               │ Lower            │ Higher          │
└────────────────────┴──────────────────┴─────────────────┘
"""

IO.puts(comparison)

# Example 7: Advanced CoT techniques
IO.puts("\n\nExample 7: Advanced Chain-of-Thought techniques")
IO.puts("----------------------------------------------")

IO.puts("""
1. Zero-shot CoT
   Just add "Let's think step by step" to any prompt

2. Few-shot CoT
   Provide examples with reasoning:
   Q: What is 2+2?
   A: Let's think step by step. 2+2=4. Answer: 4
   Q: What is 3+3?
   A: ...

3. Self-Consistency + CoT
   Generate multiple CoT responses, take majority vote

4. CoT with Verification
   Generate CoT response, verify each step
""")

# Summary
IO.puts("\n=== Summary ===")
IO.puts("-----------")
IO.puts("Chain-of-Thought provides:")
IO.puts("  • Explicit reasoning steps")
IO.puts("  • Reduced error rates on math/logic")
IO.puts("  • Easy to implement (just add to prompt)")
IO.puts("  • Works well with self-consistency")
IO.puts("\nBest practices:")
IO.puts("  1. Always use 'step by step' in prompt")
IO.puts("  2. Show work clearly")
IO.puts("  3. Consider multi-step breakdown")
IO.puts("  4. Combine with self-consistency for hard problems")
IO.puts("\n")
