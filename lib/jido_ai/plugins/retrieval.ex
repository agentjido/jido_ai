require Jido.AI.Actions.Retrieval.ClearMemory
require Jido.AI.Actions.Retrieval.RecallMemory
require Jido.AI.Actions.Retrieval.UpsertMemory

defmodule Jido.AI.Plugins.Retrieval do
  @moduledoc """
  Cross-cutting retrieval and memory enrichment plugin.

  Provides in-process memory operations plus optional prompt enrichment for
  `chat.message` and `reasoning.*.run` signals.
  """

  use Jido.Plugin,
    name: "retrieval",
    state_key: :retrieval,
    actions: [
      Jido.AI.Actions.Retrieval.UpsertMemory,
      Jido.AI.Actions.Retrieval.RecallMemory,
      Jido.AI.Actions.Retrieval.ClearMemory
    ],
    description: "In-process retrieval memory with optional prompt enrichment",
    category: "ai",
    tags: ["retrieval", "memory", "rag"],
    vsn: "1.0.0"

  alias Jido.AI.Retrieval.Store
  alias Jido.Signal

  @enrichable_signals ["chat.message"]

  @impl true
  def mount(agent, config) do
    namespace =
      Map.get(config, :namespace) ||
        if(is_map(agent) and is_binary(agent.id), do: agent.id, else: "default")

    {:ok,
     %{
       enabled: Map.get(config, :enabled, true),
       namespace: namespace,
       top_k: Map.get(config, :top_k, 3),
       max_snippet_chars: Map.get(config, :max_snippet_chars, 280)
     }}
  end

  def schema do
    Zoi.object(%{
      enabled: Zoi.boolean(description: "Enable prompt enrichment") |> Zoi.default(true),
      namespace: Zoi.string(description: "Retrieval namespace key") |> Zoi.optional(),
      top_k: Zoi.integer(description: "Default top-k recall count") |> Zoi.default(3),
      max_snippet_chars: Zoi.integer(description: "Max chars per injected memory snippet") |> Zoi.default(280)
    })
  end

  @impl true
  def signal_routes(_config) do
    [
      {"retrieval.upsert", Jido.AI.Actions.Retrieval.UpsertMemory},
      {"retrieval.recall", Jido.AI.Actions.Retrieval.RecallMemory},
      {"retrieval.clear", Jido.AI.Actions.Retrieval.ClearMemory}
    ]
  end

  @impl true
  def handle_signal(%Signal{} = signal, context) do
    state = plugin_state(context)

    if state[:enabled] == true and enrichable_signal?(signal.type) do
      maybe_enrich_signal(signal, state)
    else
      {:ok, :continue}
    end
  end

  def handle_signal(_signal, _context), do: {:ok, :continue}

  defp maybe_enrich_signal(%Signal{data: data} = signal, state) when is_map(data) do
    if data[:disable_retrieval] == true or data["disable_retrieval"] == true do
      {:ok, :continue}
    else
      query = extract_query(data)

      if is_binary(query) and query != "" do
        namespace = state[:namespace] || "default"
        top_k = max(state[:top_k] || 3, 1)
        snippets = Store.recall(namespace, query, top_k: top_k)

        if snippets == [] do
          {:ok, :continue}
        else
          enriched_prompt = build_enriched_prompt(query, snippets, state[:max_snippet_chars] || 280)

          enriched_data =
            data
            |> Map.put(:prompt, enriched_prompt)
            |> Map.put(:retrieval, %{
              namespace: namespace,
              snippets: Enum.map(snippets, &Map.take(&1, [:id, :score, :metadata]))
            })

          {:ok, {:continue, %{signal | data: enriched_data}}}
        end
      else
        {:ok, :continue}
      end
    end
  end

  defp maybe_enrich_signal(_signal, _state), do: {:ok, :continue}

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

  defp extract_query(data) do
    first_present([
      Map.get(data, :prompt),
      Map.get(data, "prompt"),
      Map.get(data, :query),
      Map.get(data, "query")
    ])
  end

  defp enrichable_signal?(type) when is_binary(type) do
    type in @enrichable_signals or
      (String.starts_with?(type, "reasoning.") and String.ends_with?(type, ".run"))
  end

  defp enrichable_signal?(_), do: false

  defp plugin_state(%{agent: %{state: state}, plugin_instance: %{state_key: state_key}})
       when is_map(state) and is_atom(state_key) do
    Map.get(state, state_key, %{})
  end

  defp plugin_state(_), do: %{}

  defp first_present(values), do: Enum.find(values, &(not is_nil(&1)))
end
