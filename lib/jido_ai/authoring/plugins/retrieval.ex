defmodule Jido.AI.Plugins.Retrieval do
  @moduledoc """
  Retrieval defaults and live memory enrichment for core Agents.

  Supervise `Jido.AI.Retrieval.Store` in the application. An explicit `store`
  option selects another registered store. Agents with the same store and
  namespace share memory. The store lives independently of individual Agents.

  Keyword configuration replaces v2 mount configuration. Declare the three
  `signal_routes/1` routes to store Action results in `into` (default `:result`).
  Plugin state contains configuration only. Core live admission performs memory
  reads for Chat, reasoning and native AI requests. Pure preparation only binds
  capability input; direct Agent commands do not implicitly read memory.
  """
  use Jido.Plugin
  alias Jido.AI.Retrieval.Store
  alias Jido.AI.Actions.Retrieval.{UpsertMemory, RecallMemory, ClearMemory}
  @defaults %{enabled: true, namespace: nil, top_k: 3, max_snippet_chars: 280}
  @routes %{
    "retrieval.upsert" => UpsertMemory,
    "retrieval.recall" => RecallMemory,
    "retrieval.clear" => ClearMemory
  }

  def name, do: "retrieval"
  def description, do: "In-process retrieval memory with optional prompt enrichment"
  def category, do: "ai"
  def tags, do: ["retrieval", "memory", "rag"]
  def vsn, do: "1.0.0"
  def state_key, do: :retrieval
  def actions, do: [UpsertMemory, RecallMemory, ClearMemory]

  def signal_routes(_),
    do:
      Enum.map(
        ["retrieval.upsert", "retrieval.recall", "retrieval.clear"],
        &{&1, Jido.AI.Actions.Retrieval.RunCapability}
      )

  def schema, do: state_schema(@defaults)

  @impl Jido.Plugin
  def state_spec(opts) do
    Jido.AI.PluginConfig.validate!(opts, Map.keys(@defaults) ++ [:into, :store], "Retrieval")
    into = Keyword.get(opts, :into, :result)
    store = Keyword.get(opts, :store, Store)

    unless is_atom(into) and into not in [nil, true, false],
      do: raise(ArgumentError, "into must be a field atom")

    unless is_atom(store) and store not in [nil, true, false],
      do: raise(ArgumentError, "store must be a registered name")

    case Zoi.parse(schema(), opts |> Keyword.drop([:into, :store]) |> Map.new()) do
      {:ok, defaults} -> {:retrieval, state_schema(defaults)}
      {:error, errors} -> raise ArgumentError, "Invalid Retrieval defaults: #{inspect(errors)}"
    end
  end

  defp state_schema(defaults) do
    Zoi.object(%{
      enabled: Zoi.boolean() |> Zoi.default(defaults.enabled),
      namespace: Zoi.string() |> Zoi.optional() |> Zoi.default(defaults.namespace),
      top_k: Zoi.integer() |> Zoi.default(defaults.top_k),
      max_snippet_chars: Zoi.integer() |> Zoi.min(1) |> Zoi.default(defaults.max_snippet_chars)
    })
    |> Zoi.default(defaults)
  end

  @impl Jido.Plugin
  def prepare(command, opts) do
    state = effective_state(command)
    context = Map.put(command.context, :retrieval_store, Keyword.get(opts, :store, Store))

    binding =
      if action = @routes[command.signal.type] do
        %{
          action: action,
          key: :retrieval,
          defaults: state,
          into: Keyword.get(opts, :into, :result)
        }
      end

    Jido.AI.Capability.bind(%{command | context: context}, :jido_ai_retrieval_capability, binding)
  end

  @impl Jido.Plugin
  def admit(_, command, opts) do
    state = effective_state(command)
    signal = command.signal
    binding = Jido.AI.Authoring.request_binding(command.agent, signal)
    data = if binding, do: binding.input, else: signal.data
    native? = not is_nil(binding)

    eligible? =
      native? or signal.type == "chat.message" or
        (String.starts_with?(signal.type, "reasoning.") and String.ends_with?(signal.type, ".run"))

    if state.enabled and eligible? and is_map(data) and
         data[:disable_retrieval] != true and data["disable_retrieval"] != true do
      query = if native?, do: Map.get(data, :query, data["query"]), else: extract_query(data)
      enrich(command, query, if(native?, do: :query, else: :prompt), state, opts)
    else
      {:ok, command}
    end
  end

  defp effective_state(command) do
    state = command.agent.state.retrieval
    %{state | namespace: state.namespace || command.agent.id || "default"}
  end

  defp enrich(command, query, key, state, opts) when is_binary(query) and query != "" do
    snippets =
      Store.recall(state.namespace, query,
        top_k: max(state.top_k, 1),
        store: Keyword.get(opts, :store, Store)
      )

    if snippets == [] do
      {:ok, command}
    else
      data =
        command.signal.data
        |> Map.put(key, build_enriched_prompt(query, snippets, state.max_snippet_chars))
        |> Map.put(:retrieval, %{
          namespace: state.namespace,
          snippets: Enum.map(snippets, &Map.take(&1, [:id, :score, :metadata]))
        })

      {:ok, %{command | signal: %{command.signal | data: data}}}
    end
  end

  defp enrich(command, _, _, _, _), do: {:ok, command}

  defp build_enriched_prompt(query, snippets, max_snippet_chars) do
    memory_block =
      snippets
      |> Enum.map_join("\n", fn snippet ->
        text =
          snippet
          |> Map.get(:text, "")
          |> to_string()
          |> String.slice(0, max_snippet_chars)

        "- #{text}"
      end)

    """
    Relevant memory:
    #{memory_block}

    User prompt:
    #{query}
    """
    |> String.trim()
  end

  defp extract_query(data),
    do: Enum.find([data[:prompt], data["prompt"], data[:query], data["query"]], &(not is_nil(&1)))
end
