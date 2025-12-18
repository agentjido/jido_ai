defmodule DateTimeParser do
  docs = "README.md" |> File.read!() |> String.split("<!-- MDOC -->") |> Enum.fetch!(1)
  docs = if elem(:os.type(), 0) == :win32, do: String.replace(docs, "\r\n", "\n"), else: docs
  @moduledoc docs
  @external_resource "README.md"

  import DateTimeParser.Formatters
  alias DateTimeParser.Parser

  @type assume_date :: {:assume_date, boolean() | Date.t()}
  @type assume_time :: {:assume_time, boolean() | Time.t()}
  @type assume_utc :: {:assume_utc, boolean()}
  @type assume_tz_abbreviations :: {:assume_utc, map()}
  @type assume_tz_offsets :: {:assume_utc, map()}
  @type use_1904_date_system :: {:use_1904_date_system, boolean()}
  @type to_utc :: {:to_utc, boolean()}

  @typedoc "List of modules that implement the `DateTimeParser.Parser` behaviour."
  @type parsers :: {:parsers, list(atom())}

  @typedoc """
  Options for `parse_datetime/2`

  * `:assume_utc` Default `false`.
  Only applicable for strings where parsing could not determine a timezone. Instead of returning a
  NaiveDateTime, this option will assume them to be in UTC timezone, and therefore return a
  DateTime. If the timezone is determined, then it will continue to be returned in the original
  timezone. See `to_utc` option to also convert it to UTC.

  * `:to_utc` Default `false`.
  If there's a timezone detected in the string, then attempt to convert to UTC timezone. If you
  know that your timestamps are in the future and are going to store it for later use, it may be
  better to convert to UTC and keep the original timestamp since government organizations may change
  timezone rules before the timestamp elapses, therefore making the UTC timestamp wrong or invalid.
  [Check out the guide on future timestamps](./future-utc-datetime.html).

  * `:assume_time` Default `false`.
  If a time cannot be determined, then it will not be assumed by default. If you supply `true`, then
  `~T[00:00:00]` will be assumed. You can also supply your own time, and the found tokens will be
  merged with it.

  * `:use_1904_date_system` Default `false`.
  For Serial timestamps, the parser will use the 1900 Date System by default. If you supply `true`, then
  the 1904 Date System will be used to parse the timestamp.

  * `:assume_tz_offsets`.
  Timezones may be expressed as time offsets, eg "-0400" to represent 4 hours before GMT. The default
  assumption for these offsets is to map them directly to "Etc/GMT-4" when possible. However, you may
  provide your own assumptions. To see the default offets, see
  `DateTimeParser.TimezoneAbbreviations.default_offsets`.

  * `:assume_tz_abbreviations`.
  Timezones may be expressed as timezone abbreviations, eg "EST" can represent Eastern Standard Time.
  The default assumptions for these abbreviations is to map them to the most likely timezone. However,
  you may prefer a different set of timezone assumptions, eg: "CST" means US Central Standard Time by
  default, but you may want it to mean China Standard Time; you would provide: `%{"CST" => "Asia/Shanghai"}`
  To see the default abbreviations, see `DateTimeParser.TimezoneAbbreviations.default_abbreviations`.

  * `:parsers` The parsers to use when analyzing the string. When `Parser.Tokenizer`, the appropriate tokenizer
  will be used depending on the function used and conditions found in the string. **Order matters**
  and determines the order in which parsers are attempted. These are the available built-in parsers:
  #{for parser <- DateTimeParser.Parser.builtin_parsers(), do: "  * `#{inspect(parser)}`\n"}
    This is the default in this order:
  #{for parser <- DateTimeParser.Parser.default_parsers(), do: "  1. `#{inspect(parser)}`\n"}
  """
  @type parse_datetime_options :: [
          assume_utc()
          | to_utc()
          | assume_time()
          | use_1904_date_system()
          | parsers()
          | assume_tz_offsets()
          | assume_tz_abbreviations()
        ]

  @typedoc """
  Options for `parse_date/2`

  * `:assume_date` Default `false`.
  If a date cannot be fully determined, then it will not be assumed by default. If you supply
  `true`, then `Date.utc_today()` will be assumed. You can also supply your own date, and the found
  tokens will be merged with it.
  """
  @type parse_date_options :: [assume_date() | parsers()]

  @typedoc """
  Options for `parse_time/2`.

  See `t:parse_datetime_options/0` for further definition.
  """
  @type parse_time_options :: [parsers()]

  @typedoc """
  Options for `parse/2`.

  Combination of `t:parse_date_options/0` and `t:parse_datetime_options/0` and
  `t:parse_time_options/0`
  """
  @type parse_options :: parse_datetime_options() | parse_date_options() | parse_time_options()

  @doc """
  Parse a `%DateTime{}`, `%NaiveDateTime{}`, `%Date{}`, or `%Time{}` from a string.

  Accepts `t:parse_options/0`
  """
  @spec parse(String.t() | nil, parse_options()) ::
          {:ok, DateTime.t() | NaiveDateTime.t() | Date.t() | Time.t()} | {:error, String.t()}
  def parse(string, opts \\ [])

  def parse(string, opts) when is_binary(string) do
    opts = Keyword.put(opts, :context, :best)

    with {:error, _} <- parse_datetime(string, opts),
         {:error, _} <- parse_date(string, opts) do
      parse_time(string, opts)
    end
  end

  def parse(value, _opts), do: {:error, "Could not parse #{inspect(value)}"}

  @doc """
  Parse a `%DateTime{}`, `%NaiveDateTime{}`, `%Date{}`, or `%Time{}` from a string. Raises a
  `DateTimeParser.ParseError` when parsing fails.

  Accepts `t:parse_options/0`.
  """
  @spec parse!(String.t() | nil, parse_options()) ::
          DateTime.t() | NaiveDateTime.t() | Date.t() | Time.t() | no_return()
  def parse!(string, opts \\ []) do
    case parse(string, opts) do
      {:ok, result} -> result
      {:error, message} -> raise(__MODULE__.ParseError, message)
    end
  end

  @doc """
  Parse a `%DateTime{}` or `%NaiveDateTime{}` from a string.

  Accepts options `t:parse_datetime_options/0`
  """
  @spec parse_datetime(String.t() | nil, parse_datetime_options()) ::
          {:ok, DateTime.t() | NaiveDateTime.t()} | {:error, String.t()}
  def parse_datetime(string, opts \\ [])

  def parse_datetime(string, opts) when is_binary(string) do
    with {:ok, parser} <- string |> clean() |> Parser.build(:datetime, opts),
         {:ok, datetime} <- parser.mod.parse(parser) do
      {:ok, datetime}
    else
      _ ->
        {:error, "Could not parse #{inspect(string)}"}
    end
  end

  def parse_datetime(value, _opts), do: {:error, "Could not parse #{inspect(value)}"}

  @doc """
  Parse a `%DateTime{}` or `%NaiveDateTime{}` from a string. Raises a `DateTimeParser.ParseError` when
  parsing fails.

  Accepts options `t:parse_datetime_options/0`.
  """
  @spec parse_datetime!(String.t() | nil, parse_datetime_options()) ::
          DateTime.t() | NaiveDateTime.t() | no_return()
  def parse_datetime!(string, opts \\ []) do
    case parse_datetime(string, opts) do
      {:ok, result} -> result
      {:error, message} -> raise(__MODULE__.ParseError, message)
    end
  end

  @doc """
  Parse `%Time{}` from a string. Accepts options `t:parse_time_options/0`
  """
  @spec parse_time(String.t() | nil, parse_time_options()) ::
          {:ok, Time.t()} | {:error, String.t()}
  def parse_time(string, opts \\ [])

  def parse_time(string, opts) when is_binary(string) do
    with {:ok, parser} <- string |> clean() |> Parser.build(:time, opts),
         {:ok, time} <- parser.mod.parse(parser) do
      {:ok, time}
    else
      _ ->
        {:error, "Could not parse #{inspect(string)}"}
    end
  end

  def parse_time(value, _opts), do: {:error, "Could not parse #{inspect(value)}"}

  @doc """
  Parse `%Time{}` from a string. Raises a `DateTimeParser.ParseError` when parsing fails.
  """
  @spec parse_time!(String.t() | nil, parse_time_options()) :: Time.t() | no_return()
  def parse_time!(string, opts \\ []) do
    case parse_time(string, opts) do
      {:ok, result} -> result
      {:error, message} -> raise(__MODULE__.ParseError, message)
    end
  end

  @doc """
  Parse `%Date{}` from a string.

  Accepts options `t:parse_date_options/0`
  """
  @spec parse_date(String.t() | nil, parse_date_options()) ::
          {:ok, Date.t()} | {:error, String.t()}
  def parse_date(string, opts \\ [])

  def parse_date(string, opts) when is_binary(string) do
    with {:ok, parser} <- string |> clean() |> Parser.build(:date, opts),
         {:ok, date} <- parser.mod.parse(parser) do
      {:ok, date}
    else
      _ ->
        {:error, "Could not parse #{inspect(string)}"}
    end
  end

  def parse_date(value, _opts), do: {:error, "Could not parse #{inspect(value)}"}

  @doc """
  Parse a `%Date{}` from a string. Raises a `DateTimeParser.ParseError` when parsing fails.

  Accepts options `t:parse_date_options/0`.
  """
  @spec parse_date!(String.t() | nil, parse_datetime_options()) ::
          Date.t() | no_return()
  def parse_date!(string, opts \\ []) do
    case parse_date(string, opts) do
      {:ok, result} -> result
      {:error, message} -> raise(__MODULE__.ParseError, message)
    end
  end
end
