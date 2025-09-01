defmodule Mix.Tasks.Ws.Deps.Get do
  @moduledoc """
  Safely fetch dependencies across all workspace projects.
  
  With jido_dep, dependencies automatically resolve correctly for both
  workspace development and publishing.
  """
  @shortdoc "Get dependencies across workspace projects"

  use Mix.Task

  def run(args \\ []) do
    Application.ensure_all_started(:jido_workspace)
    JidoWorkspace.Runner.run_task_all("deps.get", args)
  end
end
