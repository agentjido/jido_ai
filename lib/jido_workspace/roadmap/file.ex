defmodule JidoWorkspace.Roadmap.File do
  @moduledoc """
  Represents a roadmap markdown file with metadata and content.
  """

  defstruct [:path, :meta, :body_lines, :tasks]

  @type t :: %__MODULE__{
          path: String.t(),
          meta: map(),
          body_lines: [String.t()],
          tasks: [JidoWorkspace.Roadmap.Task.t()]
        }

  @doc """
  Creates a new Roadmap.File struct from a file path.
  """
  def new(path) do
    %__MODULE__{
      path: path,
      meta: %{},
      body_lines: [],
      tasks: []
    }
  end

  @doc """
  Gets the project name from the file path.
  """
  def project(%__MODULE__{path: path}) do
    cond do
      String.contains?(path, "roadmap/workspace/") -> "workspace"
      String.contains?(path, "roadmap/projects/") ->
        path
        |> String.split("/")
        |> Enum.drop_while(&(&1 != "projects"))
        |> Enum.at(1, "unknown")
      true -> "unknown"
    end
  end

  @doc """
  Gets the file type (milestone, backlog, ideas, etc.)
  """
  def file_type(%__MODULE__{path: path}) do
    filename = Path.basename(path, ".md")
    
    cond do
      String.starts_with?(filename, "milestone-") -> :milestone
      filename == "backlog" -> :backlog
      filename == "ideas" -> :ideas
      String.starts_with?(filename, "v") -> :version
      true -> :other
    end
  end

  @doc """
  Gets the milestone number if this is a milestone file.
  """
  def milestone_number(%__MODULE__{path: path}) do
    filename = Path.basename(path, ".md")
    
    if String.starts_with?(filename, "milestone-") do
      filename
      |> String.replace_prefix("milestone-", "")
      |> String.to_integer()
    else
      nil
    end
  end
end
