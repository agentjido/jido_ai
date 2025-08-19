defmodule JidoWorkbenchWeb.CatalogLive do
  use JidoWorkbenchWeb, :live_view
  import JidoWorkbenchWeb.WorkbenchLayout

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Jido Discovery Catalog"
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.workbench_layout current_page={:catalog}>
      <div class="bg-white dark:bg-secondary-900 text-secondary-900 dark:text-secondary-100 p-8">
        <div class="max-w-4xl mx-auto">
          <div class="text-center mb-12">
            <h1 class="text-4xl font-bold text-primary-600 dark:text-primary-500 mb-4">
              Jido Catalog
            </h1>
            <p class="text-xl text-secondary-600 dark:text-secondary-400">
              Explore and discover all available components in the Jido ecosystem. The catalog provides a comprehensive reference of Actions, Agents, Sensors, and Skills that you can use to build powerful workflows.
            </p>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <.catalog_card
              title="Actions"
              icon="hero-bolt"
              description="Browse available actions that can be executed within workflows. Actions are the building blocks for creating complex automations."
              link="/catalog/actions"
              color="text-primary-600 dark:text-primary-500"
            />

            <.catalog_card
              title="Agents"
              icon="hero-user-circle"
              description="Discover AI agents that can perform specific tasks or roles. Agents combine multiple skills to achieve complex goals."
              link="/catalog/agents"
              color="text-primary-600 dark:text-primary-500"
            />

            <.catalog_card
              title="Sensors"
              icon="hero-signal"
              description="Explore available sensors that can monitor and collect data from various sources in real-time."
              link="/catalog/sensors"
              color="text-primary-600 dark:text-primary-500"
            />

            <.catalog_card
              title="Skills"
              icon="hero-academic-cap"
              description="View the collection of skills that agents can use. Skills are specialized capabilities that enable specific functionalities."
              link="/catalog/skills"
              color="text-primary-600 dark:text-primary-500"
            />
          </div>
        </div>
      </div>
    </.workbench_layout>
    """
  end

  defp catalog_card(assigns) do
    ~H"""
    <.link
      navigate={@link}
      class="block p-6 bg-white dark:bg-secondary-800 rounded-lg border border-secondary-200 dark:border-secondary-700 hover:border-primary-200 dark:hover:border-primary-700 transition-colors"
    >
      <div class="flex items-center gap-3 mb-4">
        <div class={@color}>
          <.icon name={@icon} class="w-8 h-8" />
        </div>
        <h2 class="text-2xl font-semibold text-primary-600 dark:text-primary-500">{@title}</h2>
      </div>
      <p class="text-secondary-600 dark:text-secondary-400">{@description}</p>
      <div class="mt-4 flex items-center text-primary-600 dark:text-primary-500 font-medium">
        Explore {@title}
        <.icon name="hero-arrow-right" class="w-4 h-4 ml-2" />
      </div>
    </.link>
    """
  end
end
