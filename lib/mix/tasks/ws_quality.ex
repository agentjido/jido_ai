defmodule Mix.Tasks.Ws.Quality do
  @moduledoc """
  Run quality checks (format, compile, dialyzer, credo) across all projects in the workspace.
  """
  @shortdoc "Run quality checks for all workspace projects"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:jido_workspace)
    JidoWorkspace.ensure_workspace_env()

    case args do
      [] ->
        JidoWorkspace.Runner.run_task_all("quality", [])

      [project_name] ->
        projects = JidoWorkspace.config()

        case Enum.find(projects, &(&1.name == project_name)) do
          nil ->
            IO.puts("Project '#{project_name}' not found")
            System.halt(1)

          project ->
            JidoWorkspace.Runner.run_task_in_project(project, "quality", [])
        end

      _ ->
        IO.puts("Usage: mix ws.quality [project_name]")
        System.halt(1)
    end
  end
end
