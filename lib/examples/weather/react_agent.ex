defmodule Jido.AI.Examples.Weather.ReActAgent do
  @moduledoc """
  ReAct weather agent with live tool-calling.

  This is the practical, production-style weather example based on `Jido.AI.Agent`.

  ## CLI Usage

      mix jido_ai --agent Jido.AI.Examples.Weather.ReActAgent \\
        "Should I bring an umbrella in Chicago this evening?"
  """

  use Jido.AI.Agent,
    name: "weather_react_agent",
    description: "Weather assistant using ReAct tool-calling",
    max_iterations: 10,
    tools: [
      Jido.Tools.Weather.Geocode,
      Jido.Tools.Weather.Forecast,
      Jido.Tools.Weather.HourlyForecast,
      Jido.Tools.Weather.CurrentConditions,
      Jido.Tools.Weather.LocationToGrid
    ],
    system_prompt: """
    You are a weather planning assistant.

    Use tools for weather facts and keep advice practical:
    - Temperature and precipitation
    - Timing (morning/afternoon/evening) when possible
    - Clothing, transit, and backup plans

    Tool workflow requirements:
    1. If location is a place name (for example "Seattle, WA"), call weather_geocode first.
    2. Then call weather_location_to_grid using the returned coordinates (lat,lng format only).
    3. Then call forecast/current tools from the returned NWS URLs.
    4. Never pass a city/state string directly into weather_location_to_grid.

    If location/date is ambiguous, ask a concise clarification.
    """

  @doc "Returns the CLI adapter used by `mix jido_ai` for this example."
  @spec cli_adapter() :: module()
  def cli_adapter, do: Jido.AI.Reasoning.ReAct.CLIAdapter

  @doc """
  Build a weather-aware commute plan for a location.
  """
  @spec commute_plan_sync(pid(), String.t(), keyword()) :: {:ok, any()} | {:error, term()}
  def commute_plan_sync(pid, location, opts \\ []) do
    ask_sync(
      pid,
      "Create a commute weather plan for #{location} in the next 12 hours. Include clothing, rain risk, and a backup transit option.",
      opts
    )
  end
end
