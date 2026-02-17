defmodule Jido.AI.Examples.WeatherAgent do
  @moduledoc """
  Agent for weather queries and travel advice (`Jido.AI.Agent`, ReAct strategy implied).

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

      # Async request handle (production-friendly)
      {:ok, req} = Jido.AI.Examples.WeatherAgent.ask(pid, "Do I need a jacket in Boston tonight?")
      {:ok, answer} = Jido.AI.Examples.WeatherAgent.await(req, timeout: 30_000)

      # Optional cancellation with request scope
      :ok = Jido.AI.Examples.WeatherAgent.cancel(pid, request_id: req.id, reason: :user_cancelled)

  ## CLI Usage

      mix jido_ai --agent Jido.AI.Examples.WeatherAgent \\
        "Should I bring an umbrella to Chicago this weekend?"

      mix jido_ai --agent Jido.AI.Examples.WeatherAgent \\
        "I'm hiking in Denver tomorrow - what should I wear?"

  ## Notes

  Uses the free National Weather Service API (no API key required).
  Works best with US locations. For international locations, coordinates are needed.
  """

  use Jido.AI.Agent,
    name: "weather_agent",
    description: "Weather assistant with travel and activity advice",
    request_policy: :reject,
    tool_timeout_ms: 15_000,
    tool_max_retries: 1,
    tool_retry_backoff_ms: 200,
    observability: %{
      emit_telemetry?: true,
      emit_lifecycle_signals?: true,
      redact_tool_args?: true,
      emit_llm_deltas?: true
    },
    tags: ["example"],
    tools: [
      Jido.Tools.Weather,
      Jido.Tools.Weather.ByLocation,
      Jido.Tools.Weather.Forecast,
      Jido.Tools.Weather.HourlyForecast,
      Jido.Tools.Weather.CurrentConditions,
      Jido.Tools.Weather.Geocode
    ],
    system_prompt: """
    You are a helpful weather assistant. You help users understand weather
    conditions and plan their activities accordingly.

    IMPORTANT: The weather tools ONLY accept "lat,lng" coordinates (e.g., "41.8781,-87.6298").
    They do NOT accept city names, addresses, or zip codes directly.

    When answering weather questions:
    1. Determine the location - ask for clarification if ambiguous
    2. Convert the location to coordinates:
       - Use weather_geocode to convert city/state/address to coordinates
       - Or use these common US city coordinates:
         - New York: 40.7128,-74.0060
         - Los Angeles: 34.0522,-118.2437
         - Chicago: 41.8781,-87.6298
         - Seattle: 47.6062,-122.3321
         - Denver: 39.7392,-104.9903
         - Miami: 25.7617,-80.1918
         - Boston: 42.3601,-71.0589
    3. Fetch the appropriate forecast using the coordinates
    4. Provide practical advice based on conditions

    Always include:
    - Temperature range
    - Precipitation chances
    - Practical recommendations (clothing, umbrella, sunscreen, etc.)

    Be conversational and helpful, not just a data dump.
    """,
    max_iterations: 10

  @default_timeout 30_000

  @doc """
  Get weather forecast for a location.

  ## Examples

      {:ok, forecast} = WeatherAgent.get_forecast(pid, "Seattle")

  """
  @spec get_forecast(pid(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def get_forecast(pid, location, opts \\ []) do
    query = """
    Get the weather forecast for #{location}.
    Include temperature, precipitation, and recommendations.
    """

    ask_sync(pid, query, Keyword.put_new(opts, :timeout, @default_timeout))
  end

  @doc """
  Check current weather conditions for a location.

  ## Examples

      {:ok, conditions} = WeatherAgent.get_conditions(pid, "Denver")

  """
  @spec get_conditions(pid(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def get_conditions(pid, location, opts \\ []) do
    ask_sync(
      pid,
      "What are the current conditions in #{location}?",
      Keyword.put_new(opts, :timeout, @default_timeout)
    )
  end

  @doc """
  Check if you should bring an umbrella to a location.

  ## Examples

      {:ok, advice} = WeatherAgent.need_umbrella?(pid, "Chicago")

  """
  @spec need_umbrella?(pid(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def need_umbrella?(pid, location, opts \\ []) do
    ask_sync(
      pid,
      "Should I bring an umbrella in #{location} today?",
      Keyword.put_new(opts, :timeout, @default_timeout)
    )
  end
end
