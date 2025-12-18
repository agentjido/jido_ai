defmodule Dotenvy do
  @moduledoc """
  `Dotenvy` is an Elixir port of the original [dotenv](https://github.com/bkeepers/dotenv) Ruby gem.

  It is designed to help applications follow the principles of
  the [12-factor app](https://12factor.net/) and its recommendation to store
  configuration in the environment.

  Unlike other configuration helpers, `Dotenvy` enforces no convention for the naming
  of your files: `.env` is a common choice, you may name your configuration files whatever
  you wish.

  See the [Getting Started](docs/getting_started.md) page for more info.
  """

  import Dotenvy.Transformer

  alias Dotenvy.Transformer.Error

  require Logger

  @typedoc """
  An input source may be either a path to an env file or a map with string keys
  and values, e.g. `"envs/.env"` or `%{"FOO" => "bar"}`. This allows users to
  specify a list of env files interspersed with other values from other sources,
  most commonly `System.get_env()`.
  """
  @type input_source :: String.t() | %{optional(String.t()) => String.t()}

  @default_parser Dotenvy.Parser

  @doc """
  A parser implementation should receive the `contents` read from a file,
  a map of `vars` (with string keys, as would come from `System.get_env/0`),
  and a keyword list of `opts`.

  See `Dotenvy.Parser` for the default implementation of this callback.
  """
  @callback parse(contents :: binary(), vars :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, any()}

  defmodule Error do
    @moduledoc """
    This error module can be useful when writing your own custom conversion
    functions because special contextual information will be included with any
    errors.

    ## Examples

    Let's say your configuration needs to supply one of a set of possible values
    (i.e. an enum). We can define a custom function to support this and pass it
    as the second argument to `Dotenvy.env!/2`

        # runtime.exs
        import Config
        import Dotenvy

        size_enum = fn
          "large" -> :large
          "small" -> :small
          _ ->
            raise Dotenvy.Error, message: "allowed size_enum values are large or small"
        end

        config :myapp, :some_bool, env!("SIZE", size_enum)
    """
    defexception message: "non-empty value required"
  end

  @doc """
  Reads an env variable and converts its output or returns a default value.

  > #### Use `env!/2` when possible {: .info}
  >
  > `env!/2` is recommended over `env!/3` because it creates a stronger contract with
  > the environment: your app literally will not start when required env variables are missing.

  If the given `variable` is *set*, its value is converted to the given `type`.
  The provided `default` value is _only_ used when the variable is _not_ set
  (i.e. when it does not exist).

  **The `default` value is returned as-is, without conversion**. This allows
  greater control of the output.

  Conversion is delegated to `Dotenvy.Transformer.to!/2`, which may raise an error.
  See its documentation for a list of supported types.

  This function attempts to read a value from a local data store of sourced values.

  ## Examples

      iex> env!("PORT", :integer, 5432)
      5433

      iex> env!("NOT_SET", :boolean, %{not: "converted"})
      %{not: "converted"}

      iex> System.put_env("HOST", "")
      iex> env!("HOST", :string!, "localhost")
      ** (RuntimeError) Error converting HOST to string!: non-empty value required
  """
  @doc since: "0.3.0"
  @spec env!(
          variable :: binary(),
          type :: Dotenvy.Transformer.conversion_type(),
          default :: any()
        ) :: any() | no_return()
  def env!(variable, type, default) do
    case fetch_var(variable) do
      :error -> default
      {:ok, value} -> to!(value, type)
    end
  rescue
    error in Error ->
      if is_function(type) do
        reraise "Error converting variable #{variable} using custom function: #{error.message}",
                __STACKTRACE__
      else
        reraise "Error converting variable #{variable} to #{type}: #{error.message}",
                __STACKTRACE__
      end

    error ->
      reraise error, __STACKTRACE__
  end

  @doc """
  Reads the given env `variable` and converts its value to the given `type`.

  This function attempts to read a value from a local data store of sourced values.

  This function may raise an error because type conversion is delegated to
  `Dotenvy.Transformer.to!/2` -- see its documentation for a list of supported types.

  ## Examples

      iex> env!("PORT", :integer)
      5432
      iex> env!("ENABLED", :boolean)
      true
  """
  @spec env!(variable :: binary(), type :: Dotenvy.Transformer.conversion_type()) ::
          any() | no_return()
  def env!(variable, type \\ :string)

  def env!(variable, type) do
    case fetch_var(variable) do
      :error -> raise "Environment variable #{variable} not set"
      {:ok, value} -> to!(value, type)
    end
  rescue
    error in Error ->
      if is_function(type) do
        reraise "Error converting variable #{variable} using custom function: #{error.message}",
                __STACKTRACE__
      else
        reraise "Error converting variable #{variable} to #{type}: #{error.message}",
                __STACKTRACE__
      end

    error ->
      reraise error, __STACKTRACE__
  end

  @doc """
  Like its Bash namesake command, `source/2` accumulates values from the given input(s).
  The accumulated values are stored via a side effect function to make them available
  to the `env!/2` and `env!/3` functions.

  Think of `source/2` as a _merging operation_ which can accept maps (like `Map.merge/2`)
  or paths to env files.

  Inputs are processed from left to right so that values can be overridden by each
  subsequent input. As with `Map.merge/2`, the right-most input takes precedence.

  ## Options

  - `:parser` module that implements the `c:Dotenvy.parse/3` callback. Default: `Dotenvy.Parser`

  - `:require_files` specifies which of the given `files` (if any) *must* be present.
    When `true`, all the listed files must exist.
    When `false`, none of the listed files must exist.
    When some of the files are required and some are optional, provide a list
    specifying which files are required. If a file listed here is not included
    in the function's `files` argument, it is ignored. Default: `false`

  - `:side_effect` an arity 1 function called after successfully parsing inputs.
    The default is an internal function that stores the values inside a process dictionary so
    the values are available to the `env!/2` and `env!/3` functions. This option
    is overridable to facilitate testing. Changing it is not recommended.

  All other options are passed through to `Dotenvy.Parser.parse/3`, e.g. `:sys_cmd_fn`.

  ## Examples

  The simplest implementation is to parse a single file by including its path:

      iex> Dotenvy.source(".env")
      {:ok, %{
        "TIMEOUT" => "5000",
        "DATABASE_URL" => "postgres://postgres:postgres@localhost/myapp",
        # ...etc...
        }
      }

  More commonly, you will source _multiple_ files (often based on the `config_env()`)
  and you will defer to pre-existing system variables. The most common pattern looks like this:

        iex> Dotenvy.source([
          "\#\{config_env()\}.env",
          "\#\{config_env()\}.override.env",
          System.get_env()
        ])

  In the above example, the `prod.env`, `dev.env`, and `test.env` files would be version-controlled,
  but the `*.override.env` variants would be ignored, giving developers the ability to override
  values without needing to modify versioned files.

  > #### Give Precedence to System Envs! {: .warning}
  >
  > Don't forget to include `System.get_env()` as the final input to `source/2` so that
  > system environment variables take precedence over values sourced from `.env` files.
  >
  > When you run a shell command like `❯ LOG_LEVEL=debug mix run`, your expectation is probably that
  > the `LOG_LEVEL` variable would be set to `debug`, overriding whatever may have been defined
  > in your sourced `.env` files. Similarly, you may export env vars in your Bash profile.
  > System env vars are not granted precedence automatically: you must explicitly include
  > `System.get_env()` as the final input to `source/2`.


  If your env files are making use of variable substitution based on system env vars,
  e.g. `${PWD}` (see the [Dotenv File Format](docs/dotenv-file-format.md)), then you
  would need to specify `System.get_env()` as the first argument to `source/2`.

  For example, if your `.env` references the system `HOME` variable:
    ```
    # .env
    CACHE_DIR=${HOME}/cache
    ```

  then your `source/2` command would need to make the system env vars available
  to the parser by including them as one of the inputs, e.g.

        iex> Dotenvy.source([System.get_env(), ".env"])

  In some cases, you may wish to reference the system vars both _before and after_
  your own .env files, e.g.

        iex> Dotenvy.source([System.get_env(), ".env", System.get_env()])

  or you may wish to cherry-pick which variables you need to make available for
  variable substitution:

        iex> Dotenvy.source([
          %{"HOME" => System.get_env("HOME")},
          ".env",
          System.get_env()
        ])

  This syntax favors explicitness so there is no confusion over what might have been
  "automagically" accumulated.

  If you need to make any variables parsed from your files available elsewhere in
  the application via `System.get_env/2`, then you can call `System.put_env/1` on
  the output of `Dotenvy.source/2`, e.g.

      iex> {:ok, parsed_vars} = Dotenvy.source([".env", System.get_env()])
      iex> System.put_env(parsed_vars)

  """
  @spec source(inputs :: input_source() | [input_source()], opts :: keyword()) ::
          {:ok, %{optional(String.t()) => String.t()}} | {:error, any()}
  def source(files, opts \\ [])

  def source(file, opts) when is_binary(file), do: source([file], opts)

  def source(inputs, opts) when is_list(inputs) do
    side_effect = Keyword.get(opts, :side_effect, &put_all_vars/1)
    require_files = Keyword.get(opts, :require_files, false)

    with :ok <- verify_inputs(inputs, require_files),
         {:ok, vals} <- acc_vals(inputs, %{}, opts) do
      if is_function(side_effect), do: side_effect.(vals)
      {:ok, vals}
    end
  end

  @doc """
  As `source/2`, but returns a map on success or raises on error.
  """
  @spec source!(files :: binary() | [binary()], opts :: keyword()) ::
          %{optional(String.t()) => String.t()} | no_return()
  def source!(files, opts \\ [])

  def source!(file, opts) when is_binary(file), do: source!([file], opts)

  def source!(files, opts) when is_list(files) do
    case source(files, opts) do
      {:ok, vars} -> vars
      {:error, error} -> raise error
    end
  end

  defp fetch_var(variable) do
    :dotenvy_vars
    |> Process.get(%{})
    |> Map.fetch(variable)
  end

  defp put_all_vars(vars), do: Process.put(:dotenvy_vars, vars)

  # handles the parsing of a single file or an input map
  defp acc_vals([], acc, _opts), do: {:ok, acc}

  defp acc_vals([map | remaining], acc, opts) when is_map(map) do
    acc_vals(remaining, Map.merge(acc, map), opts)
  end

  defp acc_vals([file | remaining], acc, opts) when is_binary(file) do
    parser = Keyword.get(opts, :parser, @default_parser)

    require_files = Keyword.get(opts, :require_files, false)

    with {:ok, contents} <- read_file(file, require_files),
         {:ok, new_vars} <- parser.parse(contents, acc, opts) do
      acc_vals(remaining, Map.merge(acc, new_vars), opts)
    else
      :continue ->
        acc_vals(remaining, acc, opts)

      {:error, error} ->
        {:error, "There was error with file #{inspect(file)}: #{inspect(error)}"}
    end
  end

  @spec verify_inputs(list(), list() | boolean()) :: :ok | {:error, any()}
  defp verify_inputs(_, true), do: :ok
  defp verify_inputs(_, false), do: :ok

  defp verify_inputs(inputs, require_files) do
    input_set = inputs |> Enum.filter(fn x -> is_binary(x) end) |> MapSet.new()
    required_set = MapSet.new(require_files)

    case MapSet.equal?(required_set, input_set) || MapSet.subset?(required_set, input_set) do
      true ->
        :ok

      false ->
        missing_set = MapSet.difference(required_set, input_set)

        {:error,
         "Missing file(s) specified by require_files: #{inspect(Enum.join(missing_set, ";"))}"}
    end
  end

  # Reads the file after checking whether or not it exists
  @spec read_file(file :: binary(), require_files :: true | false | [binary()]) ::
          {:ok, binary()} | {:error, any()} | :continue
  defp read_file(file, false) do
    case File.exists?(file) do
      true -> File.read(file)
      false -> :continue
    end
  end

  defp read_file(file, true) do
    case File.exists?(file) do
      true -> File.read(file)
      false -> {:error, "file not found"}
    end
  end

  defp read_file(file, require_files) when is_list(require_files) do
    file
    |> read_file(Enum.member?(require_files, file))
  end
end
