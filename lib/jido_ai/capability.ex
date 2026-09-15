defmodule Jido.AI.Capability do
  @moduledoc false

  def prepared(context, package) when is_map(context) do
    context
    |> Map.get(:plugin_inputs, %{})
    |> Map.get(package, %Jido.Plugin.Input{})
    |> Map.get(:prepared)
  end

  def prepared_reasoning(context) when is_map(context) do
    context
    |> Map.get(:plugin_inputs, %{})
    |> Enum.find_value(fn
      {_package, %Jido.Plugin.Input{prepared: %{owner: owner, strategy: _} = binding}}
      when is_atom(owner) ->
        binding

      _ ->
        nil
    end)
  end

  def bind(command, key, binding) do
    with :ok <- result_field(command.agent.schema, binding) do
      {:ok, %{command | context: Map.put(command.context, key, binding)}}
    end
  end

  def run(action, params, context, %{key: key, defaults: defaults, into: into} = binding) do
    params = Jido.AI.Plugins.Retrieval.apply_input(params, context)
    params = apply_model_route(params, context)

    scoped =
      context
      |> Map.put(:plugin_state, %{key => defaults})
      |> Map.put(:provided_params, Map.keys(params))

    scoped =
      case {key, Map.get(binding, :store)} do
        {:quota, store} when not is_nil(store) -> Map.put(scoped, :quota_store, store)
        {:retrieval, store} when not is_nil(store) -> Map.put(scoped, :retrieval_store, store)
        _ -> scoped
      end

    with :ok <- result_field_from_context(context, binding),
         {:ok, result} <- Jido.Exec.run(action, params, scoped) do
      {:ok, Map.replace!(context.agent_state, into, result)}
    end
  end

  defp apply_model_route(params, context) do
    model = Jido.AI.Capability.prepared(context, Jido.AI.Plugins.ModelRouting)

    if model in [nil, ""] do
      params
    else
      params
      |> Map.delete("model")
      |> Map.put(:model, model)
    end
  end

  defp result_field_from_state(state, into) do
    if Map.has_key?(state, into), do: :ok, else: invalid_field(into)
  end

  defp result_field_from_context(context, %{key: key, into: into} = binding) do
    case live_agent(context) do
      %Jido.Agent{schema: schema} ->
        result_field(schema, binding)

      nil when into == key ->
        invalid_field(into)

      nil ->
        result_field_from_state(context.agent_state, into)
    end
  end

  defp live_agent(%{jido: jido, agent_id: id} = context)
       when is_atom(jido) and not is_nil(jido) and is_binary(id) do
    case Jido.whereis_agent(jido, id, partition: context[:partition]) do
      pid when is_pid(pid) -> Jido.AgentServer.agent(pid)
      nil -> nil
    end
  catch
    :exit, _ -> nil
  end

  defp live_agent(_), do: nil

  defp result_field(_, nil), do: :ok

  defp result_field(%Zoi.Types.Map{fields: fields}, %{into: into}) do
    if Keyword.has_key?(fields, into), do: :ok, else: invalid_field(into)
  end

  defp result_field(_, %{into: into}), do: invalid_field(into)
  defp result_field(_, binding) when is_map(binding), do: :ok

  defp invalid_field(into) do
    {:error,
     Jido.Error.validation_error("Capability result must select a declared domain field",
       kind: :config,
       details: %{into: into}
     )}
  end
end
