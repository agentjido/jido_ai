defmodule Sparq.Parser do
  @moduledoc """
  Main parser module that combines all submodules and provides the public API.
  """
  import NimbleParsec
  alias Sparq.Parser.{Core, Script, Tokens}

  # Import helper functions from Core
  import Core,
    only: [
      count_chars: 1,
      build_line_comment: 1,
      build_block_comment: 1
    ]

  # Import builder functions from Script
  import Script,
    only: [
      build_character_block: 1,
      build_scene_block: 1,
      build_beat_block: 1,
      build_say_command: 1
    ]

  # Define the script parser
  defparsecp(:parse_script, Script.script())

  @whitespace_token_types [:spaces, :newline, :line_comment, :block_comment]

  @doc """
  Parses a script into tokens.
  Returns {:ok, tokens} on success or {:error, reason} on failure.

  Options:
  - include_whitespace: boolean - whether to include whitespace tokens in output (default: true)
  """
  def parse(input, opts \\ []) when is_binary(input) do
    include_whitespace = Keyword.get(opts, :whitespace, true)

    case parse_script(input) do
      {:ok, [{:script, tokens}], "", _, _, _} ->
        tokens = if include_whitespace, do: tokens, else: remove_whitespace(tokens)
        {:ok, tokens}

      {:error, reason, _, _, _, _} ->
        {:error, reason}
    end
  end

  @doc """
  Removes whitespace tokens from the AST.
  """
  def remove_whitespace(tokens) when is_list(tokens) do
    Enum.map(tokens, fn
      {type, meta, children} when is_list(children) ->
        filtered_children =
          children
          |> Enum.map(fn
            list when is_list(list) -> remove_whitespace(list)
            other -> other
          end)
          |> Enum.reject(&is_nil/1)

        {type, meta, filtered_children}

      {type, _, _} when type in @whitespace_token_types ->
        nil

      token ->
        token
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Forward formatting functions to Tokens module
  defdelegate format(tokens), to: Tokens
  defdelegate debug_format(tokens), to: Tokens
end
