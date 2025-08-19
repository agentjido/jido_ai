defmodule Mix.Tasks.Workspace.Status do
  use Mix.Task

  @shortdoc "Show workspace status"

  def run(_) do
    Application.ensure_all_started(:jido_workspace)
    JidoWorkspace.status()
  end
end
