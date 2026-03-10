defmodule Jido.AI.Examples.Skills.Calculator do
  @moduledoc """
  Calculator skill that provides precise arithmetic operations.

  This skill demonstrates how to create a module-based skill that:
  - Defines allowed tools for arithmetic operations
  - Provides prompt context for the LLM
  - Associates with action modules

  ## Usage

      # Use with an agent
      defmodule MyAgent do
        use Jido.AI.Agent,
          name: "my_agent",
          tools: [
            Jido.Tools.Arithmetic.Add,
            Jido.Tools.Arithmetic.Subtract,
            Jido.Tools.Arithmetic.Multiply,
            Jido.Tools.Arithmetic.Divide
          ]
      end
      
      # Inject skill context into system prompt
      skill_prompt = Jido.AI.Skill.Prompt.render([Jido.AI.Examples.Skills.Calculator])
      full_prompt = skill_prompt <> "\\n\\n" <> base_system_prompt
  """

  use Jido.AI.Skill,
    name: "calculator",
    description: "Performs precise arithmetic calculations using tool calls instead of mental math.",
    license: "Apache-2.0",
    allowed_tools: ~w(add subtract multiply divide),
    actions: [
      Jido.Tools.Arithmetic.Add,
      Jido.Tools.Arithmetic.Subtract,
      Jido.Tools.Arithmetic.Multiply,
      Jido.Tools.Arithmetic.Divide
    ],
    tags: ["math", "arithmetic", "utility"],
    body: """
    # Calculator Skill

    ## Purpose
    Use this skill when users need help with arithmetic or mathematical expressions.
    ALWAYS use tool calls for calculations - never attempt mental math.

    ## Available Operations
    - `add(value, amount)` - Adds amount to value
    - `subtract(value, amount)` - Subtracts amount from value  
    - `multiply(value, amount)` - Multiplies value by amount
    - `divide(value, amount)` - Divides value by amount (handles zero division)

    ## Workflow
    1. Parse the mathematical expression into individual operations
    2. Execute operations in the correct order (respect operator precedence)
    3. Chain results: use the result of one operation as input to the next
    4. Present the final answer with a clear explanation

    ## Examples

    For "15 * 7 + 3":
    1. First multiply: multiply(15, 7) => 105
    2. Then add: add(105, 3) => 108
    3. Answer: "15 × 7 + 3 = 108"

    For "100 / 4 - 10":
    1. First divide: divide(100, 4) => 25
    2. Then subtract: subtract(25, 10) => 15
    3. Answer: "100 ÷ 4 - 10 = 15"

    ## Best Practices
    - Break complex expressions into simple operations
    - Show your work step by step
    - Verify results make sense
    - Handle edge cases (division by zero, etc.)
    """
end
