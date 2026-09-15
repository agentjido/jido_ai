defmodule Jido.AI.Actions.Retrieval.RecallMemory do
  @moduledoc """
  Recalls top-k memory snippets from the in-process retrieval store.
  """

  use Jido.Action,
    name: "retrieval_recall_memory",
    description: "Recall memory snippets relevant to a query",
    schema:
      Zoi.object(%{
        query: Zoi.string(description: "Recall query text"),
        top_k: Zoi.integer(description: "Number of memory snippets to return") |> Zoi.default(3),
        namespace: Zoi.string(description: "Memory namespace") |> Zoi.optional()
      })

  alias Jido.AI.Retrieval.Store

  def category, do: "ai"
  def tags, do: ["retrieval", "memory"]
  def vsn, do: "1.0.0"
  @impl Jido.Action
  def on_before_validate_params(params), do: Jido.AI.ActionInput.before_validate(schema(), params)

  @impl Jido.Action
  def run(params, context) do
    Jido.AI.Actions.Retrieval.Request.run(schema(), params, context, fn params, namespace, store ->
      memories = Store.recall(namespace, params.query, top_k: max(params.top_k, 1), store: store)

      {:ok,
       %{
         retrieval: %{
           namespace: namespace,
           query: params.query,
           memories: memories,
           count: length(memories)
         }
       }}
    end)
  end
end
