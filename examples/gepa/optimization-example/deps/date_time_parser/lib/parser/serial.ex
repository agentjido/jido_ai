defmodule DateTimeParser.Parser.Serial do
  @moduledoc """
  Parses a spreadsheet Serial timestamp. This is gated by the number of present digits. It must
  contain 1 through 5 digits that represent days, with an optional precision of up to 10 digits that
  represents time. Negative serial timestamps are supported.

  Microsoft Excel has, since its earliest versions, incorrectly considered 1900 to be a leap year,
  and therefore that February 29, 1900 comes between February 28 and March 1 of that year. The bug
  originated from Lotus 1-2-3 and was purposely implemented in Excel for the purpose of backward
  compatibility. Microsoft has written an article about this bug, explaining the reasons for
  treating 1900 as a leap year. This bug has been promoted into a requirement in the Ecma Office
  Open XML (OOXML) specification.

  Microsoft Excel on Macintosh defaults to using the 1904 date system. By default, this parser will
  assume the 1900. If you want to opt-into the 1904 date system, see the `t:use_1904_date_system`
  option.

  See more at https://en.wikipedia.org/wiki/Leap_year_bug
  """
  @behaviour DateTimeParser.Parser
  @serial_regex ~r|\A(?<days>-?\d{1,5})(?:\.(?<time>\d{1,10}))?\z|

  @impl DateTimeParser.Parser
  def preflight(%{string: string} = parser) do
    case Regex.named_captures(@serial_regex, string) do
      nil -> {:error, :not_compatible}
      results -> {:ok, %{parser | preflight: results}}
    end
  end

  @impl DateTimeParser.Parser
  @empty ["", nil]
  def parse(%{preflight: %{"time" => time, "days" => day}} = parser) when time in @empty do
    case Integer.parse(day) do
      {num, ""} -> from_tokens(parser, num)
      _ -> {:error, :failed_to_parse_integer}
    end
  end

  def parse(%{string: string} = parser) do
    case Float.parse(string) do
      {num, ""} -> from_tokens(parser, num)
      _ -> {:error, :failed_to_parse_float}
    end
  end

  defp from_tokens(%{context: context, opts: opts}, serial) do
    with serial <- set_date_system(serial, opts),
         {:ok, date_or_datetime} <- from_serial(serial) do
      for_context(context, date_or_datetime, opts[:assume_time])
    end
  end

  defp for_context(:best, result, assume_time) do
    DateTimeParser.Parser.first_ok(
      [
        fn -> for_context(:datetime, result, assume_time) end,
        fn -> for_context(:date, result, assume_time) end,
        fn -> for_context(:time, result, assume_time) end
      ],
      "cannot convert #{inspect(result)} to context :best"
    )
  end

  defp for_context(:datetime, %NaiveDateTime{} = ndt, _), do: {:ok, ndt}
  defp for_context(:datetime, %Date{} = date, true), do: assume_time(date, ~T[00:00:00])
  defp for_context(:datetime, %Date{} = date, %Time{} = time), do: assume_time(date, time)
  defp for_context(:date, %Date{} = date, _), do: {:ok, date}
  defp for_context(:date, %NaiveDateTime{} = ndt, _), do: {:ok, NaiveDateTime.to_date(ndt)}
  defp for_context(:time, %NaiveDateTime{} = ndt, _), do: {:ok, NaiveDateTime.to_time(ndt)}

  defp for_context(context, result, _opts) do
    {:error, "cannot convert #{inspect(result)} to context #{context}"}
  end

  defp from_serial(float) when is_float(float) do
    {serial_date, serial_time} = split_float(float)
    erl_time = time_from_serial(serial_time)
    erl_date = date_from_serial(serial_date)
    NaiveDateTime.from_erl({erl_date, erl_time})
  end

  defp from_serial(integer) when is_integer(integer) do
    erl_date = date_from_serial(integer)
    Date.from_erl(erl_date)
  end

  defp assume_time(%Date{} = date, %Time{} = time) do
    NaiveDateTime.new(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
      time.second,
      time.microsecond
    )
  end

  defp time_from_serial(serial_time) do
    case serial_time do
      zero when zero in [+0.0, -0.0] ->
        {0, 0, 0}

      serial_time ->
        {hours, min_fraction} = split_float(serial_time * 24)
        {minutes, sec_fraction} = split_float(min_fraction * 60)
        {seconds, _microseconds} = split_float(sec_fraction * 60)

        {hours, minutes, seconds}
    end
  end

  defp date_from_serial(serial_date) do
    {1899, 12, 31}
    |> :calendar.date_to_gregorian_days()
    |> Kernel.+(serial_date)
    |> adjust_for_lotus_bug
    |> :calendar.gregorian_days_to_date()
  end

  defp split_float(float) when float >= 0 do
    whole = float |> Float.floor() |> round()
    {whole, float - whole}
  end

  defp split_float(float) when float < 0 do
    whole = abs(float) |> Float.floor() |> round()
    fraction = 1 - (abs(float) - whole)
    fraction = if fraction == 1.0, do: +0.0, else: fraction
    {whole * -1, fraction}
  end

  defp adjust_for_lotus_bug(day) when day > 59, do: day - 1
  defp adjust_for_lotus_bug(day), do: day

  defp set_date_system(serial, opts) do
    if Keyword.get(opts, :use_1904_date_system, false), do: serial + 1462, else: serial
  end
end
