defmodule Jido.AI.Effects.State do
  @moduledoc "A complete proposed Agent state returned by a tool."
  @enforce_keys [:state]
  defstruct [:state]
  @type t :: %__MODULE__{state: map()}
end

defmodule Jido.AI.Effects.Candidate do
  @moduledoc false
  alias Jido.AI.Effects.State

  def new(state), do: %{base: state, state: state, directives: []}

  def stage(plan, base, effects, agent) do
    Enum.reduce_while(effects, {:ok, plan}, fn effect, {:ok, plan} ->
      case stage_one(plan, base, effect, agent) do
        {:ok, plan} -> {:cont, {:ok, plan}}
        error -> {:halt, error}
      end
    end)
  end

  def assemble(current, %{base: base, state: proposed}, agent),
    do: merge(base, current, proposed, agent)

  defp stage_one(plan, base, %State{state: proposed}, agent) do
    with {:ok, next} <- merge(base, plan.state, proposed, agent),
         do: {:ok, %{plan | state: next}}
  end

  defp stage_one(plan, _base, directive, agent) do
    with {:ok, directive} <- validate_directive(directive, agent),
         do: {:ok, %{plan | directives: plan.directives ++ [directive]}}
  end

  def validate_directive(directive, agent) do
    with {:ok, specs} <- Jido.Plugin.normalize_all(agent.plugins) do
      cond do
        Jido.Agent.Directive.built_in?(directive) ->
          Jido.Agent.Directive.validate(directive)

        owner = Jido.Plugin.directive_owner(specs, directive) ->
          if owner.agent.legacy? do
            Jido.Plugin.validate_directive(owner, directive)
          else
            Jido.Agent.Directive.validate(directive)
          end

        true ->
          {:error, {:unowned_tool_directive, directive}}
      end
    end
  end

  defp merge(base, current, proposed, agent) when is_map(proposed) and not is_struct(proposed) do
    with :ok <- Jido.Action.validate_static_data(proposed),
         {:ok, specs} <- Jido.Plugin.normalize_all(agent.plugins),
         agent_specs = Jido.Agent.Plugin.specs(specs),
         :ok <- protect_plugin_state(base, proposed, agent_specs) do
      changed =
        Enum.filter(
          Enum.uniq(Map.keys(base) ++ Map.keys(proposed)),
          &(Map.fetch(base, &1) != Map.fetch(proposed, &1))
        )

      conflicts = Enum.filter(changed, &(Map.fetch(base, &1) != Map.fetch(current, &1)))

      if conflicts == [] do
        candidate =
          Enum.reduce(changed, current, fn key, acc ->
            case Map.fetch(proposed, key) do
              {:ok, value} -> Map.put(acc, key, value)
              :error -> Map.delete(acc, key)
            end
          end)

        with {:ok, validated} <- Jido.Agent.transition(%{agent | state: current}, candidate),
             do: {:ok, validated.state}
      else
        {:error, {:tool_state_conflict, Enum.sort(conflicts)}}
      end
    end
  end

  defp merge(_base, _current, _proposed, _agent), do: {:error, :invalid_tool_state}

  defp protect_plugin_state(base, proposed, specs) do
    changed =
      for %{state_key: key} <- specs,
          not is_nil(key),
          Map.fetch(base, key) != Map.fetch(proposed, key),
          do: key

    if changed == [] do
      :ok
    else
      {:error,
       Jido.Plugin.Error.execution(
         "Agent executable changed Plugin-owned state",
         :core,
         Jido.Agent.Plugin.Pipeline,
         %{keys: changed, code: :plugin_state_owner_violation}
       )}
    end
  end
end
