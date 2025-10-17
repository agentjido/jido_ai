defmodule Examples.BooleanAgent03 do
  alias Jido.AI.Agent
  require Logger

  def demo do
    {:ok, pid} =
      Agent.start_link(
        ai: [
          model: {:openai, model: "gpt-4o-mini"},
          prompt: """
          You are given a math problem and you need to determine if the result is positive or negative.

          <%= @message %>
          """,
          verbose: true
        ]
      )

    Logger.info("Agent started successfully")

    pos_question = "Is 273 + 112 - 937 positive?"
    neg_question = "Is 273 + 112 - 937 negative?"

    boolean_response(pid, pos_question)
    boolean_response(pid, neg_question)
  end

  defp boolean_response(pid, question) do
    Logger.info("Question: #{question}")

    case Agent.boolean_response(pid, question) do
      {:ok, %{result: bool_result, confidence: confidence}} ->
        if bool_result,
          do: Logger.info("Result: true (#{confidence}%)"),
          else: Logger.info("Result: false (#{confidence}%)")

      {:error, error} ->
        Logger.error("Error: #{inspect(error, pretty: true)}")
    end
  end
end
