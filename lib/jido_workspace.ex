defmodule JidoWorkspace do
  @moduledoc """
  Git subtree-powered monorepo workspace manager for the Jido ecosystem.
  """

  require Logger

  @doc """
  Ensure JIDO_WORKSPACE environment variable is set for workspace operations.
  """
  def ensure_workspace_env do
    unless System.get_env("JIDO_WORKSPACE") do
      System.put_env("JIDO_WORKSPACE", "1")
    end
  end

  @doc """
  Check if the working tree is clean (no local modifications).
  """
  def check_clean_working_tree do
    repo = Git.new(".")
    
    case Git.status(repo, "--porcelain") do
      {:ok, ""} ->
        :ok

      {:ok, output} ->
        Logger.error(
          "Working tree has local modifications. Please commit or stash changes first:"
        )

        Logger.error(output)
        {:error, :dirty_working_tree}

      {:error, reason} ->
        Logger.error("Failed to check git status: #{reason}")
        {:error, :git_error}
    end
  end

  @doc """
  Get the workspace configuration.
  """
  def config do
    # Read config using Config.Reader for proper evaluation
    config_path = Path.join(File.cwd!(), "config/workspace.exs")

    case Config.Reader.read!(config_path) do
      [{:jido_workspace, workspace_config}] ->
        Keyword.get(workspace_config, :projects, [])

      _ ->
        []
    end
  end

  @doc """
  Pull all projects from their upstream repositories.
  """
  def sync_all do
    with :ok <- check_clean_working_tree() do
      Logger.info("Syncing all projects...")

      config()
      |> Enum.map(&pull_project(&1.name))
      |> Enum.all?(&(&1 == :ok))
      |> case do
        true ->
          Logger.info("All projects synced successfully")
          :ok

        false ->
          Logger.error("Some projects failed to sync")
          :error
      end
    else
      error -> error
    end
  end

  @doc """
  Pull a specific project from its upstream repository.
  """
  def pull_project(name) when is_binary(name) do
    with :ok <- check_clean_working_tree() do
      case find_project(name) do
        nil ->
          Logger.error("Project '#{name}' not found in workspace config")
          :error

        project ->
          Logger.info("Pulling project: #{project.name}")

          if File.exists?(project.path) do
            git_subtree_pull(project)
          else
            git_subtree_add(project)
          end
      end
    else
      error -> error
    end
  end

  @doc """
  Push changes for a specific project to its upstream repository.
  """
  def push_project(name, opts \\ []) when is_binary(name) do
    case find_project(name) do
      nil ->
        Logger.error("Project '#{name}' not found in workspace config")
        :error

      project ->
        branch = Keyword.get(opts, :branch, project.branch)
        Logger.info("Pushing project: #{project.name} to branch: #{branch}")
        git_subtree_push(project, branch)
    end
  end

  @doc """
  Run tests across all projects.
  """
  def test_all do
    Logger.info("Running tests for all projects...")

    config()
    |> Enum.filter(&(&1.type == :application))
    |> Enum.map(&test_project/1)
    |> Enum.all?(&(&1 == :ok))
    |> case do
      true ->
        Logger.info("All tests passed")
        :ok

      false ->
        Logger.error("Some tests failed")
        :error
    end
  end

  @doc """
  Show the status of the workspace and all projects.
  """
  def status do
    Logger.info("Workspace status:")

    config()
    |> Enum.each(fn project ->
      status = if File.exists?(project.path), do: "present", else: "missing"
      Logger.info("  #{project.name}: #{status} (#{project.type})")
    end)

    :ok
  end

  # Private functions

  defp find_project(name) do
    Enum.find(config(), &(&1.name == name))
  end

  defp git_subtree_add(%{name: name, upstream_url: url, branch: branch, path: path}) do
    repo = Git.new(".")
    
    case Git.subtree(repo, ["add", "--prefix=#{path}", url, branch, "--squash"]) do
      {:ok, output} ->
        Logger.info("Successfully added subtree: #{name}")
        Logger.debug(output)
        :ok

      {:error, reason} ->
        Logger.error("Failed to add subtree #{name}: #{reason}")
        :error
    end
  end

  defp git_subtree_pull(%{name: name, upstream_url: url, branch: branch, path: path}) do
    repo = Git.new(".")
    
    case Git.subtree(repo, ["pull", "--prefix=#{path}", url, branch, "--squash"]) do
      {:ok, output} ->
        Logger.info("Successfully pulled subtree: #{name}")
        Logger.debug(output)
        :ok

      {:error, reason} ->
        Logger.error("Failed to pull subtree #{name}: #{reason}")
        :error
    end
  end

  defp git_subtree_push(%{name: name, upstream_url: url, path: path}, target_branch) do
    repo = Git.new(".")
    
    case Git.subtree(repo, ["push", "--prefix=#{path}", url, target_branch]) do
      {:ok, output} ->
        Logger.info("Successfully pushed subtree: #{name}")
        Logger.debug(output)
        :ok

      {:error, reason} ->
        Logger.error("Failed to push subtree #{name}: #{reason}")
        :error
    end
  end

  defp test_project(%{name: name, path: path, type: :application}) do
    Logger.info("Testing project: #{name}")

    case System.cmd("mix", ["test"], cd: path, stderr_to_stdout: true) do
      {output, 0} ->
        Logger.info("Tests passed for #{name}")
        Logger.debug(output)
        :ok

      {output, code} ->
        Logger.error("Tests failed for #{name} (exit code: #{code})")
        Logger.error(output)
        :error
    end
  end

  defp test_project(%{type: :library}), do: :ok
end
