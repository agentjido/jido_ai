defmodule DateTimeParser.Parser.Time do
  @moduledoc """
  Tokenizes the string for time elements. This will also attempt to extract the time out of the
  string first before tokenizing to reduce noise in an attempt to be more accurate. For example,

  ```elixir
  iex> DateTimeParser.parse_time("Hello Johnny 5, it's 9:30PM")
  {:ok, ~T[21:30:00]}
  ```

  This will use a regex to extract the part of the string that looks like time, ie, `"9:30PM"`
  """
  @behaviour DateTimeParser.Parser
  @time_regex ~r|(?<time>\d{1,2}:\d{2}(?::\d{2})?(?:.*)?)|

  alias DateTimeParser.Combinators
  import DateTimeParser.Formatters, only: [format_token: 2]

  @impl DateTimeParser.Parser
  def preflight(parser), do: {:ok, parser}

  @impl DateTimeParser.Parser
  def parse(%{string: string} = parser) do
    case string |> extract_time() |> Combinators.parse_time() do
      {:ok, tokens, _, _, _, _} -> from_tokens(parser, tokens)
      _ -> {:error, :failed_to_parse}
    end
  end

  defp from_tokens(%{context: context, opts: opts}, tokens) do
    case Time.new(
           format_token(tokens, :hour) || 0,
           format_token(tokens, :minute) || 0,
           format_token(tokens, :second) || 0,
           format_token(tokens, :microsecond) || {0, 0}
         ) do
      {:ok, time} -> for_context(context, time, Keyword.get(opts, :assume_date, false))
      _ -> {:error, "Could not parse time"}
    end
  end

  @doc false
  def parsed_time?(parsed_values) do
    Enum.all?([parsed_values[:hour], parsed_values[:minute]])
  end

  defp extract_time(string) do
    case Regex.named_captures(@time_regex, string) do
      %{"time" => time} -> time
      _ -> string
    end
  end

  defp for_context(:best, time, %Date{} = date), do: NaiveDateTime.new(date, time)
  defp for_context(:best, time, _), do: {:ok, time}
  defp for_context(:time, time, _), do: {:ok, time}
  defp for_context(:date, time, _), do: {:error, "Could not parse a date from #{inspect(time)}"}

  defp for_context(:datetime, time, _),
    do: {:error, "Could not parse a datetime from #{inspect(time)}"}
end
