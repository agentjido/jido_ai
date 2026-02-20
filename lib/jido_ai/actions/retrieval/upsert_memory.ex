defmodule Jido.AI.Actions.Retrieval.UpsertMemory do
  @moduledoc """
  Upserts a memory snippet into the in-process retrieval store.
  """

  use Jido.Action,
    name: "retrieval_upsert_memory",
    description: "Insert or update retrieval memory",
    category: "ai",
    tags: ["retrieval", "memory"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        id: Zoi.string(description: "Memory ID") |> Zoi.optional(),
        text: Zoi.string(description: "Memory text content"),
        metadata: Zoi.map(description: "Optional memory metadata") |> Zoi.default(%{}),
        namespace: Zoi.string(description: "Memory namespace") |> Zoi.optional()
      })

  alias Jido.AI.Retrieval.Store

  @impl true
  def run(params, context) do
    namespace = params[:namespace] || resolve_namespace(context)

    entry =
      Store.upsert(namespace, %{
        id: params[:id] || "mem_#{Jido.Util.generate_id()}",
        text: params[:text],
        metadata: params[:metadata] || %{}
      })

    {:ok,
     %{
       retrieval: %{
         namespace: namespace,
         last_upsert: entry
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
