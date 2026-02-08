defmodule Jido.AI.AgentRestore do
  @moduledoc false

  @spec restore(module(), map(), map()) :: {:ok, Jido.Agent.t()} | {:error, term()}
  def restore(agent_module, data, ctx) when is_atom(agent_module) and is_map(ctx) do
    agent = agent_module.new(id: data[:id] || data["id"])
    base_state = data[:state] || data["state"] || %{}
    agent = %{agent | state: Map.merge(agent.state, base_state)}
    externalized_keys = data[:externalized_keys] || %{}

    Enum.reduce_while(agent_module.plugin_instances(), {:ok, agent}, fn instance, {:ok, acc} ->
      restore_plugin(instance, acc, data, externalized_keys, ctx)
    end)
  end

  defp restore_plugin(instance, agent, data, externalized_keys, ctx) do
    case restore_pointer(instance.state_key, data, externalized_keys) do
      nil ->
        {:cont, {:ok, agent}}

      pointer ->
        restore_ctx = Map.put(ctx, :config, instance.config || %{})
        apply_restored_state(instance, pointer, agent, restore_ctx)
    end
  end

  defp restore_pointer(state_key, data, externalized_keys) do
    Enum.find_value(externalized_keys, fn {externalized_key, mapped_state_key} ->
      if mapped_state_key == state_key, do: data[externalized_key]
    end)
  end

  defp apply_restored_state(instance, pointer, agent, restore_ctx) do
    case instance.module.on_restore(pointer, restore_ctx) do
      {:ok, nil} ->
        {:cont, {:ok, agent}}

      {:ok, restored_state} ->
        updated_agent = %{agent | state: Map.put(agent.state, instance.state_key, restored_state)}
        {:cont, {:ok, updated_agent}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end
end
