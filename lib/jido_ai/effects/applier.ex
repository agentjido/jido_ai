defmodule Jido.AI.Effects.Applier do
  @moduledoc """
  Shared helpers to normalize, filter, and apply effectful tool results.
  """

  alias Jido.AI.Effects.Policy
  alias Jido.Agent
  alias Jido.Agent.StateOps

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
  Applies filtered effects from a result envelope to an agent.

  Returns `{updated_agent, directives, stats, filtered_result}`.
  """
  @spec apply_result(Agent.t(), term(), Policy.t() | map() | keyword() | nil) ::
          {Agent.t(), [term()], stats(), result_tuple()}
  def apply_result(%Agent{} = agent, result, policy_input) do
    {filtered_result, stats} = filter_result(result, policy_input)
    {_status, _payload, effects} = filtered_result

    case effects do
      [] ->
        {agent, [], stats, filtered_result}

      list when is_list(list) ->
        {updated_agent, directives} = StateOps.apply_state_ops(agent, list)
        {updated_agent, directives, stats, filtered_result}
    end
  end
end
