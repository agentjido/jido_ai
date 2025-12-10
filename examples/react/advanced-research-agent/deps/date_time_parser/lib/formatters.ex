defmodule DateTimeParser.Formatters do
  @moduledoc false

  def format_token(tokens, :hour) do
    case {find_token(tokens, :hour), tokens |> find_token(:am_pm) |> format()} do
      {{:hour, 0}, _} ->
        0

      {{:hour, 12}, "AM"} ->
        0

      {{:hour, hour}, "PM"} when hour < 12 ->
        hour + 12

      {{:hour, hour}, _} ->
        hour

      _ ->
        nil
    end
  end

  def format_token(tokens, :year) do
    case tokens |> find_token(:year) |> format() do
      nil ->
        nil

      year ->
        year |> to_4_year() |> String.to_integer()
    end
  end

  def format_token(tokens, token) do
    tokens |> find_token(token) |> format()
  end

  defp find_token(tokens, find_me) do
    Enum.find(tokens, fn
      {token, _} -> token == find_me
      _ -> false
    end)
  end

  # If the parsed two-digit year is 00 to 49, then
  #  - If the last two digits of the current year are 00 to 49, then the returned year has the same
  #    first two digits as the current year.
  #  - If the last two digits of the current year are 50 to 99, then the first 2 digits of the
  #    returned year are 1 greater than the first 2 digits of the current year.
  # If the parsed two-digit year is 50 to 99, then
  #  - If the last two digits of the current year are 00 to 49, then the first 2 digits of the
  #    returned year are 1 less than the first 2 digits of the current year.
  #  - If the last two digits of the current year are 50 to 99, then the returned year has the same
  #    first two digits as the current year.
  defp to_4_year(parsed_3yr) when byte_size(parsed_3yr) == 3 do
    [current_millenia | _rest] =
      DateTime.utc_now()
      |> Map.get(:year)
      |> Integer.digits()

    "#{current_millenia}#{parsed_3yr}"
  end

  defp to_4_year(parsed_2yr) when byte_size(parsed_2yr) == 2 do
    [current_millenia, current_century, current_decade, current_year] =
      DateTime.utc_now()
      |> Map.get(:year)
      |> Integer.digits()

    parsed_2yr = String.to_integer(parsed_2yr)
    current_2yr = String.to_integer("#{current_decade}#{current_year}")

    cond do
      parsed_2yr < 50 && current_2yr < 50 ->
        "#{current_millenia}#{current_century}#{parsed_2yr}"

      parsed_2yr < 50 && current_2yr >= 50 ->
        [_parsed_millenia, parsed_century] =
          [current_millenia, current_century]
          |> Integer.undigits()
          |> Kernel.+(1)
          |> Integer.digits()

        "#{current_millenia}#{parsed_century}#{parsed_2yr}"

      parsed_2yr >= 50 && current_2yr < 50 ->
        [parsed_millenia, parsed_century] =
          [current_millenia, current_century]
          |> Integer.undigits()
          |> Kernel.-(1)
          |> Integer.digits()

        "#{parsed_millenia}#{parsed_century}#{parsed_2yr}"

      parsed_2yr >= 50 && current_2yr >= 50 ->
        "#{current_millenia}#{current_century}#{parsed_2yr}"
    end
  end

  defp to_4_year(parsed_year), do: parsed_year

  def format({:microsecond, value}) do
    val = value |> to_string |> String.slice(0, 6)

    {
      val |> String.pad_trailing(6, "0") |> String.to_integer(),
      val |> byte_size()
    }
  end

  def format({:zone_abbr, value}), do: String.upcase(value)
  def format({:utc_offset, offset}), do: to_string(offset)
  def format({:year, value}), do: to_string(value)
  def format({:am_pm, value}), do: String.upcase(value)
  def format({_, value}) when is_integer(value), do: value
  def format({_, value}), do: String.to_integer(value)
  def format(_), do: nil

  def clean(string) when is_binary(string) do
    string
    |> String.trim()
    |> String.replace(" @ ", "T")
    |> String.replace(~r{[[:space:]]+}, " ")
    |> String.replace(" - ", "-")
    |> String.replace("//", "/")
    |> String.replace(~r{=|"|'|,|\\}, "")
    |> String.downcase()
  end

  def clean(%{} = map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end
end
