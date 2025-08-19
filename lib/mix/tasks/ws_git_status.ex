defmodule Mix.Tasks.Ws.Git.Status do
  use Mix.Task

  @shortdoc "Show workspace and git status"

  @moduledoc """
  Show the status of the workspace and git status for each project.

  ## Examples

      mix ws.git.status
  """

  def run(_) do
    Application.ensure_all_started(:jido_workspace)
    JidoWorkspace.ensure_workspace_env()
    JidoWorkspace.status()
  end
end
