defmodule JidoWorkbenchWeb.MenuItems do
  @moduledoc """
  Defines the menu structure for the workbench layout.
  """
  use JidoWorkbenchWeb, :live_component
  require Logger

  @livebook_root "lib/jido_workbench_web/live"

  @doc """
  Converts a documentation menu tree node into the menu items format.
  """
  # In lib/jido_workbench_web/menu_items.ex
  defp convert_doc_tree_to_menu_items(tree, base_path) do
    tree
    |> Enum.map(fn {section_name, section_data} ->
      menu_item =
        if doc = Map.get(section_data, :doc) do
          path_segment =
            case String.trim_leading(doc.path, "/") |> String.split("/", parts: 2) do
              [_category, rest] -> rest
              _ -> ""
            end

          %{
            name: String.to_atom(doc.id),
            label: doc.title,
            path: if(path_segment == "", do: base_path, else: "#{base_path}/#{path_segment}"),
            icon: nil
          }
        else
          %{
            name: String.to_atom(section_name),
            label: Phoenix.Naming.humanize(section_name),
            path: base_path,
            icon: nil
          }
        end

      children = Map.get(section_data, :children, %{})

      if Enum.empty?(children) do
        menu_item
      else
        child_base_path = "#{base_path}/#{section_name}"
        Map.put(menu_item, :menu_items, convert_doc_tree_to_menu_items(children, base_path))
      end
    end)
    |> Enum.sort_by(& &1.label)
  end

  def menu_items() do
    doc_tree = JidoWorkbench.Documentation.menu_tree()
    docs_section = get_in(doc_tree, ["docs", :children]) || %{}
    cookbook_section = get_in(doc_tree, ["cookbook", :children]) || %{}
    docs_menu_items = convert_doc_tree_to_menu_items(docs_section, ~p"/docs")
    cookbook_menu_items = convert_doc_tree_to_menu_items(cookbook_section, ~p"/cookbook")

    [
      %{
        title: "",
        menu_items: [
          %{name: :home, label: "Home", path: ~p"/", icon: nil}
          # %{name: :jido, label: "Agent Jido", path: ~p"/jido", icon: nil}
        ]
      },
      %{
        title: "",
        menu_items: [
          %{name: :all_docs, label: "Documentation", path: ~p"/docs", icon: nil, menu_items: docs_menu_items}
        ]
      },
      %{
        title: "",
        menu_items: [
          %{name: :all_cookbook, label: "Cookbook", path: ~p"/cookbook", icon: nil, menu_items: cookbook_menu_items}
        ]
      },
      %{
        title: "",
        menu_items: [
          %{
            name: :catalog,
            label: "Catalog",
            path: ~p"/catalog",
            icon: nil,
            menu_items: [
              %{name: :agents, label: "Agents", path: ~p"/catalog/agents", icon: nil},
              %{name: :actions, label: "Actions", path: ~p"/catalog/actions", icon: nil},
              %{name: :skills, label: "Skills", path: ~p"/catalog/skills", icon: nil},
              %{name: :sensors, label: "Sensors", path: ~p"/catalog/sensors", icon: nil}
            ]
          }
        ]
      },
      %{
        title: "",
        menu_items: [
          %{name: :blog, label: "Blog", path: ~p"/blog", icon: nil},
          %{name: :settings, label: "Settings", path: ~p"/settings", icon: nil}
        ]
      }
    ]
  end
end
