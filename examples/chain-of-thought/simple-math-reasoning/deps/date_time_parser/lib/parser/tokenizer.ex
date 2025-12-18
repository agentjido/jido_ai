defmodule DateTimeParser.Parser.Tokenizer do
  @moduledoc """
  This parser doesn't parse, instead it checks the string and assigns the appropriate parser during
  preflight. The appropriate parser is determined by whether there is a `"/"` present in the string,
  and if so it will assume the string is a US-formatted date or datetime, and therefore use the
  US-optimized tokenizer module (ie, `DateTimeParser.Parser.DateUS` or
  `DateTimeParser.Parser.DateTimeUS`) for them. Time will always be parsed with
  `DateTimeParser.Parser.Time`.
  """
  @behaviour DateTimeParser.Parser

  alias DateTimeParser.Parser

  @impl DateTimeParser.Parser
  def preflight(%{string: string, context: context} = parser) do
    {:ok, %{parser | mod: get_token_parser(context, string)}}
  end

  @impl DateTimeParser.Parser
  def parse(_parser) do
    raise DateTimeParser.ParseError, "Cannot parse with DateTimeParser.Parser.Tokenizer"
  end

  defp get_token_parser(:datetime, string) do
    if String.contains?(string, "/") do
      Parser.DateTimeUS
    else
      Parser.DateTime
    end
  end

  defp get_token_parser(:date, string) do
    if String.contains?(string, "/") do
      Parser.DateUS
    else
      Parser.Date
    end
  end

  defp get_token_parser(:time, _string) do
    Parser.Time
  end
end
