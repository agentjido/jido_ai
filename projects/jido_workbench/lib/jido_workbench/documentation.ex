defmodule JidoWorkbench.Documentation do
  alias JidoWorkbench.Documentation.Document
  alias JidoWorkbench.Documentation.LivebookParser

  # Update the pattern to include both .md and .livemd files
  use NimblePublisher,
    build: Document,
    from: Application.app_dir(:jido_workbench, "priv/documentation/**/*.{md,livemd}"),
    as: :documents,
    highlighters: [:makeup_elixir, :makeup_js, :makeup_html],
    parser: LivebookParser

  # Sort documents by order
  @documents Enum.sort_by(@documents, & &1.order)

  # Get all tags
  @tags @documents |> Enum.flat_map(&(&1.tags || [])) |> Enum.uniq() |> Enum.sort()

  # Get all unique categories (first level of directory hierarchy)
  @categories @documents
              |> Enum.map(& &1.category)
              |> Enum.uniq()
              |> Enum.sort()

  # Export the data
  def all_documents, do: @documents
  def all_tags, do: @tags
  def all_categories, do: @categories
  def menu_tree, do: build_menu_tree(@documents)

  defmodule NotFoundError do
    defexception [:message, plug_status: 404]
  end

  @doc """
  Returns all documents in a given category.
  """
  def all_documents_by_category(category) when is_atom(category) do
    case Enum.filter(all_documents(), &(&1.category == category)) do
      [] -> raise NotFoundError, "documents with category=#{category} not found"
      documents -> documents
    end
  end

  @doc """
  Returns a document by its ID.
  """
  def get_document_by_id!(id) do
    Enum.find(all_documents(), &(&1.id == id)) ||
      raise NotFoundError, "document with id=#{id} not found"
  end

  @doc """
  Returns a document by its path.
  """
  def get_document_by_path!(path) do
    Enum.find(all_documents(), &(&1.path == path)) ||
      raise NotFoundError, "document with path=#{path} not found"
  end

  @doc """
  Returns all documents with a given tag.
  """
  def get_documents_by_tag!(tag) do
    case Enum.filter(all_documents(), &(tag in &1.tags)) do
      [] -> raise NotFoundError, "documents with tag=#{tag} not found"
      documents -> documents
    end
  end

  @doc """
  Builds a hierarchical menu tree from the list of documents.
  This organizes documents into a nested structure for UI rendering.
  """
  def build_menu_tree(documents) do
    # Sort documents by order first
    sorted_docs = Enum.sort_by(documents, & &1.order)

    # Create a hierarchical structure based on path
    sorted_docs
    |> Enum.reduce(%{}, fn doc, acc ->
      # Handle root documents differently
      if doc.path == "" or doc.path == "/" do
        # Add root document at the top level
        Map.put(acc, "root", %{doc: doc, children: %{}})
      else
        # Split path into segments for menu hierarchy
        segments = doc.path |> String.trim_leading("/") |> String.split("/")
        insert_into_menu_tree(acc, segments, doc)
      end
    end)
  end

  # Helper to insert documents in the proper place in the tree
  defp insert_into_menu_tree(tree, [segment], doc) do
    # Leaf node - store the document
    Map.update(tree, segment, %{doc: doc, children: %{}}, fn existing ->
      Map.put(existing, :doc, doc)
    end)
  end

  defp insert_into_menu_tree(tree, [segment | rest], doc) do
    # Interior node - recurse into the tree
    Map.update(tree, segment, %{children: insert_into_menu_tree(%{}, rest, doc)}, fn existing ->
      children = Map.get(existing, :children, %{})
      Map.put(existing, :children, insert_into_menu_tree(children, rest, doc))
    end)
  end
end
