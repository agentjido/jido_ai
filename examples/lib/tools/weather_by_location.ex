defmodule Jido.AI.Examples.Tools.Weather.ByLocation do
  @moduledoc """
  Weather lookup by location with automatic geocoding fallback.

  Accepts either explicit coordinates (`lat,lng`) or a place string (city/state,
  address, zip code). For place strings, the action geocodes first and then
  queries the NWS forecast APIs.
  """

  alias Jido.Action.Error

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

  @coordinates_regex ~r/^\s*-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?\s*$/

  @impl Jido.Action
  def run(params, context) do
    format = normalized_format(params)

    with {:ok, resolved_location} <- resolve_location(params[:location], context),
         {:ok, grid_info} <- get_grid_info(resolved_location, context),
         {:ok, forecast_data} <- get_forecast(grid_info[:urls][:forecast], params, format, context) do
      {:ok, build_result(grid_info, forecast_data, params, format, params[:location], resolved_location)}
    end
  end

  defp resolve_location(location, context) when is_binary(location) do
    normalized = normalize_coordinates(location)

    if coordinate_input?(normalized) do
      {:ok, normalized}
    else
      geocode_location(location, context)
    end
  end

  defp resolve_location(location, _context) do
    {:error,
     Error.execution_error("Location must be a string", %{
       type: :invalid_location_type,
       reason: %{location: location}
     })}
  end

  defp geocode_location(location, context) do
    case Jido.Exec.run(
           Jido.Tools.Weather.Geocode,
           %{location: location},
           context,
           internal_exec_opts(context)
         ) do
      {:ok, %{coordinates: coordinates}} when is_binary(coordinates) ->
        {:ok, normalize_coordinates(coordinates)}

      {:ok, geocode_result} ->
        {:error,
         Error.execution_error("Geocode result did not include coordinates", %{
           type: :geocode_coordinates_missing,
           reason: geocode_result
         })}

      {:error, reason} ->
        {:error,
         Error.execution_error("Failed to geocode location: #{error_message(reason)}", %{
           type: :geocode_failed,
           reason: reason
         })}
    end
  end

  defp get_grid_info(location, context) do
    case Jido.Exec.run(
           Jido.Tools.Weather.LocationToGrid,
           %{location: location},
           context,
           internal_exec_opts(context)
         ) do
      {:ok, grid_info} ->
        {:ok, grid_info}

      {:error, reason} ->
        {:error,
         Error.execution_error("Failed to get grid info: #{error_message(reason)}", %{
           type: :grid_lookup_failed,
           reason: reason
         })}
    end
  end

  defp get_forecast(forecast_url, params, format, context) do
    forecast_params = %{
      forecast_url: forecast_url,
      periods: params[:periods] || 7,
      format: if(format == :text, do: :detailed, else: format)
    }

    case Jido.Exec.run(
           Jido.Tools.Weather.Forecast,
           forecast_params,
           context,
           internal_exec_opts(context)
         ) do
      {:ok, forecast} ->
        {:ok, forecast}

      {:error, reason} ->
        {:error,
         Error.execution_error("Failed to get forecast: #{error_message(reason)}", %{
           type: :forecast_fetch_failed,
           reason: reason
         })}
    end
  end

  defp build_result(grid_info, forecast_data, params, format, query_location, resolved_location) do
    base_result = %{
      location: %{
        query: query_location,
        resolved_coordinates: resolved_location,
        city: grid_info[:city],
        state: grid_info[:state],
        timezone: grid_info[:timezone]
      },
      forecast: format_forecast_output(forecast_data[:periods], format),
      updated: forecast_data[:updated]
    }

    if params[:include_location_info] do
      Map.put(base_result, :grid_info, grid_info[:grid])
    else
      base_result
    end
  end

  defp format_forecast_output(periods, :text) do
    periods
    |> Enum.take(7)
    |> Enum.map_join("\n\n", fn period ->
      temp_info = "#{period[:temperature]}°#{period[:temperature_unit]}"

      base_info = """
      #{period[:name]}:
      Temperature: #{temp_info}
      Wind: #{period[:wind_speed]} #{period[:wind_direction]}
      Conditions: #{period[:short_forecast]}
      """

      if Map.has_key?(period, :detailed_forecast) and period[:detailed_forecast] do
        base_info <> "\nDetails: #{period[:detailed_forecast]}"
      else
        base_info
      end
      |> String.trim()
    end)
  end

  defp format_forecast_output(periods, _format), do: periods

  defp coordinate_input?(location) do
    String.match?(location, @coordinates_regex) and
      case parse_coordinates(location) do
        {:ok, {lat, lng}} ->
          lat >= -90.0 and lat <= 90.0 and lng >= -180.0 and lng <= 180.0

        :error ->
          false
      end
  end

  defp parse_coordinates(location) do
    case String.split(location, ",", parts: 2) do
      [lat_str, lng_str] ->
        with {lat, ""} <- Float.parse(String.trim(lat_str)),
             {lng, ""} <- Float.parse(String.trim(lng_str)) do
          {:ok, {lat, lng}}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp normalize_coordinates(location) do
    case String.split(location, ",", parts: 2) do
      [lat, lng] -> "#{String.trim(lat)},#{String.trim(lng)}"
      _ -> location
    end
  end

  defp normalized_format(params) do
    case params[:format] do
      format when format in [:detailed, :summary, :text] -> format
      _ -> :summary
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

  defp error_message(reason) when is_exception(reason), do: Exception.message(reason)
  defp error_message(reason), do: inspect(reason)
end
