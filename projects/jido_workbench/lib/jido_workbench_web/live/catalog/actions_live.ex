defmodule JidoWorkbenchWeb.CatalogActionsLive do
  use JidoWorkbenchWeb, :live_view
  import JidoWorkbenchWeb.WorkbenchLayout

  @impl true
  def mount(params, _session, socket) do
    actions = Jido.list_actions()

    # Get search term from URL params or default to empty
    search_term = Map.get(params, "search", "")

    # Apply filtering if there's a search term
    filtered_actions =
      if search_term == "" do
        actions
      else
        search_term = String.downcase(search_term)

        Enum.filter(actions, fn action ->
          searchable_text =
            [
              action.name,
              action.description,
              action.category,
              Atom.to_string(action.module),
              action |> Map.get(:tags, []) |> Enum.join(" ")
            ]
            |> Enum.join(" ")
            |> String.downcase()

          String.contains?(searchable_text, search_term)
        end)
      end
      |> Enum.sort_by(& &1.name)

    selected_action =
      case params do
        %{"slug" => slug} -> Enum.find(actions, &(&1.slug == slug))
        _ -> nil
      end

    {:ok,
     assign(socket,
       page_title: "Actions Dashboard",
       actions: filtered_actions,
       all_actions: actions,
       selected_action: selected_action,
       result: nil,
       active_tab: :actions,
       search: search_term,
       is_searching: false
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.workbench_layout current_page={:actions}>
      <div class="flex bg-white dark:bg-secondary-900 text-secondary-900 dark:text-secondary-100">
        <div class="w-96 border-r border-secondary-200 dark:border-secondary-700 flex flex-col">
          <div class="p-4 border-b border-secondary-200 dark:border-secondary-700">
            <h2 class="text-xl mb-4 flex items-center gap-2">
              <.icon name="hero-bolt" class="w-6 h-6 text-primary-600 dark:text-primary-500" /> Available Actions
            </h2>
            <div class="relative">
              <.icon name="hero-magnifying-glass" class="w-5 h-5 absolute left-3 top-2.5 text-secondary-400 dark:text-secondary-500" />
              <.input
                type="text"
                name="search"
                value={@search}
                placeholder="Search actions..."
                phx-keyup="search"
                phx-debounce="300"
                class="w-full bg-white dark:bg-secondary-800 rounded-md py-2 pl-10 pr-4 focus:outline-none focus:ring-2 focus:ring-primary-500 dark:focus:ring-primary-400"
              />
              <%= if @is_searching do %>
                <div class="absolute right-3 top-2.5">
                  <.icon name="hero-arrow-path" class="w-5 h-5 text-primary-500 animate-spin" />
                </div>
              <% end %>
            </div>
          </div>

          <div class="flex-1 overflow-y-auto">
            <%= for action <- @actions do %>
              <.link
                navigate={~p"/catalog/actions/#{action.slug}"}
                class={"w-full p-4 text-left hover:bg-secondary-100 dark:hover:bg-secondary-800 flex items-center justify-between group #{if @selected_action && @selected_action.slug == action.slug, do: "bg-secondary-100 dark:bg-secondary-800 border-l-2 border-primary-500", else: ""}"}
              >
                <div class="flex items-center space-x-3">
                  <div class="text-primary-600 dark:text-primary-500">
                    <.icon name="hero-bolt" class="w-5 h-5" />
                  </div>
                  <div>
                    <div class="font-medium flex items-center gap-2">
                      {action.name}
                      <span class="text-xs px-2 py-0.5 rounded-full bg-secondary-100 dark:bg-secondary-800 text-secondary-600 dark:text-secondary-400">
                        {action.category}
                      </span>
                    </div>
                    <div class="text-sm text-secondary-600 dark:text-secondary-400">
                      {action.description}
                    </div>
                  </div>
                </div>
                <.icon name="hero-chevron-right" class="w-5 h-5 text-secondary-400 dark:text-secondary-500 opacity-0 group-hover:opacity-100" />
              </.link>
            <% end %>
          </div>
        </div>

        <div class="flex-1 p-6">
          <%= if @selected_action do %>
            <div class="max-w-3xl">
              <div class="flex items-center gap-3 mb-8">
                <div class="p-2 rounded-lg bg-primary-500/10 text-primary-600 dark:text-primary-500">
                  <.icon name="hero-bolt" class="w-6 h-6" />
                </div>
                <div>
                  <h1 class="text-2xl font-semibold text-secondary-900 dark:text-secondary-100">
                    {@selected_action.name}
                  </h1>
                  <p class="text-secondary-600 dark:text-secondary-400">
                    {@selected_action.description}
                  </p>
                </div>
              </div>

              <div class="space-y-6 mb-8">
                <div class="flex items-center gap-2 bg-secondary-900/5 dark:bg-secondary-800 px-4 py-3 rounded-lg">
                  <div class="flex items-center gap-2 text-sm text-secondary-700 dark:text-secondary-300 font-mono">
                    <.icon name="hero-code-bracket" class="w-4 h-4 text-secondary-500" />
                    {inspect(@selected_action.module)}
                  </div>
                </div>

                <div class="grid grid-cols-2 gap-4">
                  <div class="bg-secondary-900/5 dark:bg-secondary-800 px-4 py-3 rounded-lg">
                    <div class="text-sm font-medium text-secondary-500 dark:text-secondary-400">Category</div>
                    <div class="mt-1 text-secondary-900 dark:text-secondary-100">
                      {@selected_action.category}
                    </div>
                  </div>

                  <%= if Map.get(@selected_action, :vsn) do %>
                    <div class="bg-secondary-900/5 dark:bg-secondary-800 px-4 py-3 rounded-lg">
                      <div class="text-sm font-medium text-secondary-500 dark:text-secondary-400">Version</div>
                      <div class="mt-1 text-secondary-900 dark:text-secondary-100 font-mono">
                        {inspect(@selected_action.vsn)}
                      </div>
                    </div>
                  <% end %>
                </div>

                <%= if tags = Map.get(@selected_action, :tags) do %>
                  <div class="bg-secondary-900/5 dark:bg-secondary-800 px-4 py-3 rounded-lg">
                    <div class="text-sm font-medium text-secondary-500 dark:text-secondary-400 mb-2">Tags</div>
                    <div class="flex flex-wrap gap-2">
                      <%= for tag <- tags do %>
                        <span class="inline-flex items-center px-2.5 py-1 rounded-md text-xs font-medium bg-secondary-900/10 dark:bg-secondary-700 text-secondary-700 dark:text-secondary-300">
                          {tag}
                        </span>
                      <% end %>
                    </div>
                  </div>
                <% end %>

                <%= if Map.get(@selected_action, :compensation_enabled) do %>
                  <div class="bg-primary-500/10 dark:bg-primary-900/20 px-4 py-3 rounded-lg flex items-center gap-2 text-primary-700 dark:text-primary-400">
                    <.icon name="hero-arrow-path" class="w-4 h-4" />
                    <span class="text-sm font-medium">Compensation Enabled</span>
                  </div>
                <% end %>
              </div>

              <div class="mb-8">
                <h3 class="text-lg font-semibold text-secondary-900 dark:text-secondary-100 mb-4">Parameters</h3>
                <div class="space-y-4">
                  <%= for {field, schema} <- @selected_action.schema do %>
                    <div class="bg-secondary-900/5 dark:bg-secondary-800 px-4 py-3 rounded-lg">
                      <div class="flex items-center justify-between mb-2">
                        <div class="flex items-center gap-2">
                          <div class="font-medium text-secondary-900 dark:text-secondary-100">
                            {field}
                          </div>
                          <%= if schema[:required] do %>
                            <span class="text-xs px-1.5 py-0.5 rounded bg-danger-500/10 text-danger-600 dark:text-danger-400 font-medium">Required</span>
                          <% end %>
                        </div>
                        <div class="text-xs px-2 py-1 rounded-md bg-secondary-900/10 dark:bg-secondary-700 text-secondary-600 dark:text-secondary-400 font-mono">
                          {format_type(schema[:type])}
                        </div>
                      </div>
                      <%= if schema[:doc] do %>
                        <p class="text-sm text-secondary-600 dark:text-secondary-400 mb-2">
                          {schema[:doc]}
                        </p>
                      <% end %>
                      <div class="space-y-1">
                        <%= if schema[:default] do %>
                          <div class="flex items-center gap-2 text-xs text-secondary-500 dark:text-secondary-400">
                            <span class="font-medium">Default:</span>
                            <code class="px-1.5 py-0.5 rounded bg-secondary-900/10 dark:bg-secondary-700 font-mono">{inspect(schema[:default])}</code>
                          </div>
                        <% end %>
                        <%= if validation_rules = get_validation_rules(schema) do %>
                          <div class="flex items-center gap-2 text-xs text-secondary-500 dark:text-secondary-400">
                            <span class="font-medium">Validation:</span>
                            <code class="px-1.5 py-0.5 rounded bg-secondary-900/10 dark:bg-secondary-700 font-mono">{validation_rules}</code>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% else %>
            <div class="h-full flex items-center justify-center text-secondary-500 dark:text-secondary-400">
              Select an action to get started
            </div>
          <% end %>
        </div>
      </div>
    </.workbench_layout>
    """
  end

  @impl true
  def handle_event("search", %{"value" => search_term}, socket) do
    require Logger
    Logger.info("Searching for: #{inspect(search_term)}")

    socket = assign(socket, is_searching: true)

    filtered_actions =
      if search_term == "" do
        Logger.info("Empty search term, returning all actions")
        socket.assigns.all_actions
      else
        search_term = String.downcase(search_term)
        Logger.info("Filtering actions with term: #{search_term}")

        filtered =
          Enum.filter(socket.assigns.all_actions, fn action ->
            searchable_text =
              [
                action.name,
                action.description,
                action.category,
                Atom.to_string(action.module),
                action |> Map.get(:tags, []) |> Enum.join(" ")
              ]
              |> Enum.join(" ")
              |> String.downcase()

            String.contains?(searchable_text, search_term)
          end)
          |> Enum.sort_by(& &1.name)

        Logger.info("Found #{length(filtered)} matching actions")
        filtered
      end

    # Small delay to ensure spinner is visible even for fast searches
    Process.sleep(50)

    # Push the search term to the URL to maintain state during navigation
    push_patch_opts = [
      to:
        case socket.assigns.selected_action do
          nil -> ~p"/catalog/actions?search=#{search_term}"
          action -> ~p"/catalog/actions/#{action.slug}?search=#{search_term}"
        end
    ]

    socket =
      socket
      |> assign(actions: filtered_actions, search: search_term, is_searching: false)
      |> push_patch(push_patch_opts)

    {:noreply, socket}
  end

  @impl true
  def handle_event("execute", params, socket) do
    action = socket.assigns.selected_action.module
    %{"action" => action_params} = params

    # Convert string keys to atoms safely
    converted_params =
      case safe_atomize_keys(action_params) do
        {:ok, converted} -> converted
        {:error, reason} -> %{error: reason}
      end

    result =
      case action do
        nil ->
          {:error, "Action not found"}

        action ->
          case converted_params do
            %{error: reason} -> {:error, reason}
            params -> Jido.Workflow.run(action, params, %{}, [])
          end
      end

    {:noreply, assign(socket, result: result)}
  end

  # Safely converts string keys to existing atoms
  defp safe_atomize_keys(map) when is_map(map) do
    Enum.reduce_while(map, {:ok, %{}}, fn {key, val}, {:ok, acc} ->
      case safe_existing_atom(key) do
        {:ok, atom_key} -> {:cont, {:ok, Map.put(acc, atom_key, val)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp safe_existing_atom(string) when is_binary(string) do
    try do
      {:ok, String.to_existing_atom(string)}
    rescue
      ArgumentError ->
        {:error, "Invalid parameter: #{string} is not a recognized field"}
    end
  end

  defp build_form(action) do
    types =
      action.schema
      |> Enum.map(fn {field, opts} -> {field, get_ecto_type(opts[:type])} end)
      |> Map.new()
      |> Map.put(:action_slug, :string)

    data = %{action_slug: action.slug}

    {data, types}
    |> Ecto.Changeset.cast(%{}, Map.keys(types))
    |> to_form(as: "action")
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

  defp format_type({:in, values}), do: "one of #{inspect(values)}"
  defp format_type(:string), do: "string"
  defp format_type(:integer), do: "integer"
  defp format_type(:float), do: "float"
  defp format_type(:boolean), do: "boolean"
  defp format_type(:atom), do: "atom"
  defp format_type(:non_neg_integer), do: "non-negative integer"
  defp format_type(type), do: inspect(type)

  defp get_validation_rules(schema) do
    rules = []

    rules =
      if type = schema[:type], do: ["type: #{format_type(type)}" | rules], else: rules

    rules =
      case schema[:type] do
        {:in, values} -> ["must be one of: #{Enum.map_join(values, ", ", &inspect/1)}" | rules]
        _ -> rules
      end

    case rules do
      [] -> nil
      rules -> Enum.join(Enum.reverse(rules), ", ")
    end
  end
end
