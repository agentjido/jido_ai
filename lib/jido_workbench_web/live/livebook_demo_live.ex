defmodule JidoWorkbenchWeb.LivebookDemoLive do
  use JidoWorkbenchWeb, :live_view
  import JidoWorkbenchWeb.WorkbenchLayout
  alias JidoWorkbench.Documentation
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Loading...", documents: [], selected_category: nil)}
  end

  @impl true
  def handle_params(params, uri, socket) do
    type = get_route_tag(uri)
    path = URI.parse(uri).path

    # Get all documents for this type
    documents =
      try do
        Documentation.all_documents_by_category(type)
      rescue
        e in Documentation.NotFoundError ->
          Logger.warning("No documents found for category #{type}: #{Exception.message(e)}")
          []

        e ->
          Logger.error("Error fetching documents for category #{type}: #{Exception.message(e)}")
          []
      end

    # Build menu items from documents
    menu_items = build_document_menu(documents)

    case path do
      "/docs" -> handle_index(socket, :docs, documents, menu_items)
      "/cookbook" -> handle_index(socket, :cookbook, documents, menu_items)
      _ -> handle_show(socket, type, path, documents, menu_items)
    end
  end

  # Handle index pages for docs and examples
  defp handle_index(socket, type, documents, menu_items) do
    # Try to find the appropriate index document
    root_doc =
      Enum.find(documents, fn doc ->
        doc.id == "#{type}" || doc.path == "/#{type}" || doc.path == "/#{type}/index"
      end)

    if root_doc do
      # Generate TOC for the index document
      toc = build_toc(root_doc.body)

      {:noreply,
       assign(socket,
         page_title: root_doc.title,
         documents: documents,
         selected_document: root_doc,
         document_content: %{html: root_doc.body, toc: toc},
         type: type,
         menu_items: menu_items
       )}
    else
      # Otherwise, show the index listing
      {:noreply,
       assign(socket,
         page_title: if(type == :cookbook, do: "Cookbook", else: "Documentation"),
         documents: documents,
         selected_document: nil,
         type: type,
         menu_items: menu_items
       )}
    end
  end

  # Handle show pages for individual documents
  defp handle_show(socket, type, path, documents, menu_items) do
    try do
      # Find document by matching the full path
      document =
        Enum.find(documents, fn doc ->
          path == doc.path || path == String.trim_trailing(doc.path, "/")
        end)

      case document do
        nil ->
          Logger.warning("No document found for path: #{path}")

          {:noreply,
           socket
           |> put_flash(:error, "Document not found")
           |> push_navigate(to: ~p"/#{type}")}

        doc ->
          toc = build_toc(doc.body)

          {:noreply,
           assign(socket,
             page_title: doc.title,
             documents: documents,
             selected_document: doc,
             document_content: %{html: doc.body, toc: toc},
             type: type,
             menu_items: menu_items
           )}
      end
    rescue
      e ->
        Logger.error("Error loading document for path #{path}: #{Exception.message(e)}")

        {:noreply,
         socket
         |> put_flash(:error, "Error loading document")
         |> push_navigate(to: ~p"/#{type}")}
    end
  end

  @doc """
  Gets the route tag from the URI path.
  Returns :docs for /docs/* paths and :cookbook for /cookbook/* paths.

  ## Examples

      iex> get_route_tag(%URI{path: "/docs/getting-started"})
      :docs

      iex> get_route_tag(%URI{path: "/cookbook/tool-use-intro"})
      :cookbook
  """
  defp get_route_tag(uri) do
    # Extract the first part of the path to determine if we're in docs or cookbook
    path = URI.parse(uri).path || "/"
    base_path = path |> String.split("/") |> Enum.at(1, "")

    case base_path do
      "docs" -> :docs
      "cookbook" -> :cookbook
      # Default to cookbook for root path
      _ -> :cookbook
    end
  end

  defp build_toc(html_content) do
    case Floki.parse_fragment(html_content) do
      {:ok, document} ->
        # Find all h1, h2, and h3 tags
        headers =
          document
          |> Floki.find("h1, h2, h3")
          |> Enum.map(fn header ->
            # Get the header level from the tag name
            {tag_name, attrs, content} = header
            level = String.to_integer(String.trim_leading(tag_name, "h"))

            # Get existing ID from attributes or generate one
            id = get_header_id_from_attrs(attrs) || slugify(Floki.text(header))
            title = Floki.text(header)

            %{
              id: id,
              title: title,
              level: level,
              children: []
            }
          end)

        # Build the hierarchy
        build_toc_hierarchy(headers)

      {:error, error} ->
        Logger.warning("Failed to parse HTML for TOC: #{inspect(error)}")
        []
    end
  end

  # Build a hierarchical TOC structure
  defp build_toc_hierarchy(headers) do
    headers
    |> Enum.reduce({[], nil, nil}, fn header, {acc, current_h2, _} ->
      case header.level do
        1 ->
          # h1 starts a new top-level entry
          {[header | acc], nil, nil}

        2 ->
          # h2 goes under the previous h1, or at the top if no h1
          header = Map.put(header, :children, [])
          {acc, header, nil}

        3 ->
          # h3 goes under the current h2
          if current_h2 do
            updated_h2 =
              Map.update!(current_h2, :children, fn children ->
                [header | children]
              end)

            # Update the last h2 in the accumulator
            new_acc =
              case acc do
                [previous_h1 | rest] when is_map(previous_h1) ->
                  [%{previous_h1 | children: [updated_h2 | previous_h1.children || []]} | rest]

                _ ->
                  [updated_h2 | acc]
              end

            {new_acc, updated_h2, header}
          else
            # If no h2 parent, just add it to the top level
            {[header | acc], nil, header}
          end
      end
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.map(fn section ->
      Map.update(section, :children, [], &Enum.reverse/1)
    end)
  end

  # Get ID from HTML attributes
  defp get_header_id_from_attrs(attrs) do
    Enum.find_value(attrs, fn
      {"id", id} -> id
      _ -> nil
    end)
  end

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w-]+/, "-")
    |> String.trim("-")
  end

  defp build_document_menu(documents) do
    # Group documents by tags or other criteria that makes sense for your UI
    documents_by_tag =
      documents
      |> Enum.filter(fn doc -> doc.tags != nil && doc.tags != [] end)
      |> Enum.flat_map(fn doc ->
        Enum.map(doc.tags, fn tag -> {tag, doc} end)
      end)
      |> Enum.group_by(fn {tag, _} -> tag end, fn {_, doc} -> doc end)

    # Convert to menu structure
    tag_sections =
      documents_by_tag
      |> Enum.map(fn {tag, docs} ->
        %{
          label: Phoenix.Naming.humanize(to_string(tag)),
          menu_items:
            Enum.map(docs, fn item ->
              # Extract path segment after category
              path_segment =
                case String.trim_leading(item.path, "/") |> String.split("/", parts: 2) do
                  [_, rest] -> rest
                  [_] -> ""
                  _ -> ""
                end

              %{
                label: item.title,
                path: ~p"/#{if item.category == :docs, do: "docs", else: "cookbook"}/#{path_segment}",
                icon: Map.get(item, :icon, "hero-document"),
                description: item.description
              }
            end)
            |> Enum.sort_by(& &1.label)
        }
      end)
      |> Enum.sort_by(& &1.label)

    # If no tag-based sections, group by directory structure
    if tag_sections == [] do
      Enum.group_by(documents, fn doc ->
        case String.trim_leading(doc.path, "/") |> String.split("/") do
          [_, dir | _] -> dir
          _ -> "Other"
        end
      end)
      |> Enum.map(fn {dir, docs} ->
        %{
          label: Phoenix.Naming.humanize(dir),
          menu_items:
            Enum.map(docs, fn item ->
              # Extract path segment after category
              path_segment =
                case String.trim_leading(item.path, "/") |> String.split("/", parts: 2) do
                  [_, rest] -> rest
                  _ -> ""
                end

              %{
                label: item.title,
                path: ~p"/#{if item.category == :docs, do: "docs", else: "cookbook"}/#{path_segment}",
                icon: Map.get(item, :icon, "hero-document"),
                description: item.description
              }
            end)
            |> Enum.sort_by(& &1.label)
        }
      end)
      |> Enum.sort_by(& &1.label)
    else
      tag_sections
    end
  end
end
