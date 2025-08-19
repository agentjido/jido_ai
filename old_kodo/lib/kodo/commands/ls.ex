defmodule Kodo.Commands.Ls do
  @moduledoc """
  List directory contents command.
  """
  @behaviour Kodo.Ports.Command

  @impl true
  def name, do: "ls"

  @impl true
  def description, do: "List directory contents"

  @impl true
  def usage, do: "ls [directory]"

  @impl true
  def meta, do: [:builtin, :pure]

  @impl true
  def execute([], context), do: execute(["."], context)

  @impl true
  def execute([path], context) do
    full_path = Path.expand(path, context.current_dir)

    case File.ls(full_path) do
      {:ok, files} ->
        formatted =
          files
          |> Enum.sort()
          |> format_output(full_path)

        {:ok, formatted}

      {:error, reason} ->
        {:error, "Cannot access '#{path}': #{:file.format_error(reason)}"}
    end
  end

  def execute(_args, _context) do
    {:error, "Usage: #{usage()}"}
  end

  # Private functions

  defp format_output(files, path) do
    files
    |> Enum.map(fn file ->
      full_path = Path.join(path, file)

      if File.dir?(full_path) do
        file <> "/"
      else
        file
      end
    end)
    |> Enum.join("  ")
  end
end
