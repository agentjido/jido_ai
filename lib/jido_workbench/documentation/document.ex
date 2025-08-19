defmodule JidoWorkbench.Documentation.Document do
  @github_repo "https://github.com/agentjido/jido_workbench"
  @enforce_keys [:title, :category]
  # Extended struct with new fields
  defstruct [
    :id,
    :title,
    :body,
    :description,
    :category,
    :tags,
    # Path relative to documentation root
    :path,
    :order,
    # Original file path
    :source_path,
    # Boolean flag for livebook files
    :is_livebook,
    # URL to the livebook file in GitHub
    :github_url,
    # URL to run the livebook file in Livebook
    :livebook_url,
    # List of path segments for menu hierarchy
    :menu_path
  ]

  @doc """
  Builds a document struct from a file.

  - filename: The full path to the file
  - attrs: Map of metadata attributes from the markdown frontmatter
  - body: The parsed content of the file
  """
  def build(filename, attrs, body) do
    # Ensure required fields are present
    unless Map.has_key?(attrs, :title) and Map.has_key?(attrs, :category) do
      raise ArgumentError, "Document requires both title and category in frontmatter"
    end

    order = Map.get(attrs, :order, 0)

    # Get the full application path
    full_app_path = Application.app_dir(:jido_workbench)

    # Store the original source path
    source_path = filename

    # Extract path relative to the application directory
    app_relative_path = String.replace(filename, full_app_path, "")

    # Extract path relative to priv/documentation
    doc_root = "/priv/documentation"
    path = String.replace(app_relative_path, doc_root, "")

    # Determine if it's a Livebook file
    is_livebook = String.ends_with?(filename, ".livemd")

    # Build the path
    path =
      if String.ends_with?(path, "/index.md") or
           String.ends_with?(path, "/index.livemd") do
        # For index files, just use the directory path
        path
        |> String.replace(~r{/index\.(md|livemd)$}, "")
      else
        # For normal files, replace extension with nothing
        path
        |> String.replace(~r{\.(md|livemd)$}, "")
      end

    # Generate a unique and consistent ID
    id =
      path
      |> String.trim_leading("/")
      |> String.replace("/", "-")

    # For empty path (root), use "root" as the ID
    id =
      path
      |> String.trim_leading("/")
      |> String.split("/", parts: 2)
      |> case do
        # Remove category from ID
        [_category, rest] -> rest
        # For root documents
        [only] -> only
        # Fallback
        [] -> "root"
      end
      |> String.replace("/", "-")

    # Create the GitHub URL for Livebook files
    github_url = "#{@github_repo}/blob/main#{doc_root}#{path}.livemd"

    # Create the Livebook URL for Livebook files
    livebook_url =
      if is_livebook do
        "https://livebook.dev/run?url=#{github_url}"
      else
        nil
      end

    # Build the menu tree path components
    menu_path =
      path
      |> String.trim_leading("/")
      |> String.split("/")
      |> Enum.filter(fn part -> part != "index" end)

    # Build the struct with all fields
    struct!(
      __MODULE__,
      [
        id: id,
        body: body,
        path: path,
        source_path: source_path,
        is_livebook: is_livebook,
        github_url: github_url,
        livebook_url: livebook_url,
        menu_path: menu_path,
        order: order
      ] ++ Map.to_list(attrs)
    )
  end
end
