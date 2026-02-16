defmodule Mix.Tasks.Docs.Check do
  @moduledoc false
  use Mix.Task

  @shortdoc "Checks markdown docs for stale Jido.AI module references and deprecated config keys"

  @module_ref_regex ~r/\bJido\.AI(?:\.[A-Z][A-Za-z0-9_]*)+\b/
  @deprecated_config_regex ~r/config\s+:jido_ai,\s*:models\b/

  @doc_globs [
    "README.md",
    "usage-rules.md",
    "guides/**/*.md",
    "examples/**/*.md"
  ]

  @impl Mix.Task
  def run(_args) do
    files = docs_files()
    invalid_refs = invalid_module_refs(files)
    deprecated_configs = deprecated_config_refs(files)

    if invalid_refs == [] and deprecated_configs == [] do
      Mix.shell().info("Documentation reference check passed.")
      :ok
    else
      print_invalid_refs(invalid_refs)
      print_deprecated_configs(deprecated_configs)

      Mix.raise("""
      Documentation reference check failed.
      Fix stale module references and deprecated config keys in markdown docs.
      """)
    end
  end

  defp docs_files do
    @doc_globs
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp invalid_module_refs(files) do
    Enum.flat_map(files, &invalid_module_refs_in_file/1)
  end

  defp invalid_module_refs_in_file(file) do
    file
    |> File.stream!()
    |> Stream.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      line
      |> extract_module_refs()
      |> Enum.reject(&module_ref_valid?/1)
      |> Enum.map(fn module_ref ->
        %{file: file, line: line_number, module_ref: module_ref}
      end)
    end)
  end

  defp extract_module_refs(line) do
    @module_ref_regex
    |> Regex.scan(line)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp module_exists?(module_ref) when is_binary(module_ref) do
    module_ref
    |> String.split(".")
    |> Module.concat()
    |> Code.ensure_loaded?()
  end

  defp module_ref_valid?(module_ref) do
    module_exists?(module_ref) or namespace_ref?(module_ref)
  end

  defp namespace_ref?(module_ref) do
    prefix = "Elixir." <> module_ref <> "."

    (Application.spec(:jido_ai, :modules) || [])
    |> Enum.any?(fn module ->
      module
      |> Atom.to_string()
      |> String.starts_with?(prefix)
    end)
  end

  defp deprecated_config_refs(files) do
    Enum.flat_map(files, &deprecated_config_refs_in_file/1)
  end

  defp deprecated_config_refs_in_file(file) do
    file
    |> File.stream!()
    |> Stream.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      if Regex.match?(@deprecated_config_regex, line) do
        [%{file: file, line: line_number, snippet: String.trim(line)}]
      else
        []
      end
    end)
  end

  defp print_invalid_refs([]), do: :ok

  defp print_invalid_refs(refs) do
    Mix.shell().error("Invalid Jido.AI module references found:")

    Enum.each(refs, fn %{file: file, line: line, module_ref: module_ref} ->
      Mix.shell().error("  #{file}:#{line} -> #{module_ref}")
    end)
  end

  defp print_deprecated_configs([]), do: :ok

  defp print_deprecated_configs(refs) do
    Mix.shell().error("Deprecated config key `config :jido_ai, :models` found:")

    Enum.each(refs, fn %{file: file, line: line, snippet: snippet} ->
      Mix.shell().error("  #{file}:#{line} -> #{snippet}")
    end)
  end
end
