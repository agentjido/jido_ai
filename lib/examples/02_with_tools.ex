defmodule Examples.ToolAgent02 do
  alias Jido.AI.Agent
  alias Jido.Actions.Arithmetic.{Add, Subtract, Multiply, Divide}
  require Logger

  def demo do
    {:ok, pid} =
      Agent.start_link(
        ai: [
          model: {:anthropic,  model_id: "claude-3-haiku-20240307"},
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

    # {:ok, agent_state} = Agent.state(pid)
    # Logger.info("Agent state: #{inspect(agent_state, pretty: true)}")

    {:ok, result} = Agent.tool_response(pid, "What is 100 + 100?")
    Logger.info("Result: #{inspect(result, pretty: true)}")

    # agent_state = Agent.state(pid)

    # Logger.info("Agent state: #{inspect(agent_state)}")

    # result = Agent.tool_response(pid, "What is 100 + 100?")
    # Logger.info("Result: #{inspect(result)}")
  end
end
