defmodule Jido.AI.Examples.ReActDemoAgent do
  @moduledoc """
  Demo ReAct agent using `Jido.AI.ReActAgent`.

  Shows how to create a ReAct-powered agent with minimal boilerplate.

  ## Usage

      {:ok, pid} = Jido.AgentServer.start(agent: Jido.AI.Examples.ReActDemoAgent)
      :ok = Jido.AI.Examples.ReActDemoAgent.ask(pid, "What is 15 * 7?")

      # Wait for completion
      agent = Jido.AgentServer.get(pid)
      agent.state.completed   # => true
      agent.state.last_answer # => "15 * 7 = 105"
  """

  use Jido.AI.ReActAgent,
    name: "react_demo_agent",
    description: "Demo ReAct agent with arithmetic and weather tools",
    tools: [
      Jido.Tools.Arithmetic.Add,
      Jido.Tools.Arithmetic.Subtract,
      Jido.Tools.Arithmetic.Multiply,
      Jido.Tools.Arithmetic.Divide,
      Jido.Tools.Weather
    ],
    max_iterations: 10
end
