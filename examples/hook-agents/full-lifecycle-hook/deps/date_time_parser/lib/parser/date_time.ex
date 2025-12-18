defmodule DateTimeParser.Parser.DateTime do
  @moduledoc """
  Tokenizes the string for both date and time formats. This prioritizes the international standard
  for representing dates.
  """
  @behaviour DateTimeParser.Parser
  alias DateTimeParser.Combinators
  alias DateTimeParser.TimezoneAbbreviations
  import DateTimeParser.Formatters, only: [format_token: 2, clean: 1]

  @impl DateTimeParser.Parser
  def preflight(parser), do: {:ok, parser}

  @impl DateTimeParser.Parser
  def parse(%{string: string} = parser) do
    case Combinators.parse_datetime(string) do
      {:ok, tokens, _, _, _, _} -> from_tokens(parser, tokens)
      _ -> {:error, :failed_to_parse}
    end
  end

  @doc false
  def from_tokens(%{opts: opts}, tokens) do
    parsed_values =
      clean(%{
        year: format_token(tokens, :year),
        month: format_token(tokens, :month),
        day: format_token(tokens, :day),
        hour: format_token(tokens, :hour),
        minute: format_token(tokens, :minute),
        second: format_token(tokens, :second),
        microsecond: format_token(tokens, :microsecond)
      })

    with true <- DateTimeParser.Parser.Date.parsed_date?(parsed_values),
         {:ok, ndt} <- to_naive_date_time(opts, parsed_values),
         {:ok, ndt} <- validate_day(ndt),
         {:ok, dt} <- to_datetime(opts, ndt, tokens) do
      maybe_convert_to_utc(dt, opts)
    end
  end

  @doc false
  def validate_day(ndt), do: DateTimeParser.Parser.Date.validate_day(ndt)

  @doc false
  def from_naive_datetime_and_tokens(opts, naive_datetime, tokens) do
    with timezone when not is_nil(timezone) <- tokens[:zone_abbr] || tokens[:utc_offset],
         {:ok, %{} = timezone_info} <- timezone_from_tokens(tokens, naive_datetime, opts) do
      naive_datetime
      |> DateTime.from_naive!("Etc/UTC")
      |> Map.merge(timezone_info)
    else
      _ -> naive_datetime
    end
  end

  @doc """
  Convert the given NaiveDateTime to a DateTime if the user provided `to_utc: true`. If the result
  is already in UTC, this will pass through.
  """
  def maybe_convert_to_utc(%DateTime{zone_abbr: "Etc/UTC"} = datetime, _opts) do
    {:ok, datetime}
  end

  def maybe_convert_to_utc(%NaiveDateTime{} = naive_datetime, opts) do
    if Keyword.get(opts, :assume_utc, false) do
      naive_datetime
      |> DateTime.from_naive!("Etc/UTC")
      |> maybe_convert_to_utc(opts)
    else
      {:ok, naive_datetime}
    end
  end

  def maybe_convert_to_utc(%DateTime{} = datetime, opts) do
    if Keyword.get(opts, :to_utc, false) do
      DateTime.shift_zone(datetime, "Etc/UTC")
    else
      {:ok, datetime}
    end
  end

  defp to_naive_date_time(opts, parsed_values) do
    case Keyword.get(opts, :assume_time, false) do
      false ->
        if DateTimeParser.Parser.Time.parsed_time?(parsed_values) do
          NaiveDateTime.new(
            parsed_values[:year],
            parsed_values[:month],
            parsed_values[:day],
            parsed_values[:hour],
            parsed_values[:minute],
            parsed_values[:second] || 0,
            parsed_values[:microsecond] || {0, 0}
          )
        else
          {:error, :cannot_assume_time}
        end

      %Time{} = assumed_time ->
        assume_time(parsed_values, assumed_time)

      true ->
        assume_time(parsed_values, ~T[00:00:00])
    end
  end

  defp assume_time(parsed_values, %Time{} = time) do
    NaiveDateTime.new(
      parsed_values[:year],
      parsed_values[:month],
      parsed_values[:day],
      parsed_values[:hour] || time.hour,
      parsed_values[:minute] || time.minute,
      parsed_values[:second] || time.second,
      parsed_values[:microsecond] || time.microsecond
    )
  end

  defp timezone_from_tokens(tokens, naive_datetime, opts) do
    zone = format_token(tokens, :zone_abbr)
    offset = format_token(tokens, :utc_offset)

    timezone_from_zone(zone, naive_datetime, opts) ||
      timezone_from_offset(offset, naive_datetime, opts) ||
      naive_datetime
  end

  defp timezone_from_zone(nil, _naive_datetime, _opts), do: nil

  defp timezone_from_zone(abbr, naive_datetime, opts) do
    with %{name: name} <-
           TimezoneAbbreviations.zone_by_abbreviation(
             abbr,
             Keyword.put(opts, :at, naive_datetime)
           ) do
      DateTime.from_naive(naive_datetime, name)
    end
  end

  defp timezone_from_offset(nil, _naive_datetime, _opts), do: nil

  defp timezone_from_offset(offset, naive_datetime, opts) do
    with %{name: name} <-
           TimezoneAbbreviations.zone_by_offset(offset, Keyword.put(opts, :at, naive_datetime)) do
      DateTime.from_naive(naive_datetime, name)
    end
  end

  defp to_datetime(_opts, %DateTime{} = datetime, _tokens), do: {:ok, datetime}

  defp to_datetime(opts, %NaiveDateTime{} = ndt, tokens) do
    {:ok, from_naive_datetime_and_tokens(opts, ndt, tokens)}
  end

  defp to_datetime(_opts, _error, _tokens), do: :error
end
