defmodule Jido.Tools.Weather.Forecast do
  @moduledoc """
  Fetches detailed weather forecast data from the National Weather Service API using ReqTool.

  Uses the forecast URL obtained from LocationToGrid to get detailed period-by-period
  weather information including temperature, wind, and conditions.
  """

  use Jido.Action,
    name: "weather_forecast",
    description: "Get detailed weather forecast from NWS forecast URL",
    category: "Weather",
    tags: ["weather", "forecast", "nws"],
    vsn: "1.0.0",
    schema: [
      forecast_url: [
        type: :string,
        required: true,
        doc: "NWS forecast URL from LocationToGrid action"
      ],
      periods: [
        type: :integer,
        default: 14,
        doc: "Number of forecast periods to return (max available)"
      ],
      format: [
        type: {:in, [:detailed, :summary]},
        default: :summary,
        doc: "Level of detail in forecast"
      ]
    ]

  @impl Jido.Action
  def run(%{forecast_url: forecast_url} = params, _context) do
    req_options = [
      method: :get,
      url: forecast_url,
      headers: %{
        "User-Agent" => "jido_action/1.0 (weather tool)",
        "Accept" => "application/geo+json"
      }
    ]

    try do
      response = Req.request!(req_options)

      transform_result(%{
        request: %{url: forecast_url, method: :get, params: params},
        response: %{status: response.status, body: response.body, headers: response.headers}
      })
    rescue
      e -> {:error, "HTTP error: #{Exception.message(e)}"}
    end
  end

  defp transform_result(%{request: %{params: params}, response: %{status: 200, body: body}}) do
    periods = body["properties"]["periods"]
    limited_periods = Enum.take(periods, params[:periods] || 14)

    formatted_periods =
      case params[:format] do
        :detailed -> format_detailed_periods(limited_periods)
        _ -> format_summary_periods(limited_periods)
      end

    result = %{
      forecast_url: params.forecast_url,
      updated: body["properties"]["updated"],
      elevation: body["properties"]["elevation"],
      periods: formatted_periods,
      total_periods: length(periods)
    }

    {:ok, result}
  end

  defp transform_result(%{response: %{status: status, body: body}}) when status != 200 do
    {:error, "NWS forecast API error (#{status}): #{inspect(body)}"}
  end

  defp transform_result(_payload) do
    {:error, "Unexpected forecast response format"}
  end

  defp format_summary_periods(periods) do
    Enum.map(periods, fn period ->
      %{
        name: period["name"],
        temperature: period["temperature"],
        temperature_unit: period["temperatureUnit"],
        wind_speed: period["windSpeed"],
        wind_direction: period["windDirection"],
        short_forecast: period["shortForecast"],
        is_daytime: period["isDaytime"]
      }
    end)
  end

  defp format_detailed_periods(periods) do
    Enum.map(periods, fn period ->
      %{
        number: period["number"],
        name: period["name"],
        start_time: period["startTime"],
        end_time: period["endTime"],
        is_daytime: period["isDaytime"],
        temperature: period["temperature"],
        temperature_unit: period["temperatureUnit"],
        temperature_trend: period["temperatureTrend"],
        wind_speed: period["windSpeed"],
        wind_direction: period["windDirection"],
        icon: period["icon"],
        short_forecast: period["shortForecast"],
        detailed_forecast: period["detailedForecast"]
      }
    end)
  end
end
