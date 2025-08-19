defmodule Mix.Tasks.Workspace.Push do
  use Mix.Task

  @shortdoc "Push project changes to upstream"

  def run([project_name]) do
    Application.ensure_all_started(:jido_workspace)
    JidoWorkspace.push_project(project_name)
  end
  
  def run(_) do
    Mix.shell().error("Usage: mix workspace.push <project_name>")
  end
end
