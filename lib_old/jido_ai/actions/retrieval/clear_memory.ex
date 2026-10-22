defmodule Jido.AI.Actions.Retrieval.ClearMemory do
  @moduledoc """
  Clears retrieval memories in a namespace from the in-process store.
  """

  use Jido.Action,
    name: "retrieval_clear_memory",
    description: "Clear retrieval memories in a namespace",
    schema:
      Zoi.object(%{
        namespace: Zoi.string(description: "Memory namespace") |> Zoi.optional()
      })

  alias Jido.AI.Retrieval.Store

  @doc "Returns the Action category."
  def category, do: "ai"

  @doc "Returns tags that classify this Action."
  def tags, do: ["retrieval", "memory"]
  @doc "Returns the Action metadata version."
  def vsn, do: "1.0.0"
  @impl Jido.Action
  def on_before_validate_params(params), do: Jido.AI.ActionInput.before_validate(schema(), params)

  @impl Jido.Action
  def run(params, context) do
    Jido.AI.Actions.Retrieval.Request.run(schema(), params, context, fn _params, namespace, store ->
      {:ok, %{retrieval: %{namespace: namespace, cleared: Store.clear(namespace, store)}}}
    end)
  end
end
