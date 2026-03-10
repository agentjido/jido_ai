defmodule Jido.AI.Examples.CalculatorAgent do
  @moduledoc """
  Example agent that uses the Calculator skill for arithmetic operations.

  This demonstrates how to integrate skills with a `Jido.AI.Agent`:
  - Skills provide prompt context via `Skill.Prompt.render/1`
  - Skills can filter tools via `Skill.Prompt.filter_tools/2`
  - The agent uses skill-specified tools for calculations

  ## Usage

      # Start the agent
      {:ok, pid} = Jido.AgentServer.start(agent: Jido.AI.Examples.CalculatorAgent)
      
      # Ask a calculation question
      Jido.AI.Examples.CalculatorAgent.ask(pid, "What is 25 * 4 + 50?")
      
      # Get the result
      agent = Jido.AgentServer.get(pid)
      agent.state.last_answer  # => "25 × 4 + 50 = 150"

  ## How It Works

  1. The agent is configured with arithmetic tools
  2. On initialization, the Calculator skill's body is injected into the system prompt
  3. The LLM uses the skill instructions to properly chain tool calls
  4. Results are combined and presented clearly
  """

  use Jido.AI.Agent,
    name: "calculator_agent",
    description: "A calculator agent that uses skills for arithmetic",
    tools: [
      Jido.Tools.Arithmetic.Add,
      Jido.Tools.Arithmetic.Subtract,
      Jido.Tools.Arithmetic.Multiply,
      Jido.Tools.Arithmetic.Divide
    ],
    system_prompt: """
    You are a helpful calculator assistant. You MUST use tool calls for all arithmetic operations.
    Never attempt mental math - always use the provided tools.
    Show your work step by step and provide clear answers.
    """,
    max_iterations: 10
end
