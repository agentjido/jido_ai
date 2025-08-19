defmodule Mix.Tasks.Ws.Git.Pull do
  use Mix.Task

  @shortdoc "Pull project updates from upstream"

  @moduledoc """
  Pull updates from upstream repositories for workspace projects.

  ## Examples

      mix ws.git.pull           # Pull all projects
      mix ws.git.pull jido      # Pull specific project
  """

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
    Mix.shell().error("Usage: mix ws.git.pull [project_name]")
  end
end
