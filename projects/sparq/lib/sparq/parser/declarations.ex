defmodule Sparq.Parser.Declarations do
  @moduledoc """
  Parsers for variable declarations and assignments.
  """
  import NimbleParsec
  alias Sparq.Parser.Tokens

  def declaration do
    choice([
      identifier(),
      equals(),
      integer()
    ])
  end

  def identifier do
    ascii_string([?a..?z, ?A..?Z], min: 1)
    |> map({Tokens, :wrap_identifier, []})
  end

  def equals do
    string("=")
    |> map({Tokens, :wrap_equals, []})
  end

  def integer do
    integer(min: 1)
    |> map({Tokens, :wrap_integer, []})
  end
end
