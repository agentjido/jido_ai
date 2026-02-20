defmodule Jido.AI.Actions.Retrieval.ClearMemory do
  @moduledoc """
  Clears retrieval memories in a namespace from the in-process store.
  """

  use Jido.Action,
    name: "retrieval_clear_memory",
    description: "Clear retrieval memories in a namespace",
    category: "ai",
    tags: ["retrieval", "memory"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        namespace: Zoi.string(description: "Memory namespace") |> Zoi.optional()
      })

  alias Jido.AI.Retrieval.Store

  @impl true
  def run(params, context) do
    namespace = params[:namespace] || resolve_namespace(context)
    cleared = Store.clear(namespace)

    {:ok,
     %{
       retrieval: %{
         namespace: namespace,
         cleared: cleared
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
