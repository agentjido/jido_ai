defmodule Mix.Tasks.Ws.Upgrade.Deps do
  @moduledoc """
  Upgrade dependencies across all projects in the workspace.
  """
  @shortdoc "Check/upgrade dependencies for all workspace projects"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:jido_workspace)
    JidoWorkspace.ensure_workspace_env()

    {opts, remaining_args} = parse_args(args)

    case remaining_args do
      [] ->
        if opts[:check] do
          JidoWorkspace.Runner.run_task_all("hex.outdated", [])
        else
          upgrade_all_deps(opts)
        end

      [project_name] ->
        projects = JidoWorkspace.config()

        case Enum.find(projects, &(&1.name == project_name)) do
          nil ->
            IO.puts("Project '#{project_name}' not found")
            System.halt(1)

          project ->
            if opts[:check] do
              JidoWorkspace.Runner.run_task_in_project(project, "hex.outdated", [])
            else
              upgrade_single_project(project, opts)
            end
        end

      _ ->
        print_usage()
        System.halt(1)
    end
  end

  defp parse_args(args) do
    {opts, remaining} =
      Enum.reduce(args, {[], []}, fn arg, {opts, remaining} ->
        case arg do
          "--check" -> {[check: true] ++ opts, remaining}
          "--upgrade" -> {[upgrade: true] ++ opts, remaining}
          _ -> {opts, [arg | remaining]}
        end
      end)

    {opts, Enum.reverse(remaining)}
  end

  defp upgrade_all_deps(opts) do
    IO.puts("Upgrading dependencies for all projects...")

    projects = JidoWorkspace.config()

    results =
      Enum.map(projects, fn project ->
        IO.puts("\n=== Upgrading #{project.name} ===")
        result = upgrade_project_deps(project.path, opts)
        {project.name, result}
      end)

    print_upgrade_summary(results)
  end

  defp upgrade_single_project(project, opts) do
    IO.puts("Upgrading dependencies for #{project.name}...")

    case upgrade_project_deps(project.path, opts) do
      {0, _} ->
        IO.puts("✓ Dependencies upgraded successfully")

      {code, output} ->
        IO.puts("✗ Dependency upgrade failed (exit code: #{code})")
        IO.puts(output)
        System.halt(code)
    end
  end

  defp upgrade_project_deps(project_path, _opts) do
    with {0, _} <- run_mix_in_project(project_path, ["deps.get"]),
         {0, _} <- run_mix_in_project(project_path, ["deps.unlock", "--all"]),
         {0, _} <- run_mix_in_project(project_path, ["deps.update", "--all"]) do
      {0, "Success"}
    else
      {exit_code, output} -> {exit_code, output}
    end
  end

  defp run_mix_in_project(project_path, args) do
    case System.cmd("mix", args, cd: project_path, stderr_to_stdout: true) do
      {output, exit_code} -> {exit_code, output}
    end
  end

  defp print_upgrade_summary(results) do
    IO.puts("\n=== Dependency Upgrade Summary ===")

    {successful, failed} = Enum.split_with(results, fn {_name, {code, _}} -> code == 0 end)

    Enum.each(successful, fn {project_name, _} ->
      IO.puts("✓ #{project_name}")
    end)

    Enum.each(failed, fn {project_name, {code, _}} ->
      IO.puts("✗ #{project_name} (exit code: #{code})")
    end)

    IO.puts("\nSuccessful: #{length(successful)}, Failed: #{length(failed)}")

    if length(failed) > 0 do
      System.halt(1)
    end
  end

  defp print_usage do
    IO.puts("""
    Usage: mix ws.upgrade.deps [project_name] [options]

    Options:
      --check    Only check for outdated dependencies, don't upgrade
      --upgrade  Upgrade dependencies (default behavior)

    Examples:
      mix ws.upgrade.deps                    # Upgrade all projects
      mix ws.upgrade.deps --check           # Check all for outdated deps
      mix ws.upgrade.deps jido              # Upgrade specific project
    """)
  end
end
