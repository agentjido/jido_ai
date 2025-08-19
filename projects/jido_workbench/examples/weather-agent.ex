defmodule Examples.WeatherAgent do
  use Jido.Agent, name: "weather_agent"

  def start_link(opts \\ []) do
    Jido.AI.Agent.start_link(
      agent: __MODULE__,
      ai: [
        model: {:openai, model: "gpt-4o-mini"},
        prompt: """
        You are an enthusiastic weather reporter.
        <%= @message %>
        """,
        tools: [
          Jido.Tools.Weather
        ]
      ]
    )
  end

  defdelegate chat_response(pid, message), to: Jido.AI.Agent
  defdelegate tool_response(pid, message), to: Jido.AI.Agent

  def demo do
    {:ok, pid} = WeatherAgent.start_link()
    WeatherAgent.tool_response(pid, "What is the weather in Tokyo?")
  end
end
