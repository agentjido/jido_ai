defmodule Kodo.Core.Parsing.ShellParser do
  @moduledoc """
  A robust shell syntax parser using NimbleParsec.
  Supports pipes, redirections, control operators, and proper quoting.
  """

  import NimbleParsec
  alias Kodo.Core.Parsing.ExecutionPlan

  # Basic characters and whitespace
  whitespace = ascii_char([?\s, ?\t, ?\n, ?\r]) |> times(min: 1) |> ignore()
  optional_whitespace = ascii_char([?\s, ?\t, ?\n, ?\r]) |> times(min: 0) |> ignore()

  # Escaped character (backslash followed by any character)
  escaped_char =
    ignore(ascii_char([?\\]))
    |> ascii_char([])
    |> unwrap_and_tag(:escaped)

  # Single-quoted string (no escaping inside, except for single quotes)
  single_quoted =
    ignore(ascii_char([?']))
    |> repeat(ascii_char([{:not, ?'}]))
    |> ignore(ascii_char([?']))
    |> reduce(:chars_to_string)
    |> unwrap_and_tag(:single_quoted)

  # Double-quoted string (allows escaping)
  double_quoted =
    ignore(ascii_char([?"]))
    |> repeat(
      choice([
        escaped_char,
        ascii_char([{:not, ?"}])
      ])
    )
    |> ignore(ascii_char([?"]))
    |> reduce(:join_quoted_chars)
    |> unwrap_and_tag(:double_quoted)

  # Plain unquoted token (no special characters, but allows escaped ones)
  # We'll use specific character ranges instead of negation
  plain_char =
    choice([
      # Alphanumeric
      ascii_char([?A..?Z, ?a..?z, ?0..?9]),
      # Safe punctuation
      ascii_char([?_, ?-, ?., ?/, ?:, ?=, ?+, ?@, ?%])
    ])

  plain_token =
    times(
      choice([
        escaped_char,
        plain_char
      ]),
      min: 1
    )
    |> reduce(:join_token_chars)
    |> unwrap_and_tag(:plain)

  # Any token (quoted or unquoted)
  token =
    choice([
      single_quoted,
      double_quoted,
      plain_token
    ])

  # Word (one or more adjacent tokens)
  word =
    times(token, min: 1)
    |> reduce(:join_tokens)

  # Redirection operators
  redirect_in = string("<") |> unwrap_and_tag(:redirect_in)
  redirect_out = string(">") |> unwrap_and_tag(:redirect_out)
  redirect_append = string(">>") |> unwrap_and_tag(:redirect_append)

  redirection_op = choice([redirect_append, redirect_out, redirect_in])

  # Redirection (operator followed by filename)
  redirection =
    redirection_op
    |> ignore(optional_whitespace)
    |> concat(word)
    |> tag(:redirection)

  # Command with arguments and redirections
  command_segment =
    word
    |> repeat(
      ignore(whitespace)
      |> choice([
        redirection,
        word
      ])
    )
    |> tag(:command)

  # Pipeline (commands separated by pipes)
  pipeline =
    command_segment
    |> repeat(
      ignore(optional_whitespace)
      |> ignore(string("|"))
      |> ignore(optional_whitespace)
      |> concat(command_segment)
    )
    |> tag(:pipeline)

  # Control operators
  and_op = string("&&") |> replace(:and)
  or_op = string("||") |> replace(:or)
  semicolon = string(";") |> replace(:semicolon)
  background = string("&") |> replace(:background)

  control_op = choice([and_op, or_op, semicolon, background])

  # Full command line (pipelines separated by control operators)
  command_line =
    ignore(optional_whitespace)
    |> choice([
      # Empty input case
      eos() |> replace([]),
      # Normal case with pipelines
      pipeline
      |> repeat(
        ignore(optional_whitespace)
        |> concat(control_op)
        |> ignore(optional_whitespace)
        |> concat(pipeline)
      )
      |> optional(
        ignore(optional_whitespace)
        |> concat(control_op)
        |> ignore(optional_whitespace)
      )
    ])
    |> ignore(optional_whitespace)
    |> eos()
    |> tag(:command_line)

  defparsec(:parse_command_line, command_line)

  @doc """
  Parse a shell command line into an execution plan.
  """
  @spec parse(String.t()) :: {:ok, ExecutionPlan.t()} | {:error, String.t()}
  def parse(input) when is_binary(input) do
    case parse_command_line(input) do
      {:ok, [{:command_line, parsed}], "", _, _, _} ->
        execution_plan = build_execution_plan(parsed)
        {:ok, execution_plan}

      {:ok, _, remaining, _, _, _} ->
        {:error, "Unexpected input: #{remaining}"}

      {:error, reason, _remaining, _context, _line, _column} ->
        {:error, "Parse error: #{reason}"}
    end
  end

  # Helper functions for building tokens and execution plans

  defp chars_to_string(chars) do
    chars |> List.to_string()
  end

  defp join_quoted_chars(chars) do
    chars
    |> Enum.map(fn
      {:escaped, char} -> <<char>>
      char when is_integer(char) -> <<char>>
    end)
    |> Enum.join("")
  end

  defp join_token_chars(chars) do
    chars
    |> Enum.map(fn
      {:escaped, char} -> <<char>>
      char when is_integer(char) -> <<char>>
    end)
    |> Enum.join("")
  end

  defp join_tokens(tokens) do
    tokens
    |> Enum.map(fn
      {:plain, text} -> text
      {:single_quoted, text} -> text
      {:double_quoted, text} -> text
    end)
    |> Enum.join("")
  end

  defp build_execution_plan([]) do
    %ExecutionPlan{pipelines: [], control_ops: []}
  end

  defp build_execution_plan(parsed_items) do
    {pipelines, control_ops} = extract_pipelines_and_ops(parsed_items)
    %ExecutionPlan{pipelines: pipelines, control_ops: control_ops}
  end

  defp extract_pipelines_and_ops(items) do
    extract_pipelines_and_ops(items, [], [])
  end

  defp extract_pipelines_and_ops([], pipelines, control_ops) do
    {Enum.reverse(pipelines), Enum.reverse(control_ops)}
  end

  defp extract_pipelines_and_ops([{:pipeline, pipeline_data} | rest], pipelines, control_ops) do
    pipeline = build_pipeline(pipeline_data, false)
    extract_pipelines_and_ops(rest, [pipeline | pipelines], control_ops)
  end

  defp extract_pipelines_and_ops(
         [control_op | [{:pipeline, pipeline_data} | rest]],
         pipelines,
         control_ops
       )
       when control_op in [:and, :or, :semicolon, :background] do
    background? = control_op == :background
    pipeline = build_pipeline(pipeline_data, background?)
    extract_pipelines_and_ops(rest, [pipeline | pipelines], [control_op | control_ops])
  end

  # Handle trailing background operator (e.g., "command &")
  defp extract_pipelines_and_ops([control_op], pipelines, control_ops)
       when control_op in [:and, :or, :semicolon, :background] do
    # Mark the last pipeline as background if it's a background operator
    case control_op do
      :background when pipelines != [] ->
        [last_pipeline | other_pipelines] = pipelines
        updated_pipeline = %{last_pipeline | background?: true}

        {Enum.reverse([updated_pipeline | other_pipelines]),
         Enum.reverse([control_op | control_ops])}

      _ ->
        {Enum.reverse(pipelines), Enum.reverse([control_op | control_ops])}
    end
  end

  defp extract_pipelines_and_ops([_item | rest], pipelines, control_ops) do
    extract_pipelines_and_ops(rest, pipelines, control_ops)
  end

  defp build_pipeline(commands, background?) do
    pipeline_commands =
      commands
      |> Enum.filter(fn {tag, _} -> tag == :command end)
      |> Enum.map(&build_command/1)

    %ExecutionPlan.Pipeline{commands: pipeline_commands, background?: background?}
  end

  defp build_command({:command, command_data}) do
    {command_name, args, redirections} = extract_command_parts(command_data)

    %ExecutionPlan.Command{
      name: command_name,
      args: args,
      redirections: redirections,
      env: nil
    }
  end

  defp extract_command_parts([name | rest]) do
    {args, redirections} =
      rest
      |> Enum.reduce({[], []}, fn
        {:redirection, [op, target]}, {args_acc, redir_acc} ->
          redirection = build_redirection(op, target)
          {args_acc, [redirection | redir_acc]}

        arg, {args_acc, redir_acc} ->
          {[arg | args_acc], redir_acc}
      end)

    {name, Enum.reverse(args), Enum.reverse(redirections)}
  end

  defp build_redirection({op_type, _}, target) do
    type =
      case op_type do
        :redirect_in -> :input
        :redirect_out -> :output
        :redirect_append -> :append
      end

    %ExecutionPlan.Redirection{
      type: type,
      target: target
    }
  end
end
