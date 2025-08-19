defmodule JidoWorkspace.Runner do
  @moduledoc """
  Executes Mix tasks across all workspace projects.
  """

  require Logger

  @doc """
  Run a Mix task across all workspace projects asynchronously.
  """
  def run_task_all(task, args \\ []) do
    Logger.info("Running 'mix #{task} #{Enum.join(args, " ")}' across all projects...")

    projects = JidoWorkspace.config()
    
    # Start async tasks for all projects
    async_tasks = 
      projects
      |> Enum.map(fn project ->
        Task.async(fn -> run_task_in_project(project, task, args) end)
      end)

    # Wait for all tasks to complete
    results = Task.await_many(async_tasks, :infinity)

    # Zip projects with results to track which succeeded/failed
    project_results = Enum.zip(projects, results)
    succeeded = Enum.filter(project_results, fn {_project, result} -> result == :ok end)
    failed = Enum.filter(project_results, fn {_project, result} -> result == :error end)

    case Enum.all?(results, &(&1 == :ok)) do
      true ->
        Logger.info("✓ Task '#{task}' completed successfully in all #{length(succeeded)} projects")
        print_final_summary(task, succeeded, failed)
        :ok

      false ->
        Logger.error("✗ Task '#{task}' failed: #{length(succeeded)} succeeded, #{length(failed)} failed")
        print_final_summary(task, succeeded, failed)
        :error
    end
  end

  defp print_final_summary(task, succeeded, failed) do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("WORKSPACE SUMMARY: mix #{task}")
    IO.puts(String.duplicate("=", 80))
    
    if Enum.empty?(failed) do
      IO.puts("SUCCESS: All #{length(succeeded)} projects completed successfully")
    else
      IO.puts("FAILED: #{length(succeeded)} succeeded, #{length(failed)} failed")
    end
    
    unless Enum.empty?(succeeded) do
      IO.puts("SUCCEEDED: #{Enum.map_join(succeeded, ", ", fn {project, _} -> project.name end)}")
    end
    
    unless Enum.empty?(failed) do
      IO.puts("FAILED: #{Enum.map_join(failed, ", ", fn {project, _} -> project.name end)}")
    end
    
    IO.puts(String.duplicate("=", 80) <> "\n")
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
