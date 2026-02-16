defmodule Mix.Tasks.Quality.DialyzerIgnores do
  @moduledoc false
  use Mix.Task

  @shortdoc "Validates dialyzer ignores are reviewed and tracked"

  @default_ignore_file ".dialyzer_ignore.exs"
  @default_metadata_file ".dialyzer_ignore_metadata.exs"
  @required_metadata_keys [:owner, :rationale, :cleanup_plan, :reviewed_by, :reviewed_on]

  @doc false
  @impl Mix.Task
  def run(args) do
    {ignore_file, metadata_file} = parse_args(args)

    with {:ok, ignore_entries} <- read_entries(ignore_file, "Dialyzer ignore file"),
         {:ok, metadata_entries} <- read_entries(metadata_file, "Dialyzer ignore metadata file"),
         :ok <- validate(ignore_entries, metadata_entries) do
      Mix.shell().info("Dialyzer ignore review policy passed.")
      :ok
    else
      {:error, errors} ->
        Mix.shell().error("Dialyzer ignore review policy issues:")
        Enum.each(errors, &Mix.shell().error("  - #{&1}"))

        Mix.raise("""
        Dialyzer ignore review policy failed.
        Update #{metadata_file} so every ignore has owner, rationale, cleanup plan, and review details.
        """)
    end
  end

  @doc """
  Validates that each dialyzer ignore pattern has a matching reviewed metadata entry.
  """
  @spec validate([term()], [term()]) :: :ok | {:error, [String.t()]}
  def validate(ignore_entries, metadata_entries)
      when is_list(ignore_entries) and is_list(metadata_entries) do
    {ignores_by_key, ignore_errors} = normalize_ignores(ignore_entries)
    {metadata_by_key, metadata_errors} = normalize_metadata(metadata_entries)

    missing_review_errors =
      ignores_by_key
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(metadata_by_key, &1))
      |> Enum.map(fn key ->
        "Missing reviewed metadata for ignore pattern #{inspect(Map.fetch!(ignores_by_key, key))}."
      end)

    stale_metadata_errors =
      metadata_by_key
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(ignores_by_key, &1))
      |> Enum.map(fn key ->
        "Metadata entry #{inspect(Map.fetch!(metadata_by_key, key).pattern)} does not match any ignore pattern."
      end)

    errors = Enum.sort(ignore_errors ++ metadata_errors ++ missing_review_errors ++ stale_metadata_errors)

    if errors == [], do: :ok, else: {:error, errors}
  end

  def validate(_ignore_entries, _metadata_entries) do
    {:error, ["Ignore entries and metadata entries must both evaluate to lists."]}
  end

  defp parse_args([]), do: {@default_ignore_file, @default_metadata_file}
  defp parse_args([ignore_file, metadata_file]), do: {ignore_file, metadata_file}

  defp parse_args(_args) do
    Mix.raise("Usage: mix quality.dialyzer_ignores [ignore_file metadata_file]")
  end

  defp read_entries(path, label) do
    expanded_path = Path.expand(path)

    cond do
      not File.exists?(expanded_path) ->
        {:error, ["#{label} not found at #{path}."]}

      true ->
        try do
          case Code.eval_file(expanded_path) do
            {entries, _binding} when is_list(entries) ->
              {:ok, entries}

            {_other, _binding} ->
              {:error, ["#{label} must evaluate to a list (#{path})."]}
          end
        rescue
          error ->
            {:error, ["Unable to read #{path}: #{Exception.message(error)}"]}
        end
    end
  end

  defp normalize_ignores(ignore_entries) do
    Enum.reduce(ignore_entries, {%{}, []}, fn entry, {acc, errors} ->
      case pattern_key(entry) do
        {:ok, key} ->
          if Map.has_key?(acc, key) do
            {acc, ["Duplicate ignore pattern #{inspect(entry)}." | errors]}
          else
            {Map.put(acc, key, entry), errors}
          end

        {:error, reason} ->
          {acc, ["Invalid ignore entry #{inspect(entry)}: #{reason}." | errors]}
      end
    end)
  end

  defp normalize_metadata(metadata_entries) do
    metadata_entries
    |> Enum.with_index(1)
    |> Enum.reduce({%{}, []}, fn {entry, index}, {acc, errors} ->
      case normalize_metadata_entry(entry, index) do
        {:ok, key, normalized} ->
          if Map.has_key?(acc, key) do
            {acc, ["Duplicate metadata entry for pattern #{inspect(normalized.pattern)}." | errors]}
          else
            {Map.put(acc, key, normalized), errors}
          end

        {:error, entry_errors} ->
          {acc, entry_errors ++ errors}
      end
    end)
  end

  defp normalize_metadata_entry(entry, index) when is_map(entry) do
    case fetch_required(entry, :pattern, index) do
      {:ok, pattern} ->
        {key, pattern_errors} =
          case pattern_key(pattern) do
            {:ok, key} -> {key, []}
            {:error, reason} -> {nil, ["Metadata entry #{index} has invalid pattern: #{reason}."]}
          end

        errors =
          pattern_errors ++
            validate_required_metadata(entry, index) ++ validate_reviewed_on(entry, index)

        if errors == [] do
          {:ok, key, %{pattern: pattern}}
        else
          {:error, errors}
        end

      {:error, message} ->
        {:error, [message]}
    end
  end

  defp normalize_metadata_entry(entry, index) do
    {:error, ["Metadata entry #{index} must be a map, got #{inspect(entry)}."]}
  end

  defp validate_required_metadata(entry, index) do
    Enum.reduce(@required_metadata_keys, [], fn key, errors ->
      case fetch_optional(entry, key) do
        value when is_binary(value) ->
          if String.trim(value) == "" do
            ["Metadata entry #{index} is missing required `#{key}`." | errors]
          else
            errors
          end

        _ ->
          ["Metadata entry #{index} is missing required `#{key}`." | errors]
      end
    end)
  end

  defp validate_reviewed_on(entry, index) do
    case fetch_optional(entry, :reviewed_on) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          []
        else
          case Date.from_iso8601(value) do
            {:ok, _date} ->
              []

            _ ->
              [
                "Metadata entry #{index} has invalid `reviewed_on` date #{inspect(value)} (expected YYYY-MM-DD)."
              ]
          end
        end

      _ ->
        []
    end
  end

  defp fetch_required(entry, key, index) do
    case fetch_optional(entry, key) do
      nil ->
        {:error, "Metadata entry #{index} is missing required `#{key}`."}

      value ->
        {:ok, value}
    end
  end

  defp fetch_optional(entry, key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(entry, key) -> Map.get(entry, key)
      Map.has_key?(entry, string_key) -> Map.get(entry, string_key)
      true -> nil
    end
  end

  defp pattern_key(%Regex{} = pattern) do
    {:ok, {:regex, pattern.source, pattern.opts |> Enum.sort()}}
  end

  defp pattern_key(pattern) when is_binary(pattern) do
    {:ok, {:string, pattern}}
  end

  defp pattern_key(other) do
    {:error, "pattern must be a regex or string, got #{inspect(other)}"}
  end
end
