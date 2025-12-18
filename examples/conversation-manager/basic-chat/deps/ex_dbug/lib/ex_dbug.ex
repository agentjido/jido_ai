defmodule ExDbug do
  @external_resource "README.md"
  @moduledoc File.read!("README.md")
             |> String.split("## Contributing")
             |> List.first()
             |> String.trim()

  require Logger

  @type debug_opts :: [
          enabled: boolean(),
          context: atom() | String.t(),
          max_depth: non_neg_integer(),
          include_timing: boolean(),
          include_stack: boolean(),
          truncate: boolean() | non_neg_integer()
        ]

  defmacro __using__(opts \\ []) do
    enabled = get_debug_enabled(opts)

    if enabled do
      quote do
        import ExDbug
        require Logger
        require ExDbug

        @debug_opts ExDbug.merge_options(unquote(opts))
        @context Keyword.get(unquote(opts), :context, __MODULE__) |> to_string()

        Process.put(:ex_dbug_opts, @debug_opts)

        @before_compile ExDbug
      end
    else
      quote do
        require Logger
        defmacro dbug(_, _ \\ []), do: nil
        defmacro error(_, _ \\ []), do: nil
        # def __debug_context__, do: nil
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def __debug_context__, do: @context
    end
  end

  defmacro dbug(message, metadata \\ []) do
    caller_context = compute_caller_context(__CALLER__)

    quote bind_quoted: [
            message: message,
            metadata: metadata,
            caller_context: caller_context
          ] do
      context = __debug_context__() || caller_context
      ExDbug.log(:debug, message, metadata, context)
    end
  end

  defmacro error(message, metadata \\ []) do
    caller_context = compute_caller_context(__CALLER__)

    quote bind_quoted: [
            message: message,
            metadata: metadata,
            caller_context: caller_context
          ] do
      context = __debug_context__() || caller_context
      ExDbug.log(:error, message, metadata, context)
    end
  end

  defmacro track(value, name) do
    quote do
      result = unquote(value)
      dbug("Value tracked: #{unquote(name)} = #{inspect(result)}")
      result
    end
  end

  @doc false
  def get_debug_enabled(opts) do
    env_enabled = Application.get_env(:ex_dbug, :enabled, true)
    Keyword.get(opts, :enabled, env_enabled)
  end

  @doc false
  def merge_options(opts) do
    defaults = [
      max_depth: 3,
      include_timing: true,
      include_stack: true,
      truncate: 100,
      levels: [:debug, :error]
    ]

    app_config = Application.get_env(:ex_dbug, :config, [])
    merged = Keyword.merge(defaults, app_config) |> Keyword.merge(opts)

    truncate =
      cond do
        Keyword.has_key?(merged, :truncate_threshold) ->
          Keyword.get(merged, :truncate_threshold)

        true ->
          Keyword.get(merged, :truncate)
      end

    Keyword.put(merged, :truncate, truncate)
  end

  @doc false
  def format_output(message, context) when is_binary(context) or is_atom(context) do
    context_str =
      context
      |> to_string()
      |> String.replace(~r/^Elixir\./, "")

    "[#{context_str}] #{message}"
  end

  def format_output(message, context, metadata, opts \\ %{}) do
    context_str =
      context
      |> to_string()
      |> String.replace(~r/^Elixir\./, "")

    formatted_metadata = format_metadata(metadata, opts)
    base = "[#{context_str}] #{message}"

    if formatted_metadata != "", do: "#{base} #{formatted_metadata}", else: base
  end

  @doc false
  def log(level, message, metadata, context)
      when level in [:debug, :error] and (is_binary(context) or is_atom(context)) do
    context_str = to_string(context)

    if should_log?(level, metadata, context_str) do
      debug_opts = Process.get(:ex_dbug_opts, [])

      opts =
        debug_opts
        |> Keyword.take([:truncate])
        |> Keyword.merge(metadata_to_keyword_list(metadata))
        |> Map.new()

      formatted = format_output(message, context_str, metadata, opts)

      case level do
        :debug -> Logger.debug(formatted)
        :error -> Logger.error(formatted)
      end
    end
  end

  @doc false
  def log(level, message, metadata, opts) when level in [:debug, :error] and is_map(opts) do
    context = Map.get(opts, :context) || "unknown"
    metadata = metadata_to_keyword_list(metadata)
    log(level, message, metadata, context)
  end

  @doc false
  defp compute_caller_context(env) do
    case env.function do
      nil ->
        quote do
          __MODULE__
          |> Atom.to_string()
          |> String.replace(~r/^Elixir\./, "")
        end

      {name, _arity} ->
        escaped_name = Macro.escape(name)

        quote do
          module_name =
            __MODULE__
            |> Atom.to_string()
            |> String.replace(~r/^Elixir\./, "")

          function_name = unquote(escaped_name) |> Atom.to_string()
          "#{module_name}.#{function_name}"
        end
    end
  end

  @doc false
  defp should_log?(level, metadata, context) do
    metadata = metadata_to_keyword_list(metadata)
    debug_levels = Keyword.get(metadata, :levels, [:debug, :error])
    level_allowed = level in debug_levels
    pattern_match = namespace_enabled?(context)

    level_allowed and pattern_match
  end

  @doc false
  defp namespace_enabled?(context) do
    patterns = parse_debug_env()
    matches_namespace?(context, patterns)
  end

  @doc false
  defp parse_debug_env do
    debug_val = System.get_env("DEBUG", "")
    parse_patterns(debug_val)
  end

  @doc false
  defp parse_patterns(string) when is_binary(string) do
    raw = String.split(string, [",", " "], trim: true)

    {includes, excludes} =
      Enum.reduce(raw, {[], []}, fn pattern, {inc, exc} ->
        pattern = String.trim(pattern)

        cond do
          pattern == "" ->
            {inc, exc}

          String.starts_with?(pattern, "-") ->
            {inc, [String.trim_leading(pattern, "-") | exc]}

          true ->
            {[pattern | inc], exc}
        end
      end)

    {Enum.reverse(includes), Enum.reverse(excludes)}
  end

  @doc false
  defp matches_namespace?(namespace, {includes, excludes}) do
    cond do
      includes == [] and excludes == [] ->
        true

      true ->
        included = includes == [] or Enum.any?(includes, &wildcard_match?(namespace, &1))
        excluded = Enum.any?(excludes, &wildcard_match?(namespace, &1))
        included and not excluded
    end
  end

  @doc false
  defp wildcard_match?(string, pattern) do
    regex_pattern =
      pattern
      |> Regex.escape()
      |> String.replace("\\*", ".*")

    Regex.match?(Regex.compile!("^" <> regex_pattern <> "$"), string)
  end

  defp format_metadata(metadata, opts) when is_list(metadata) do
    truncate = Map.get(opts, :truncate, 100)

    case metadata do
      [] ->
        ""

      _ ->
        Enum.map_join(metadata, ", ", fn {key, value} ->
          formatted_value = format_value(value, truncate)
          "#{key}: #{formatted_value}"
        end)
    end
  end

  defp format_metadata(metadata, opts) when is_map(metadata) do
    format_metadata(Map.to_list(metadata), opts)
  end

  defp format_metadata(_, _), do: ""

  defp format_value(value, truncate) do
    formatted = inspect(value, limit: :infinity, pretty: false)

    case truncate do
      false ->
        formatted

      true ->
        if String.length(formatted) > 100 do
          String.slice(formatted, 0, 100) <> "... (truncated)"
        else
          formatted
        end

      threshold when is_integer(threshold) and threshold > 0 ->
        if String.length(formatted) > threshold do
          String.slice(formatted, 0, threshold) <> "... (truncated)"
        else
          formatted
        end
    end
  end

  defp metadata_to_keyword_list(metadata) when is_list(metadata), do: metadata
  defp metadata_to_keyword_list(metadata) when is_map(metadata), do: Map.to_list(metadata)
  defp metadata_to_keyword_list(_), do: []
end
