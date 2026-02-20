defmodule Jido.AI.Actions.Quota.Reset do
  @moduledoc """
  Resets quota counters for a scope.
  """

  use Jido.Action,
    name: "quota_reset",
    description: "Reset quota usage counters",
    category: "ai",
    tags: ["quota", "usage", "budget"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        scope: Zoi.string(description: "Quota scope key") |> Zoi.optional()
      })

  alias Jido.AI.Quota.Store

  @impl true
  def run(params, context) do
    scope = params[:scope] || resolve_scope(context)
    :ok = Store.reset(scope)
    {:ok, %{quota: %{scope: scope, reset: true}}}
  end

  defp resolve_scope(context) when is_map(context) do
    first_present([
      get_in(context, [:plugin_state, :quota, :scope]),
      get_in(context, [:state, :quota, :scope]),
      get_in(context, [:agent, :id]),
      "default"
    ])
  end

  defp resolve_scope(_), do: "default"

  defp first_present(values), do: Enum.find(values, &(not is_nil(&1)))
end
