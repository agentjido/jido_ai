defmodule Dotenvy.Parser do
  @moduledoc """
  This module handles the parsing of the contents of `.env` files into maps with
  string keys. See [Dotenv File Format](docs/dotenv-file-format.md) for details
  on the supported file format.

  This implementation uses parsing over regular expressions for most of its work.
  """
  @behaviour Dotenvy

  # Formalizes parser opts for easier pattern matching
  defmodule Opts do
    @moduledoc false
    # - interpolate?: boolean indicating whether the parser is inside a double-quoted
    #   value where variables like `${FOO}` should be interpolated.
    # - stop_on: indicates the "closing" value the parser shuld look for when accumulating values
    # - key: the key for which the value is being accumulated
    # - sys_cmd_fn: arity 3 function used when processing $()
    # - sys_cmd_opts: options passed as the 3rd arg to `sys_cmd_fn`
    defstruct interpolate?: true,
              stop_on: nil,
              key: nil,
              sys_cmd_fn: nil,
              sys_cmd_opts: []
  end

  @doc """
  Parse the given `contents`, substituting and merging with the given `vars`.

  ## Examples

  If you wish to disable or limit support for executing system commands (i.e. those inside `$()`),
  you can provide a custom `:sys_cmd_fn` option. For example, to disable the feature altogether:

      iex> Dotenvy.Parser.parse(contents, %{}, sys_cmd_fn: fn _cmd, _args, _opts -> {"", 0} end)

  If you wish to limit the available commands, you can customize your function, e.g.

      iex> Dotenvy.Parser.parse(contents, %{}, sys_cmd_fn: fn
        "op", args, opts -> System.cmd("op", args, opts)
        _cmd, _args, _opts -> raise "Command not allowed"
      end)

  ## Options

  - `:sys_cmd_fn` an arity 3 function returning a tuple matching the spec for
    the [System.cmd/3](https://hexdocs.pm/elixir/System.html#cmd/3) function: the
    first element is the raw output and the second represents the exit status (0
    on success). Default: `System.cmd/3`
  - `:sys_cmd_opts` keyword list of options passed as the 3rd arg to the `:sys_cmd_fn`.
  """
  # The parsing bounces between seeking keys and seeking values.
  @impl true
  def parse(contents, vars \\ %{}, opts \\ []) when is_binary(contents) do
    find_key(contents, "", vars, %Opts{
      sys_cmd_fn: Keyword.get(opts, :sys_cmd_fn, &System.cmd/3),
      sys_cmd_opts: Keyword.get(opts, :sys_cmd_opts, [])
    })
  end

  # EOF. Done!
  defp find_key("", acc, vars, _opts) do
    case String.trim(acc) do
      "" -> {:ok, vars}
      _ -> {:error, "Invalid syntax: variable missing value"}
    end
  end

  # Entering a comment
  defp find_key(<<?#, tail::binary>>, _acc, vars, opts) do
    tail
    |> fast_forward_to_line_end()
    |> find_key("", vars, opts)
  end

  # When we hit the equals sign, we look at what we have accumulated
  # to see if it is a valid variable name (i.e. a key).
  defp find_key(<<?=, tail::binary>>, acc, vars, %Opts{} = opts) do
    key =
      acc
      |> String.trim_leading("export ")
      |> String.trim()

    case Regex.match?(~r/(^[a-zA-Z_]+[a-zA-Z0-9_]*$)/, key) do
      true ->
        find_value(tail, "", vars, %{opts | key: key, stop_on: nil})

      _ ->
        {:error, "Invalid variable name syntax: #{inspect(acc)}"}
    end
  end

  defp find_key(<<?\n, tail::binary>>, acc, vars, opts) do
    case String.trim(acc) do
      "" -> find_key(tail, "", vars, opts)
      _ -> {:error, "Invalid syntax for line. No equals sign for key: #{inspect(acc)}"}
    end
  end

  # Shift the char onto the accumulator and keep looking...
  defp find_key(<<char::utf8, tail::binary>>, acc, vars, opts) do
    find_key(tail, acc <> <<char>>, vars, opts)
  end

  # Find a value that corresponds with the key...
  # ''' heredoc opening
  @spec find_value(str :: binary(), acc :: binary(), vars :: map(), opts :: %Opts{}) :: any()
  defp find_value(
         <<?', ?', ?', tail::binary>>,
         acc,
         %{} = vars,
         %Opts{key: key, stop_on: nil} = opts
       ) do
    case String.trim(acc) do
      "" ->
        {tail, acc} = accumulate_rest_of_line(tail, "")

        case String.trim(acc) do
          "" ->
            find_value(tail, "", vars, %{
              opts
              | key: key,
                interpolate?: false,
                stop_on: <<?', ?', ?'>>
            })

          _ ->
            {:error,
             "Key: #{key}: heredoc allows only zero or more whitespace characters followed by a new line after '''"}
        end

      _ ->
        {:error, "Key: #{key}: Improper syntax before opening heredoc: #{inspect(acc)}"}
    end
  end

  # """ heredoc opening
  defp find_value(
         <<?", ?", ?", tail::binary>>,
         acc,
         %{} = vars,
         %Opts{key: key, stop_on: nil} = opts
       ) do
    case String.trim(acc) do
      "" ->
        {tail, acc} = accumulate_rest_of_line(tail, "")

        case String.trim(acc) do
          "" ->
            find_value(tail, "", vars, %{
              opts
              | key: key,
                interpolate?: true,
                stop_on: <<?", ?", ?">>
            })

          _ ->
            {:error,
             "Key: #{key}: heredoc allows only zero or more whitespace characters followed by a new line after \"\"\""}
        end

      _ ->
        {:error, "Key: #{key}: Improper syntax before opening heredoc: #{inspect(acc)}"}
    end
  end

  # heredoc closing (single- or double-quotes)
  defp find_value(
         <<h::binary-size(3), tail::binary>>,
         acc,
         vars,
         %Opts{key: key, stop_on: stop} = opts
       )
       when h == stop and stop != nil do
    {tail, rest_of_line} = accumulate_rest_of_line(tail, "")

    case String.trim(rest_of_line) do
      "" -> find_key(tail, "", Map.put(vars, key, acc), opts)
      _ -> {:error, "Invalid syntax following #{inspect(stop)}: #{inspect(rest_of_line)}"}
    end
  end

  # double-quote quote opening
  defp find_value(
         <<?", tail::binary>>,
         acc,
         vars,
         %Opts{key: key, stop_on: nil} = opts
       ) do
    case String.trim(acc) do
      "" ->
        find_value(tail, "", vars, %{opts | key: key, interpolate?: true, stop_on: <<?">>})

      _ ->
        {:error, "Improper syntax before opening quote: #{inspect(acc)}"}
    end
  end

  # single-quote opening
  defp find_value(
         <<?', tail::binary>>,
         acc,
         vars,
         %Opts{key: key, stop_on: nil} = opts
       ) do
    case String.trim(acc) do
      "" ->
        find_value(tail, "", vars, %{opts | key: key, interpolate?: false, stop_on: <<?'>>})

      _ ->
        {:error, "Improper syntax before opening quote: #{inspect(acc)}"}
    end
  end

  # Comment - ignore the rest of the line
  defp find_value(<<?#, tail::binary>>, acc, vars, %Opts{key: key, stop_on: nil} = opts) do
    tail
    |> fast_forward_to_line_end()
    |> find_key("", Map.put(vars, key, String.trim(acc)), opts)
  end

  # End of un-quoted line, EOF
  defp find_value("", acc, vars, %Opts{key: key, stop_on: nil} = _opts)
       when key != nil do
    {:ok, Map.put(vars, key, String.trim(acc))}
  end

  # End of un-quoted line
  defp find_value(
         <<?\n, tail::binary>>,
         acc,
         vars,
         %Opts{key: key, stop_on: nil} = opts
       )
       when key != nil do
    find_key(tail, "", Map.put(vars, key, String.trim(acc)), opts)
  end

  # Start of variable interpolation e.g. ${FOO}
  defp find_value(<<?$, ?{, tail::binary>>, acc, vars, %Opts{interpolate?: true} = opts) do
    with {:ok, var_name, tail} <- acc_inner_value(tail, "", <<?}>>),
         {:ok, interpolated_val} <- map_fetch(vars, var_name) do
      find_value(tail, acc <> interpolated_val, vars, opts)
    end
  end

  # Start of shell command e.g. $(whoami)
  defp find_value(<<?$, ?(, tail::binary>>, acc, vars, %Opts{interpolate?: true} = opts) do
    with {:ok, inner_value, tail} <- acc_inner_value(tail, "", <<?)>>),
         {:ok, cmd, args} <- parse_cmd_args(inner_value),
         {:ok, returned_value} <- execute_shell_cmd(cmd, args, opts) do
      find_value(tail, acc <> returned_value, vars, opts)
    end
  end

  # closing character
  defp find_value(
         <<h::binary-size(1), tail::binary>>,
         acc,
         vars,
         %Opts{key: key, stop_on: stop} = opts
       )
       when h == stop and stop != nil do
    {tail, rest_of_line} = accumulate_rest_of_line(tail, "")

    case String.trim(rest_of_line) do
      "" ->
        find_key(tail, "", Map.put(vars, key, acc), opts)

      _ ->
        {:error,
         "Invalid syntax for key #{key} following #{inspect(stop)}: #{inspect(rest_of_line)}"}
    end
  end

  # Escape sequences
  # credo:disable-for-lines:19
  defp find_value(
         <<?\\, char::utf8, tail::binary>>,
         acc,
         vars,
         %Opts{interpolate?: true} = opts
       ) do
    case char do
      ?n -> find_value(tail, acc <> "\n", vars, opts)
      ?r -> find_value(tail, acc <> "\r", vars, opts)
      ?t -> find_value(tail, acc <> "\t", vars, opts)
      ?f -> find_value(tail, acc <> "\f", vars, opts)
      ?b -> find_value(tail, acc <> "\b", vars, opts)
      ?" -> find_value(tail, acc <> "\"", vars, opts)
      ?' -> find_value(tail, acc <> "\'", vars, opts)
      ?\\ -> find_value(tail, acc <> "\\", vars, opts)
      ?u -> do_unicode(tail, acc, vars, opts)
      # for any other character, we just drop the backslash
      _ -> find_value(tail, acc <> <<char::utf8>>, vars, opts)
    end
  end

  defp find_value("", _acc, _vars, %Opts{key: key, stop_on: stop} = _opts)
       when key != nil and stop != nil do
    {:error,
     "Could not parse value for #{inspect(key)}. Stop sequence not found: #{inspect(stop)}"}
  end

  # accumulate the char as part of the value and keep going...
  defp find_value(<<char::utf8, tail::binary>>, acc, vars, opts) do
    find_value(tail, acc <> <<char>>, vars, opts)
  end

  # Parses text into a command and args
  defp parse_cmd_args(str) do
    case String.split(str, " ") do
      [""] -> {:error, "Shell command missing arguments; $() cannot be empty."}
      [cmd | args] -> {:ok, cmd, args}
    end
  end

  defp execute_shell_cmd(cmd, args, %Opts{sys_cmd_fn: sys_cmd_fn, sys_cmd_opts: sys_cmd_opts}) do
    case sys_cmd_fn.(cmd, args, sys_cmd_opts) do
      {raw_output, 0} ->
        {:ok, String.trim(raw_output)}

      {_, exit_status} ->
        {:error,
         "Command #{inspect(cmd)} with args #{inspect(args)} returned non-zero exit status: #{exit_status}"}
    end
  end

  # Accumulates a value up to the given `stop` character, e.g. a variable name
  # for variable interpolation e.g. `FOO` in "${FOO}" or `whoami` in "$(whoami)"
  defp acc_inner_value(<<h::binary-size(1), tail::binary>>, acc, stop) when h == stop do
    # done!
    {:ok, String.trim(acc), tail}
  end

  defp acc_inner_value(<<char::utf8, tail::binary>>, acc, stop) do
    # accumulate the char and keep going...
    acc_inner_value(tail, acc <> <<char>>, stop)
  end

  defp acc_inner_value("", _acc, stop) do
    {:error, "Stop sequence not found: #{inspect(stop)}"}
  end

  @spec accumulate_rest_of_line(tail :: binary(), acc :: binary()) :: {binary(), binary()}
  defp accumulate_rest_of_line("", acc), do: {"", acc}
  defp accumulate_rest_of_line(<<?\n, tail::binary>>, acc), do: {tail, acc}

  defp accumulate_rest_of_line(<<?#, tail::binary>>, acc) do
    {fast_forward_to_line_end(tail), acc}
  end

  defp accumulate_rest_of_line(<<char::utf8, tail::binary>>, acc) do
    accumulate_rest_of_line(tail, acc <> <<char>>)
  end

  defp do_unicode(<<hex_chars::binary-size(4), tail::binary>>, acc, vars, %Opts{key: key} = opts) do
    case Integer.parse(hex_chars, 16) do
      {as_integer, ""} -> find_value(tail, acc <> <<as_integer::utf8>>, vars, opts)
      _ -> {:error, "Invalid unicode format for key #{key}: \\u#{hex_chars}"}
    end
  end

  defp do_unicode(_, _, _, %Opts{key: key}) do
    {:error, "Invalid unicode format for key #{key}: incomplete"}
  end

  # Moves the cursor up to the next line, e.g. after a `#`
  # EOF
  defp fast_forward_to_line_end(""), do: ""

  defp fast_forward_to_line_end(<<?\n, tail::binary>>), do: tail

  defp fast_forward_to_line_end(<<_::binary-size(1), tail::binary>>) do
    fast_forward_to_line_end(tail)
  end

  # provides consistent :ok/:error tuple output
  defp map_fetch(vars, varname) do
    with :error <- Map.fetch(vars, varname) do
      {:error, "Could not interpolate variable ${#{varname}}: variable undefined."}
    end
  end
end
