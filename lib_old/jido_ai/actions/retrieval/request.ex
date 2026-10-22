defmodule Jido.AI.Actions.Retrieval.Request do
  @moduledoc false
  def run(schema, params, context, fun) do
    context = Jido.AI.ActionInput.context(context)

    Jido.AI.Error.capture(fn ->
      with {:ok, params} <- Jido.AI.ActionInput.parse(schema, params, context) do
        namespace = params[:namespace] || namespace(context)
        fun.(params, namespace, Map.get(context, :retrieval_store, Jido.AI.Retrieval.Store))
      end
    end)
  end

  def namespace(context) do
    Enum.map(
      [
        [:plugin_state, :retrieval, :namespace],
        [:state, :retrieval, :namespace],
        [:agent, :state, :retrieval, :namespace],
        [:agent, :id]
      ],
      &nested(context, &1)
    )
    |> Enum.find("default", &(not is_nil(&1)))
  end

  defp nested(value, []), do: value
  defp nested(value, [key | rest]) when is_map(value), do: nested(Map.get(value, key), rest)
  defp nested(_, _), do: nil
end
