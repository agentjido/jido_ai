defmodule Jido.AI.Actions.Quota.GetStatus do
  @moduledoc """
  Returns current quota usage and budget status.
  """

  use Jido.Action,
    name: "quota_get_status",
    description: "Get current quota usage status",
    schema:
      Zoi.object(%{
        scope: Zoi.string(description: "Quota scope key") |> Zoi.optional()
      })

  alias Jido.AI.Quota.Store

  @doc "Returns the Action category."
  def category, do: "ai"

  @doc "Returns tags that classify this Action."
  def tags, do: ["quota", "usage", "budget"]
  @doc "Returns the Action metadata version."
  def vsn, do: "1.0.0"
  @impl Jido.Action
  def on_before_validate_params(params), do: Jido.AI.ActionInput.before_validate(schema(), params)
  @impl Jido.Action
  def run(params, context) do
    Jido.AI.Actions.Quota.Request.run(schema(), params, context, fn scope, defaults, store ->
      {:ok, %{quota: Store.status(scope, defaults, defaults.window_ms, store)}}
    end)
  end
end
