defmodule AbnfParsec.Parser do
  import NimbleParsec

  @extra_utf8_range Application.compile_env(:abnf_parsec, :extra_utf8_range, [])

  @moduledoc """
  Abnf Parser.
  """

  rulename_tail = ascii_char([?0..?9, ?a..?z, ?A..?Z, ?-])

  help_space = ascii_string([?\s, ?\t], min: 1)

  comment =
    ignore(string(";"))
    |> optional(ignore(help_space))
    |> repeat_while(utf8_char([?\s, ?\t, 0x21..0x7E] ++ @extra_utf8_range), {:not_cr_lf, []})
    |> ignore(string("\r\n"))
    |> reduce({List, :to_string, []})
    |> unwrap_and_tag(:comment)

  defp not_cr_lf(<<"\r\n", _::binary>>, context, _, _), do: {:halt, context}
  defp not_cr_lf(_, context, _, _), do: {:cont, context}

  c_nl = choice([parsec(:comment), ignore(string("\r\n"))])

  c_wsp = choice([ignore(help_space), c_nl |> ignore(help_space)])

  string_literal =
    ignore(string("\""))
    |> ascii_string([0x20, 0x21, 0x23..0x7E], min: 0)
    |> ignore(string("\""))

  case_insensitive_string_literal =
    ignore(string("%i"))
    |> concat(string_literal)
    |> unwrap_and_tag(:case_insensitive)

  case_sensitive_string_literal =
    ignore(string("%s"))
    |> concat(string_literal)
    |> unwrap_and_tag(:case_sensitive)

  char_val =
    choice([
      string_literal,
      case_insensitive_string_literal,
      case_sensitive_string_literal
    ])

  number = ascii_string([?0..?9, ?A..?F, ?a..?f], min: 1)

  numeric =
    ignore(string("%"))
    |> ascii_string(~c"xbd", 1)
    |> unwrap_and_tag(:base)
    |> concat(number)

  defcombinatorp :num_literal, numeric |> tag(:num_literal)

  num_range =
    numeric
    |> ignore(string("-"))
    |> concat(number)
    |> tag(:num_range)

  num_sequence =
    numeric
    |> times(ignore(string(".")) |> concat(number), min: 1)
    |> tag(:num_sequence)

  num_val = choice([num_range, num_sequence, parsec(:num_literal)])

  rulename =
    ascii_char([?a..?z, ?A..?Z])
    |> repeat(rulename_tail)
    |> reduce({List, :to_string, []})
    |> unwrap_and_tag(:rulename)

  define_as =
    repeat(c_wsp)
    |> choice([string("="), string("=/")])
    |> repeat(c_wsp)

  group =
    ignore(string("("))
    |> ignore(repeat(c_wsp))
    |> concat(parsec(:alternation))
    |> ignore(repeat(c_wsp))
    |> ignore(string(")"))

  option =
    ignore(string("["))
    |> ignore(repeat(c_wsp))
    |> concat(parsec(:alternation))
    |> ignore(repeat(c_wsp))
    |> ignore(string("]"))
    |> tag(:option)

  prose_val =
    ignore(string("<"))
    |> ascii_string([0x20..0x3D, 0x3F..0x7E], min: 1)
    |> ignore(string(">"))
    |> unwrap_and_tag(:prose_val)

  element =
    choice([
      parsec(:rulename),
      parsec(:group),
      parsec(:option),
      parsec(:char_val),
      parsec(:num_val),
      parsec(:exception),
      parsec(:prose_val)
    ])

  repeat_range =
    optional(integer(min: 1) |> unwrap_and_tag(:min))
    |> ignore(string("*"))
    |> optional(integer(min: 1) |> unwrap_and_tag(:max))

  repeat_exact = integer(min: 1) |> unwrap_and_tag(:times)

  repeat_expr = choice([repeat_range, repeat_exact]) |> tag(:repeat)

  repetition =
    optional(repeat_expr)
    |> parsec(:element)
    |> tag(:repetition)
    |> post_traverse({:flatten, []})

  defcombinatorp :ignore_c_wsp, ignore(times(c_wsp, min: 1))

  concatenation =
    parsec(:repetition)
    |> repeat(parsec(:ignore_c_wsp) |> parsec(:repetition))
    |> tag(:concatenation)
    |> post_traverse({:flatten, []})

  alternation =
    parsec(:concatenation)
    |> repeat(
      ignore(repeat(c_wsp) |> string("/") |> repeat(c_wsp))
      |> parsec(:concatenation)
    )
    |> tag(:alternation)
    |> post_traverse({:flatten, []})

  defp flatten(rest, [{tag, [one]}], context, _, _)
       when tag in [:repetition, :concatenation, :alternation] do
    {rest, [one], context}
  end

  defp flatten(rest, args, context, _, _) do
    {rest, args, context}
  end

  elements = parsec(:alternation) |> repeat(c_wsp)

  rule =
    parsec(:rulename)
    |> ignore(define_as)
    |> concat(elements)
    |> concat(c_nl)
    |> tag(:rule)

  rulelist = times(choice([rule, repeat(c_wsp) |> concat(c_nl)]), min: 1)

  def parse(text) do
    text |> normalize() |> rulelist()
  end

  def parse!(text) do
    case parse(text) do
      {:ok, syntax, "", _, _, _} ->
        syntax

      {:ok, _, leftover, _, _, _} ->
        raise AbnfParsec.LeftoverTokenError, "Leftover: #{leftover}"

      {:error, error, _, _, _, _} ->
        raise AbnfParsec.UnexpectedTokenError, error
    end
  end

  def normalize(text) do
    text
    |> String.split(["\r\n", "\n"], trim: true)
    |> Enum.join("\r\n")
    |> Kernel.<>("\r\n")
  end

  defparsec :rulename, rulename
  defparsec :comment, comment
  defparsec :repetition, repetition
  defparsec :option, option
  defparsec :group, group
  defparsec :num_val, num_val
  defparsec :concatenation, concatenation
  defparsec :alternation, alternation
  defparsec :char_val, char_val
  defparsec :prose_val, prose_val
  defparsec :element, element
  defparsec :rule, rule
  defparsec :rulelist, rulelist

  # Extension

  defcombinatorp :one_char_string_literal,
                 ignore(string("\""))
                 |> ascii_string([0x20, 0x21, 0x23..0x7E], 1)
                 |> ignore(string("\""))

  defcombinatorp :rulename_or_char,
                 choice([
                   parsec(:rulename),
                   parsec(:one_char_string_literal),
                   parsec(:num_literal)
                 ])

  exception =
    ignore(string("<any"))
    |> parsec(:ignore_c_wsp)
    |> parsec(:rulename)
    |> parsec(:ignore_c_wsp)
    |> ignore(string("except"))
    |> parsec(:ignore_c_wsp)
    |> parsec(:rulename_or_char)
    |> repeat(
      ignore(
        times(c_wsp, min: 1)
        |> string("and")
        |> times(c_wsp, min: 1)
      )
      |> parsec(:rulename_or_char)
    )
    |> ignore(string(">"))
    |> tag(:exception)

  @doc """
  Extension: Used in RFC3501
  """
  defparsec :exception, exception
end
