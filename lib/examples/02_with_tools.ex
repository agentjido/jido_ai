defmodule Examples.ToolAgent02 do
  alias Jido.AI.Agent
  alias Jido.Actions.Arithmetic.{Add, Subtract, Multiply, Divide}

  def demo do
    {:ok, pid} =
      Agent.start_link(
        ai: [
          model: {:anthropic, chat: :small},
          prompt: """
          You are a super math genius.
          You are given a math problem and you need to solve it using the tools provided.
          """,
          tools: [
            Add,
            Subtract,
            Multiply,
            Divide
          ]
        ]
      )

    agent_state = Agent.state(pid)

    require Logger
    Logger.info("Agent state: #{inspect(agent_state)}")

    result = Agent.tool_response(pid, "What is 100 + 100?")
    Logger.info("Result: #{inspect(result)}")
  end
end
