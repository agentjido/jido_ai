defmodule Jido.AI.Examples.WeatherAgent do
  @moduledoc """
  ReAct agent for weather queries and travel advice.

  Demonstrates iterative tool-use for weather lookups:
  1. Interprets user location (city name → coordinates)
  2. Fetches weather forecasts
  3. Provides contextual advice (packing, activities, etc.)

  **Why ReAct?** Users often provide incomplete info (no dates, vague locations).
  ReAct enables: clarify → fetch → interpret → advise.

  ## Usage

      # Start the agent
      {:ok, pid} = Jido.start_agent(MyApp.Jido, Jido.AI.Examples.WeatherAgent)

      # Ask about weather
      :ok = Jido.AI.Examples.WeatherAgent.ask(pid, "What's the weather in Seattle?")

      # Check result
      agent = Jido.AgentServer.get(pid)
      agent.state.last_answer

  ## CLI Usage

      mix jido_ai.agent --agent Jido.AI.Examples.WeatherAgent \\
        "Should I bring an umbrella to Chicago this weekend?"

      mix jido_ai.agent --agent Jido.AI.Examples.WeatherAgent \\
        "I'm hiking in Denver tomorrow - what should I wear?"

  ## Notes

  Uses the free National Weather Service API (no API key required).
  Works best with US locations. For international locations, coordinates are needed.
  """

  use Jido.AI.ReActAgent,
    name: "weather_agent",
    description: "Weather assistant with travel and activity advice",
    tools: [
      Jido.Tools.Weather,
      Jido.Tools.Weather.ByLocation,
      Jido.Tools.Weather.Forecast,
      Jido.Tools.Weather.HourlyForecast,
      Jido.Tools.Weather.CurrentConditions
    ],
    system_prompt: """
    You are a helpful weather assistant. You help users understand weather
    conditions and plan their activities accordingly.

    When answering weather questions:
    1. Determine the location - ask for clarification if ambiguous
    2. For US cities, use common coordinates:
       - New York: 40.7128,-74.0060
       - Los Angeles: 34.0522,-118.2437
       - Chicago: 41.8781,-87.6298
       - Seattle: 47.6062,-122.3321
       - Denver: 39.7392,-104.9903
       - Miami: 25.7617,-80.1918
       - Boston: 42.3601,-71.0589
    3. Fetch the appropriate forecast (current, hourly, or extended)
    4. Provide practical advice based on conditions

    Always include:
    - Temperature range
    - Precipitation chances
    - Practical recommendations (clothing, umbrella, sunscreen, etc.)

    Be conversational and helpful, not just a data dump.
    """,
    max_iterations: 10
end
