defmodule JidoTest.Tools.WeatherTest do
  use JidoTest.ActionCase, async: false

  import ExUnit.CaptureIO
  import Mimic

  alias Jido.Tools.Weather

  @moduletag :capture_log

  setup :set_mimic_global

  # Valid US coordinates for Chicago (default location)
  @chicago_coords "41.8781,-87.6298"
  # Valid US coordinates for NYC
  @nyc_coords "40.7128,-74.0060"

  # Mock NWS API responses
  defp mock_location_to_grid_response(location) do
    case location do
      @chicago_coords ->
        %{
          status: 200,
          body: %{
            "properties" => %{
              "relativeLocation" => %{
                "properties" => %{
                  "city" => "Chicago",
                  "state" => "IL"
                }
              },
              "timeZone" => "America/Chicago",
              "forecast" => "https://api.weather.gov/gridpoints/LOT/76,73/forecast",
              "forecastHourly" => "https://api.weather.gov/gridpoints/LOT/76,73/forecast/hourly",
              "gridId" => "LOT",
              "gridX" => 76,
              "gridY" => 73
            }
          },
          headers: %{"content-type" => "application/geo+json"}
        }

      @nyc_coords ->
        %{
          status: 200,
          body: %{
            "properties" => %{
              "relativeLocation" => %{
                "properties" => %{
                  "city" => "Hoboken",
                  "state" => "NJ"
                }
              },
              "timeZone" => "America/New_York",
              "forecast" => "https://api.weather.gov/gridpoints/OKX/33,35/forecast",
              "forecastHourly" => "https://api.weather.gov/gridpoints/OKX/33,35/forecast/hourly",
              "gridId" => "OKX",
              "gridX" => 33,
              "gridY" => 35
            }
          },
          headers: %{"content-type" => "application/geo+json"}
        }

      _ ->
        %{
          status: 404,
          body: %{
            "correlationId" => "6a6bbd9",
            "detail" => "'/points/#{location}' is not a valid resource path",
            "instance" => "https://api.weather.gov/requests/6a6bbd9",
            "status" => 404,
            "title" => "Not Found",
            "type" => "https://api.weather.gov/problems/NotFound"
          },
          headers: %{"content-type" => "application/problem+json"}
        }
    end
  end

  defp mock_forecast_response(forecast_url, periods) do
    case forecast_url do
      "https://api.weather.gov/gridpoints/LOT/76,73/forecast" ->
        # Chicago forecast data
        periods_data =
          [
            %{
              "number" => 1,
              "name" => "Tonight",
              "startTime" => "2025-08-24T19:00:00-05:00",
              "endTime" => "2025-08-25T06:00:00-05:00",
              "isDaytime" => false,
              "temperature" => 56,
              "temperatureUnit" => "F",
              "temperatureTrend" => "",
              "windSpeed" => "10 to 15 mph",
              "windDirection" => "NW",
              "icon" => "https://api.weather.gov/icons/land/night/sct?size=medium",
              "shortForecast" => "Partly Cloudy",
              "detailedForecast" =>
                "Partly cloudy, with a low around 56. Northwest wind 10 to 15 mph, with gusts as high as 25 mph."
            },
            %{
              "number" => 2,
              "name" => "Monday",
              "startTime" => "2025-08-25T06:00:00-05:00",
              "endTime" => "2025-08-25T18:00:00-05:00",
              "isDaytime" => true,
              "temperature" => 70,
              "temperatureUnit" => "F",
              "temperatureTrend" => "",
              "windSpeed" => "10 to 15 mph",
              "windDirection" => "NW",
              "icon" => "https://api.weather.gov/icons/land/day/sct?size=medium",
              "shortForecast" => "Mostly Sunny",
              "detailedForecast" =>
                "Mostly sunny, with a high near 70. Northwest wind 10 to 15 mph."
            },
            %{
              "number" => 3,
              "name" => "Monday Night",
              "startTime" => "2025-08-25T18:00:00-05:00",
              "endTime" => "2025-08-26T06:00:00-05:00",
              "isDaytime" => false,
              "temperature" => 57,
              "temperatureUnit" => "F",
              "temperatureTrend" => "",
              "windSpeed" => "10 mph",
              "windDirection" => "NW",
              "icon" => "https://api.weather.gov/icons/land/night/sct?size=medium",
              "shortForecast" => "Partly Cloudy",
              "detailedForecast" =>
                "Partly cloudy, with a low around 57. Northwest wind around 10 mph, with gusts as high as 20 mph."
            }
          ]
          |> Enum.take(periods)

        %{
          status: 200,
          body: %{
            "properties" => %{
              "updated" => nil,
              "periods" => periods_data
            }
          },
          headers: %{"content-type" => "application/geo+json"}
        }

      "https://api.weather.gov/gridpoints/OKX/33,35/forecast" ->
        # NYC forecast data
        periods_data =
          [
            %{
              "number" => 1,
              "name" => "This Afternoon",
              "startTime" => "2025-08-24T14:00:00-04:00",
              "endTime" => "2025-08-24T18:00:00-04:00",
              "isDaytime" => true,
              "temperature" => 78,
              "temperatureUnit" => "F",
              "temperatureTrend" => "",
              "windSpeed" => "16 mph",
              "windDirection" => "S",
              "icon" => "https://api.weather.gov/icons/land/day/bkn?size=medium",
              "shortForecast" => "Partly Sunny",
              "detailedForecast" =>
                "Partly sunny. High near 78, with temperatures falling to around 75 in the afternoon. South wind around 16 mph."
            },
            %{
              "number" => 2,
              "name" => "Tonight",
              "startTime" => "2025-08-24T18:00:00-04:00",
              "endTime" => "2025-08-25T06:00:00-04:00",
              "isDaytime" => false,
              "temperature" => 71,
              "temperatureUnit" => "F",
              "temperatureTrend" => "",
              "windSpeed" => "5 to 14 mph",
              "windDirection" => "S",
              "icon" =>
                "https://api.weather.gov/icons/land/night/bkn/rain_showers,20?size=medium",
              "shortForecast" => "Mostly Cloudy then Slight Chance Rain Showers",
              "detailedForecast" =>
                "A slight chance of rain showers after 2am. Mostly cloudy, with a low around 71. South wind 5 to 14 mph. Chance of precipitation is 20%."
            }
          ]
          |> Enum.take(periods)

        %{
          status: 200,
          body: %{
            "properties" => %{
              "updated" => nil,
              "periods" => periods_data
            }
          },
          headers: %{"content-type" => "application/geo+json"}
        }

      _ ->
        %{
          status: 404,
          body: %{
            "correlationId" => "abc123",
            "detail" => "Forecast not found",
            "status" => 404,
            "title" => "Not Found"
          },
          headers: %{"content-type" => "application/problem+json"}
        }
    end
  end

  defp setup_weather_mocks(location \\ @chicago_coords, periods \\ 5) do
    location_response = mock_location_to_grid_response(location)

    # Use stub to handle multiple calls with the same response
    stub(Req, :request!, fn opts ->
      cond do
        String.contains?(opts[:url], "/points/") ->
          # LocationToGrid call
          expected_url = "https://api.weather.gov/points/#{location}"
          assert opts[:url] == expected_url
          assert opts[:method] == :get
          location_response

        String.contains?(opts[:url], "/forecast") ->
          # Forecast call
          if location_response.status == 200 do
            forecast_url = location_response.body["properties"]["forecast"]
            forecast_response = mock_forecast_response(forecast_url, periods)
            assert opts[:method] == :get
            forecast_response
          else
            # Should not be called if location lookup failed
            raise "Forecast called when location lookup failed"
          end

        true ->
          raise "Unexpected URL: #{opts[:url]}"
      end
    end)
  end

  describe "run/2 basic functionality" do
    test "uses Chicago coordinates as default location with default text format" do
      setup_weather_mocks()

      params = %{}

      assert {:ok, result} = Weather.run(params, %{})
      # Default format is text, so Weather action returns just the forecast string
      assert is_binary(result)
      assert result =~ "Temperature:"
      assert result =~ "°F"
      assert result =~ "Tonight"
      assert result =~ "56°F"
    end

    test "accepts explicit location coordinates" do
      setup_weather_mocks(@nyc_coords)

      params = %{location: @nyc_coords}

      assert {:ok, result} = Weather.run(params, %{})
      # Default format is text, so Weather action returns just the forecast string
      assert is_binary(result)
      assert result =~ "Temperature:"
      assert result =~ "°F"
      assert result =~ "This Afternoon"
      assert result =~ "78°F"
    end

    test "supports different periods parameter" do
      setup_weather_mocks(@chicago_coords, 3)

      params = %{periods: 3}

      assert {:ok, result} = Weather.run(params, %{})
      # Default format is text, so Weather action returns just the forecast string
      assert is_binary(result)
      assert result =~ "Temperature:"
      assert result =~ "°F"
      # Should have 3 periods
      assert result =~ "Tonight"
      assert result =~ "Monday"
      assert result =~ "Monday Night"
    end

    test "supports different format parameters" do
      # Test text format (raw forecast string)
      setup_weather_mocks(@chicago_coords, 2)

      params = %{format: :text, periods: 2}
      assert {:ok, result} = Weather.run(params, %{})
      # Text format returns just the forecast string
      assert is_binary(result)
      assert result =~ "Temperature:"

      # Test summary format (full map structure)
      setup_weather_mocks(@chicago_coords, 2)

      params = %{format: :summary, periods: 2}
      assert {:ok, result} = Weather.run(params, %{})
      # Summary format returns the full map structure
      assert is_map(result)
      assert Map.has_key?(result, :location)
      assert Map.has_key?(result, :forecast)
      assert is_list(result.forecast)
      assert length(result.forecast) == 2

      # Test detailed format (full map structure)
      setup_weather_mocks(@chicago_coords, 2)

      params = %{format: :detailed, periods: 2}
      assert {:ok, result} = Weather.run(params, %{})
      # Detailed format returns the full map structure
      assert is_map(result)
      assert Map.has_key?(result, :location)
      assert Map.has_key?(result, :forecast)
      assert is_list(result.forecast)
      assert length(result.forecast) == 2
    end
  end

  describe "run/2 error handling" do
    test "handles invalid location format gracefully" do
      setup_weather_mocks("invalid_location")

      params = %{location: "invalid_location"}

      assert {:error, error} = Weather.run(params, %{})
      assert is_binary(error)
      assert error =~ "Failed to fetch weather"
      assert error =~ "NWS API error"
    end

    test "handles empty location gracefully" do
      setup_weather_mocks("")

      params = %{location: ""}

      assert {:error, error} = Weather.run(params, %{})
      assert is_binary(error)
      assert error =~ "Failed to fetch weather"
    end

    test "handles invalid format gracefully" do
      # Don't set up mocks since validation should fail before API calls
      params = %{format: :invalid_format}

      assert {:error, error} = Weather.run(params, %{})
      assert is_binary(error)
      assert error =~ "Invalid parameters"
      assert error =~ "expected one of [:detailed, :summary, :text]"
    end
  end

  describe "run/2 format validation" do
    test "validates format parameter options" do
      # Valid formats should not raise validation errors immediately
      for format <- [:text, :summary, :detailed] do
        setup_weather_mocks()

        params = %{format: format}
        assert {:ok, _result} = Weather.run(params, %{})
      end
    end

    test "rejects invalid format options" do
      # This was valid in old API, invalid in new
      params = %{format: :map}

      assert {:error, error} = Weather.run(params, %{})
      assert error =~ "Invalid parameters"
      assert error =~ "expected one of [:detailed, :summary, :text]"
    end
  end

  describe "run/2 result structure" do
    test "returns proper structure for successful calls with summary format" do
      setup_weather_mocks(@chicago_coords, 2)

      params = %{location: @chicago_coords, format: :summary, periods: 2}

      assert {:ok, result} = Weather.run(params, %{})
      # Summary format returns the full map structure
      assert is_map(result)
      assert Map.has_key?(result, :location)
      assert Map.has_key?(result, :forecast)
      assert Map.has_key?(result, :updated)

      # Location should have expected structure
      location = result.location
      assert Map.has_key?(location, :query)
      assert Map.has_key?(location, :city)
      assert Map.has_key?(location, :state)
      assert Map.has_key?(location, :timezone)
      assert location.query == @chicago_coords
      assert location.city == "Chicago"
      assert location.state == "IL"

      # Summary format should return list
      assert is_list(result.forecast)
      assert length(result.forecast) == 2
    end

    test "text format returns raw forecast string" do
      setup_weather_mocks(@chicago_coords, 1)

      params = %{format: :text, periods: 1}

      assert {:ok, result} = Weather.run(params, %{})
      # Text format returns just the forecast string, not a map
      assert is_binary(result)
      assert result =~ "Temperature:"
      assert result =~ "°F"
      assert result =~ "Tonight"
    end

    test "summary and detailed formats return structured data" do
      for format <- [:summary, :detailed] do
        setup_weather_mocks(@chicago_coords, 2)

        params = %{format: format, periods: 2}

        assert {:ok, result} = Weather.run(params, %{})
        # Summary/detailed formats return the full map structure
        assert is_map(result)
        assert Map.has_key?(result, :location)
        forecast = result.forecast
        assert is_list(forecast)
        assert length(forecast) == 2
      end
    end
  end

  describe "demo/0" do
    test "demo function runs without crashing" do
      # Set up mocks for the demo function calls
      # Chicago text format
      setup_weather_mocks(@chicago_coords, 5)

      # LA map format (will fail validation)
      # No mock needed since it fails at parameter validation

      # NYC detailed format
      setup_weather_mocks(@nyc_coords, 3)

      output =
        capture_io(fn ->
          Weather.demo()
        end)

      assert output =~ "Testing NWS API"
    end
  end
end
