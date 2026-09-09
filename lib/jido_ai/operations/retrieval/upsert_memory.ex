defmodule Jido.AI.Actions.Retrieval.UpsertMemory do
  @moduledoc """
  Upserts a memory snippet into the in-process retrieval store.
  """

  use Jido.Action,
    name: "retrieval_upsert_memory",
    description: "Insert or update retrieval memory",
    schema:
      Zoi.object(%{
        id: Zoi.string(description: "Memory ID") |> Zoi.optional(),
        text: Zoi.string(description: "Memory text content"),
        metadata: Zoi.map(description: "Optional memory metadata") |> Zoi.default(%{}),
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
      entry = Store.upsert(namespace, Map.take(params, [:id, :text, :metadata]), store)
      {:ok, %{retrieval: %{namespace: namespace, last_upsert: entry}}}
    end)
  end
end
