defmodule Mix.Tasks.Workspace.Test.All do
  use Mix.Task

  @shortdoc "Run tests for all projects"

  def run(_) do
    Application.ensure_all_started(:jido_workspace)
    JidoWorkspace.test_all()
  end
end
