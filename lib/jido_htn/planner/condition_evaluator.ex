defmodule Jido.HTN.Planner.ConditionEvaluator do
  @moduledoc """
  Handles evaluation of conditions in the HTN planner.
  """

  use ExDbug, enabled: false

  @doc """
  Evaluates a list of preconditions against the current world state.
  Returns a tuple of {boolean, [boolean]} indicating overall success and individual results.
  """
  @spec preconditions_met?(map(), list(), map()) :: {boolean(), [boolean()]}
  def preconditions_met?(domain, preconditions, world_state) do
    Enum.reduce_while(preconditions, {true, []}, fn condition, {_, results} ->
      case evaluate_condition(domain, condition, world_state) do
        true -> {:cont, {true, [true | results]}}
        false -> {:halt, {false, [false | results]}}
      end
    end)
  end

  @doc """
  Evaluates method conditions against the current world state.
  """
  @spec method_conditions_met?(map(), struct(), map()) :: {boolean(), [boolean()]}
  def method_conditions_met?(domain, method, world_state) do
    preconditions_met?(domain, method.conditions, world_state)
  end

  @doc """
  Evaluates a single condition against the world state.
  """
  @spec evaluate_condition(map(), function() | binary() | boolean(), map()) :: boolean()
  def evaluate_condition(_domain, condition, world_state) when is_function(condition, 1) do
    condition.(world_state)
  end

  def evaluate_condition(domain, condition, world_state) when is_binary(condition) do
    case Map.get(domain.callbacks, condition) do
      nil -> false
      callback -> callback.(world_state)
    end
  end

  def evaluate_condition(_domain, condition, _world_state) when is_boolean(condition) do
    condition
  end
end
