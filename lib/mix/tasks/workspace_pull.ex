defmodule Mix.Tasks.Workspace.Pull do
  use Mix.Task

  @shortdoc "Pull project updates from upstream"

  def run([]) do
  Application.ensure_all_started(:jido_workspace)
  JidoWorkspace.ensure_workspace_env()
    JidoWorkspace.sync_all()
  end

  def run([project_name]) do
  Application.ensure_all_started(:jido_workspace)
    JidoWorkspace.ensure_workspace_env()
    JidoWorkspace.pull_project(project_name)
  end
  
  def run(_) do
    Mix.shell().error("Usage: mix workspace.pull [project_name]")
  end
end
