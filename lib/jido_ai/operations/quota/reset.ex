defmodule Jido.AI.Actions.Quota.Reset do
  @moduledoc """
  Resets quota counters for a scope.
  """

  use Jido.Action,
    name: "quota_reset",
    description: "Reset quota usage counters",
    schema:
      Zoi.object(%{
        scope: Zoi.string(description: "Quota scope key") |> Zoi.optional()
      })

  alias Jido.AI.Quota.Store

  def category, do: "ai"
  def tags, do: ["quota", "usage", "budget"]
  def vsn, do: "1.0.0"
  @impl Jido.Action
  def on_before_validate_params(params), do: Jido.AI.ActionInput.before_validate(schema(), params)
  @impl Jido.Action
  def run(params, context) do
    Jido.AI.Actions.Quota.Request.run(schema(), params, context, fn scope, _defaults, store ->
      :ok = Store.reset(scope, store)
      {:ok, %{quota: %{scope: scope, reset: true}}}
    end)
  end
end
