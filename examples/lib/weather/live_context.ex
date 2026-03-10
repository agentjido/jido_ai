defmodule Jido.AI.Examples.Weather.LiveContext do
  @moduledoc false

  alias Jido.AI.Examples.Tools.Weather.ByLocation

  @default_location "Seattle"

  @known_locations [
    "Seattle",
    "Denver",
    "Chicago",
    "Boston",
    "New York",
    "Los Angeles",
    "Miami",
    "San Francisco",
    "Portland"
  ]

  @spec enrich_prompt(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def enrich_prompt(prompt) when is_binary(prompt) do
    location = infer_location(prompt)

    case fetch_weather_summary(location) do
      {:ok, summary} ->
        {:ok,
         """
         #{prompt}

         LIVE_WEATHER_CONTEXT (National Weather Service):
         #{summary}

         Response requirements:
         - Treat the live weather context above as authoritative.
         - Explicitly mention the location name in your answer.
         - Cite at least one explicit forecast period name.
         - Include one practical recommendation and one backup recommendation.
         """}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp infer_location(prompt) do
    prompt_downcased = String.downcase(prompt)

    Enum.find(@known_locations, @default_location, fn location ->
      String.contains?(prompt_downcased, String.downcase(location))
    end)
  end

  defp fetch_weather_summary(location) do
    case ByLocation.run(%{location: location, periods: 4, format: :summary}, %{}) do
      {:ok, %{location: place, forecast: periods}} when is_list(periods) and periods != [] ->
        city = Map.get(place, :city, location)
        state = Map.get(place, :state, "")
        tz = Map.get(place, :timezone, "")

        lines =
          periods
          |> Enum.take(4)
          |> Enum.map_join("\n", fn period ->
            temp = Map.get(period, :temperature)
            unit = Map.get(period, :temperature_unit, "F")
            wind = Map.get(period, :wind_speed, "")
            short = Map.get(period, :short_forecast, "")
            name = Map.get(period, :name, "Period")
            "- #{name}: #{temp}#{unit}, #{short}, wind #{wind}"
          end)

        {:ok, "Location: #{city}, #{state} (#{tz})\n#{lines}"}

      {:ok, _unexpected} ->
        {:error, "Live weather fetch returned an unexpected shape for #{location}"}

      {:error, reason} ->
        {:error, "Live weather fetch failed for #{location}: #{inspect(reason)}"}
    end
  end
end
