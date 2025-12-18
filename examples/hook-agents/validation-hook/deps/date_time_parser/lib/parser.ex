defmodule DateTimeParser.Parser do
  @moduledoc """
  Interface for the DateTimeParser to use when parsing a string.

  The flow is:

  1. Preflight the string to see if the parser is appropriate. Sometimes the parsing can happen at
    this stage if it's a simple parser, for example it can be done in a single regex. Results of the
    preflight, if needed, can be stored in the `struct.preflight`.
  2. Parse the string. You have `t:context/0` to check if you should return a time, date, or datetime.
    Also make sure you're honoring the user's options supplied in `struct.opts`

  You may create your own parser and use it with the DateTimeParser by creating a module that
  follows this behaviour.
  """

  defstruct [:string, :mod, :preflight, :context, opts: []]

  @type context :: :datetime | :date | :time | :best
  @type t :: %__MODULE__{
          string: String.t(),
          mod: module(),
          context: context(),
          preflight: any(),
          opts: Keyword.t()
        }

  alias DateTimeParser.Parser
  require Logger

  @doc """
  Determine if the string is appropriate to parse with this parser. If not, then other parsers will
  be attempted.
  """
  @callback preflight(t()) :: {:ok, t()} | {:error, :not_compatible}

  @doc """
  Parse the string.
  """
  @callback parse(t()) ::
              {:ok, DateTime.t() | NaiveDateTime.t() | Time.t() | Date.t()} | {:error, any()}

  @default_parsers [Parser.Epoch, Parser.Serial, Parser.Tokenizer]
  @builtin_parsers @default_parsers ++
                     [Parser.DateTime, Parser.DateTimeUS, Parser.Date, Parser.DateUS, Parser.Time]

  @doc false
  def builtin_parsers, do: @builtin_parsers

  @doc false
  def default_parsers, do: @default_parsers

  @doc false
  def build(string, context, opts) do
    parser = %__MODULE__{context: context, string: string, opts: opts}

    {parsers, opts} =
      Keyword.pop(
        opts,
        :parsers,
        Application.get_env(:date_time_parser, :parsers, @default_parsers)
      )

    parsers
    |> Enum.map(&to_parser_mod/1)
    |> Enum.find_value({:error, :no_parser}, fn parser_mod ->
      case parser_mod.preflight(parser) do
        {:ok, parser} ->
          {:ok,
           put_new_mod(%{parser | context: opts[:context] || context, opts: opts}, parser_mod)}

        {:error, _} ->
          false
      end
    end)
  end

  defp put_new_mod(%{mod: nil} = parser, mod), do: %{parser | mod: mod}
  defp put_new_mod(parser, _), do: parser

  defp to_parser_mod(:tokenizer) do
    Logger.info("Using :tokenizer is deprecated. Use DateTimeParser.Parser.Tokenizer instead.")
    Parser.Tokenizer
  end

  defp to_parser_mod(:epoch) do
    Logger.info("Using :epoch is deprecated. Use DateTimeParser.Parser.Epoch instead.")
    Parser.Epoch
  end

  defp to_parser_mod(:serial) do
    Logger.info("Using :serial is deprecated. Use DateTimeParser.Parser.Serial instead.")
    Parser.Serial
  end

  defp to_parser_mod(mod), do: mod

  @doc false
  def first_ok(funs, error_msg) do
    Enum.find_value(
      funs,
      {:error, error_msg},
      fn x ->
        case x.() do
          {:error, _} -> false
          result -> result
        end
      end
    )
  end
end
