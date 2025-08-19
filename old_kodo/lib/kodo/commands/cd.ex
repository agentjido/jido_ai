defmodule Kodo.Commands.Cd do
  @moduledoc """
  Change current working directory command.
  """
  @behaviour Kodo.Ports.Command

  @impl true
  def name, do: "cd"

  @impl true
  def description, do: "Change the current working directory"

  @impl true
  def usage, do: "cd <directory>"

  @impl true
  def meta, do: [:builtin, :changes_dir]

  @impl true
  def execute([path], context) do
    new_path = Path.expand(path, context.current_dir)

    case File.dir?(new_path) do
      true ->
        # Instead of calling Session directly, return a description of the state change
        {:ok, "", %{session_updates: %{set_env: %{"PWD" => new_path}}}}

      false ->
        {:error, "Directory does not exist: #{path}"}
    end
  end

  def execute([], context) do
    home = context.env["HOME"] || "/"
    execute([home], context)
  end

  def execute(_args, _context) do
    {:error, "Usage: #{usage()}"}
  end
end
