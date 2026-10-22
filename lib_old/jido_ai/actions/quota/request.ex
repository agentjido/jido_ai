defmodule Jido.AI.Actions.Quota.Request do
  @moduledoc false
  def run(schema, params, context, fun) do
    context = Jido.AI.ActionInput.context(context)

    Jido.AI.Error.capture(fn ->
      with {:ok, params} <- Jido.AI.ActionInput.parse(schema, params, context) do
        defaults =
          Map.new(
            [scope: nil, window_ms: 60_000, max_requests: nil, max_total_tokens: nil],
            fn {key, default} ->
              value =
                Enum.map(
                  [
                    [:plugin_state, :quota, key],
                    [:state, :quota, key],
                    [:agent, :state, :quota, key]
                  ],
                  &nested(context, &1)
                )
                |> Enum.find(default, &(not is_nil(&1)))

              {key, value}
            end
          )

        scope = params[:scope] || defaults.scope || nested(context, [:agent, :id]) || "default"
        fun.(scope, defaults, Map.get(context, :quota_store, Jido.AI.Quota.Store))
      end
    end)
  end

  defp nested(value, []), do: value
  defp nested(value, [key | rest]) when is_map(value), do: nested(Map.get(value, key), rest)
  defp nested(_, _), do: nil
end
