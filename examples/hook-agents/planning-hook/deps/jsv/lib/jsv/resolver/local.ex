defmodule JSV.Resolver.Local do
  alias __MODULE__

  @moduledoc """
  This module allows to build `JSV.Resolver` implementations that resolves
  schemas based on disk based on their `$id` property. It is not itself a
  `JSV.Resolver` implementation.

  To define your own local resolver, `use` this module by providing the
  `:source` option with a path to a directory, a path to a file, or a list of
  paths to directories and files:

  ```elixir
  schemas_dir = "priv/messaging/schemas"
  other_schema = "priv/users/user-schema.schema.json"

  defmodule MyApp.LocalResolver do
    use JSV.Resolver.Local, source: [schemas_dir, other_schema]
  end
  ```

  The macro will read all `.json` files from the given sources and build an
  index mapping the `$id` property of each schema to its JSON-deserialized
  value.

  For convenience, nested lists are accepted. Duplicated files accepted as well
  but not duplicates due to symlinks.


  ### Compilation and caching

  Schemas are loaded directly into the generated module code. The module will
  recompile everytime a loaded schema file is modified or deleted.

  Recompilation will also happen when new files are added in directories listed
  as sources.


  ### Debugging

  The `use JSV.Resolver.Local` also accepts the following options:

  * `:warn` - A `boolean` flag enabling compilation warnings when a `.json` file
    cannot be read or loaded properly. Defaults to `true`.
  * `:debug` - A `boolean` flag enabling printouts of the loaded schemas on
    compilation. Defaults to `false`.


  ### Example

  The `"priv/schemas/user-schema.schema.json"` file contains the following JSON
  text:

  ```json
  {
    "$id": "myapp:user-0.0.1",
    "type": "object",
    "properties": {
      "username": {
        "type": "string"
      }
    }
  }
  ```

  Then this can be used as a source in your module.

  ```elixir
  defmodule MyApp.LocalResolver do
    use JSV.Resolver.Local, source: "priv/schemas"
  end
  ```

  You can now build validation roots (`JSV.Root`) by referencing this user
  schema in `$ref` and by providing your resolver to the `JSV.build!/2`
  function:

      iex> schema = %{"$ref" => "myapp:user-0.0.1"}
      iex> root   = JSV.build!(schema, resolver: MyApp.LocalResolver)
      iex> # Here we pass an invalid username (an integer)
      iex> result = JSV.validate(%{"username" => 123}, root)
      iex> match?({:error, %JSV.ValidationError{}}, result)
      true

  You can also directly fetch a schema from the defined module:

      iex> MyApp.LocalResolver.resolve("myapp:user-0.0.1")
      {:ok,
        %{
          "$id" => "myapp:user-0.0.1",
          "type" => "object",
          "properties" => %{"username" => %{"type" => "string"}}
        }}

      iex> MyApp.LocalResolver.resolve("myapp:other")
      {:error, {:unknown_id, "myapp:other"}}



  Remember that schemas are identified and resolved by their `$id` property and
  not their path.
  """
  defmacro __using__(opts) do
    source_opt =
      case Keyword.fetch(opts, :source) do
        {:ok, q} -> q
        :error -> raise ArgumentError, "the :source option is required when using #{inspect(__MODULE__)}"
      end

    warn? =
      case Keyword.fetch(opts, :warn) do
        {:ok, q} -> !!q
        :error -> true
      end

    debug? =
      case Keyword.fetch(opts, :debug) do
        {:ok, q} -> !!q
        :error -> false
      end

    quote bind_quoted: binding(), location: :keep do
      {:current_stacktrace, [_ | warn_stack]} = Process.info(self(), :current_stacktrace)
      cfg = %{stacktrace: warn_stack, warn?: warn?, debug?: debug?, module: __MODULE__}
      expanded_sources = Local.collect_files(List.wrap(source_opt), cfg)
      schemas_sources = Local.read_sources(expanded_sources, cfg)

      @__jsv_resolver_compiled_source_opt source_opt
      @__jsv_resolver_mtime_index Local.sources_fingerprint(expanded_sources)

      @behaviour JSV.Resolver

      # Not part of the behaviour implementation. This is added as a convenience
      # for the users. So there is no need to return {:normal, _}.
      def resolve(id) do
        case resolve(id, []) do
          {:normal, schema} -> {:ok, schema}
          {:error, _} = err -> err
        end
      end

      @impl true
      def resolve(id, opts)

      Enum.each(schemas_sources, fn {id, raw_schema} ->
        def resolve(unquote(id), _opts) do
          {:normal, unquote(Macro.escape(raw_schema))}
        end
      end)

      def resolve(id, _opts) do
        {:error, {:unknown_id, id}}
      end

      ids_list = Enum.map(schemas_sources, fn {id, _} -> id end)

      def resolvable_ids do
        unquote(ids_list)
      end

      def __mix_recompile__? do
        cfg = %{stacktrace: [], warn?: false}

        current_index =
          @__jsv_resolver_compiled_source_opt
          |> List.wrap()
          |> Local.collect_files(cfg)
          |> Local.sources_fingerprint()

        current_index != @__jsv_resolver_mtime_index
      rescue
        _ -> true
      end

      defoverridable JSV.Resolver
      defoverridable __mix_recompile__?: 0
    end
  end

  @doc false
  @spec collect_files(binary | [binary], map) :: [binary]
  def collect_files(sources, cfg) when is_binary(sources) when is_list(sources) do
    sources
    |> List.wrap()
    |> :lists.flatten()
    |> do_collect(cfg)
    |> Enum.uniq_by(&Path.expand/1)
  end

  defp do_collect(sources, cfg) when is_list(sources) do
    sources
    |> Enum.filter(fn source ->
      case check_valid(source) do
        :ok ->
          true

        {:error, reason} ->
          maybe_warn_error(reason, source, cfg)
          false
      end
    end)
    |> Enum.flat_map(&do_collect(&1, cfg))
  end

  defp do_collect(dir_or_file, _) when is_binary(dir_or_file) do
    cond do
      File.regular?(dir_or_file) ->
        case Path.extname(dir_or_file) do
          ".json" -> [dir_or_file]
          _ -> []
        end

      File.dir?(dir_or_file) ->
        Path.wildcard("#{dir_or_file}/**/*.json")
    end
  end

  @doc false
  @spec read_sources([binary], map) :: [{id :: binary(), raw_schema :: map()}]
  def read_sources(expanded_sources, cfg) do
    stream =
      expanded_sources
      |> Stream.flat_map(fn path ->
        with {:ok, json} <- read_source(path),
             {:ok, %{"$id" => id} = decoded} <- decode_source(json) do
          [{path, {id, decoded}}]
        else
          {:error, reason} ->
            :ok = maybe_warn_error(reason, path, cfg)
            []
        end
      end)
      |> Stream.transform(%{}, fn {path, {id, _raw_schema} = item}, seen ->
        seen =
          case seen do
            %{^id => prev_path} ->
              raise "duplicate $id #{inspect(id)} defined in #{prev_path} and #{path}"

            _ ->
              Map.put(seen, id, path)
          end

        {[item], seen}
      end)

    stream =
      if cfg.debug? do
        module_str = inspect(cfg.module)

        Stream.each(stream, fn {id, _} ->
          IO.puts(IO.ANSI.format([:green, "✔ ", module_str, " loaded ", id]))
        end)
      else
        stream
      end

    Enum.to_list(stream)
  end

  @doc false
  @spec sources_fingerprint([binary]) :: %{binary() => {integer(), integer()}}
  def sources_fingerprint(expanded_sources) do
    # works like a hash or checksum but using the data direcly.
    Map.new(expanded_sources, fn path ->
      stat = File.stat!(path, time: :posix)
      time = max(stat.mtime, stat.ctime)
      {path, {time, stat.size}}
    end)
  end

  defp check_valid(dir_or_file) when is_binary(dir_or_file) do
    if File.exists?(dir_or_file) do
      :ok
    else
      {:error, {:file_error, :does_not_exist}}
    end
  end

  defp check_valid(other) do
    {:error, {:bad_source, other}}
  end

  defp read_source(path) do
    case File.read(path) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, {:file_error, reason}}
    end
  end

  defp decode_source(json) do
    case JSV.Codec.decode(json) do
      {:ok, %{"$id" => id} = decoded} when is_binary(id) -> {:ok, decoded}
      {:ok, decoded} when is_map(decoded) -> {:error, :schema_no_id}
      {:ok, _} -> {:error, :schema_not_object}
      {:error, reason} -> {:error, {:json_decode_error, reason}}
      {:error, :invalid, reason} -> {:error, {:json_decode_error, {:invalid, reason}}}
    end
  end

  defp maybe_warn_error(reason, path, cfg) do
    if cfg.warn? do
      :ok = warn_error(reason, path, cfg)
    else
      :ok
    end
  end

  defp warn_error(reason, path, cfg) do
    case reason do
      {:file_error, err} ->
        IO.warn("could not read file: #{path} got: #{inspect(err)}", cfg.stacktrace)

      :schema_no_id ->
        IO.warn("json schema at #{path} does not have $id", cfg.stacktrace)

      :schema_not_object ->
        IO.warn("json schema at #{path} is not an object", cfg.stacktrace)

      {:json_decode_error, err} ->
        IO.warn("could not decode json schema at path #{path}, got: #{inspect(err)}", cfg.stacktrace)

      {:bad_source, ^path} ->
        IO.warn("invalid source, expected a binary path, got: #{inspect(path)}", cfg.stacktrace)
    end
  end
end
