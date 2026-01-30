defmodule Jido.AI.Examples.OrchestratorDemo do
  @moduledoc """
  Demo orchestrator agent for testing multi-agent coordination via CLI.

  This agent coordinates two specialist agents:
  - **Math Specialist**: Handles arithmetic calculations
  - **Weather Specialist**: Provides weather information

  ## Usage with CLI

      # Run a math query (will delegate to math specialist)
      mix jido_ai.agent --agent Jido.AI.Examples.OrchestratorDemo "What is 15 * 7?"

      # Run a weather query (will delegate to weather specialist)
      mix jido_ai.agent --agent Jido.AI.Examples.OrchestratorDemo "What's the weather in Tokyo?"

      # With trace mode to see orchestration flow
      mix jido_ai.agent --agent Jido.AI.Examples.OrchestratorDemo --trace "Calculate 100 / 4"

  ## How It Works

  1. Query arrives at the orchestrator
  2. LLM analyzes query and available specialists via DelegateTask
  3. Routes to appropriate specialist (math or weather)
  4. Specialist executes with its tools
  5. Result returns to orchestrator and then to user
  """

  use Jido.AI.OrchestratorAgent,
    name: "orchestrator_demo",
    description: "Demo orchestrator that coordinates math and weather specialists",
    specialists: [
      %{
        name: "math_specialist",
        description:
          "Expert at mathematical calculations including addition, subtraction, multiplication, and division",
        capabilities: ["math", "arithmetic", "calculation", "add", "subtract", "multiply", "divide", "sum", "product"],
        tools: [
          Jido.Tools.Arithmetic.Add,
          Jido.Tools.Arithmetic.Subtract,
          Jido.Tools.Arithmetic.Multiply,
          Jido.Tools.Arithmetic.Divide
        ]
      },
      %{
        name: "weather_specialist",
        description: "Provides current weather information for any location",
        capabilities: ["weather", "forecast", "temperature", "conditions", "climate"],
        tools: [Jido.Tools.Weather]
      }
    ]
end
