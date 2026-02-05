defmodule Jido.AI.Examples.Tools.ConvertTemperature do
  @moduledoc "Converts temperature between Celsius, Fahrenheit, and Kelvin."

  use Jido.Action,
    name: "convert_temperature",
    description: "Converts temperature between Celsius, Fahrenheit, and Kelvin.",
    schema: [
      value: [type: :float, required: true, doc: "The temperature value to convert"],
      from: [type: :string, required: true, doc: "Source unit: celsius, fahrenheit, or kelvin"],
      to: [type: :string, required: true, doc: "Target unit: celsius, fahrenheit, or kelvin"]
    ]

  @impl true
  def run(params, _context) do
    value = params.value
    from = String.downcase(params.from)
    to = String.downcase(params.to)

    result =
      value
      |> to_celsius(from)
      |> from_celsius(to)

    {:ok, %{result: Float.round(result, 2), from: from, to: to, original: value}}
  end

  defp to_celsius(value, "celsius"), do: value
  defp to_celsius(value, "fahrenheit"), do: (value - 32) * 5 / 9
  defp to_celsius(value, "kelvin"), do: value - 273.15
  defp to_celsius(value, _), do: value

  defp from_celsius(value, "celsius"), do: value
  defp from_celsius(value, "fahrenheit"), do: value * 9 / 5 + 32
  defp from_celsius(value, "kelvin"), do: value + 273.15
  defp from_celsius(value, _), do: value
end

defmodule Jido.AI.Examples.Tools.ConvertDistance do
  @moduledoc "Converts distance between metric and imperial units."

  use Jido.Action,
    name: "convert_distance",
    description: "Converts distance between meters, kilometers, miles, feet, inches, and yards.",
    schema: [
      value: [type: :float, required: true, doc: "The distance value to convert"],
      from: [type: :string, required: true, doc: "Source unit"],
      to: [type: :string, required: true, doc: "Target unit"]
    ]

  @impl true
  def run(params, _context) do
    value = params.value
    from = String.downcase(params.from)
    to = String.downcase(params.to)

    result =
      value
      |> to_meters(from)
      |> from_meters(to)

    {:ok, %{result: Float.round(result, 2), from: from, to: to, original: value}}
  end

  defp to_meters(value, "meters"), do: value
  defp to_meters(value, "kilometers"), do: value * 1000
  defp to_meters(value, "miles"), do: value * 1609.344
  defp to_meters(value, "feet"), do: value * 0.3048
  defp to_meters(value, "inches"), do: value * 0.0254
  defp to_meters(value, "yards"), do: value * 0.9144
  defp to_meters(value, _), do: value

  defp from_meters(value, "meters"), do: value
  defp from_meters(value, "kilometers"), do: value / 1000
  defp from_meters(value, "miles"), do: value / 1609.344
  defp from_meters(value, "feet"), do: value / 0.3048
  defp from_meters(value, "inches"), do: value / 0.0254
  defp from_meters(value, "yards"), do: value / 0.9144
  defp from_meters(value, _), do: value
end

defmodule Jido.AI.Examples.Tools.ConvertWeight do
  @moduledoc "Converts weight between metric and imperial units."

  use Jido.Action,
    name: "convert_weight",
    description: "Converts weight between kilograms, pounds, ounces, grams, and stones.",
    schema: [
      value: [type: :float, required: true, doc: "The weight value to convert"],
      from: [type: :string, required: true, doc: "Source unit"],
      to: [type: :string, required: true, doc: "Target unit"]
    ]

  @impl true
  def run(params, _context) do
    value = params.value
    from = String.downcase(params.from)
    to = String.downcase(params.to)

    result =
      value
      |> to_kilograms(from)
      |> from_kilograms(to)

    {:ok, %{result: Float.round(result, 2), from: from, to: to, original: value}}
  end

  defp to_kilograms(value, "kilograms"), do: value
  defp to_kilograms(value, "grams"), do: value / 1000
  defp to_kilograms(value, "pounds"), do: value * 0.453592
  defp to_kilograms(value, "ounces"), do: value * 0.0283495
  defp to_kilograms(value, "stones"), do: value * 6.35029
  defp to_kilograms(value, _), do: value

  defp from_kilograms(value, "kilograms"), do: value
  defp from_kilograms(value, "grams"), do: value * 1000
  defp from_kilograms(value, "pounds"), do: value / 0.453592
  defp from_kilograms(value, "ounces"), do: value / 0.0283495
  defp from_kilograms(value, "stones"), do: value / 6.35029
  defp from_kilograms(value, _), do: value
end
