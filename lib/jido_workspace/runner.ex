defmodule JidoWorkspace.Runner do
  @moduledoc """
  Common functionality for running Mix tasks across all workspace projects.
  """

  require Logger

  @doc """
  Run a mix task across all projects in the workspace.

  ## Parameters
  - `task` - The mix task to run (e.g., "test", "quality", "compile")
  - `args` - Additional arguments to pass to the task (default: [])
  - `opts` - Options for execution:
    - `:parallel` - Run tasks in parallel (default: false)
    - `:continue_on_error` - Continue running other projects if one fails (default: true)
    - `:show_output` - Show command output in real-time (default: true)

  ## Returns
  A list of `{project_path, result}` tuples where result is `{exit_code, output}`.
  """
  def run_task_all(task, args \\ [], opts \\ []) do
    projects = JidoWorkspace.config()
    parallel = Keyword.get(opts, :parallel, false)
    continue_on_error = Keyword.get(opts, :continue_on_error, true)
    show_output = Keyword.get(opts, :show_output, true)

    if show_output do
      IO.puts("Running 'mix #{task}' for all projects...")
    end

    runner_fn = fn project ->
      project_path = project.path

      if show_output do
        IO.puts("\n=== #{project.name} (#{project_path}) ===")
      end

      result = run_mix_task(project_path, task, args, show_output)
      {project_path, result}
    end

    results =
      if parallel do
        projects
        |> Task.async_stream(runner_fn, timeout: :infinity)
        |> Enum.map(fn {:ok, result} -> result end)
      else
        Enum.map(projects, runner_fn)
      end

    if show_output do
      print_summary(task, results, continue_on_error)
    end

    results
  end

  @doc """
  Run a mix task for a specific project.
  """
  def run_task_single(project_path, task, args \\ [], show_output \\ true) do
    if show_output do
      IO.puts("Running 'mix #{task}' for #{project_path}...")
    end

    result = run_mix_task(project_path, task, args, show_output)

    case result do
      {0, _} ->
        if show_output, do: IO.puts("✓ Task completed successfully")
        :ok

      {code, output} ->
        if show_output do
          IO.puts("✗ Task failed (exit code: #{code})")
          IO.puts(output)
        end

        {:error, {code, output}}
    end
  end

  defp run_mix_task(project_path, task, args, show_output) do
    full_args = [task | args]

    if show_output do
      {_, exit_code} =
        System.cmd("mix", full_args,
          cd: project_path,
          stderr_to_stdout: true,
          into: IO.stream(:stdio, :line)
        )

      {exit_code, ""}
    else
      case System.cmd("mix", full_args, cd: project_path, stderr_to_stdout: true) do
        {output, exit_code} -> {exit_code, output}
      end
    end
  end

  defp print_summary(task, results, continue_on_error) do
    IO.puts("\n=== #{String.upcase(task)} Summary ===")

    {passed, failed} = Enum.split_with(results, fn {_path, {code, _}} -> code == 0 end)

    Enum.each(passed, fn {project_path, _} ->
      project_name = Path.basename(project_path)
      IO.puts("✓ #{project_name}")
    end)

    Enum.each(failed, fn {project_path, {code, _}} ->
      project_name = Path.basename(project_path)
      IO.puts("✗ #{project_name} (exit code: #{code})")
    end)

    IO.puts("\nPassed: #{length(passed)}, Failed: #{length(failed)}")

    if length(failed) > 0 and not continue_on_error do
      System.halt(1)
    end
  end
end
