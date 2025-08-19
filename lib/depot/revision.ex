defmodule Depot.Revision do
  @moduledoc """
  Represents a Git revision/commit in the Depot filesystem.

  Contains metadata about a specific point in the repository's history.
  """

  @enforce_keys [:sha, :author_name, :author_email, :message, :timestamp]
  defstruct [:sha, :author_name, :author_email, :message, :timestamp]

  @type t :: %__MODULE__{
          sha: String.t(),
          author_name: String.t(),
          author_email: String.t(),
          message: String.t(),
          timestamp: DateTime.t()
        }
end
