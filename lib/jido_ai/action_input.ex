defmodule Jido.AI.ActionInput do
  @moduledoc false
  @provided :__jido_ai_action_provided__

  def before_validate(schema, params) do
    params = Jido.AI.SchemaInput.normalize(schema, params)
    {:ok, Map.put(params, @provided, Map.keys(params) -- [@provided])}
  end

  def parse(schema, params, context, defaults \\ %{}, scopes \\ []) do
    Zoi.parse(schema, apply_defaults(schema, params, context, defaults, scopes))
  end

  def apply_defaults(schema, params, context, defaults, scopes) when is_map(params) do
    params = Jido.AI.SchemaInput.normalize(schema, params)

    provided =
      case context[:provided_params] do
        keys when is_list(keys) -> keys
        _ -> Map.get(params, @provided, Map.keys(params))
      end

    Enum.reduce(defaults, Map.delete(params, @provided), fn {key, aliases}, acc ->
      explicit? = is_list(provided) and Enum.any?(provided, &(&1 in [key, Atom.to_string(key)]))

      values =
        Enum.map(aliases, &Map.get(context, &1)) ++
          for alias_key <- aliases,
              path <- [[:plugin_state], [:state], [:agent, :state]],
              scope <- scopes,
              do: nested(context, path ++ [scope, alias_key])

      default = first_present(values)
      if explicit? or is_nil(default), do: acc, else: Map.put(acc, key, default)
    end)
  end

  def apply_defaults(_, params, _, _, _), do: params

  def options(params, context, keys \\ [:max_tokens, :temperature]) do
    provider = Map.get(context, :model_options, [])

    if Keyword.keyword?(provider) do
      generation = Enum.map(keys, &{&1, params[&1]}) ++ [receive_timeout: params[:timeout]]
      {:ok, Keyword.merge(provider, Enum.reject(generation, fn {_, v} -> is_nil(v) end))}
    else
      {:error, :invalid_model_options}
    end
  end

  def tools(context) do
    paths = [
      [:tools],
      [:tool_calling, :tools],
      [:chat, :tools],
      [:state, :tool_calling, :tools],
      [:state, :chat, :tools],
      [:agent, :state, :tool_calling, :tools],
      [:agent, :state, :chat, :tools],
      [:plugin_state, :tool_calling, :tools],
      [:plugin_state, :chat, :tools]
    ]

    first_present(Enum.map(paths, &nested(context, &1))) || %{}
  end

  def context(context) when is_map(context), do: context
  def context(_), do: %{}
  defp nested(value, []), do: value
  defp nested(value, [key | rest]) when is_map(value), do: nested(Map.get(value, key), rest)
  defp nested(_, _), do: nil
  defp first_present(values), do: Enum.find(values, &(not is_nil(&1)))
end
