unless Code.ensure_loaded?(Jido.Tools.Weather.ByLocation) do
  defmodule Jido.Tools.Weather.ByLocation do
    @moduledoc """
    Compatibility wrapper for the example-local weather-by-location tool.
    """

    @delegate_module Jido.AI.Examples.Tools.Weather.ByLocation

    def name, do: apply(@delegate_module, :name, [])
    def description, do: apply(@delegate_module, :description, [])
    def schema, do: apply(@delegate_module, :schema, [])
    def category, do: apply(@delegate_module, :category, [])
    def tags, do: apply(@delegate_module, :tags, [])
    def vsn, do: apply(@delegate_module, :vsn, [])
    def run(params, context), do: apply(@delegate_module, :run, [params, context])
  end
end

unless Code.ensure_loaded?(Jido.Tools.Weather.Geocode) do
  defmodule Jido.Tools.Weather.Geocode do
    @moduledoc """
    Example-local fallback for the legacy weather geocode tool removed from `jido_action`.
    """

    alias Jido.Action.Error

    use Jido.Action,
      name: "weather_geocode",
      description: "Convert a location string to lat,lng coordinates",
      category: "Weather",
      tags: ["weather", "location", "geocode"],
      vsn: "1.0.0",
      schema: [
        location: [
          type: :string,
          required: true,
          doc: "Location as city/state, address, zipcode, or place name"
        ]
      ]

    @deadline_key :__jido_deadline_ms__

    @impl Jido.Action
    def run(%{location: location}, context) do
      req_options = [
        method: :get,
        url: "https://nominatim.openstreetmap.org/search",
        params: %{
          q: location,
          format: "json",
          limit: 1
        },
        headers: %{
          "User-Agent" => "jido_ai/examples weather tool",
          "Accept" => "application/json"
        }
      ]

      with {:ok, req_options} <- apply_deadline_timeout(req_options, context) do
        try do
          response = Req.request!(req_options)
          transform_result(response.status, response.body, location)
        rescue
          error ->
            {:error,
             Error.execution_error("Geocoding HTTP error: #{Exception.message(error)}",
               details: %{type: :geocode_http_error, reason: error}
             )}
        end
      end
    end

    defp transform_result(200, [result | _], _location) do
      lat = parse_coordinate(result["lat"])
      lng = parse_coordinate(result["lon"])

      {:ok,
       %{
         latitude: lat,
         longitude: lng,
         coordinates: "#{lat},#{lng}",
         display_name: result["display_name"]
       }}
    end

    defp transform_result(200, [], location) do
      {:error,
       Error.execution_error("No geocoding results found for location: #{location}",
         details: %{type: :geocode_no_results, reason: %{location: location}}
       )}
    end

    defp transform_result(status, body, _location) do
      {:error,
       Error.execution_error("Geocoding API error (#{status})",
         details: %{type: :geocode_request_failed, status: status, reason: %{status: status, body: body}}
       )}
    end

    defp parse_coordinate(value) when is_binary(value) do
      {float, _} = Float.parse(value)
      Float.round(float, 4)
    end

    defp parse_coordinate(value) when is_float(value), do: Float.round(value, 4)
    defp parse_coordinate(value) when is_integer(value), do: value / 1

    defp apply_deadline_timeout(req_options, context) do
      case context[@deadline_key] do
        deadline_ms when is_integer(deadline_ms) ->
          now = System.monotonic_time(:millisecond)
          remaining = deadline_ms - now

          if remaining <= 0 do
            {:error,
             Error.timeout_error("Execution deadline exceeded before geocode request dispatch", %{
               deadline_ms: deadline_ms,
               now_ms: now
             })}
          else
            {:ok, put_receive_timeout(req_options, remaining)}
          end

        _ ->
          {:ok, req_options}
      end
    end

    defp put_receive_timeout(req_options, remaining) do
      case Keyword.get(req_options, :receive_timeout) do
        timeout when is_integer(timeout) and timeout >= 0 ->
          Keyword.put(req_options, :receive_timeout, min(timeout, remaining))

        _ ->
          Keyword.put(req_options, :receive_timeout, remaining)
      end
    end
  end
end

unless Code.ensure_loaded?(Jido.Tools.Weather.LocationToGrid) do
  defmodule Jido.Tools.Weather.LocationToGrid do
    @moduledoc """
    Example-local fallback for the legacy NWS grid lookup tool removed from `jido_action`.
    """

    alias Jido.Action.Error

    use Jido.Action,
      name: "weather_location_to_grid",
      description: "Convert location to NWS grid coordinates and forecast URLs",
      category: "Weather",
      tags: ["weather", "location", "nws"],
      vsn: "1.0.0",
      schema: [
        location: [
          type: :string,
          required: true,
          doc: "Location as 'lat,lng' coordinates"
        ]
      ]

    @deadline_key :__jido_deadline_ms__

    @impl Jido.Action
    def run(%{location: location} = params, context) do
      req_options = [
        method: :get,
        url: "https://api.weather.gov/points/#{location}",
        headers: %{
          "User-Agent" => "jido_ai/examples weather tool",
          "Accept" => "application/geo+json"
        }
      ]

      with {:ok, req_options} <- apply_deadline_timeout(req_options, context) do
        try do
          response = Req.request!(req_options)

          transform_result(%{
            request: %{params: params},
            response: %{status: response.status, body: response.body}
          })
        rescue
          error ->
            {:error,
             Error.execution_error("HTTP error fetching grid location: #{Exception.message(error)}",
               details: %{type: :location_to_grid_http_error, reason: error}
             )}
        end
      end
    end

    defp transform_result(%{request: %{params: params}, response: %{status: 200, body: body}}) do
      properties = body["properties"]

      {:ok,
       %{
         location: params[:location],
         grid: %{
           office: properties["gridId"],
           grid_x: properties["gridX"],
           grid_y: properties["gridY"]
         },
         urls: %{
           forecast: properties["forecast"],
           forecast_hourly: properties["forecastHourly"],
           forecast_grid_data: properties["forecastGridData"],
           observation_stations: properties["observationStations"]
         },
         timezone: properties["timeZone"],
         city: get_in(properties, ["relativeLocation", "properties", "city"]),
         state: get_in(properties, ["relativeLocation", "properties", "state"])
       }}
    end

    defp transform_result(%{response: %{status: status, body: body}}) do
      {:error,
       Error.execution_error("NWS API error (#{status})",
         details: %{type: :location_to_grid_request_failed, status: status, reason: %{status: status, body: body}}
       )}
    end

    defp apply_deadline_timeout(req_options, context) do
      case context[@deadline_key] do
        deadline_ms when is_integer(deadline_ms) ->
          now = System.monotonic_time(:millisecond)
          remaining = deadline_ms - now

          if remaining <= 0 do
            {:error,
             Error.timeout_error("Execution deadline exceeded before grid lookup dispatch", %{
               deadline_ms: deadline_ms,
               now_ms: now
             })}
          else
            {:ok, put_receive_timeout(req_options, remaining)}
          end

        _ ->
          {:ok, req_options}
      end
    end

    defp put_receive_timeout(req_options, remaining) do
      case Keyword.get(req_options, :receive_timeout) do
        timeout when is_integer(timeout) and timeout >= 0 ->
          Keyword.put(req_options, :receive_timeout, min(timeout, remaining))

        _ ->
          Keyword.put(req_options, :receive_timeout, remaining)
      end
    end
  end
end

unless Code.ensure_loaded?(Jido.Tools.Weather.Forecast) do
  defmodule Jido.Tools.Weather.Forecast do
    @moduledoc """
    Example-local fallback for the legacy NWS forecast tool removed from `jido_action`.
    """

    alias Jido.Action.Error

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

    @deadline_key :__jido_deadline_ms__

    @impl Jido.Action
    def run(%{forecast_url: forecast_url} = params, context) do
      req_options = [
        method: :get,
        url: forecast_url,
        headers: %{
          "User-Agent" => "jido_ai/examples weather tool",
          "Accept" => "application/geo+json"
        }
      ]

      with {:ok, req_options} <- apply_deadline_timeout(req_options, context) do
        try do
          response = Req.request!(req_options)

          transform_result(%{
            request: %{params: params},
            response: %{status: response.status, body: response.body}
          })
        rescue
          error ->
            {:error,
             Error.execution_error("HTTP error fetching forecast: #{Exception.message(error)}",
               details: %{type: :forecast_http_error, reason: error}
             )}
        end
      end
    end

    defp transform_result(%{request: %{params: params}, response: %{status: 200, body: body}}) do
      periods = get_in(body, ["properties", "periods"]) || []
      limited_periods = Enum.take(periods, params[:periods] || 14)

      formatted_periods =
        case params[:format] do
          :detailed -> format_detailed_periods(limited_periods)
          _ -> format_summary_periods(limited_periods)
        end

      {:ok,
       %{
         forecast_url: params[:forecast_url],
         updated: get_in(body, ["properties", "updated"]),
         elevation: get_in(body, ["properties", "elevation"]),
         periods: formatted_periods,
         total_periods: length(periods)
       }}
    end

    defp transform_result(%{response: %{status: status, body: body}}) do
      {:error,
       Error.execution_error("NWS forecast API error (#{status})",
         details: %{type: :forecast_request_failed, status: status, reason: %{status: status, body: body}}
       )}
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

    defp apply_deadline_timeout(req_options, context) do
      case context[@deadline_key] do
        deadline_ms when is_integer(deadline_ms) ->
          now = System.monotonic_time(:millisecond)
          remaining = deadline_ms - now

          if remaining <= 0 do
            {:error,
             Error.timeout_error("Execution deadline exceeded before forecast request dispatch", %{
               deadline_ms: deadline_ms,
               now_ms: now
             })}
          else
            {:ok, put_receive_timeout(req_options, remaining)}
          end

        _ ->
          {:ok, req_options}
      end
    end

    defp put_receive_timeout(req_options, remaining) do
      case Keyword.get(req_options, :receive_timeout) do
        timeout when is_integer(timeout) and timeout >= 0 ->
          Keyword.put(req_options, :receive_timeout, min(timeout, remaining))

        _ ->
          Keyword.put(req_options, :receive_timeout, remaining)
      end
    end
  end
end

unless Code.ensure_loaded?(Jido.Tools.Weather.HourlyForecast) do
  defmodule Jido.Tools.Weather.HourlyForecast do
    @moduledoc """
    Example-local fallback for the legacy NWS hourly forecast tool removed from `jido_action`.
    """

    alias Jido.Action.Error

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

    @deadline_key :__jido_deadline_ms__

    @impl Jido.Action
    def run(%{hourly_forecast_url: hourly_forecast_url} = params, context) do
      req_options = [
        method: :get,
        url: hourly_forecast_url,
        headers: %{
          "User-Agent" => "jido_ai/examples weather tool",
          "Accept" => "application/geo+json"
        }
      ]

      with {:ok, req_options} <- apply_deadline_timeout(req_options, context) do
        try do
          response = Req.request!(req_options)

          transform_result(%{
            request: %{params: params},
            response: %{status: response.status, body: response.body}
          })
        rescue
          error ->
            {:error,
             Error.execution_error(
               "HTTP error fetching hourly forecast: #{Exception.message(error)}",
               %{
                 type: :hourly_forecast_http_error,
                 reason: error
               }
             )}
        end
      end
    end

    defp transform_result(%{request: %{params: params}, response: %{status: 200, body: body}}) do
      periods = get_in(body, ["properties", "periods"]) || []
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

      {:ok,
       %{
         hourly_forecast_url: params[:hourly_forecast_url],
         updated: get_in(body, ["properties", "updated"]),
         periods: formatted_periods,
         total_periods: length(periods)
       }}
    end

    defp transform_result(%{response: %{status: status, body: body}}) do
      {:error,
       Error.execution_error("NWS hourly forecast API error (#{status})",
         details: %{type: :hourly_forecast_request_failed, status: status, reason: %{status: status, body: body}}
       )}
    end

    defp apply_deadline_timeout(req_options, context) do
      case context[@deadline_key] do
        deadline_ms when is_integer(deadline_ms) ->
          now = System.monotonic_time(:millisecond)
          remaining = deadline_ms - now

          if remaining <= 0 do
            {:error,
             Error.timeout_error(
               "Execution deadline exceeded before hourly forecast request dispatch",
               %{
                 deadline_ms: deadline_ms,
                 now_ms: now
               }
             )}
          else
            {:ok, put_receive_timeout(req_options, remaining)}
          end

        _ ->
          {:ok, req_options}
      end
    end

    defp put_receive_timeout(req_options, remaining) do
      case Keyword.get(req_options, :receive_timeout) do
        timeout when is_integer(timeout) and timeout >= 0 ->
          Keyword.put(req_options, :receive_timeout, min(timeout, remaining))

        _ ->
          Keyword.put(req_options, :receive_timeout, remaining)
      end
    end
  end
end

unless Code.ensure_loaded?(Jido.Tools.Weather.CurrentConditions) do
  defmodule Jido.Tools.Weather.CurrentConditions do
    @moduledoc """
    Example-local fallback for the legacy current-conditions tool removed from `jido_action`.
    """

    alias Jido.Action.Error

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

    @deadline_key :__jido_deadline_ms__

    @impl Jido.Action
    def run(%{observation_stations_url: observation_stations_url}, context) do
      with {:ok, stations} <- get_observation_stations(observation_stations_url, context) do
        get_current_conditions(List.first(stations), context)
      end
    end

    defp get_observation_stations(stations_url, context) do
      req_options = [
        method: :get,
        url: stations_url,
        headers: %{
          "User-Agent" => "jido_ai/examples weather tool",
          "Accept" => "application/geo+json"
        }
      ]

      with {:ok, req_options} <- apply_deadline_timeout(req_options, context) do
        try do
          response = Req.request!(req_options)

          case response do
            %{status: 200, body: body} ->
              stations =
                (body["features"] || [])
                |> Enum.map(fn feature ->
                  %{
                    id: get_in(feature, ["properties", "stationIdentifier"]),
                    name: get_in(feature, ["properties", "name"]),
                    url: feature["id"]
                  }
                end)

              {:ok, stations}

            %{status: status, body: body} ->
              {:error,
               Error.execution_error("Failed to get observation stations (#{status})",
                 details: %{
                   type: :observation_stations_request_failed,
                   status: status,
                   reason: %{status: status, body: body}
                 }
               )}
          end
        rescue
          error ->
            {:error,
             Error.execution_error(
               "HTTP error getting observation stations: #{Exception.message(error)}",
               details: %{type: :observation_stations_http_error, reason: error}
             )}
        end
      end
    end

    defp get_current_conditions(%{url: station_url}, context) do
      req_options = [
        method: :get,
        url: "#{station_url}/observations/latest",
        headers: %{
          "User-Agent" => "jido_ai/examples weather tool",
          "Accept" => "application/geo+json"
        }
      ]

      with {:ok, req_options} <- apply_deadline_timeout(req_options, context) do
        try do
          response = Req.request!(req_options)

          case response do
            %{status: 200, body: body} ->
              props = body["properties"] || %{}

              {:ok,
               %{
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
               }}

            %{status: status, body: body} ->
              {:error,
               Error.execution_error("Failed to get current conditions (#{status})",
                 details: %{
                   type: :current_conditions_request_failed,
                   status: status,
                   reason: %{status: status, body: body}
                 }
               )}
          end
        rescue
          error ->
            {:error,
             Error.execution_error(
               "HTTP error getting current conditions: #{Exception.message(error)}",
               details: %{type: :current_conditions_http_error, reason: error}
             )}
        end
      end
    end

    defp get_current_conditions(nil, _context) do
      {:error,
       Error.execution_error("No observation stations available",
         details: %{type: :observation_stations_empty, reason: :no_observation_stations}
       )}
    end

    defp format_measurement(%{"value" => nil}), do: nil

    defp format_measurement(%{"value" => value, "unitCode" => unit_code}) do
      %{value: value, unit: parse_unit_code(unit_code)}
    end

    defp format_measurement(nil), do: nil

    defp parse_unit_code("wmoUnit:" <> unit), do: unit
    defp parse_unit_code(unit), do: unit

    defp apply_deadline_timeout(req_options, context) do
      case context[@deadline_key] do
        deadline_ms when is_integer(deadline_ms) ->
          now = System.monotonic_time(:millisecond)
          remaining = deadline_ms - now

          if remaining <= 0 do
            {:error,
             Error.timeout_error(
               "Execution deadline exceeded before current conditions request dispatch",
               %{
                 deadline_ms: deadline_ms,
                 now_ms: now
               }
             )}
          else
            {:ok, put_receive_timeout(req_options, remaining)}
          end

        _ ->
          {:ok, req_options}
      end
    end

    defp put_receive_timeout(req_options, remaining) do
      case Keyword.get(req_options, :receive_timeout) do
        timeout when is_integer(timeout) and timeout >= 0 ->
          Keyword.put(req_options, :receive_timeout, min(timeout, remaining))

        _ ->
          Keyword.put(req_options, :receive_timeout, remaining)
      end
    end
  end
end

unless Code.ensure_loaded?(Jido.Tools.Weather) do
  defmodule Jido.Tools.Weather do
    @moduledoc """
    Example-local fallback for the legacy aggregate weather tool removed from `jido_action`.
    """

    use Jido.Action,
      name: "weather",
      description: "Get weather forecast using the National Weather Service API",
      category: "Weather",
      tags: ["weather", "nws", "forecast"],
      vsn: "3.0.0",
      schema: [
        location: [
          type: :string,
          doc: "Location as coordinates (lat,lng) - defaults to Chicago, IL",
          default: "41.8781,-87.6298"
        ],
        periods: [
          type: :integer,
          doc: "Number of forecast periods to return",
          default: 5
        ],
        format: [
          type: {:in, [:text, :map, :detailed]},
          doc: "Output format (text/map/detailed)",
          default: :text
        ]
      ]

    @impl Jido.Action
    def run(params, context) do
      format = params[:format] || :text

      by_location_params = %{
        location: params[:location] || "41.8781,-87.6298",
        periods: params[:periods] || 5,
        format: format,
        include_location_info: false
      }

      case Jido.Exec.run(Jido.Tools.Weather.ByLocation, by_location_params, context, internal_exec_opts(context)) do
        {:ok, weather_data} when format == :text ->
          {:ok, %{forecast: weather_data[:forecast]}}

        {:ok, weather_data} ->
          {:ok, weather_data}

        {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} ->
          {:error, "Failed to fetch weather: #{message}"}

        {:error, reason} ->
          {:error, "Failed to fetch weather: #{inspect(reason)}"}
      end
    end

    defp internal_exec_opts(context) do
      override_opts =
        if is_map(context), do: Map.get(context, :__jido_internal_exec_opts__), else: nil

      case override_opts do
        opts when is_list(opts) -> Keyword.merge([max_retries: 0], opts)
        _ -> [max_retries: 0]
      end
    end
  end
end
