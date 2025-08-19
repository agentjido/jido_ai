defmodule Sparq.Parser.Tokens do
  @moduledoc """
  Defines all token types and their wrapping/formatting functions.
  """

  # Token type definitions
  @type token ::
          {:spaces, list(), non_neg_integer()}
          | {:tabs, list(), non_neg_integer()}
          | {:newline, list(), :cr | :lf | :crlf}
          | {:integer, list(), integer()}
          | {:identifier, list(), atom()}
          | {:equals, list(), String.t()}
          | {:line_comment, list(), String.t()}
          | {:block_comment, list(), String.t()}
          | {:keyword, list(), atom()}
          | {:string, list(), String.t()}
          | {:symbol, list(), atom()}
          | {:comma, list(), String.t()}
          | {:character_block, list(), list()}
          | {:scene_block, list(), list()}
          | {:beat_block, list(), list()}
          | {:say_command, list(), list()}

  # Token wrapping helpers
  def wrap_spaces(count), do: {:spaces, [], count}
  def wrap_tabs(count), do: {:tabs, [], count}
  def wrap_newline(type), do: {:newline, [], parse_newline(type)}
  def wrap_integer(value), do: {:integer, [], value}
  def wrap_identifier(value), do: {:identifier, [], String.to_atom(value)}
  def wrap_equals(_), do: {:equals, [], "="}
  def wrap_line_comment(content), do: {:line_comment, [], content}
  def wrap_block_comment(content), do: {:block_comment, [], content}
  def wrap_keyword(value), do: {:keyword, [], String.to_atom(value)}
  def wrap_string(value), do: {:string, [], value}
  def wrap_symbol(value), do: {:symbol, [], String.to_atom(value)}
  def wrap_comma(_), do: {:comma, [], ","}

  # Newline parsing
  defp parse_newline("\r\n"), do: :crlf
  defp parse_newline("\n"), do: :lf
  defp parse_newline("\r"), do: :cr
  defp parse_newline(:crlf), do: :crlf
  defp parse_newline(:lf), do: :lf
  defp parse_newline(:cr), do: :cr

  # Token formatting
  def format(tokens) when is_list(tokens) do
    tokens |> Enum.map(&format_token/1) |> Enum.join()
  end

  defp format_token({:spaces, _, count}), do: String.duplicate(" ", count)
  defp format_token({:tabs, _, count}), do: String.duplicate("\t", count)
  defp format_token({:newline, _, :crlf}), do: "\r\n"
  defp format_token({:newline, _, :lf}), do: "\n"
  defp format_token({:newline, _, :cr}), do: "\r"
  defp format_token({:integer, _, value}), do: to_string(value)
  defp format_token({:identifier, _, value}), do: Atom.to_string(value)
  defp format_token({:equals, _, _}), do: "="
  defp format_token({:line_comment, _, content}), do: "//#{content}"
  defp format_token({:block_comment, _, content}), do: "/*#{content}*/"
  defp format_token({:keyword, _, value}), do: Atom.to_string(value)
  defp format_token({:string, _, value}), do: ~s("#{value}")
  defp format_token({:symbol, _, value}), do: ":#{Atom.to_string(value)}"
  defp format_token({:comma, _, _}), do: ","

  # Block formatting
  defp format_token({:character, _, [name, body]}) do
    [
      "character ",
      Atom.to_string(name),
      " do\n",
      format(body),
      "end"
    ]
    |> Enum.join()
  end

  defp format_token({:scene, _, [name, body]}) do
    [
      "scene ",
      Atom.to_string(name),
      " do\n",
      format(body),
      "end"
    ]
    |> Enum.join()
  end

  defp format_token({:beat, _, [name, body]}) do
    [
      "beat ",
      ":#{Atom.to_string(name)}",
      " do\n",
      format(body),
      "end"
    ]
    |> Enum.join()
  end

  defp format_token({:say, _, [character, text]}) do
    [
      "say ",
      Atom.to_string(character),
      ", ",
      ~s("#{text}")
    ]
    |> Enum.join()
  end

  # Debug helper
  def debug_format(tokens) do
    tokens
    |> Enum.map(&debug_format_token/1)
    |> Enum.join("\n")
  end

  defp debug_format_token({type, meta, value}) do
    "{#{inspect(type)}, #{inspect(meta)}, #{inspect(value)}}"
  end
end
