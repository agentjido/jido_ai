defmodule Jido.AI.Profile.References do
  @moduledoc false

  import Jido.AI.Profile, only: [error: 2, fields: 3, traverse: 2]

  @stages [:input, :model, :operation, :output]
  @control_fields [:max_iterations, :max_model_calls, :max_tool_calls, :timeout] ++ @stages

  # Resolve only explicit references. Profile retains defaults and policy validation.
  def resolve(attrs, registries) do
    with {:ok, {tool_sources, tools}} <- split_tool_inputs(Map.get(attrs, :tools, [])),
         {:ok, explicit_sources} <- tool_source_inputs(Map.get(attrs, :tool_sources, [])),
         tool_sources = explicit_sources ++ tool_sources,
         {:ok, instructions} <- resolve_instructions(attrs[:instructions], registries),
         {:ok, tools} <- resolve_tools(tools, registries),
         {:ok, result} <- resolve_result(attrs[:result], registries),
         {:ok, models} <- resolve_router(Map.get(attrs, :models), registries),
         {:ok, controls} <- resolve_control_references(Map.get(attrs, :controls, %{}), registries) do
      attrs =
        if Map.has_key?(attrs, :instructions),
          do: Map.put(attrs, :instructions, instructions),
          else: attrs

      {:ok,
       attrs
       |> Map.put(:tools, tools)
       |> Map.put(:tool_sources, tool_sources)
       |> Map.put(:result, result)
       |> Map.put(:models, models)
       |> Map.put(:controls, controls)}
    end
  end

  defp split_tool_inputs(values) when is_list(values),
    do: {:ok, Enum.split_with(values, &Jido.AI.ToolSource.source_input?/1)}

  defp split_tool_inputs(_), do: error("tools", "Expected a tool list")

  defp tool_source_inputs(values) when is_list(values), do: {:ok, values}
  defp tool_source_inputs(_), do: error("tool_sources", "Expected a tool-source list")

  defp resolve_instructions(%{} = value, registries) do
    action = Map.get(value, :action, Map.get(value, "action"))

    if is_binary(action) and map_size(value) == 1,
      do: registry(registries, :actions, action),
      else: {:ok, value}
  end

  defp resolve_instructions(value, _), do: {:ok, value}

  defp resolve_tools(values, registries) when is_list(values),
    do: traverse(values, &resolve_tool(&1, registries))

  defp resolve_tools(value, _), do: {:ok, value}

  defp resolve_tool(%{} = value, registries) when not is_struct(value) do
    ref = Map.get(value, :ref, Map.get(value, "ref"))
    kind = Map.get(value, :kind, Map.get(value, "kind", "action"))

    if is_binary(ref) do
      registry_kind = if kind in [:flow, "flow"], do: :flows, else: :actions

      with {:ok, target} <- registry(registries, registry_kind, ref),
           {:ok, fields} <-
             fields(
               value,
               [
                 :kind,
                 :ref,
                 :name,
                 :as,
                 :description,
                 :forward_context,
                 :timeout,
                 :max_retries,
                 :retry_backoff,
                 :idempotency,
                 :approval,
                 :metadata
               ],
               "tools"
             ) do
        name = Map.get(fields, :as, Map.get(fields, :name))

        {:ok,
         fields
         |> Map.drop([:kind, :ref, :as])
         |> Map.put(:target, target)
         |> then(fn tool -> if is_nil(name), do: tool, else: Map.put(tool, :name, to_string(name)) end)}
      end
    else
      {:ok, value}
    end
  end

  defp resolve_tool(%Jido.Flow{} = value, _registries), do: {:ok, %{target: value}}
  defp resolve_tool(value, _registries) when is_atom(value), do: {:ok, %{target: value}}
  defp resolve_tool(value, _), do: {:ok, value}

  defp resolve_result(nil, _), do: {:ok, nil}

  defp resolve_result(value, registries) when is_list(value) do
    if Keyword.keyword?(value), do: resolve_result(Map.new(value), registries), else: {:ok, value}
  end

  defp resolve_result(%{} = value, registries) do
    with {:ok, schema} <- resolve_schema(Map.get(value, :schema, Map.get(value, "schema")), registries),
         {:ok, repair} <-
           resolve_action_ref(
             Map.get(value, :repair_action, Map.get(value, "repair_action")),
             registries
           ),
         {:ok, fields} <-
           fields(
             value,
             [:schema, :into, :max_repairs, :repair_fun, :repair_action, :on_validation_error],
             "result"
           ) do
      value = if is_nil(schema), do: Map.delete(fields, :schema), else: Map.put(fields, :schema, schema)

      {:ok,
       if(is_nil(repair),
         do: Map.delete(value, :repair_action),
         else: Map.put(value, :repair_action, repair)
       )}
    end
  end

  defp resolve_result(value, _), do: {:ok, value}

  defp resolve_schema(nil, _), do: {:ok, nil}

  defp resolve_schema(%{} = value, registries) do
    ref = Map.get(value, :ref, Map.get(value, "ref"))
    if is_binary(ref), do: registry(registries, :schemas, ref), else: {:ok, value}
  end

  defp resolve_schema(value, _), do: {:ok, value}

  defp resolve_action_ref(nil, _), do: {:ok, nil}

  defp resolve_action_ref(%{} = value, registries) do
    ref = Map.get(value, :ref, Map.get(value, "ref"))
    if is_binary(ref), do: registry(registries, :actions, ref), else: {:ok, value}
  end

  defp resolve_action_ref(value, _), do: {:ok, value}

  defp resolve_router(nil, _), do: {:ok, nil}

  defp resolve_router(%{} = models, registries) do
    router = Map.get(models, :router, Map.get(models, "router"))

    if is_map(router) do
      ref = Map.get(router, :ref, Map.get(router, "ref"))

      if is_binary(ref) do
        with {:ok, module} <- registry(registries, :model_routers, ref) do
          fallback = Map.get(router, :fallback, Map.get(router, "fallback"))
          resolved = %{module: module, fallback: fallback}

          key = if Map.has_key?(models, :router), do: :router, else: "router"
          {:ok, Map.put(models, key, resolved)}
        end
      else
        {:ok, models}
      end
    else
      {:ok, models}
    end
  end

  defp resolve_router(value, _), do: {:ok, value}

  defp resolve_control_references(value, registries) when is_map(value) or is_list(value) do
    with {:ok, value} <- control_input_map(value),
         {:ok, value} <- fields(value, @control_fields, "controls") do
      Enum.reduce_while(@stages, {:ok, value}, fn stage, {:ok, acc} ->
        with {:ok, controls} <-
               traverse(Map.get(acc, stage, []), &resolve_control_reference(&1, registries)) do
          {:cont, {:ok, Map.put(acc, stage, controls)}}
        else
          error -> {:halt, error}
        end
      end)
    end
  end

  defp resolve_control_references(value, _registries), do: {:ok, value}

  defp resolve_control_reference(%{} = value, registries) do
    ref = Map.get(value, :ref, Map.get(value, "ref"))

    if is_binary(ref) do
      with {:ok, module} <- registry(registries, :controls, ref) do
        case Map.get(value, :when, Map.get(value, "when")) do
          nil -> {:ok, module}
          match -> {:ok, %{module: module, when: match}}
        end
      end
    else
      {:ok, value}
    end
  end

  defp resolve_control_reference(value, _registries), do: {:ok, value}

  defp registry(%Jido.Codec.Registry{} = registry, kind, id) do
    core_kind = if kind == :actions, do: :action, else: if(kind == :flows, do: :flow, else: nil)

    if core_kind,
      do: Jido.Codec.Registry.resolve(registry, id, core_kind),
      else: error("registries", "This Registry does not contain #{kind}")
  end

  defp registry(registries, kind, id) when is_map(registries) do
    values = Map.get(registries, kind, Map.get(registries, Atom.to_string(kind), %{}))

    case values do
      %{} ->
        case Map.fetch(values, id) do
          {:ok, value} -> {:ok, value}
          :error -> error("registries.#{kind}", "Unknown reference #{inspect(id)}")
        end

      _ ->
        error("registries.#{kind}", "Expected a reference map")
    end
  end

  defp registry(_, kind, id),
    do: error("registries.#{kind}", "Unknown reference #{inspect(id)}")

  defp control_input_map(value) when is_map(value) and not is_struct(value), do: {:ok, value}

  defp control_input_map(value) when is_list(value) do
    if Keyword.keyword?(value) and length(value) == length(Keyword.keys(value) |> Enum.uniq()),
      do: {:ok, Map.new(value)},
      else: error("profile", "Expected unique keyword fields")
  end

  defp control_input_map(_), do: error("profile", "Expected a map or keyword list")
end
