defmodule Jido.AI.Effects do
  @moduledoc """
  Facade for effect policy, filtering, and state/directive application.
  """

  alias Jido.AI.Effects.{Applier, Policy}
  alias Jido.Agent

  @type policy_input :: Policy.t() | map() | keyword() | nil

  @doc "Returns the default effect policy."
  @spec default_policy() :: Policy.t()
  def default_policy, do: Policy.default()

  @doc "Builds a normalized policy struct."
  @spec new_policy(policy_input()) :: Policy.t()
  def new_policy(input), do: Policy.new(input)

  @doc "Intersects agent and strategy policies (strategy may only narrow)."
  @spec intersect_policies(policy_input(), policy_input()) :: Policy.t()
  def intersect_policies(agent_policy, strategy_policy) do
    Policy.intersect(agent_policy, strategy_policy)
  end

  @doc "Normalizes result envelope to canonical triple tuple."
  @spec normalize_result(term()) :: Applier.result_tuple()
  def normalize_result(result), do: Applier.normalize_result(result)

  @doc "Filters result effects by policy."
  @spec filter_result(term(), policy_input()) :: {Applier.result_tuple(), Applier.stats()}
  def filter_result(result, policy), do: Applier.filter_result(result, policy)

  @doc "Applies filtered effects to an agent and returns directives."
  @spec apply_result(Agent.t(), term(), policy_input()) ::
          {Agent.t(), [term()], Applier.stats(), Applier.result_tuple()}
  def apply_result(agent, result, policy), do: Applier.apply_result(agent, result, policy)

  @doc """
  Resolves an effect policy from context.

  Supports maps with atom or string keys.
  """
  @spec policy_from_context(map(), policy_input()) :: Policy.t()
  def policy_from_context(context, fallback \\ nil)

  def policy_from_context(context, fallback) when is_map(context) do
    context_policy = Map.get(context, :effect_policy, Map.get(context, "effect_policy"))
    base = if is_nil(context_policy), do: fallback, else: context_policy
    Policy.new(base)
  end

  def policy_from_context(_context, fallback), do: Policy.new(fallback)
end
