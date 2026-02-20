defmodule Jido.AI.Examples.WeatherByLocationToolTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.Examples.Tools.Weather.ByLocation

  setup :set_mimic_from_context

  setup do
    Mimic.copy(Jido.Exec)
    :ok
  end

  test "geocodes non-coordinate input before grid lookup" do
    parent = self()

    Mimic.stub(Jido.Exec, :run, fn
      Jido.Tools.Weather.Geocode, %{location: "Denver"}, _context, _opts ->
        send(parent, :geocode_called)
        {:ok, %{coordinates: "39.7392,-104.9903"}}

      Jido.Tools.Weather.LocationToGrid, %{location: "39.7392,-104.9903"}, _context, _opts ->
        send(parent, :grid_called)

        {:ok,
         %{
           location: "39.7392,-104.9903",
           grid: %{office: "BOU", grid_x: 62, grid_y: 61},
           urls: %{forecast: "https://example.test/forecast"},
           timezone: "America/Denver",
           city: "Denver",
           state: "CO"
         }}

      Jido.Tools.Weather.Forecast,
      %{forecast_url: "https://example.test/forecast", periods: 7, format: :summary},
      _context,
      _opts ->
        send(parent, :forecast_called)
        {:ok, %{periods: [%{name: "Today", short_forecast: "Sunny"}], updated: "2026-02-20T00:00:00Z"}}
    end)

    assert {:ok, result} = ByLocation.run(%{location: "Denver"}, %{})
    assert result.location.query == "Denver"
    assert result.location.resolved_coordinates == "39.7392,-104.9903"

    assert_received :geocode_called
    assert_received :grid_called
    assert_received :forecast_called
  end

  test "uses coordinates directly without geocoding" do
    parent = self()

    Mimic.stub(Jido.Exec, :run, fn
      Jido.Tools.Weather.LocationToGrid, %{location: "39.7392,-104.9903"}, _context, _opts ->
        send(parent, :grid_called)

        {:ok,
         %{
           location: "39.7392,-104.9903",
           grid: %{office: "BOU", grid_x: 62, grid_y: 61},
           urls: %{forecast: "https://example.test/forecast"},
           timezone: "America/Denver",
           city: "Denver",
           state: "CO"
         }}

      Jido.Tools.Weather.Forecast,
      %{forecast_url: "https://example.test/forecast", periods: 7, format: :summary},
      _context,
      _opts ->
        send(parent, :forecast_called)
        {:ok, %{periods: [%{name: "Today", short_forecast: "Sunny"}], updated: "2026-02-20T00:00:00Z"}}
    end)

    assert {:ok, result} = ByLocation.run(%{location: "39.7392,-104.9903"}, %{})
    assert result.location.resolved_coordinates == "39.7392,-104.9903"

    assert_received :grid_called
    assert_received :forecast_called
    refute_received :geocode_called
  end
end
