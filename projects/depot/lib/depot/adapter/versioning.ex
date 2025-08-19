defmodule Depot.Adapter.Versioning do
  @moduledoc """
  Behaviour for versioning operations in Depot adapters.

  This behaviour defines a consistent interface for version control operations
  that can be implemented by adapters that support versioning functionality.

  The versioning API is designed to be adapter-agnostic, allowing different
  storage backends to implement versioning in their own way while presenting
  a unified interface to the user.

  ## Types

    * `config` - Adapter configuration struct
    * `revision` - Version identifier (could be SHA, timestamp, ID, etc.)
    * `revision_info` - Structured information about a revision

  ## Callbacks

  All callbacks are optional, allowing adapters to implement only the
  versioning features they support.

  ### Core Operations

    * `commit/3` - Create a new version/commit
    * `revisions/3` - List available revisions for a path
    * `read_revision/4` - Read content at a specific revision

  ### Advanced Operations

    * `rollback/3` - Rollback to a previous revision
    * `diff/4` - Show differences between revisions
    * `merge/4` - Merge changes from another revision

  """

  @type config :: struct()
  @type revision :: any()
  @type revision_info :: %{
          revision: revision(),
          author_name: String.t(),
          author_email: String.t(),
          message: String.t(),
          timestamp: DateTime.t()
        }

  @doc """
  Commit staged changes with an optional message.

  Creates a new revision containing all current staged changes.
  The exact behavior depends on the adapter implementation.

  ## Options

    * `:author` - Override author information for this commit
    * `:timestamp` - Override timestamp for this commit

  ## Examples

      # Simple commit
      :ok = MyAdapter.commit(config, "Add new feature")

      # Commit with options
      :ok = MyAdapter.commit(config, "Fix bug", author: [name: "Dev", email: "dev@example.com"])

  """
  @callback commit(config, message :: String.t() | nil, opts :: keyword()) ::
              :ok | {:error, term()}

  @doc """
  List revisions for a given path.

  Returns a list of revision information ordered by most recent first.

  ## Options

    * `:limit` - Maximum number of revisions to return
    * `:since` - Only revisions after this datetime
    * `:until` - Only revisions before this datetime
    * `:author` - Only revisions by this author

  ## Examples

      # List all revisions for a file
      {:ok, revisions} = MyAdapter.revisions(config, "file.txt")

      # List last 10 revisions
      {:ok, revisions} = MyAdapter.revisions(config, ".", limit: 10)

  """
  @callback revisions(config, path :: Path.t(), opts :: keyword()) ::
              {:ok, [revision_info()]} | {:error, term()}

  @doc """
  Read the content of a file as it existed at a specific revision.

  ## Examples

      {:ok, content} = MyAdapter.read_revision(config, "file.txt", "abc123")

  """
  @callback read_revision(config, path :: Path.t(), revision, opts :: keyword()) ::
              {:ok, binary()} | {:error, term()}

  @doc """
  Rollback to a previous revision.

  The behavior depends on the adapter and options provided.

  ## Options

    * `:path` - Only rollback changes to a specific path (if supported)
    * `:create_commit` - Whether to create a new commit for the rollback

  ## Examples

      # Rollback entire filesystem
      :ok = MyAdapter.rollback(config, "abc123")

      # Rollback single file
      :ok = MyAdapter.rollback(config, "abc123", path: "file.txt")

  """
  @callback rollback(config, revision, opts :: keyword()) :: :ok | {:error, term()}

  @doc """
  Show differences between two revisions.

  ## Examples

      {:ok, diff} = MyAdapter.diff(config, "abc123", "def456")

  """
  @callback diff(config, from_revision :: revision, to_revision :: revision, opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Merge changes from another revision.

  ## Examples

      :ok = MyAdapter.merge(config, "feature-branch", "Merge feature branch")

  """
  @callback merge(
              config,
              from_revision :: revision,
              message :: String.t() | nil,
              opts :: keyword()
            ) ::
              :ok | {:error, term()}

  @optional_callbacks commit: 3,
                      revisions: 3,
                      read_revision: 4,
                      rollback: 3,
                      diff: 4,
                      merge: 4

  @doc """
  Check if an adapter supports versioning operations.

  Returns `true` if the adapter implements any versioning callbacks.
  """
  @spec versioning_supported?(module()) :: boolean()
  def versioning_supported?(adapter) do
    versioning_callbacks = [:commit, :revisions, :read_revision, :rollback, :diff, :merge]

    Enum.any?(versioning_callbacks, fn callback ->
      case callback do
        :commit -> function_exported?(adapter, :commit, 3)
        :revisions -> function_exported?(adapter, :revisions, 3)
        :read_revision -> function_exported?(adapter, :read_revision, 4)
        :rollback -> function_exported?(adapter, :rollback, 3)
        :diff -> function_exported?(adapter, :diff, 4)
        :merge -> function_exported?(adapter, :merge, 4)
      end
    end)
  end

  @doc """
  Get supported versioning operations for an adapter.

  Returns a list of atoms representing the versioning operations
  the adapter supports.
  """
  @spec supported_operations(module()) :: [atom()]
  def supported_operations(adapter) do
    [
      {:commit, 3},
      {:revisions, 3},
      {:read_revision, 4},
      {:rollback, 3},
      {:diff, 4},
      {:merge, 4}
    ]
    |> Enum.filter(fn {fun, arity} -> function_exported?(adapter, fun, arity) end)
    |> Enum.map(fn {fun, _arity} -> fun end)
  end
end
