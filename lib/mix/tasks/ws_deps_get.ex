defmodule Mix.Tasks.Ws.Deps.Get do
  @moduledoc """
  Workspace-safe deps.get that preserves mix.lock files.
  
  This command temporarily unsets JIDO_WORKSPACE when running deps.get
  to ensure that remote dependencies stay in the lock files.
  """
  @shortdoc "Get dependencies across workspace projects (preserves lock files)"

  use Mix.Task

  def run(args \\ []) do
    Application.ensure_all_started(:jido_workspace)
    
    # Temporarily unset JIDO_WORKSPACE for deps.get to preserve lock files
    original_workspace = System.get_env("JIDO_WORKSPACE")
    System.delete_env("JIDO_WORKSPACE")
    
    try do
      JidoWorkspace.Runner.run_task_all("deps.get", args)
    after
      # Restore original JIDO_WORKSPACE setting
      if original_workspace do
        System.put_env("JIDO_WORKSPACE", original_workspace)
      end
    end
  end
end
