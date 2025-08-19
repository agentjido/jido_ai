defmodule JidoWorkbenchWeb.Menu do
  use Phoenix.Component
  import PetalComponents.Link

  @doc """
  A simplified menu component that displays a menu tree without collapsible items.

  ## Menu items structure

  Menu items should have this structure:

        [
          %{
            name: :sign_in,
            label: "Sign in",
            path: "/sign-in",
            icon: nil,
          }
        ]

  ## Menu groups

  Menu supports grouped structure:

      main_menu_items = [
        %{
          title: "Menu group 1",
          menu_items: [ ... menu items ... ]
        },
        %{
          title: "Menu group 2",
          menu_items: [ ... menu items ... ]
        },
      ]
  """

  attr(:menu_items, :list, required: true)
  attr(:current_page, :atom, required: true)
  attr(:title, :string, default: nil)

  def vertical_menu(%{menu_items: []} = assigns) do
    ~H"""
    """
  end

  def vertical_menu(assigns) do
    ~H"""
    <%= if menu_items_grouped?(@menu_items) do %>
      <div class="h-full">
        <.menu_group
          :for={menu_group <- @menu_items}
          title={menu_group[:title]}
          menu_items={menu_group.menu_items}
          current_page={@current_page}
        />
      </div>
    <% else %>
      <.menu_group title={@title} menu_items={@menu_items} current_page={@current_page} />
    <% end %>
    """
  end

  attr(:current_page, :atom)
  attr(:menu_items, :list)
  attr(:title, :string)

  def menu_group(assigns) do
    ~H"""
    <nav :if={@menu_items != []} class="menu-group">
      <h3 :if={@title != ""} class="menu-group-title">
        <%= @title %>
      </h3>

      <div class="menu-items">
        <.menu_item :for={menu_item <- @menu_items} current_page={@current_page} {menu_item} />
      </div>
    </nav>
    """
  end

  attr(:current_page, :atom)
  attr(:path, :string, default: nil)
  attr(:icon, :any, default: nil)
  attr(:label, :string)
  attr(:name, :atom, default: nil)
  attr(:menu_items, :list, default: nil)

  def menu_item(assigns) do
    # Check if this item or any of its children is active
    active = menu_item_active?(assigns.name, assigns.current_page, assigns.menu_items || [])

    # Check if this item is exactly the current page
    exact_match = assigns.name == assigns.current_page

    assigns = assign(assigns, :active, active)
    assigns = assign(assigns, :exact_match, exact_match)
    assigns = assign(assigns, :has_children, assigns.menu_items != nil && assigns.menu_items != [])

    ~H"""
    <div class="menu-item-container">
      <.a
        to={@path}
        link_type="live_redirect"
        class={[
          "menu-item",
          @active && "menu-item-active",
          @active && !@exact_match && @has_children && "parent-active"
        ]}
      >
        <%= @label %>
      </.a>

      <%= if @menu_items do %>
        <div class="submenu">
          <.menu_item :for={menu_item <- @menu_items} current_page={@current_page} {menu_item} />
        </div>
      <% end %>
    </div>
    """
  end

  # Helper functions
  defp menu_items_grouped?(menu_items) do
    Enum.all?(menu_items, fn menu_item ->
      Map.has_key?(menu_item, :title)
    end)
  end

  # Check if the current menu item or any of its children is active
  defp menu_item_active?(name, current_page, _submenu_items) when name == current_page, do: true

  defp menu_item_active?(_name, current_page, submenu_items) do
    Enum.any?(submenu_items, fn menu_item ->
      menu_item_active?(menu_item[:name], current_page, menu_item[:menu_items] || [])
    end)
  end
end
