defmodule Depot.Adapter.Git do
  @moduledoc """
  Depot Adapter for Git repositories with versioning support.

  This adapter provides filesystem operations backed by a Git repository,
  with automatic or manual commit modes for version control.

  ## Direct usage

      filesystem = Depot.Adapter.Git.configure(
        path: "/path/to/repo",
        mode: :manual,
        author: [name: "Bot", email: "bot@example.com"]
      )
      
      Depot.write(filesystem, "file.txt", "content")
      Depot.commit(filesystem, "Add new file")

  ## Options

    * `:path` - Path to Git repository (will be created if doesn't exist)
    * `:branch` - Git branch to use (defaults to current branch or "main")
    * `:mode` - `:auto` commits on every operation, `:manual` requires explicit commits
    * `:author` - Author info `[name: "Name", email: "email@domain.com"]`
    * `:commit_message` - Function to generate commit messages `(operation_info) -> String.t()`

  """

  alias Depot.Adapter.Local
  alias Depot.Revision

  defmodule Config do
    @enforce_keys [:repo_path, :branch, :author_name, :author_email, :auto_commit?, :local_config]
    defstruct [
      :repo_path,
      :branch,
      :author_name,
      :author_email,
      :auto_commit?,
      :local_config,
      commit_message: &__MODULE__.default_commit_message/1
    ]

    @type t :: %__MODULE__{
            repo_path: String.t(),
            branch: String.t(),
            author_name: String.t(),
            author_email: String.t(),
            auto_commit?: boolean(),
            local_config: Local.Config.t(),
            commit_message: (map() -> String.t())
          }

    def default_commit_message(%{operation: op, path: path}) do
      "Depot #{op} #{path} at #{DateTime.utc_now() |> DateTime.to_iso8601()}"
    end
  end

  @behaviour Depot.Adapter
  @behaviour Depot.Adapter.Versioning

  @impl Depot.Adapter
  @spec configure(keyword()) :: {__MODULE__, Config.t()}
  def configure(opts) do
    repo_path = Keyword.fetch!(opts, :path)
    mode = Keyword.get(opts, :mode, :manual)
    branch = Keyword.get(opts, :branch)
    author = Keyword.get(opts, :author, [])
    commit_message_fn = Keyword.get(opts, :commit_message, &Config.default_commit_message/1)

    # Ensure Git is available
    case System.find_executable("git") do
      nil -> raise "Git executable not found in PATH"
      _ -> :ok
    end

    # Initialize or validate repository
    {repo_path, current_branch} = setup_repository(repo_path, branch)

    # Configure local adapter for actual file operations
    local_config = Local.configure(prefix: repo_path) |> elem(1)

    config = %Config{
      repo_path: repo_path,
      branch: current_branch,
      author_name: Keyword.get(author, :name, "Depot"),
      author_email: Keyword.get(author, :email, "depot@localhost"),
      auto_commit?: mode == :auto,
      local_config: local_config,
      commit_message: commit_message_fn
    }

    {__MODULE__, config}
  end

  defp setup_repository(path, target_branch) do
    path = Path.expand(path)

    # Create directory if it doesn't exist
    File.mkdir_p!(path)

    # Initialize repo if not already a Git repo
    unless File.exists?(Path.join(path, ".git")) do
      git!(path, ["init"])
      # Create initial commit to establish branch
      File.write!(Path.join(path, ".gitkeep"), "")
      git!(path, ["add", ".gitkeep"])
      git!(path, ["commit", "-m", "Initial commit"])
    end

    # Get current branch
    current_branch = get_current_branch(path)

    # Handle branch selection
    final_branch =
      cond do
        target_branch == nil ->
          # Use current branch
          current_branch

        target_branch == current_branch ->
          # Already on target branch
          current_branch

        branch_exists?(path, target_branch) ->
          # Switch to existing branch
          git!(path, ["checkout", target_branch])
          target_branch

        true ->
          # Create and switch to new branch
          git!(path, ["checkout", "-b", target_branch])
          target_branch
      end

    {path, final_branch}
  end

  defp get_current_branch(repo_path) do
    case git(repo_path, ["branch", "--show-current"]) do
      {output, 0} ->
        String.trim(output)

      _ ->
        # Fallback for older Git versions or detached HEAD
        case git(repo_path, ["symbolic-ref", "--short", "HEAD"]) do
          {output, 0} -> String.trim(output)
          _ -> "main"
        end
    end
  end

  defp branch_exists?(repo_path, branch) do
    case git(repo_path, ["show-ref", "--verify", "--quiet", "refs/heads/#{branch}"]) do
      {_, 0} -> true
      _ -> false
    end
  end

  defp git!(repo_path, args) do
    case git(repo_path, args) do
      {output, 0} -> output
      {output, code} -> raise "Git command failed (#{code}): #{output}"
    end
  end

  defp git(repo_path, args) do
    System.cmd("git", args, cd: repo_path, stderr_to_stdout: true)
  end

  defp stage_and_commit(config, operation_info) do
    # Stage all changes
    git!(config.repo_path, ["add", "-A"])

    # Check if there are any changes to commit
    case git(config.repo_path, ["diff", "--cached", "--quiet"]) do
      {_, 0} ->
        # No changes to commit
        :ok

      _ ->
        # There are changes, commit them
        message = config.commit_message.(operation_info)

        git!(config.repo_path, [
          "-c",
          "user.name=#{config.author_name}",
          "-c",
          "user.email=#{config.author_email}",
          "commit",
          "-m",
          message
        ])

        :ok
    end
  end

  defp maybe_auto_commit(config, operation_info) do
    if config.auto_commit? do
      stage_and_commit(config, operation_info)
    else
      # Just stage the changes
      git!(config.repo_path, ["add", "-A"])
      :ok
    end
  end

  # Delegate all standard filesystem operations to Local adapter
  # then handle Git operations

  @impl Depot.Adapter
  def write(config, path, contents, opts) do
    case Local.write(config.local_config, path, contents, opts) do
      :ok ->
        maybe_auto_commit(config, %{operation: :write, path: path})

      error ->
        error
    end
  end

  @impl Depot.Adapter
  def read(config, path) do
    Local.read(config.local_config, path)
  end

  @impl Depot.Adapter
  def read_stream(config, path, opts) do
    Local.read_stream(config.local_config, path, opts)
  end

  @impl Depot.Adapter
  def write_stream(config, path, opts) do
    case Local.write_stream(config.local_config, path, opts) do
      {:ok, stream} ->
        # Return the stream directly - auto-commit will need to be handled externally
        {:ok, stream}

      error ->
        error
    end
  end

  @impl Depot.Adapter
  def delete(config, path) do
    case Local.delete(config.local_config, path) do
      :ok ->
        maybe_auto_commit(config, %{operation: :delete, path: path})

      error ->
        error
    end
  end

  @impl Depot.Adapter
  def move(config, source, destination, opts) do
    case Local.move(config.local_config, source, destination, opts) do
      :ok ->
        maybe_auto_commit(config, %{operation: :move, path: "#{source} -> #{destination}"})

      error ->
        error
    end
  end

  @impl Depot.Adapter
  def copy(config, source, destination, opts) do
    case Local.copy(config.local_config, source, destination, opts) do
      :ok ->
        maybe_auto_commit(config, %{operation: :copy, path: "#{source} -> #{destination}"})

      error ->
        error
    end
  end

  @impl Depot.Adapter
  def copy(_source_config, _source_path, _destination_config, _destination_path, _opts) do
    # Cross-adapter copy not supported for Git
    {:error, :unsupported}
  end

  @impl Depot.Adapter
  def file_exists(config, path) do
    Local.file_exists(config.local_config, path)
  end

  @impl Depot.Adapter
  def list_contents(config, path) do
    Local.list_contents(config.local_config, path)
  end

  @impl Depot.Adapter
  def create_directory(config, path, opts) do
    case Local.create_directory(config.local_config, path, opts) do
      :ok ->
        # Git doesn't track empty directories, so create a .gitkeep file
        gitkeep_path = Path.join(path, ".gitkeep")

        case Local.write(config.local_config, gitkeep_path, "", []) do
          :ok ->
            maybe_auto_commit(config, %{operation: :create_directory, path: path})

          error ->
            error
        end

      error ->
        error
    end
  end

  @impl Depot.Adapter
  def delete_directory(config, path, opts) do
    case Local.delete_directory(config.local_config, path, opts) do
      :ok ->
        maybe_auto_commit(config, %{operation: :delete_directory, path: path})

      error ->
        error
    end
  end

  @impl Depot.Adapter
  def clear(config) do
    case Local.clear(config.local_config) do
      :ok ->
        maybe_auto_commit(config, %{operation: :clear, path: "."})

      error ->
        error
    end
  end

  @impl Depot.Adapter
  def set_visibility(config, path, visibility) do
    case Local.set_visibility(config.local_config, path, visibility) do
      :ok ->
        maybe_auto_commit(config, %{operation: :set_visibility, path: path})

      error ->
        error
    end
  end

  @impl Depot.Adapter
  def visibility(config, path) do
    Local.visibility(config.local_config, path)
  end

  @impl Depot.Adapter
  def starts_processes, do: false

  # Versioning behaviour implementation

  @impl Depot.Adapter.Versioning
  @spec commit(Config.t(), String.t() | nil, keyword()) :: :ok | {:error, term}
  def commit(config, message \\ nil, _opts \\ []) do
    try do
      # Stage all changes first
      git!(config.repo_path, ["add", "-A"])

      # Check if there are any changes to commit
      case git(config.repo_path, ["diff", "--cached", "--quiet"]) do
        {_, 0} ->
          # No changes to commit
          :ok

        _ ->
          # There are changes, commit them
          commit_message =
            message || "Manual commit at #{DateTime.utc_now() |> DateTime.to_iso8601()}"

          git!(config.repo_path, [
            "-c",
            "user.name=#{config.author_name}",
            "-c",
            "user.email=#{config.author_email}",
            "commit",
            "-m",
            commit_message
          ])

          :ok
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @impl Depot.Adapter.Versioning
  @spec revisions(Config.t(), String.t(), keyword()) :: {:ok, [Revision.t()]} | {:error, term}
  def revisions(config, path \\ ".", opts \\ []) do
    try do
      limit = Keyword.get(opts, :limit)

      args = ["log", "--pretty=format:%H|%an|%ae|%at|%s"]
      args = if limit, do: args ++ ["--max-count=#{limit}"], else: args
      args = if path != "." and path != "", do: args ++ ["--", path], else: args

      case git(config.repo_path, args) do
        {output, 0} ->
          revisions =
            output
            |> String.split("\n", trim: true)
            |> Enum.map(&parse_revision_line/1)

          {:ok, revisions}

        {error, _code} ->
          {:error, error}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp parse_revision_line(line) do
    [sha, author_name, author_email, timestamp, message] = String.split(line, "|", parts: 5)

    datetime =
      timestamp
      |> String.to_integer()
      |> DateTime.from_unix!()

    %Revision{
      sha: sha,
      author_name: author_name,
      author_email: author_email,
      message: message,
      timestamp: datetime
    }
  end

  @impl Depot.Adapter.Versioning
  @spec read_revision(Config.t(), String.t(), String.t(), keyword()) ::
          {:ok, binary()} | {:error, term}
  def read_revision(config, path, sha, _opts \\ []) do
    try do
      case git(config.repo_path, ["show", "#{sha}:#{path}"]) do
        {output, 0} -> {:ok, output}
        {error, _code} -> {:error, error}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @impl Depot.Adapter.Versioning
  @spec rollback(Config.t(), String.t(), keyword()) :: :ok | {:error, term}
  def rollback(config, sha, opts \\ []) do
    try do
      if path = Keyword.get(opts, :path) do
        # Rollback single file
        git!(config.repo_path, ["checkout", sha, "--", path])
      else
        # Rollback entire repository
        git!(config.repo_path, ["reset", "--hard", sha])
      end

      :ok
    rescue
      e -> {:error, Exception.message(e)}
    end
  end
end
