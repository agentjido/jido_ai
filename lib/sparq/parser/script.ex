defmodule Sparq.Parser.Script do
  @moduledoc """
  Parsers for script-specific constructs like character, scene, and beat blocks.
  """
  import NimbleParsec
  alias Sparq.Parser.{Core, Declarations, Tokens}

  # Keywords
  def keyword(word) do
    string(word)
    |> map({Tokens, :wrap_keyword, []})
  end

  # String literals
  def string_literal do
    ignore(string("\""))
    |> utf8_string([not: ?"], min: 0)
    |> ignore(string("\""))
    |> map({Tokens, :wrap_string, []})
  end

  # Symbols
  def symbol do
    ignore(string(":"))
    |> ascii_string([?a..?z, ?A..?Z, ?0..?9, ?_], min: 1)
    |> map({Tokens, :wrap_symbol, []})
  end

  # Comma
  def comma do
    string(",")
    |> map({Tokens, :wrap_comma, []})
  end

  # Character block
  def character_block do
    keyword("character")
    |> concat(Core.whitespace())
    |> concat(Core.identifier())
    |> concat(Core.whitespace())
    |> concat(keyword("do"))
    |> concat(Core.newline())
    |> wrap()
    |> repeat(
      choice([
        Core.whitespace(),
        Core.comment(),
        Core.newline()
      ])
    )
    |> concat(keyword("end"))
    |> wrap()
    |> map(:build_character_block)
  end

  # Scene block
  def scene_block do
    keyword("scene")
    |> concat(Core.whitespace())
    |> concat(Core.identifier())
    |> concat(Core.whitespace())
    |> concat(keyword("do"))
    |> concat(Core.newline())
    |> wrap()
    |> repeat(
      choice([
        Core.whitespace(),
        beat_block(),
        Core.newline()
      ])
    )
    |> concat(keyword("end"))
    |> wrap()
    |> map(:build_scene_block)
  end

  # Beat block
  def beat_block do
    keyword("beat")
    |> concat(Core.whitespace())
    |> concat(symbol())
    |> concat(Core.whitespace())
    |> concat(keyword("do"))
    |> concat(Core.newline())
    |> wrap()
    |> repeat(
      choice([
        Core.whitespace(),
        say_command(),
        Core.newline()
      ])
    )
    |> concat(keyword("end"))
    |> wrap()
    |> map(:build_beat_block)
  end

  # Say command
  def say_command do
    keyword("say")
    |> concat(Core.whitespace())
    |> concat(Core.identifier())
    |> concat(comma())
    |> concat(Core.whitespace())
    |> concat(string_literal())
    |> wrap()
    |> map(:build_say_command)
  end

  # Declaration or script construct
  def declaration_or_construct do
    choice([
      character_block(),
      scene_block(),
      Declarations.declaration(),
      Core.whitespace(),
      Core.comment(),
      Core.newline()
    ])
  end

  # Script
  def script do
    repeat(declaration_or_construct())
    |> tag(:script)
  end

  # AST builders
  def build_character_block([header | body]) do
    [{:keyword, _, :character}, _ws1, {:identifier, _, name}, _ws2, {:keyword, _, :do}, _nl] =
      header

    body_tokens = Enum.take(body, length(body) - 1)
    {:character, [], [name, body_tokens]}
  end

  def build_scene_block([header | body]) do
    [{:keyword, _, :scene}, _ws1, {:identifier, _, name}, _ws2, {:keyword, _, :do}, _nl] = header
    body_tokens = Enum.take(body, length(body) - 1)
    {:scene, [], [name, body_tokens]}
  end

  def build_beat_block([header | body]) do
    [{:keyword, _, :beat}, _ws1, {:symbol, _, name}, _ws2, {:keyword, _, :do}, _nl] = header
    body_tokens = Enum.take(body, length(body) - 1)
    {:beat, [], [name, body_tokens]}
  end

  def build_say_command([
        {:keyword, _, :say},
        _ws1,
        {:identifier, _, character},
        {:comma, _, _},
        _ws2,
        {:string, _, text}
      ]) do
    {:say, [], [character, text]}
  end
end
