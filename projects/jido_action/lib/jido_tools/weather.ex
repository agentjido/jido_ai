defmodule Jido.Tools.Weather do
  @moduledoc """
  A tool for fetching weather information via the OpenWeatherMap API.

  Supports both test mode (using fake data) and live API calls.
  Can return weather data in either text or map format.
  """

  use Jido.Action,
    name: "weather",
    description: "Get the weather for a given location via the OpenWeatherMap API",
    category: "Weather",
    tags: ["weather"],
    vsn: "1.0.0",
    schema: [
      location: [type: :string, doc: "The location to get the weather for"],
      units: [type: :string, doc: "Units to use (metric/imperial)", default: "metric"],
      hours: [type: :integer, doc: "Number of hours to forecast", default: 24],
      format: [
        type: :string,
        doc: "Output format (text/map)",
        default: "text"
      ],
      test: [
        type: :boolean,
        doc: "Whether to use test data instead of real API",
        default: true
      ]
    ]

  @doc """
  Demo function to test both test and real API cases.
  Usage in IEx:
    iex> Jido.Tools.Weather.demo()
  """
  @spec demo() :: :ok
  @dialyzer {:no_match, demo: 0}
  def demo do
    demo_fake_text()
    demo_fake_map()
    demo_real_api()
  end

  defp demo_fake_text do
    IO.puts("\n=== Testing with fake data (text format) ===")
    handle_demo_result(run(%{location: "any", test: true, format: "text"}, %{}))
  end

  defp demo_fake_map do
    IO.puts("\n=== Testing with fake data (map format) ===")
    handle_demo_result(run(%{location: "any", test: true, format: "map"}, %{}))
  end

  @dialyzer :no_match
  defp demo_real_api do
    IO.puts("\n=== Testing with real API ===")
    handle_demo_result(run(%{location: "60618,US", format: "text"}, %{}))
  end

  defp handle_demo_result({:ok, result}) when is_binary(result), do: IO.puts(result)
  # credo:disable-for-next-line Credo.Check.Warning.IoInspect
  defp handle_demo_result({:ok, result}), do: IO.inspect(result, label: "Weather Data")
  defp handle_demo_result({:error, error}), do: IO.puts("Error: #{error}")

  @doc """
  Fetches weather data for the specified location.

  Returns formatted weather information based on the provided parameters.
  """
  @spec run(map(), map()) :: {:ok, String.t() | map()} | {:error, String.t()}
  def run(params, _context) do
    with {:ok, opts} <- build_opts(params),
         {:ok, response} <- Weather.API.fetch_weather(opts) do
      {:ok, format_response(response.body, params)}
    else
      {:error, error} -> {:error, "Failed to fetch weather: #{inspect(error)}"}
    end
  end

  defp build_opts(%{test: true}) do
    {:ok, Weather.Opts.new!(test: "rain")}
  end

  defp build_opts(params) do
    case System.fetch_env("OPENWEATHER_API_KEY") do
      {:ok, api_key} ->
        {:ok,
         Weather.Opts.new!(
           api_key: api_key,
           zip: params.location,
           units: params.units,
           hours: params.hours,
           twelve: false
         )}

      _ ->
        {:error, "Missing OPENWEATHER_API_KEY environment variable"}
    end
  end

  defp format_response(response, %{format: "map"}) do
    current = response["current"]
    daily = List.first(response["daily"])
    unit = if is_number(current["temp"]) and current["temp"] > 32.0, do: "F", else: "C"

    %{
      current: %{
        temperature: current["temp"],
        feels_like: current["feels_like"],
        humidity: current["humidity"],
        wind_speed: current["wind_speed"],
        conditions: List.first(current["weather"])["description"],
        unit: unit
      },
      forecast: %{
        high: daily["temp"]["max"],
        low: daily["temp"]["min"],
        summary: daily["summary"],
        unit: unit
      }
    }
  end

  defp format_response(response, _params) do
    current = response["current"]
    daily = List.first(response["daily"])

    """
    Current Weather:
    Temperature: #{current["temp"]}°#{if is_number(current["temp"]) and current["temp"] > 32.0, do: "F", else: "C"}
    Feels like: #{current["feels_like"]}°#{if is_number(current["feels_like"]) and current["feels_like"] > 32.0, do: "F", else: "C"}
    Humidity: #{current["humidity"]}%
    Wind: #{current["wind_speed"]} mph
    Conditions: #{List.first(current["weather"])["description"]}

    Today's Forecast:
    High: #{daily["temp"]["max"]}°#{if is_number(daily["temp"]["max"]) and daily["temp"]["max"] > 32.0, do: "F", else: "C"}
    Low: #{daily["temp"]["min"]}°#{if is_number(daily["temp"]["min"]) and daily["temp"]["min"] > 32.0, do: "F", else: "C"}
    Conditions: #{daily["summary"]}
    """
    |> String.trim()
  end
end
