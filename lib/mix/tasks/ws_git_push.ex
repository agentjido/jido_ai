defmodule Mix.Tasks.Ws.Git.Push do
  use Mix.Task

  @shortdoc "Push project changes to upstream"

  @moduledoc """
  Push changes to upstream repositories for workspace projects.

  ## Examples

      mix ws.git.push jido                    # Push jido project
      mix ws.git.push jido --branch feature   # Push to specific branch
  """

  def run([project_name]) do
    Application.ensure_all_started(:jido_workspace)
    JidoWorkspace.ensure_workspace_env()
    JidoWorkspace.push_project(project_name)
  end

  def run([project_name, "--branch", branch_name]) do
    Application.ensure_all_started(:jido_workspace)
    JidoWorkspace.ensure_workspace_env()
    JidoWorkspace.push_project(project_name, branch: branch_name)
  end

  def run(_) do
    Mix.shell().error("Usage: mix ws.git.push <project_name> [--branch <branch_name>]")
  end
end
