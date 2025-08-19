defmodule Jido.HTN.Planner.EffectHandler do
  @moduledoc """
  Handles the application of effects in the HTN planner.
  """

  use ExDbug, enabled: false

  @doc """
  Applies a list of effects to the world state, using the result map for any effect functions.
  """
  @spec apply_effects(map(), list(), map(), map()) :: map()
  def apply_effects(domain, effects, result, world_state) do
    Enum.reduce(effects, world_state, fn effect, acc ->
      case effect do
        effect when is_function(effect, 1) ->
          Map.merge(acc, effect.(result))

        effect when is_binary(effect) ->
          case Map.get(domain.callbacks, effect) do
            nil -> acc
            callback -> Map.merge(acc, callback.(result))
          end
      end
    end)
  end

  @doc """
  Applies all effects for planning simulation: expected_effects first, then regular effects.
  """
  @spec apply_all_effects_for_simulation(map(), struct(), map(), map()) :: map()
  def apply_all_effects_for_simulation(
        domain,
        %Jido.HTN.PrimitiveTask{effects: regular_effects, expected_effects: expected_effects},
        result,
        world_state
      ) do
    # Apply expected effects first to simulate anticipated changes
    simulated_state_after_expected =
      Enum.reduce(expected_effects, world_state, fn effect_fun, acc_state ->
        Map.merge(acc_state, effect_fun.(acc_state))
      end)

    # Then apply regular effects based on this new simulated state
    apply_effects(domain, regular_effects, result, simulated_state_after_expected)
  end
end
