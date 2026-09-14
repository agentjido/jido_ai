defmodule Jido.AI.Plugins.Retrieval do
  @moduledoc """
  Retrieval defaults and live memory enrichment for core Agents.

  Supervise `Jido.AI.Retrieval.Store` in the application. An explicit `store`
  option selects another registered store. Agents with the same store and
  namespace share memory. The store lives independently of individual Agents.

  Use keyword configuration. Declare the three
  `signal_routes/1` routes to store Action results in `into` (default `:result`).
  Plugin state contains configuration only. Core live admission performs memory
  reads for Chat, reasoning and native AI requests. Pure preparation only binds
  capability input; direct Agent commands do not implicitly read memory.
  """
  use Jido.Plugin,
    agent: Jido.AI.Plugins.Retrieval.Agent,
    agent_server: Jido.AI.Plugins.Retrieval.AgentServer

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

  @doc false
  def agent_state_spec(opts) do
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

  @doc false
  def prepare_input(preparation, opts) do
    state = effective_state(preparation.plugin_state, preparation.agent_id)
    store = Keyword.get(opts, :store, Store)

    binding =
      if action = @routes[preparation.signal.type] do
        %{
          action: action,
          key: :retrieval,
          defaults: state,
          store: store,
          into: Keyword.get(opts, :into, :result)
        }
      end

    {:ok, %{state: state, store: store, capability: binding}}
  end

  @doc false
  def admit_input(admission) do
    %{state: state, store: store} = admission.prepared_input
    signal = admission.signal
    data = signal.data

    native? =
      (String.starts_with?(signal.type, "ai.") and String.ends_with?(signal.type, ".query")) or
        Jido.AI.Runtime.Plugin.native_request?(admission)

    eligible? =
      native? or signal.type == "chat.message" or
        (String.starts_with?(signal.type, "reasoning.") and String.ends_with?(signal.type, ".run"))

    if state.enabled and eligible? and is_map(data) and
         data[:disable_retrieval] != true and data["disable_retrieval"] != true do
      query = if native?, do: Map.get(data, :query, data["query"]), else: extract_query(data)
      enrich(query, if(native?, do: :query, else: :prompt), state, store)
    else
      {:ok, nil}
    end
  end

  def apply_input(params, context) do
    case get_in(context, [:plugin_inputs, __MODULE__]) do
      %Jido.Plugin.Input{runtime: %{key: key, value: value}} -> Map.put(params, key, value)
      _ -> params
    end
  end

  defp effective_state(state, agent_id),
    do: %{state | namespace: state.namespace || agent_id || "default"}

  defp enrich(query, key, state, store) do
    query_text = retrieval_query_text(query)

    if query_text == "" do
      {:ok, nil}
    else
      enrich_with_query_text(query, query_text, key, state, store)
    end
  end

  defp enrich_with_query_text(query, query_text, key, state, store) do
    snippets =
      Store.recall(state.namespace, query_text,
        top_k: max(state.top_k, 1),
        store: store
      )

    if snippets == [] do
      {:ok, nil}
    else
      {:ok,
       %{
         key: key,
         value: build_enriched_query(query, snippets, state.max_snippet_chars),
         retrieval: %{
           namespace: state.namespace,
           snippets: Enum.map(snippets, &Map.take(&1, [:id, :score, :metadata]))
         }
       }}
    end
  end

  defp retrieval_query_text(query) when is_binary(query), do: String.trim(query)

  defp retrieval_query_text(query) when is_list(query) do
    query
    |> Enum.flat_map(fn
      %ReqLLM.Message.ContentPart{type: :text, text: text} when is_binary(text) -> [text]
      %{type: :text, text: text} when is_binary(text) -> [text]
      %{"type" => "text", "text" => text} when is_binary(text) -> [text]
      _ -> []
    end)
    |> Enum.join("\n")
    |> String.trim()
  end

  defp retrieval_query_text(_query), do: ""

  defp build_enriched_query(query, snippets, max_snippet_chars) when is_binary(query),
    do: build_enriched_prompt(query, snippets, max_snippet_chars)

  defp build_enriched_query(query, snippets, max_snippet_chars) when is_list(query) do
    memory = build_memory_block(snippets, max_snippet_chars)
    [ReqLLM.Message.ContentPart.text("Relevant memory:\n#{memory}\n\nUser prompt:") | query]
  end

  defp build_enriched_prompt(query, snippets, max_snippet_chars) do
    memory_block = build_memory_block(snippets, max_snippet_chars)

    """
    Relevant memory:
    #{memory_block}

    User prompt:
    #{query}
    """
    |> String.trim()
  end

  defp build_memory_block(snippets, max_snippet_chars) do
    Enum.map_join(snippets, "\n", fn snippet ->
      text =
        snippet
        |> Map.get(:text, "")
        |> to_string()
        |> String.slice(0, max_snippet_chars)

      "- #{text}"
    end)
  end

  defp extract_query(data),
    do: Enum.find([data[:prompt], data["prompt"], data[:query], data["query"]], &(not is_nil(&1)))
end

defmodule Jido.AI.Plugins.Retrieval.Agent do
  @moduledoc false
  use Jido.Agent.Plugin

  @impl Jido.Agent.Plugin
  def state_spec(opts), do: Jido.AI.Plugins.Retrieval.agent_state_spec(opts)

  @impl Jido.Agent.Plugin
  def prepare(preparation, opts), do: Jido.AI.Plugins.Retrieval.prepare_input(preparation, opts)
end

defmodule Jido.AI.Plugins.Retrieval.AgentServer do
  @moduledoc false
  use Jido.AgentServer.Plugin

  @impl Jido.AgentServer.Plugin
  def admit(_runtime, admission, _opts), do: Jido.AI.Plugins.Retrieval.admit_input(admission)
end
