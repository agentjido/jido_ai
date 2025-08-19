defmodule Mix.Tasks.Ws.Status.Detailed do
  @moduledoc """
  Provides a comprehensive status report across all workspace projects.

  ## Usage

      mix ws.status.detailed
      mix ws.report
      mix ws.report --clear-cache     # Clear cache and run fresh checks
      mix ws.report --refresh-all     # Refresh all cached results
      mix ws.report --dialyxir        # Refresh only dialyxir cache
      mix ws.report --credo           # Refresh only credo cache
      mix ws.report --outdated        # Refresh only outdated cache
      mix ws.report --format          # Refresh only format cache
      mix ws.report --packages pkg1,pkg2  # Filter to specific packages
      mix ws.report --upstream        # Refresh only upstream cache
      mix ws.report --local           # Refresh only local changes cache

  Displays a table with compilation, test, dialyxir, credo, outdated deps, format, upstream, and local changes status.
  Results are cached locally in .cache/ws_status/ to speed up subsequent runs.
  """

  use Mix.Task
  require Logger

  @shortdoc "Show comprehensive status report for all workspace projects"

  # Configurable timeout - default 5 minutes
  @default_compile_timeout 300_000
  @compile_timeout String.to_integer(
                     System.get_env("WS_COMPILE_TIMEOUT") || 
                     Integer.to_string(@default_compile_timeout)
                   )

  # Cache configuration
  @cache_dir Path.join([File.cwd!(), ".cache", "ws_status"])

  def run(args) do
    Mix.Task.run("loadconfig")
    
    # Handle cache operations
    refresh_types = get_refresh_types(args)
    package_filter = get_package_filter(args)
    
    if "--clear-cache" in args do
      clear_cache()
      IO.puts("Cache cleared.\n")
    end
    
    projects = Application.get_env(:jido_workspace, :projects, [])
    
    # Filter projects if package filter is provided
    filtered_projects = if package_filter do
      Enum.filter(projects, &(&1[:name] in package_filter))
    else
      projects
    end
    
    # Ensure cache directory exists
    File.mkdir_p!(@cache_dir)
    
    IO.puts("\nWorkspace Status Report\n")
    if package_filter do
      IO.puts("Filtering to packages: #{Enum.join(package_filter, ", ")}")
      IO.puts("Found #{length(filtered_projects)} projects after filtering\n")
    end
    IO.puts("Checking all projects asynchronously...\n")
    
    results = 
      filtered_projects
      |> Enum.sort_by(& &1[:name])
      |> Task.async_stream(&check_project_status(&1, refresh_types), 
           timeout: @compile_timeout + 30_000, 
           max_concurrency: min(System.schedulers_online(), 4))
      |> Enum.map(fn {:ok, result} -> result end)
    
    display_status_table(results)
  end

  defp get_refresh_types(args) do
    refresh_types = MapSet.new()
    
    refresh_types = if "--refresh-all" in args, do: MapSet.put(refresh_types, :all), else: refresh_types
    refresh_types = if "--dialyxir" in args, do: MapSet.put(refresh_types, :dialyxir), else: refresh_types
    refresh_types = if "--credo" in args, do: MapSet.put(refresh_types, :credo), else: refresh_types
    refresh_types = if "--outdated" in args, do: MapSet.put(refresh_types, :outdated), else: refresh_types
    refresh_types = if "--format" in args, do: MapSet.put(refresh_types, :format), else: refresh_types
    refresh_types = if "--upstream" in args, do: MapSet.put(refresh_types, :upstream), else: refresh_types
    refresh_types = if "--local" in args, do: MapSet.put(refresh_types, :local), else: refresh_types
    
    refresh_types
  end

  defp get_package_filter(args) do
    # Handle both --packages=value and --packages value formats
    case Enum.find_index(args, &(&1 == "--packages" or String.starts_with?(&1, "--packages="))) do
      nil -> nil
      index ->
        if String.starts_with?(Enum.at(args, index), "--packages=") do
          # Format: --packages=value
          Enum.at(args, index)
          |> String.replace_prefix("--packages=", "")
          |> String.split(",")
          |> Enum.map(&String.trim/1)
        else
          # Format: --packages value
          case Enum.at(args, index + 1) do
            nil -> nil
            value -> 
              value
              |> String.split(",")
              |> Enum.map(&String.trim/1)
          end
        end
    end
  end

  defp clear_cache do
    if File.exists?(@cache_dir) do
      File.rm_rf!(@cache_dir)
    end
  end

  defp check_project_status(project, refresh_types) do
    project_path = Path.join([File.cwd!(), project[:path]])
    
    IO.puts("Checking #{project[:name]}...")
    
    %{
      name: project[:name],
      version: get_version(project_path),
      branch: get_current_branch(project_path),
      compile_clean: get_compile_status(project_path),
      tests: get_test_status(project_path),
      dialyxir: get_dialyxir_status(project_path, refresh_types),
      credo: get_credo_status(project_path, refresh_types),
      outdated: get_outdated_status(project_path, refresh_types),
      format: get_format_status(project_path, refresh_types),
      upstream: get_upstream_status(project, refresh_types),
      local: get_local_changes_status(project, refresh_types)
    }
  end

  defp get_version(project_path) do
    mix_exs_path = Path.join(project_path, "mix.exs")
    
    if File.exists?(mix_exs_path) do
      try do
        content = File.read!(mix_exs_path)
        # Try module attribute format first (@version "x.y.z")
        case Regex.run(~r/@version\s+"([^"]+)"/, content) do
          [_, version] -> version
          _ ->
            # Fall back to inline format (version: "x.y.z")
            case Regex.run(~r/version:\s*"([^"]+)"/, content) do
              [_, version] -> version
              _ -> "unknown"
            end
        end
      rescue
        _ -> "unknown"
      end
    else
      "N/A"
    end
  end

  defp get_current_branch(project_path) do
    try do
      {result, 0} = System.cmd("git", ["branch", "--show-current"], cd: project_path, stderr_to_stdout: true)
      String.trim(result)
    rescue
      _ -> "unknown"
    end
  end

  defp get_compile_status(project_path) do
    mix_exs = Path.join(project_path, "mix.exs")

    if not File.exists?(mix_exs) do
      "N/A"
    else
      # Get dependencies first
      _ = System.cmd("mix", ["deps.get", "--only", "prod"], 
                     cd: project_path, stderr_to_stdout: true)

      try do
        {output, exit_code} = System.cmd("mix", ["compile", "--force", "--warnings-as-errors"], 
                                        cd: project_path, 
                                        stderr_to_stdout: true)

        cond do
          exit_code != 0 -> "FAIL"
          String.contains?(output, "warning") -> "WARN"
          true -> "PASS"
        end
      catch
        :exit, {:timeout, _} -> "TIMEOUT"
        _kind, _reason -> "ERROR"
      end
    end
  end

  defp get_test_status(project_path) do
    mix_exs = Path.join(project_path, "mix.exs")

    if not File.exists?(mix_exs) do
      "N/A"
    else
      # Get test dependencies first
      _ = System.cmd("mix", ["deps.get"], 
                     cd: project_path, 
                     stderr_to_stdout: true,
                     env: [{"MIX_ENV", "test"}])

      try do
        {output, exit_code} = System.cmd("mix", ["test"], 
                                        cd: project_path, 
                                        stderr_to_stdout: true,
                                        env: [{"MIX_ENV", "test"}])

        cond do
          exit_code == 0 -> "PASS"
          String.contains?(output, "0 failures") -> "PASS"
          String.contains?(output, "no tests to run") -> "N/A"
          true -> "FAIL"
        end
      catch
        :exit, {:timeout, _} -> "TIMEOUT"
        kind, reason -> 
          Logger.debug("Test error in #{Path.basename(project_path)}: #{inspect(kind)} #{inspect(reason)}")
          "ERROR"
      end
    end
  end

  defp get_cache_key(project_path, check_type) do
    project_name = Path.basename(project_path)
    "#{project_name}_#{check_type}"
  end

  defp get_cache_file(cache_key) do
    Path.join(@cache_dir, "#{cache_key}.cache")
  end

  defp read_cache(cache_key) do
    cache_file = get_cache_file(cache_key)
    
    if File.exists?(cache_file) do
      case File.read(cache_file) do
        {:ok, content} -> String.trim(content)
        _ -> nil
      end
    else
      nil
    end
  end

  defp write_cache(cache_key, value) do
    cache_file = get_cache_file(cache_key)
    File.write(cache_file, value)
  end

  defp get_dialyxir_status(project_path, refresh_types) do
    cache_key = get_cache_key(project_path, "dialyxir")
    
    should_refresh = MapSet.member?(refresh_types, :all) or MapSet.member?(refresh_types, :dialyxir)
    
    case {should_refresh, read_cache(cache_key)} do
      {true, _} ->
        status = run_dialyxir_check(project_path)
        write_cache(cache_key, status)
        status
      {false, nil} ->
        status = run_dialyxir_check(project_path)
        write_cache(cache_key, status)
        status
      {false, cached_status} -> 
        cached_status
    end
  end

  defp run_dialyxir_check(project_path) do
    mix_exs = Path.join(project_path, "mix.exs")

    if not File.exists?(mix_exs) do
      "N/A"
    else
      try do
        {output, exit_code} = System.cmd("mix", ["dialyzer"], 
                                        cd: project_path, 
                                        stderr_to_stdout: true,
                                        env: [{"MIX_ENV", "dev"}])

        cond do
          exit_code == 0 -> "PASS"
          String.contains?(output, "done (passed successfully)") -> "PASS"
          String.contains?(output, "dialyzer") and String.contains?(output, "not found") -> "N/A"
          true -> "FAIL"
        end
      catch
        :exit, {:timeout, _} -> "TIMEOUT"
        _kind, _reason -> "N/A"
      end
    end
  end

  defp get_credo_status(project_path, refresh_types) do
    cache_key = get_cache_key(project_path, "credo")
    
    should_refresh = MapSet.member?(refresh_types, :all) or MapSet.member?(refresh_types, :credo)
    
    case {should_refresh, read_cache(cache_key)} do
      {true, _} ->
        status = run_credo_check(project_path)
        write_cache(cache_key, status)
        status
      {false, nil} ->
        status = run_credo_check(project_path)
        write_cache(cache_key, status)
        status
      {false, cached_status} -> 
        cached_status
    end
  end

  defp run_credo_check(project_path) do
    mix_exs = Path.join(project_path, "mix.exs")

    if not File.exists?(mix_exs) do
      "N/A"
    else
      try do
        {output, exit_code} = System.cmd("mix", ["credo"], 
                                        cd: project_path, 
                                        stderr_to_stdout: true,
                                        env: [{"MIX_ENV", "dev"}])

        cond do
          exit_code == 0 -> "PASS"
          String.contains?(output, "credo") and String.contains?(output, "not found") -> "N/A"
          true -> "FAIL"
        end
      catch
        :exit, {:timeout, _} -> "TIMEOUT"
        _kind, _reason -> "N/A"
      end
    end
  end

  defp get_outdated_status(project_path, refresh_types) do
    cache_key = get_cache_key(project_path, "outdated")
    
    should_refresh = MapSet.member?(refresh_types, :all) or MapSet.member?(refresh_types, :outdated)
    
    case {should_refresh, read_cache(cache_key)} do
      {true, _} ->
        status = run_outdated_check(project_path)
        write_cache(cache_key, status)
        status
      {false, nil} ->
        status = run_outdated_check(project_path)
        write_cache(cache_key, status)
        status
      {false, cached_status} -> 
        cached_status
    end
  end

  defp run_outdated_check(project_path) do
    mix_exs = Path.join(project_path, "mix.exs")

    if not File.exists?(mix_exs) do
      "N/A"
    else
      try do
        {output, exit_code} = System.cmd("mix", ["hex.outdated"], 
                                        cd: project_path, 
                                        stderr_to_stdout: true)

        cond do
          exit_code == 0 and String.contains?(output, "Up-to-date") -> "PASS"
          exit_code == 0 and not String.contains?(output, "Update available") -> "PASS"
          exit_code == 0 -> "OUTDATED"
          true -> "ERROR"
        end
      catch
        :exit, {:timeout, _} -> "TIMEOUT"
        _kind, _reason -> "ERROR"
      end
    end
  end

  defp get_format_status(project_path, refresh_types) do
    cache_key = get_cache_key(project_path, "format")
    
    should_refresh = MapSet.member?(refresh_types, :all) or MapSet.member?(refresh_types, :format)
    
    case {should_refresh, read_cache(cache_key)} do
      {true, _} ->
        status = run_format_check(project_path)
        write_cache(cache_key, status)
        status
      {false, nil} ->
        status = run_format_check(project_path)
        write_cache(cache_key, status)
        status
      {false, cached_status} -> 
        cached_status
    end
  end

  defp run_format_check(project_path) do
    mix_exs = Path.join(project_path, "mix.exs")

    if not File.exists?(mix_exs) do
      "N/A"
    else
      try do
        {_output, exit_code} = System.cmd("mix", ["format", "--check-formatted"], 
                                         cd: project_path, 
                                         stderr_to_stdout: true)

        if exit_code == 0, do: "PASS", else: "FAIL"
      catch
        :exit, {:timeout, _} -> "TIMEOUT"
        _kind, _reason -> "ERROR"
      end
    end
  end

  defp get_upstream_status(project, refresh_types) do
    cache_key = get_cache_key(project[:path], "upstream")
    
    should_refresh = MapSet.member?(refresh_types, :all) or MapSet.member?(refresh_types, :upstream)
    
    case {should_refresh, read_cache(cache_key)} do
      {true, _} ->
        status = run_upstream_check(project)
        write_cache(cache_key, status)
        status
      {false, nil} ->
        status = run_upstream_check(project)
        write_cache(cache_key, status)
        status
      {false, cached_status} -> 
        cached_status
    end
  end

  defp run_upstream_check(project) do
    workspace_root = File.cwd!()
    
    try do
      # Fetch from upstream to get latest commits
      {_output, fetch_exit} = System.cmd("git", ["fetch", project[:upstream_url], project[:branch]], 
                                        cd: workspace_root, 
                                        stderr_to_stdout: true)

      if fetch_exit != 0 do
        "ERROR"
      else
        # Get the last subtree commit hash for this project
        {log_output, log_exit} = System.cmd("git", ["log", "--grep=git-subtree-dir: #{project[:path]}", "--pretty=format:%H", "-1"], 
                                           cd: workspace_root, 
                                           stderr_to_stdout: true)

        if log_exit != 0 or String.trim(log_output) == "" do
          "N/A"
        else
          last_subtree_commit = String.trim(log_output)
          
          # Get the commit that was merged in that subtree operation
          {show_output, show_exit} = System.cmd("git", ["show", "--pretty=format:%B", "-s", last_subtree_commit], 
                                               cd: workspace_root, 
                                               stderr_to_stdout: true)

          if show_exit != 0 do
            "ERROR"
          else
            # Extract the upstream commit hash from the merge message
            case Regex.run(~r/git-subtree-split:\s+([a-f0-9]+)/m, show_output) do
              [_, upstream_commit] ->
                # Check if FETCH_HEAD (latest upstream) is ahead of our last merged commit
                {rev_list_output, rev_list_exit} = System.cmd("git", ["rev-list", "--count", "#{upstream_commit}..FETCH_HEAD"], 
                                                             cd: workspace_root, 
                                                             stderr_to_stdout: true)

                if rev_list_exit == 0 do
                  ahead_count = String.trim(rev_list_output) |> String.to_integer()
                  if ahead_count > 0, do: "BEHIND", else: "CURRENT"
                else
                  "ERROR"
                end
              _ ->
                "N/A"
            end
          end
        end
      end
    catch
      :exit, {:timeout, _} -> "TIMEOUT"
      _kind, _reason -> "ERROR"
    end
  end

  defp get_local_changes_status(project, refresh_types) do
    cache_key = get_cache_key(project[:path], "local")
    
    should_refresh = MapSet.member?(refresh_types, :all) or MapSet.member?(refresh_types, :local)
    
    case {should_refresh, read_cache(cache_key)} do
      {true, _} ->
        status = run_local_changes_check(project)
        write_cache(cache_key, status)
        status
      {false, nil} ->
        status = run_local_changes_check(project)
        write_cache(cache_key, status)
        status
      {false, cached_status} -> 
        cached_status
    end
  end

  defp run_local_changes_check(project) do
    workspace_root = File.cwd!()
    
    try do
      # Get the last subtree commit hash for this project
      {log_output, log_exit} = System.cmd("git", ["log", "--grep=git-subtree-dir: #{project[:path]}", "--pretty=format:%H", "-1"], 
                                         cd: workspace_root, 
                                         stderr_to_stdout: true)

      if log_exit != 0 or String.trim(log_output) == "" do
        "N/A"
      else
        last_subtree_commit = String.trim(log_output)
        
        # Check if there are any commits in the subtree directory since the last subtree operation
        {diff_output, diff_exit} = System.cmd("git", ["diff", "--name-only", last_subtree_commit, "HEAD", "--", project[:path]], 
                                             cd: workspace_root, 
                                             stderr_to_stdout: true)

        if diff_exit != 0 do
          "ERROR"
        else
          if String.trim(diff_output) == "" do
            "CLEAN"
          else
            "MODIFIED"
          end
        end
      end
    catch
      :exit, {:timeout, _} -> "TIMEOUT"
      _kind, _reason -> "ERROR"
    end
  end

  defp display_status_table(results) do
    headers = [
      "Project",
      "Version", 
      "Branch",
      "Upstream",
      "Local",
      "Compile",
      "Tests",
      "Dialyxir",
      "Credo",
      "Outdated",
      "Format"
    ]
    
    rows = Enum.map(results, fn result ->
      [
        result.name,
        result.version,
        result.branch,
        result.upstream,
        result.local,
        result.compile_clean,
        result.tests,
        result.dialyxir,
        result.credo,
        result.outdated,
        result.format
      ]
    end)
    
    TableRex.quick_render!(rows, headers)
    |> IO.puts()
  end
end
