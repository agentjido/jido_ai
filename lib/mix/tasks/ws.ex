defmodule Mix.Tasks.Ws do
  use Mix.Task

  @shortdoc "Run any Mix task in all workspace projects"

  @moduledoc """
  Runs any Mix task across all workspace projects.

  ## Examples

      mix ws deps.get
      mix ws test
      mix ws compile --force
      mix ws format --check
  """

  def run([]) do
    Mix.shell().info("""
    Usage: mix ws <mix-task> [task args]
    
    Examples:
      mix ws deps.get        # Run deps.get in all projects
      mix ws test            # Run tests in all projects
      mix ws compile --force # Force compile all projects
      mix ws format --check  # Check formatting in all projects
    """)
  end

  def run([task | rest]) do
    Application.ensure_all_started(:jido_workspace)
    JidoWorkspace.ensure_workspace_env()
    JidoWorkspace.Runner.run_task_all(task, rest)
  end
end
