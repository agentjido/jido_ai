defmodule Jido.Tools.Weather.CurrentConditions do
  @moduledoc """
  Gets current weather conditions from nearby NWS observation stations.

  First gets the list of observation stations for a location, then fetches
  the latest conditions from the nearest station using ReqTool architecture.
  """

  use Jido.Action,
    name: "weather_current_conditions",
    description: "Get current weather conditions from nearest NWS observation station",
    category: "Weather",
    tags: ["weather", "current", "conditions", "nws"],
    vsn: "1.0.0",
    schema: [
      observation_stations_url: [
        type: :string,
        required: true,
        doc: "NWS observation stations URL from LocationToGrid action"
      ]
    ]

  @impl Jido.Action
  def run(params, _context) do
    with {:ok, stations} <- get_observation_stations(params.observation_stations_url) do
      get_current_conditions(List.first(stations))
    end
  end

  defp get_observation_stations(stations_url) do
    req_options = [
      method: :get,
      url: stations_url,
      headers: %{
        "User-Agent" => "jido_action/1.0 (weather tool)",
        "Accept" => "application/geo+json"
      }
    ]

    try do
      response = Req.request!(req_options)

      case response do
        %{status: 200, body: body} ->
          stations =
            body["features"]
            |> Enum.map(fn feature ->
              %{
                id: feature["properties"]["stationIdentifier"],
                name: feature["properties"]["name"],
                url: feature["id"]
              }
            end)

          {:ok, stations}

        %{status: status, body: body} ->
          {:error, "Failed to get observation stations (#{status}): #{inspect(body)}"}
      end
    rescue
      e -> {:error, "HTTP error getting stations: #{Exception.message(e)}"}
    end
  end

  defp get_current_conditions(%{url: station_url}) do
    observations_url = "#{station_url}/observations/latest"

    req_options = [
      method: :get,
      url: observations_url,
      headers: %{
        "User-Agent" => "jido_action/1.0 (weather tool)",
        "Accept" => "application/geo+json"
      }
    ]

    try do
      response = Req.request!(req_options)

      case response do
        %{status: 200, body: body} ->
          props = body["properties"]

          conditions = %{
            station: props["station"],
            timestamp: props["timestamp"],
            temperature: format_measurement(props["temperature"]),
            dewpoint: format_measurement(props["dewpoint"]),
            wind_direction: format_measurement(props["windDirection"]),
            wind_speed: format_measurement(props["windSpeed"]),
            wind_gust: format_measurement(props["windGust"]),
            barometric_pressure: format_measurement(props["barometricPressure"]),
            sea_level_pressure: format_measurement(props["seaLevelPressure"]),
            visibility: format_measurement(props["visibility"]),
            max_temperature_last_24_hours: format_measurement(props["maxTemperatureLast24Hours"]),
            min_temperature_last_24_hours: format_measurement(props["minTemperatureLast24Hours"]),
            precipitation_last_hour: format_measurement(props["precipitationLastHour"]),
            precipitation_last_3_hours: format_measurement(props["precipitationLast3Hours"]),
            precipitation_last_6_hours: format_measurement(props["precipitationLast6Hours"]),
            relative_humidity: format_measurement(props["relativeHumidity"]),
            wind_chill: format_measurement(props["windChill"]),
            heat_index: format_measurement(props["heatIndex"]),
            cloud_layers: props["cloudLayers"],
            text_description: props["textDescription"]
          }

          {:ok, conditions}

        %{status: status, body: body} ->
          {:error, "Failed to get current conditions (#{status}): #{inspect(body)}"}
      end
    rescue
      e -> {:error, "HTTP error getting conditions: #{Exception.message(e)}"}
    end
  end

  defp get_current_conditions(nil) do
    {:error, "No observation stations available"}
  end

  defp format_measurement(%{"value" => nil}), do: nil

  defp format_measurement(%{"value" => value, "unitCode" => unit_code}) do
    %{value: value, unit: parse_unit_code(unit_code)}
  end

  defp format_measurement(nil), do: nil

  defp parse_unit_code("wmoUnit:" <> unit), do: unit
  defp parse_unit_code(unit), do: unit
end
