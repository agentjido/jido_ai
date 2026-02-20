defmodule Jido.AI.Actions.Quota.GetStatus do
  @moduledoc """
  Returns current quota usage and budget status.
  """

  use Jido.Action,
    name: "quota_get_status",
    description: "Get current quota usage status",
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
    limits = resolve_limits(context)
    window_ms = resolve_window_ms(context)
    status = Store.status(scope, limits, window_ms)

    {:ok, %{quota: status}}
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

  defp resolve_limits(context) when is_map(context) do
    %{
      max_requests:
        first_present([
          get_in(context, [:plugin_state, :quota, :max_requests]),
          get_in(context, [:state, :quota, :max_requests]),
          nil
        ]),
      max_total_tokens:
        first_present([
          get_in(context, [:plugin_state, :quota, :max_total_tokens]),
          get_in(context, [:state, :quota, :max_total_tokens]),
          nil
        ])
    }
  end

  defp resolve_limits(_), do: %{max_requests: nil, max_total_tokens: nil}

  defp resolve_window_ms(context) when is_map(context) do
    first_present([
      get_in(context, [:plugin_state, :quota, :window_ms]),
      get_in(context, [:state, :quota, :window_ms]),
      60_000
    ])
  end

  defp resolve_window_ms(_), do: 60_000

  defp first_present(values), do: Enum.find(values, &(not is_nil(&1)))
end
