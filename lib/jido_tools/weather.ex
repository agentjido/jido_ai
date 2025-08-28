defmodule Jido.Tools.Weather do
  @moduledoc """
  A tool for fetching weather information via the National Weather Service API.

  Uses the free NWS API (no API key required) to get weather forecasts.
  Default location is Chicago, IL if no location is specified.

  For more advanced usage, see the specific weather modules:
  - `Jido.Tools.Weather.ByLocation` - Unified weather lookup by location
  - `Jido.Tools.Weather.LocationToGrid` - Convert location to NWS grid
  - `Jido.Tools.Weather.Forecast` - Get detailed forecasts
  - `Jido.Tools.Weather.HourlyForecast` - Get hourly forecasts
  - `Jido.Tools.Weather.CurrentConditions` - Get current conditions
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
    location = params[:location] || "41.8781,-87.6298"

    by_location_params = %{
      location: location,
      periods: params[:periods] || 5,
      format: params[:format] || :text,
      include_location_info: false
    }

    case Jido.Exec.run(Jido.Tools.Weather.ByLocation, by_location_params, context) do
      {:ok, weather_data} ->
        {:ok, weather_data}

      {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} ->
        {:error, "Failed to fetch weather: #{message}"}

      {:error, reason} ->
        {:error, "Failed to fetch weather: #{inspect(reason)}"}
    end
  end

  @doc """
  Demo function to test the NWS API implementation.
  Usage in IEx:
    iex> Jido.Tools.Weather.demo()
  """
  @spec demo() :: :ok
  def demo do
    demo_text_format()
    demo_map_format()
    demo_detailed_format()
  end

  defp demo_text_format do
    IO.puts("\n=== Testing NWS API with text format (Chicago) ===")
    handle_demo_result(run(%{format: :text}, %{}))
  end

  defp demo_map_format do
    IO.puts("\n=== Testing NWS API with map format (LA) ===")
    handle_demo_result(run(%{location: "34.0522,-118.2437", format: :map}, %{}))
  end

  defp demo_detailed_format do
    IO.puts("\n=== Testing NWS API with detailed format (NYC) ===")
    handle_demo_result(run(%{location: "40.7128,-74.0060", format: :detailed, periods: 3}, %{}))
  end

  defp handle_demo_result({:ok, %{forecast: forecast}}) when is_binary(forecast),
    do: IO.puts(forecast)

  # credo:disable-for-next-line Credo.Check.Warning.IoInspect
  defp handle_demo_result({:ok, result}), do: IO.inspect(result, label: "Weather Data")
  defp handle_demo_result({:error, error}), do: IO.puts("Error: #{error}")
end
