defmodule Jido.Tools.Weather.ByLocation do
  @moduledoc """
  Unified weather action that combines location lookup and forecast retrieval.

  This is a higher-level action that orchestrates the two-step NWS API process:
  1. Convert location to grid coordinates
  2. Fetch weather forecast for that grid

  Provides a simple interface for getting weather by location in one call.
  """

  use Jido.Action,
    name: "weather_by_location",
    description: "Get weather forecast for any location using NWS API",
    category: "Weather",
    tags: ["weather", "forecast", "location", "nws"],
    vsn: "1.0.0",
    schema: [
      location: [
        type: :string,
        required: true,
        doc: "Location as 'lat,lng' coordinates, zipcode, or 'city,state'"
      ],
      periods: [
        type: :integer,
        default: 7,
        doc: "Number of forecast periods to return"
      ],
      format: [
        type: {:in, [:detailed, :summary, :text]},
        default: :summary,
        doc: "Output format for forecast data"
      ],
      include_location_info: [
        type: :boolean,
        default: false,
        doc: "Include location and grid information in response"
      ]
    ]

  @impl Jido.Action
  def run(params, context) do
    with {:ok, grid_info} <- get_grid_info(params.location, context),
         {:ok, forecast_data} <- get_forecast(grid_info.urls.forecast, params, context) do
      result = build_result(grid_info, forecast_data, params)

      # Return just the text for :text format, or the full result for other formats
      case params[:format] do
        :text -> {:ok, result.forecast}
        _ -> {:ok, result}
      end
    end
  end

  defp get_grid_info(location, context) do
    case Jido.Exec.run(Jido.Tools.Weather.LocationToGrid, %{location: location}, context) do
      {:ok, grid_info} ->
        {:ok, grid_info}

      {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} ->
        {:error, "Failed to get grid info: #{message}"}

      {:error, reason} ->
        {:error, "Failed to get grid info: #{inspect(reason)}"}
    end
  end

  defp get_forecast(forecast_url, params, context) do
    forecast_params = %{
      forecast_url: forecast_url,
      periods: params[:periods] || 7,
      format: if(params[:format] == :text, do: :detailed, else: params[:format])
    }

    case Jido.Exec.run(Jido.Tools.Weather.Forecast, forecast_params, context) do
      {:ok, forecast} ->
        {:ok, forecast}

      {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} ->
        {:error, "Failed to get forecast: #{message}"}

      {:error, reason} ->
        {:error, "Failed to get forecast: #{inspect(reason)}"}
    end
  end

  defp build_result(grid_info, forecast_data, params) do
    base_result = %{
      location: %{
        query: grid_info.location,
        city: grid_info.city,
        state: grid_info.state,
        timezone: grid_info.timezone
      },
      forecast: format_forecast_output(forecast_data.periods, params.format),
      updated: forecast_data.updated
    }

    if params[:include_location_info] do
      Map.put(base_result, :grid_info, grid_info.grid)
    else
      base_result
    end
  end

  defp format_forecast_output(periods, :text) do
    periods
    # Reasonable limit for text format
    |> Enum.take(7)
    |> Enum.map_join("\n\n", fn period ->
      temp_info = "#{period.temperature}°#{period.temperature_unit}"

      base_info = """
      #{period.name}:
      Temperature: #{temp_info}
      Wind: #{period.wind_speed} #{period.wind_direction}
      Conditions: #{period.short_forecast}
      """

      # Add detailed forecast if available
      if Map.has_key?(period, :detailed_forecast) and period.detailed_forecast do
        base_info <> "\nDetails: #{period.detailed_forecast}"
      else
        base_info
      end
      |> String.trim()
    end)
  end

  defp format_forecast_output(periods, _format) do
    periods
  end
end
