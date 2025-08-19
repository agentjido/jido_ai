defmodule JidoWorkspace.Runner do
  @moduledoc """
  Executes Mix tasks across all workspace projects.
  """

  require Logger

  @doc """
  Run a Mix task across all workspace projects.
  """
  def run_task_all(task, args \\ []) do
    Logger.info("Running 'mix #{task} #{Enum.join(args, " ")}' across all projects...")

    JidoWorkspace.config()
    |> Enum.map(&run_task_in_project(&1, task, args))
    |> Enum.all?(&(&1 == :ok))
    |> case do
      true ->
        Logger.info("Task '#{task}' completed successfully in all projects")
        :ok

      false ->
        Logger.error("Task '#{task}' failed in some projects")
        :error
    end
  end

  @doc """
  Run a Mix task in a specific project.
  """
  def run_task_in_project(%{name: name, path: path}, task, args) do
    if File.exists?(path) do
      Logger.info("Running in #{name}...")

      case System.cmd("mix", [task | args], cd: path, stderr_to_stdout: true) do
        {output, 0} ->
          Logger.info("✓ #{name}: #{task} completed")
          Logger.debug(output)
          :ok

        {output, code} ->
          Logger.error("✗ #{name}: #{task} failed (exit code: #{code})")
          Logger.error(output)
          :error
      end
    else
      Logger.warning("Skipping #{name}: project directory not found at #{path}")
      :ok
    end
  end

  @doc """
  Run a Mix task in a specific project directory.
  """
  def run_task_single(project_path, task, args \\ []) do
    case System.cmd("mix", [task | args], cd: project_path, stderr_to_stdout: true) do
      {output, 0} ->
        Logger.info("Task '#{task}' completed successfully")
        Logger.debug(output)
        :ok

      {output, code} ->
        Logger.error("Task '#{task}' failed (exit code: #{code})")
        Logger.error(output)
        {:error, {code, output}}
    end
  end
end
