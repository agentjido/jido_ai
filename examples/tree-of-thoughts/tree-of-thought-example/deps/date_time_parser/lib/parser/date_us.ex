defmodule DateTimeParser.Parser.DateUS do
  @moduledoc """
  Tokenizes the string for date formats. This prioritizes the US format for representing dates.
  """
  @behaviour DateTimeParser.Parser
  alias DateTimeParser.Combinators

  @impl DateTimeParser.Parser
  def preflight(parser), do: {:ok, parser}

  @impl DateTimeParser.Parser
  def parse(%{string: string} = parser) do
    case Combinators.parse_date_us(string) do
      {:ok, tokens, _, _, _, _} ->
        DateTimeParser.Parser.Date.from_tokens(parser, tokens)

      _ ->
        {:error, :failed_to_parse}
    end
  end
end
