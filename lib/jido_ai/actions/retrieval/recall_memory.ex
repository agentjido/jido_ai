defmodule Jido.AI.Actions.Retrieval.RecallMemory do
  @moduledoc """
  Recalls top-k memory snippets from the in-process retrieval store.
  """

  use Jido.Action,
    name: "retrieval_recall_memory",
    description: "Recall memory snippets relevant to a query",
    category: "ai",
    tags: ["retrieval", "memory"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        query: Zoi.string(description: "Recall query text"),
        top_k: Zoi.integer(description: "Number of memory snippets to return") |> Zoi.default(3),
        namespace: Zoi.string(description: "Memory namespace") |> Zoi.optional()
      })

  alias Jido.AI.Retrieval.Store

  @impl true
  def run(params, context) do
    namespace = params[:namespace] || resolve_namespace(context)
    memories = Store.recall(namespace, params[:query], top_k: max(params[:top_k] || 3, 1))

    {:ok,
     %{
       retrieval: %{
         namespace: namespace,
         query: params[:query],
         memories: memories,
         count: length(memories)
       }
     }}
  end

  defp resolve_namespace(context) when is_map(context) do
    first_present([
      get_in(context, [:plugin_state, :retrieval, :namespace]),
      get_in(context, [:state, :retrieval, :namespace]),
      get_in(context, [:agent, :id]),
      "default"
    ])
  end

  defp resolve_namespace(_), do: "default"

  defp first_present(values), do: Enum.find(values, &(not is_nil(&1)))
end
