defmodule Mix.Tasks.Workspace.Diff do
  @moduledoc """
  Show differences between local workspace and upstream repositories.
  """
  @shortdoc "Show diff between local and upstream for workspace projects"

  use Mix.Task
  require Logger

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:jido_workspace)
    
    case args do
      [] ->
        show_all_diffs()

      [project_name] ->
        projects = JidoWorkspace.config()
        case Enum.find(projects, &(&1.name == project_name)) do
          nil ->
            IO.puts("Project '#{project_name}' not found")
            System.halt(1)
          project ->
            show_project_diff(project)
        end

      _ ->
        IO.puts("Usage: mix workspace.diff [project_name]")
        System.halt(1)
    end
  end

  defp show_all_diffs do
    IO.puts("Checking differences for all projects...\n")
    
    JidoWorkspace.config()
    |> Enum.each(fn project ->
      IO.puts("=== #{project.name} ===")
      show_project_diff(project)
      IO.puts("")
    end)
  end

  defp show_project_diff(%{name: name, path: path, upstream_url: url, branch: branch}) do
    if not File.exists?(path) do
      IO.puts("Project not present locally")
    else

    # Check if there are local changes in the subtree path
    case System.cmd("git", ["diff", "--name-only", "HEAD", "--", path], stderr_to_stdout: true) do
      {output, 0} ->
        if String.trim(output) == "" do
          IO.puts("No local changes")
        else
          IO.puts("Local changes detected:")
          String.split(output, "\n", trim: true)
          |> Enum.each(fn file -> IO.puts("  modified: #{file}") end)
          
          # Show the actual diff
          IO.puts("\nDiff:")
          {diff_output, _} = System.cmd("git", ["diff", "HEAD", "--", path], stderr_to_stdout: true)
          IO.puts(diff_output)
        end
      
      {error, _} ->
        Logger.error("Failed to check diff for #{name}: #{error}")
    end

    # Also check commits ahead of what would be pulled
    case System.cmd("git", ["log", "--oneline", "HEAD", "--not", "#{url}/#{branch}", "--", path], stderr_to_stdout: true) do
      {output, 0} ->
        commits = String.split(output, "\n", trim: true)
        if length(commits) > 0 do
          IO.puts("\nLocal commits (#{length(commits)}):")
          Enum.each(commits, fn commit -> IO.puts("  #{commit}") end)
        end
      
      {_error, _} ->
        # This might fail if we don't have the remote ref, which is fine
        nil
    end
    end
  end
end
