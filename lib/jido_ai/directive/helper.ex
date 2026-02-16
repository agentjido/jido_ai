defmodule Jido.AI.Directive.Helper do
  @moduledoc """
  Helper functions for DirectiveExec implementations.
  """
  @doc """
  Gets the task supervisor from agent state.

  First checks the TaskSupervisorSkill's internal state (`__task_supervisor_skill__`),
  then falls back to the top-level `:task_supervisor` field for standalone usage.

  ## Examples

      iex> state = %{__task_supervisor_skill__: %{supervisor: supervisor_pid}}
      iex> Jido.AI.Directive.Helper.get_task_supervisor(state)
      supervisor_pid

      iex> state = %{task_supervisor: supervisor_pid}
      iex> Jido.AI.Directive.Helper.get_task_supervisor(state)
      supervisor_pid

  """
  def get_task_supervisor(%Jido.AgentServer.State{agent: agent}) do
    # Handle AgentServer.State struct - extract the agent's state
    get_task_supervisor(agent.state)
  end

  def get_task_supervisor(state) when is_map(state) do
    # First check TaskSupervisorSkill's internal state
    case Map.get(state, :__task_supervisor_skill__) do
      %{supervisor: supervisor} when is_pid(supervisor) ->
        supervisor

      _ ->
        # Fall back to top-level state field (for standalone usage)
        case Map.get(state, :task_supervisor) do
          nil ->
            raise """
            Task supervisor not found in agent state.

            In Jido 2.0, each agent instance requires its own task supervisor.
            Ensure your agent is started with Jido.AI which will automatically
            create and store a per-instance supervisor in the agent state.

            Example:
                use Jido.AI.Agent,
                  name: "my_agent",
                  tools: [MyApp.Tool1, MyApp.Tool2]
            """

          supervisor when is_pid(supervisor) ->
            supervisor
        end
    end
  end
end
