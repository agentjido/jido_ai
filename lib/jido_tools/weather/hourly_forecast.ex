defmodule Jido.Tools.Weather.HourlyForecast do
  @moduledoc """
  Fetches hourly weather forecast data from the National Weather Service API using ReqTool.

  Provides hour-by-hour weather conditions for more detailed planning needs.
  """

  use Jido.Action,
    name: "weather_hourly_forecast",
    description: "Get hourly weather forecast from NWS API",
    category: "Weather",
    tags: ["weather", "hourly", "forecast", "nws"],
    vsn: "1.0.0",
    schema: [
      hourly_forecast_url: [
        type: :string,
        required: true,
        doc: "NWS hourly forecast URL from LocationToGrid action"
      ],
      hours: [
        type: :integer,
        default: 24,
        doc: "Number of hours to return (max 156)"
      ]
    ]

  @impl Jido.Action
  def run(%{hourly_forecast_url: hourly_forecast_url} = params, _context) do
    req_options = [
      method: :get,
      url: hourly_forecast_url,
      headers: %{
        "User-Agent" => "jido_action/1.0 (weather tool)",
        "Accept" => "application/geo+json"
      }
    ]

    try do
      response = Req.request!(req_options)

      transform_result(%{
        request: %{url: hourly_forecast_url, method: :get, params: params},
        response: %{status: response.status, body: response.body, headers: response.headers}
      })
    rescue
      e -> {:error, "HTTP error: #{Exception.message(e)}"}
    end
  end

  defp transform_result(%{request: %{params: params}, response: %{status: 200, body: body}}) do
    periods = body["properties"]["periods"]
    limited_periods = Enum.take(periods, params[:hours] || 24)

    formatted_periods =
      Enum.map(limited_periods, fn period ->
        %{
          start_time: period["startTime"],
          end_time: period["endTime"],
          temperature: period["temperature"],
          temperature_unit: period["temperatureUnit"],
          wind_speed: period["windSpeed"],
          wind_direction: period["windDirection"],
          short_forecast: period["shortForecast"],
          probability_of_precipitation: get_in(period, ["probabilityOfPrecipitation", "value"]),
          relative_humidity: get_in(period, ["relativeHumidity", "value"]),
          dewpoint: get_in(period, ["dewpoint", "value"])
        }
      end)

    result = %{
      hourly_forecast_url: params.hourly_forecast_url,
      updated: body["properties"]["updated"],
      periods: formatted_periods,
      total_periods: length(periods)
    }

    {:ok, result}
  end

  defp transform_result(%{response: %{status: status, body: body}}) when status != 200 do
    {:error, "NWS hourly forecast API error (#{status}): #{inspect(body)}"}
  end

  defp transform_result(_payload) do
    {:error, "Unexpected hourly forecast response format"}
  end
end
