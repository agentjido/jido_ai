defmodule JidoWorkbenchWeb.CatalogSkillsLive do
  use JidoWorkbenchWeb, :live_view
  import JidoWorkbenchWeb.WorkbenchLayout

  @impl true
  def mount(_params, _session, socket) do
    skills = Jido.list_skills()

    {:ok,
     assign(socket,
       page_title: "Skills Dashboard",
       skills: skills,
       selected_skill: nil,
       result: nil,
       active_tab: :skills,
       search: ""
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.workbench_layout current_page={:skills}>
      <div class="flex bg-white dark:bg-secondary-900 text-secondary-900 dark:text-secondary-100">
        <div class="w-96 border-r border-secondary-200 dark:border-secondary-700 flex flex-col">
          <div class="p-4 border-b border-secondary-200 dark:border-secondary-700">
            <h2 class="text-xl mb-4 flex items-center gap-2">
              <.icon name="hero-bolt" class="w-6 h-6 text-primary-600 dark:text-primary-500" /> Available Skills
            </h2>
            <div class="relative">
              <.icon name="hero-magnifying-glass" class="w-5 h-5 absolute left-3 top-2.5 text-secondary-400 dark:text-secondary-500" />
              <.input
                type="text"
                name="search"
                value={@search}
                placeholder="Search skills..."
                phx-change="search"
                phx-debounce="300"
                class="w-full bg-white dark:bg-secondary-800 rounded-md py-2 pl-10 pr-4 focus:outline-none focus:ring-2 focus:ring-primary-500 dark:focus:ring-primary-400"
              />
            </div>
          </div>

          <div class="flex-1 overflow-y-auto">
            <%= for skill <- @skills do %>
              <button
                phx-click="select-skill"
                phx-value-slug={skill.slug}
                class={"w-full p-4 text-left hover:bg-secondary-100 dark:hover:bg-secondary-800 flex items-center justify-between group #{if @selected_skill && @selected_skill.slug == skill.slug, do: "bg-secondary-100 dark:bg-secondary-800 border-l-2 border-primary-500", else: ""}"}
              >
                <div class="flex items-center space-x-3">
                  <div class="text-primary-600 dark:text-primary-500">
                    <.icon name="hero-bolt" class="w-5 h-5" />
                  </div>
                  <div>
                    <div class="font-medium flex items-center gap-2">
                      {skill.name}
                      <span class="text-xs px-2 py-0.5 rounded-full bg-secondary-100 dark:bg-secondary-800 text-secondary-600 dark:text-secondary-400">
                        {skill.category}
                      </span>
                    </div>
                    <div class="text-sm text-secondary-600 dark:text-secondary-400">
                      {skill.description}
                    </div>
                  </div>
                </div>
                <.icon name="hero-chevron-right" class="w-5 h-5 text-secondary-400 dark:text-secondary-500 opacity-0 group-hover:opacity-100" />
              </button>
            <% end %>
          </div>
        </div>

        <div class="flex-1 p-6">
          <%= if @selected_skill do %>
            <div class="max-w-2xl">
              <div class="flex items-center gap-3 mb-6">
                <div class="text-primary-600 dark:text-primary-500">
                  <.icon name="hero-bolt" class="w-6 h-6" />
                </div>
                <div>
                  <h1 class="text-2xl text-primary-600 dark:text-primary-500">
                    {@selected_skill.name}
                  </h1>
                  <div class="text-secondary-600 dark:text-secondary-400 text-sm">
                    {@selected_skill.category}
                  </div>
                </div>
              </div>

              <p class="text-secondary-600 dark:text-secondary-400 mb-8">
                {@selected_skill.description}
              </p>
            </div>
          <% else %>
            <div class="h-full flex items-center justify-center text-secondary-500 dark:text-secondary-400">
              Select a skill to get started
            </div>
          <% end %>
        </div>
      </div>
    </.workbench_layout>
    """
  end

  @impl true
  def handle_event("select-skill", %{"slug" => slug}, socket) do
    skill = Enum.find(socket.assigns.skills, &(&1.slug == slug))
    {:noreply, assign(socket, selected_skill: skill)}
  end

  @impl true
  def handle_event("search", %{"search" => search_term}, socket) do
    filtered_skills =
      socket.assigns.skills
      |> Enum.filter(fn skill ->
        String.contains?(
          String.downcase(skill.name <> skill.description),
          String.downcase(search_term)
        )
      end)

    {:noreply, assign(socket, skills: filtered_skills, search: search_term)}
  end

  @impl true
  def handle_event("execute", params, socket) do
    skill = Enum.find(socket.assigns.skills, &(&1.slug == params["skill_slug"]))
    IO.inspect(params, label: "Params")
    IO.inspect(skill, label: "Skill")

    result =
      case skill do
        nil -> {:error, "Skill not found"}
        skill -> Jido.Workflow.run(skill.module, params, %{}, [])
      end

    {:noreply, assign(socket, result: result)}
  end

  defp build_form(skill) do
    types =
      skill.schema
      |> Enum.map(fn {field, opts} -> {field, get_ecto_type(opts[:type])} end)
      |> Map.new()
      |> Map.put(:skill_slug, :string)

    data = %{skill_slug: skill.slug}

    {data, types}
    |> Ecto.Changeset.cast(%{}, Map.keys(types))
    |> to_form(as: "skill")
  end

  defp get_ecto_type(:non_neg_integer), do: :integer
  defp get_ecto_type(:integer), do: :integer
  defp get_ecto_type(:float), do: :float
  defp get_ecto_type(:boolean), do: :boolean
  defp get_ecto_type(:atom), do: :string
  defp get_ecto_type(_), do: :string

  defp get_field_type(options) do
    case options[:type] do
      :boolean -> :checkbox
      :non_neg_integer -> :number
      :integer -> :number
      :float -> :number
      _ -> :text
    end
  end
end
