defmodule DateTimeParser.Parser.DateTimeUS do
  @moduledoc """
  Tokenizes the string for both date and time formats. This prioritizes the US format for
  representing dates.
  """
  @behaviour DateTimeParser.Parser

  alias DateTimeParser.Combinators

  @impl DateTimeParser.Parser
  def preflight(parser), do: {:ok, parser}

  @impl DateTimeParser.Parser
  def parse(%{string: string} = parser) do
    case Combinators.parse_datetime_us(string) do
      {:ok, tokens, _, _, _, _} ->
        DateTimeParser.Parser.DateTime.from_tokens(parser, tokens)

      _ ->
        {:error, :failed_to_parse}
    end
  end
end
