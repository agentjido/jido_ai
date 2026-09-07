defmodule Jido.AI.Reasoning.Helpers do
  @moduledoc """
  Direct Action compatibility helpers.

  V3 Agent routes normally own execution and state transitions. These helpers
  build an immutable candidate and return its pending Directives. They do not
  commit or dispatch. Execution options are supplied in `context[:exec_opts]`.
  StateOp constructors have been removed. Use ordinary map operations and
  `Jido.AI.Effects.state/1` to propose complete state instead.
  """
  alias Jido.Agent
  alias Jido.AI.Effects

  def execute_action_instruction(%Agent{} = agent, %Jido.Instruction{} = instruction, context \\ %{}) do
    instruction = %{instruction | context: Map.merge(instruction.context, action_context(agent, context))}

    case Jido.Exec.run(instruction, %{}, %{}, Map.get(context, :exec_opts, [])) do
      {:ok, proposed} when is_map(proposed) -> apply_result(agent, proposed, [], context)
      {:ok, proposed, directives} when is_map(proposed) -> apply_result(agent, proposed, directives, context)
      {:error, reason} -> failure(agent, reason)
      {:error, reason, _} -> failure(agent, reason)
    end
  end

  def maybe_execute_action_instruction(%Agent{} = agent, %Jido.Instruction{} = instruction, context \\ %{}) do
    case Jido.Executable.resolve(instruction.target) do
      {:ok, _} -> execute_action_instruction(agent, instruction, context)
      {:error, _} -> :noop
    end
  end

  def action_context(%Agent{} = agent, context \\ %{}) do
    Map.merge(context, %{state: agent.state, agent_state: agent.state, agent_id: agent.id})
  end

  defp apply_result(agent, proposed, directives, context) do
    case Agent.transition(agent, proposed) do
      {:ok, candidate} ->
        {next, pending, _stats, result} =
          Effects.apply_result(
            agent,
            {:ok, proposed, [Effects.state(candidate.state) | directives]},
            Effects.policy_from_context(context)
          )

        case result do
          {:ok, _, _} -> {next, pending}
          {:error, reason, _} -> failure(agent, reason)
        end

      {:error, reason} ->
        failure(agent, reason)
    end
  end

  defp failure(agent, reason) do
    error = Jido.Error.execution_error("Instruction failed", details: %{reason: reason})
    {agent, [%Jido.Agent.Directive.Error{error: error, context: :instruction}]}
  end
end
