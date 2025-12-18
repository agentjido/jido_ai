defmodule DateTimeParser.Combinators do
  @moduledoc false
  # credo:disable-for-this-file

  @months_map %{
    "january" => 1,
    "february" => 2,
    "march" => 3,
    "april" => 4,
    "may" => 5,
    "june" => 6,
    "july" => 7,
    "august" => 8,
    "september" => 9,
    "october" => 10,
    "november" => 11,
    "december" => 12,
    "jan" => 1,
    "feb" => 2,
    "mar" => 3,
    "apr" => 4,
    "jun" => 6,
    "jul" => 7,
    "aug" => 8,
    "sept" => 9,
    "sep" => 9,
    "oct" => 10,
    "nov" => 11,
    "dec" => 12
  }

  def to_integer(value) when is_binary(value), do: String.to_integer(value)
  def vocal_month_to_numeric_month(value), do: Map.get(@months_map, value)

  # parsec:DateTimeParser.Combinators
  import NimbleParsec

  ### TIMEZONE
  @time_separator ":"
  @utc ~w[utc gmt zulu z]
  @timezone_abbreviations DateTimeParser.TimezoneAbbreviations.all_abbreviations()
                          |> Enum.map(&String.downcase/1)
                          |> Enum.sort_by(&{byte_size(&1), &1}, :desc)

  time_separator = string(@time_separator)

  offset =
    ["+", "-"]
    |> Enum.map(&string/1)
    |> choice()
    |> concat([?0..?9] |> ascii_char() |> times(min: 1, max: 2))
    |> lookahead_not(ascii_char([?/]))
    |> concat(time_separator |> optional() |> ignore())
    |> concat([?0..?9] |> ascii_char() |> times(2) |> optional())
    |> tag(:utc_offset)
    |> label("offset with +/- and 4 digits")

  utc =
    @utc
    |> Enum.map(&string/1)
    |> choice()
    |> eos()
    |> replace("UTC")
    |> unwrap_and_tag(:zone_abbr)
    |> label("timezone with offset")

  utc_plus_offset = concat(utc, offset)

  timezone_abbreviation =
    @timezone_abbreviations
    |> Enum.map(&string/1)
    |> choice()
    |> unwrap_and_tag(:zone_abbr)
    |> label("timezone abbreviation")

  second_letter_of_timezone_abbreviation =
    @timezone_abbreviations
    |> Enum.map(fn abbr -> abbr |> String.codepoints() |> Enum.at(1) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.map(fn char ->
      <<codepoint::utf8>> = char
      codepoint
    end)
    |> ascii_char()

  timezone =
    choice([
      utc_plus_offset,
      utc,
      offset,
      timezone_abbreviation
    ])

  ## TIME

  @hour_num ~w(00 01 02 03 04 05 06 07 08 09) ++ Enum.map(23..0//-1, &to_string/1)
  @second_minute_num ~w(00 01 02 03 04 05 06 07 08 09) ++ Enum.map(59..0//-1, &to_string/1)
  @am_pm ~w(am a.m a.m. a_m pm p.m p.m. p_m a p)

  invalid_time_first_digit = ascii_char([?6..?9])
  space_separator = string(" ")

  hour =
    @hour_num
    |> Enum.map(&string/1)
    |> choice()
    |> lookahead_not(invalid_time_first_digit)
    |> map(:to_integer)
    |> unwrap_and_tag(:hour)
    |> label("numeric hour from 00-23")

  microsecond =
    [?0..?9]
    |> ascii_char()
    |> times(min: 1, max: 24)
    |> tag(:microsecond)
    |> label("numeric subsecond up to 24 digits")

  second_or_minute =
    @second_minute_num
    |> Enum.map(&string/1)
    |> choice()
    |> lookahead_not(invalid_time_first_digit)
    |> map(:to_integer)

  second =
    second_or_minute
    |> unwrap_and_tag(:second)
    |> label("numeric second from 00-59")
    |> concat("." |> string() |> ignore() |> optional())
    |> concat(microsecond |> optional())

  minute =
    second_or_minute
    |> unwrap_and_tag(:minute)
    |> label("numeric minute from 00-59")

  hour_minute =
    hour
    |> concat(time_separator |> ignore())
    |> concat(minute)

  hour_minute_second =
    hour_minute
    |> concat(time_separator |> ignore())
    |> concat(second)

  am_pm =
    @am_pm
    |> Enum.map(&string/1)
    |> choice()
    |> lookahead_not(second_letter_of_timezone_abbreviation)
    |> unwrap_and_tag(:am_pm)
    |> label("am or pm")

  time =
    choice([
      hour_minute_second,
      hour_minute |> lookahead_not(time_separator)
    ])
    |> concat(space_separator |> optional() |> ignore())
    |> concat(am_pm |> optional())

  defparsec(:parse_time, time, inline: true)

  ## DATE

  @days_map %{
    "sun" => "Sunday",
    "mon" => "Monday",
    "tues" => "Tuesday",
    "tue" => "Tuesday",
    "wed" => "Wednesday",
    "weds" => "Wednesday",
    "thurs" => "Thursday",
    "thur" => "Thursday",
    "thu" => "Thursday",
    "fri" => "Friday",
    "sat" => "Saturday"
  }

  @vocal_days_long @days_map
                   |> Map.values()
                   |> Enum.uniq()
                   |> Enum.map(&String.downcase/1)
                   |> Enum.sort_by(&byte_size/1)
                   |> Enum.reverse()
                   |> Enum.map(&string/1)

  @vocal_days_short @days_map
                    |> Map.keys()
                    |> Enum.uniq()
                    |> Enum.map(&String.downcase/1)
                    |> Enum.sort_by(&byte_size/1)
                    |> Enum.reverse()
                    |> Enum.map(&string/1)
  @date_separator [",", ".", "/", "-", " "]

  year4 =
    [?0..?9]
    |> ascii_char()
    |> times(4)
    |> tag(:year)
    |> label("4 digit year")

  year =
    [?0..?9]
    |> ascii_char()
    |> times(max: 4, min: 2)
    |> tag(:year)
    |> label("2 or 4 digit year")

  vocal_month =
    @months_map
    |> Map.keys()
    |> Enum.sort_by(&byte_size/1)
    |> Enum.reverse()
    |> Enum.map(&string/1)
    |> choice()
    |> concat(string(".") |> optional() |> ignore())
    |> map(:vocal_month_to_numeric_month)
    |> unwrap_and_tag(:month)
    |> label("word month either fully spelled or 3-letter abbreviation")

  numeric_month2 =
    ~w(01 02 03 04 05 06 07 08 09 10 11 12)
    |> Enum.map(&string/1)
    |> choice()

  numeric_month1 =
    1..9
    |> Enum.map(&to_string/1)
    |> Enum.map(&string/1)
    |> choice()
    |> lookahead_not(integer(1))

  numeric_month =
    choice([numeric_month2, numeric_month1])
    |> map(:to_integer)
    |> unwrap_and_tag(:month)
    |> label("numeric month from 01-12")

  ordinal_suffix =
    ~w(st nd rd th)
    |> Enum.map(&string/1)
    |> choice()
    |> ignore()
    |> label("ordinal suffix (st, nd, rd, th)")

  day2 =
    (~w(01 02 03 04 05 06 07 08 09) ++ Enum.map(10..31, &to_string/1))
    |> Enum.map(&string/1)
    |> choice()

  day1 =
    1..9
    |> Enum.map(&to_string/1)
    |> Enum.map(&string/1)
    |> choice()
    |> lookahead_not(integer(1))

  day =
    choice([day2, day1])
    |> concat(ordinal_suffix |> optional())
    |> map(:to_integer)
    |> unwrap_and_tag(:day)
    |> label("numeric day from 01-31")

  date_separator =
    @date_separator
    |> Enum.map(&string/1)
    |> choice()
    |> ignore()
    |> label("date separator")

  month = choice([numeric_month, vocal_month])

  month_day =
    month
    |> concat(date_separator |> optional())
    |> concat(day)

  month_year =
    month
    |> concat(choice([string(" "), string(", ")]) |> ignore() |> optional())
    |> concat(year4)

  day_month =
    day
    |> concat(date_separator |> optional())
    |> concat(month)

  day_long_month_year =
    day
    |> concat(date_separator |> optional())
    |> concat(vocal_month)
    |> concat(date_separator |> optional())
    |> concat(year)

  year4_month_day =
    year4
    |> concat(date_separator |> optional())
    |> concat(month_day)

  year_month_day =
    year
    |> concat(date_separator |> optional())
    |> concat(month_day)

  month_day_year =
    month_day
    |> concat(date_separator |> optional())
    |> concat(year)

  day_month_year4 =
    day_month
    |> concat(date_separator)
    |> concat(year4)

  day_month_year =
    day_month
    |> concat(date_separator |> optional())
    |> concat(year)

  formal_date =
    choice([
      day_long_month_year,
      day_month_year4,
      year_month_day,
      day_month_year,
      month_year,
      month_day_year,
      month_day,
      day_month
    ])

  us_date =
    choice([
      day_long_month_year,
      year4_month_day,
      month_day_year,
      day_month_year,
      month_year,
      year_month_day,
      month_day,
      day_month
    ])

  vocal_day =
    (@vocal_days_long ++ @vocal_days_short)
    |> choice()
    |> unwrap_and_tag(:vocal_day)
    |> label("vocal day spelled out")
    |> concat(space_separator |> optional() |> ignore())

  defparsec(
    :parse_date,
    vocal_day
    |> optional()
    |> concat(formal_date)
  )

  defparsec(
    :parse_date_us,
    vocal_day
    |> optional()
    |> concat(us_date)
  )

  ## DATETIME

  @datetime_separator ~w[t - +] ++ [" "]

  datetime_separator =
    @datetime_separator
    |> Enum.map(&string/1)
    |> choice()

  vocal_month_day_time_year =
    vocal_month
    |> concat(space_separator |> ignore())
    |> concat(day)
    |> concat(space_separator |> ignore())
    |> concat(time)
    |> concat(space_separator |> optional() |> ignore())
    |> concat(year4)

  formal_date_time =
    formal_date
    |> concat(datetime_separator |> optional() |> ignore())
    |> concat(time |> optional())
    |> concat(space_separator |> optional() |> ignore())
    |> concat(timezone |> optional())

  us_date_time =
    us_date
    |> concat(datetime_separator |> optional() |> ignore())
    |> concat(time)
    |> concat(space_separator |> optional() |> ignore())
    |> concat(timezone |> optional())

  defparsec(
    :parse_datetime,
    vocal_day
    |> optional()
    |> choice([
      vocal_month_day_time_year,
      formal_date_time,
      formal_date
    ]),
    export_combinator: true
  )

  defparsec(
    :parse_datetime_us,
    vocal_day
    |> optional()
    |> choice([
      vocal_month_day_time_year,
      us_date_time,
      us_date
    ]),
    export_combinator: true
  )

  # parsec:DateTimeParser.Combinators
end
