defmodule Mix.Tasks.Workspace.Test.All do
  @moduledoc """
  Run tests across all projects in the workspace.
  """
  @shortdoc "Test all workspace projects"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:jido_workspace)
    JidoWorkspace.ensure_workspace_env()
    
    case args do
      [] ->
        JidoWorkspace.Runner.run_task_all("test", [], continue_on_error: false)

      [project_name] ->
        projects = JidoWorkspace.config()
        case Enum.find(projects, &(&1.name == project_name)) do
          nil ->
            IO.puts("Project '#{project_name}' not found")
            System.halt(1)
          project ->
            case JidoWorkspace.Runner.run_task_single(project.path, "test") do
              :ok -> :ok
              {:error, {code, _}} -> System.halt(code)
            end
        end

      _ ->
        IO.puts("Usage: mix workspace.test.all [project_name]")
        System.halt(1)
    end
  end
end
