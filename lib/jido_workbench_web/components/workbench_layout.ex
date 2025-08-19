defmodule JidoWorkbenchWeb.WorkbenchLayout do
  @moduledoc false
  use JidoWorkbenchWeb, :live_component
  use PetalComponents
  alias JidoWorkbenchWeb.{MenuItems, Menu}
  alias JidoWorkbench.GithubStarsTracker

  # Add helper function for determining show_layout
  def show_layout(params, session) do
    cond do
      is_map(params) && Map.has_key?(params, "show_layout") -> params["show_layout"]
      is_map(session) && Map.has_key?(session, "show_layout") -> session["show_layout"]
      true -> true
    end
  end

  attr(:current_page, :atom)
  attr(:show_menu, :boolean, default: true)
  attr(:show_layout, :boolean, default: true)
  slot(:inner_block)

  def workbench_layout(assigns) do
    ~H"""
    <%= if @show_layout do %>
      <div class="h-screen flex flex-col">
        <div class="fixed top-0 left-0 right-0 z-50">
          <.nav_bar />
        </div>
        <div class="flex flex-1 mt-16">
          <%= if @show_menu do %>
            <aside class="w-64 overflow-y-auto bg-secondary-50 dark:bg-secondary-950 flex-shrink-0 border-r border-secondary-800 dark:border-secondary-800">
              <div class="py-4">
                <Menu.vertical_menu current_page={@current_page} menu_items={MenuItems.menu_items()} />
              </div>
            </aside>
          <% end %>

          <main class={[
            "flex-1",
            "bg-secondary-50 dark:bg-secondary-950",
            "overflow-y-auto w-full"
          ]}>
            {render_slot(@inner_block)}
          </main>
        </div>
        <footer class="bg-secondary-50 dark:bg-secondary-950 text-secondary-600 dark:text-secondary-400 text-sm py-4 px-6 border-t border-secondary-200 dark:border-secondary-800">
          <div class="flex justify-between items-center">
            <div>
              © {DateTime.utc_now().year} - eBoss.ai - All rights reserved.
            </div>
            <div class="flex gap-4">
              <a
                href="https://hexdocs.pm/jido"
                class="text-secondary-600 dark:text-secondary-400 hover:text-primary-600 dark:hover:text-primary-400 transition-colors duration-200"
              >
                Documentation
              </a>
              <a
                href="https://github.com/agentjido/jido"
                class="text-secondary-600 dark:text-secondary-400 hover:text-primary-600 dark:hover:text-primary-400 transition-colors duration-200"
              >
                GitHub
              </a>
              <a
                href="https://x.com/agentjido"
                class="text-secondary-600 dark:text-secondary-400 hover:text-primary-600 dark:hover:text-primary-400 transition-colors duration-200"
              >
                Twitter
              </a>
            </div>
          </div>
        </footer>
      </div>
    <% else %>
      {render_slot(@inner_block)}
    <% end %>
    """
  end

  def nav_bar(assigns) do
    {stars, _} = GithubStarsTracker.get_stars()
    assigns = assign(assigns, :stars, stars)

    ~H"""
    <nav class="sticky top-0 z-50 flex items-center justify-between w-full h-16 bg-secondary-50 dark:bg-secondary-950 border-b border-secondary-200 dark:border-secondary-800">
      <div class="flex flex-wrap ml-3 sm:flex-nowrap sm:ml-4">
        <a class="inline-flex hover:opacity-90" href="/">
          <div class="font-display text-5xl text-primary-600 dark:text-primary-600 tracking-wide font-bold transition-colors duration-200">
            AGENT JIDO
          </div>
        </a>
      </div>

      <div class="flex justify-end gap-3 pr-4">
        <a
          class="inline-flex items-center gap-2 p-2 text-secondary-600 dark:text-secondary-400 rounded hover:text-primary-600 dark:hover:text-primary-400 transition-colors duration-200 group"
          href={~p"/docs"}
        >
          <.icon
            name="hero-book-open"
            solid
            class="w-5 h-5 m-0.5 mr-2 text-secondary-600 dark:text-secondary-400 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors duration-200"
          />
          <span class="hidden font-semibold sm:block text-secondary-600 dark:text-secondary-400 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors duration-200">
            Docs
          </span>
        </a>
        <a
          class="inline-flex items-center gap-2 p-2 text-secondary-600 dark:text-secondary-400 rounded hover:text-primary-600 dark:hover:text-primary-400 transition-colors duration-200 group"
          href={~p"/cookbook"}
        >
          <.icon
            name="hero-beaker"
            solid
            class="w-5 h-5 m-0.5 mr-2 text-secondary-600 dark:text-secondary-400 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors duration-200"
          />
          <span class="hidden font-semibold sm:block text-secondary-600 dark:text-secondary-400 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors duration-200">
            Cookbook
          </span>
        </a>
        <a
          class="inline-flex items-center gap-2 p-2 text-secondary-600 dark:text-secondary-400 rounded hover:text-primary-600 dark:hover:text-primary-400 transition-colors duration-200 group"
          href={~p"/catalog"}
        >
          <.icon
            name="hero-folder"
            solid
            class="w-5 h-5 m-0.5 mr-2 text-secondary-600 dark:text-secondary-400 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors duration-200"
          />
          <span class="hidden font-semibold sm:block text-secondary-600 dark:text-secondary-400 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors duration-200">
            Catalog
          </span>
        </a>
        <a
          class="inline-flex items-center gap-2 p-2 text-secondary-600 dark:text-secondary-400 rounded hover:text-primary-600 dark:hover:text-primary-400 transition-colors duration-200 group"
          href={~p"/blog"}
        >
          <.icon
            name="hero-document-text"
            solid
            class="w-5 h-5 m-0.5 mr-2 text-secondary-600 dark:text-secondary-400 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors duration-200"
          />
          <span class="hidden font-semibold sm:block text-secondary-600 dark:text-secondary-400 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors duration-200">
            Blog
          </span>
        </a>
        <a
          target="_blank"
          class="inline-flex items-center gap-2 p-2 text-secondary-600 dark:text-secondary-400 rounded hover:text-primary-600 dark:hover:text-primary-400 transition-colors duration-200 group"
          href="https://github.com/agentjido/jido"
        >
          <svg
            class="w-5 h-5 fill-secondary-600 dark:fill-secondary-400 group-hover:fill-primary-600 dark:group-hover:fill-primary-400 transition-colors duration-200"
            xmlns="http://www.w3.org/2000/svg"
            data-name="Layer 1"
            viewBox="0 0 24 24"
          >
            <path d="M12,2.2467A10.00042,10.00042,0,0,0,8.83752,21.73419c.5.08752.6875-.21247.6875-.475,0-.23749-.01251-1.025-.01251-1.86249C7,19.85919,6.35,18.78423,6.15,18.22173A3.636,3.636,0,0,0,5.125,16.8092c-.35-.1875-.85-.65-.01251-.66248A2.00117,2.00117,0,0,1,6.65,17.17169a2.13742,2.13742,0,0,0,2.91248.825A2.10376,2.10376,0,0,1,10.2,16.65923c-2.225-.25-4.55-1.11254-4.55-4.9375a3.89187,3.89187,0,0,1,1.025-2.6875,3.59373,3.59373,0,0,1,.1-2.65s.83747-.26251,2.75,1.025a9.42747,9.42747,0,0,1,5,0c1.91248-1.3,2.75-1.025,2.75-1.025a3.59323,3.59323,0,0,1,.1,2.65,3.869,3.869,0,0,1,1.025,2.6875c0,3.83747-2.33752,4.6875-4.5625,4.9375a2.36814,2.36814,0,0,1,.675,1.85c0,1.33752-.01251,2.41248-.01251,2.75,0,.26251.1875.575.6875.475A10.0053,10.0053,0,0,0,12,2.2467Z" />
          </svg>
          <span class="hidden font-semibold sm:block text-secondary-600 dark:text-secondary-400 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors duration-200">
            {@stars || 0}
          </span>
          <.icon
            name="hero-star-solid"
            class="w-4 h-4 inline text-secondary-600 dark:text-secondary-400 group-hover:text-primary-600 dark:group-hover:text-primary-400 transition-colors duration-200"
          />
        </a>
        <a
          target="_blank"
          class="inline-flex items-center gap-2 p-2 text-secondary-600 dark:text-secondary-400 rounded hover:text-primary-600 dark:hover:text-primary-400 transition-colors duration-200 group"
          href="https://x.com/agentjido"
        >
          <svg
            class="w-5 h-5 fill-secondary-600 dark:fill-secondary-400 group-hover:fill-primary-600 dark:group-hover:fill-primary-400 transition-colors duration-200"
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
          >
            <path d="M14.095479,10.316482L22.286354,1h-1.940718l-7.115352,8.087682L7.551414,1H1l8.589488,12.231093L1,23h1.940717  l7.509372-8.542861L16.448587,23H23L14.095479,10.316482z M11.436522,13.338465l-0.871624-1.218704l-6.924311-9.68815h2.981339  l5.58978,7.82155l0.867949,1.218704l7.26506,10.166271h-2.981339L11.436522,13.338465z" />
          </svg>
        </a>
        <.color_scheme_switch />
      </div>
    </nav>
    """
  end
end
