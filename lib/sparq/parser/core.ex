defmodule Sparq.Parser.Core do
  @moduledoc """
  Core parser components like whitespace and comments that are used by all other parsers.
  """
  import NimbleParsec
  alias Sparq.Parser.Tokens

  # Whitespace parsers
  def whitespace do
    choice([spaces(), tabs(), newline()])
  end

  def spaces do
    ascii_char([?\s])
    |> times(min: 1)
    |> reduce({:count_chars, []})
    |> map({Tokens, :wrap_spaces, []})
  end

  def tabs do
    ascii_char([?\t])
    |> times(min: 1)
    |> reduce({:count_chars, []})
    |> map({Tokens, :wrap_tabs, []})
  end

  def newline do
    choice([
      string("\r\n") |> map({Tokens, :wrap_newline, []}),
      string("\n") |> map({Tokens, :wrap_newline, []}),
      string("\r") |> map({Tokens, :wrap_newline, []})
    ])
  end

  # Identifier parser
  def identifier do
    ascii_string([?a..?z, ?A..?Z], 1)
    |> concat(ascii_string([?a..?z, ?A..?Z, ?0..?9, ?_], min: 0))
    |> reduce({Enum, :join, [""]})
    |> map({Tokens, :wrap_identifier, []})
  end

  # Comment parsers
  def comment do
    choice([line_comment(), block_comment()])
  end

  defp line_comment do
    string("//")
    |> concat(utf8_string([not: ?\n, not: ?\r], min: 0))
    |> wrap()
    |> map(:build_line_comment)
  end

  defp block_comment do
    string("/*")
    |> concat(utf8_string([not: ?*, not: ?/], min: 0))
    |> concat(string("*/"))
    |> wrap()
    |> map(:build_block_comment)
  end

  # Helper functions
  def count_chars(chars), do: length(chars)

  # Comment builders
  def build_line_comment(["//" | [content]]) do
    {:line_comment, [], content}
  end

  def build_block_comment(["/*" | [content | ["*/"]]]) do
    {:block_comment, [], content}
  end
end
