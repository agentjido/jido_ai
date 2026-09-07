defmodule Jido.AI.Effects.Applier do
  @moduledoc """
  Shared helpers to normalize, filter, and apply effectful tool results.
  """

  alias Jido.AI.Effects.Policy
  alias Jido.Agent
  alias Jido.AI.Effects.Candidate

  @type result_tuple ::
          {:ok, term(), [term()]}
          | {:error, term(), [term()]}

  @type stats :: %{
          received_count: non_neg_integer(),
          allowed_count: non_neg_integer(),
          dropped_count: non_neg_integer(),
          dropped_effects: [term()]
        }

  @doc """
  Normalizes a result envelope to canonical `{:ok|:error, value, effects}` shape.
  """
  @spec normalize_result(term()) :: result_tuple()
  def normalize_result({:ok, result, effects}), do: {:ok, result, List.wrap(effects)}
  def normalize_result({:ok, result}), do: {:ok, result, []}
  def normalize_result({:error, reason, effects}), do: {:error, reason, List.wrap(effects)}
  def normalize_result({:error, reason}), do: {:error, reason, []}
  def normalize_result(other), do: {:error, {:invalid_result_envelope, inspect(other)}, []}

  @doc """
  Filters effects from a result envelope according to policy.

  Returns `{filtered_result, stats}`.
  """
  @spec filter_result(term(), Policy.t() | map() | keyword() | nil) :: {result_tuple(), stats()}
  def filter_result(result, policy_input) do
    policy = Policy.new(policy_input)
    {status, payload, effects} = normalize_result(result)
    {allowed, dropped} = Policy.filter(policy, effects)

    stats = %{
      received_count: length(effects),
      allowed_count: length(allowed),
      dropped_count: length(dropped),
      dropped_effects: dropped
    }

    {{status, payload, allowed}, stats}
  end

  @doc """
  Builds a validated candidate Agent and returns its pending Directives.

  Returns `{updated_agent, directives, stats, filtered_result}`. A rejected
  proposal leaves the Agent unchanged and returns `{:error, reason, []}` as
  the fourth element. No Directive is dispatched by this function.
  """
  @spec apply_result(Agent.t(), term(), Policy.t() | map() | keyword() | nil) ::
          {Agent.t(), [term()], stats(), result_tuple()}
  def apply_result(%Agent{} = agent, result, policy_input) do
    {filtered_result, stats} = filter_result(result, policy_input)
    {_status, _payload, effects} = filtered_result

    case Candidate.stage(Candidate.new(agent.state), agent.state, effects, agent) do
      {:ok, plan} ->
        {%{agent | state: plan.state}, plan.directives, stats, filtered_result}

      {:error, reason} ->
        {agent, [], stats, {:error, reason, []}}
    end
  end
end
