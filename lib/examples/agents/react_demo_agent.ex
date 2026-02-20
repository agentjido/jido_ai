defmodule Jido.AI.Examples.ReActDemoAgent do
  @moduledoc """
  Demo agent using `Jido.AI.Agent`.

  Shows how to create an agent with ReAct strategy implied and minimal boilerplate.

  ## Usage

      {:ok, pid} = Jido.AgentServer.start(agent: Jido.AI.Examples.ReActDemoAgent)
      :ok = Jido.AI.Examples.ReActDemoAgent.ask(pid, "What is 15 * 7?")

      # Wait for completion
      agent = Jido.AgentServer.get(pid)
      agent.state.completed   # => true
      agent.state.last_answer # => "15 * 7 = 105"
  """

  use Jido.AI.Agent,
    name: "react_demo_agent",
    description: "Demo agent with arithmetic and weather tools",
    tools: [
      Jido.Tools.Arithmetic.Add,
      Jido.Tools.Arithmetic.Subtract,
      Jido.Tools.Arithmetic.Multiply,
      Jido.Tools.Arithmetic.Divide,
      Jido.Tools.Weather
    ],
    max_iterations: 10
end
