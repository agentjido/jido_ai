defmodule Jido.AI.ToolContext do
  @moduledoc "Static tool context defaults and protected runtime fields."
  @reserved ~w(agent_id agent_module agent_state state signal jido partition ai request_id run_id effect_policy)

  @doc "Checks a portable base map. Runtime bindings belong in host context."
  def validate(value) when is_map(value) and not is_struct(value) do
    with false <- Enum.any?(Map.keys(value), &reserved?/1),
         :ok <- Jido.Action.validate_static_data(value) do
      :ok
    else
      true -> Jido.AI.Profile.error("tool_context", "Runtime and skill bindings belong in host context")
      error -> error
    end
  end

  def validate(_), do: Jido.AI.Profile.error("tool_context", "Expected a static map")

  @doc false
  def bind(context, %{id: id}, profiles), do: Map.merge(context, profiles[id].tool_context)
  def bind(context, _, _), do: context

  @doc false
  def runtime(value), do: Map.reject(value, fn {key, _} -> reserved?(key) end)

  defp reserved?(key) when is_atom(key), do: reserved?(Atom.to_string(key))

  defp reserved?(key) when is_binary(key) do
    key in @reserved or String.starts_with?(key, "jido_ai_") or
      Enum.any?(Jido.AI.Skill.Runtime.reserved_keys(), &(Atom.to_string(&1) == key))
  end

  defp reserved?(_), do: false
end
