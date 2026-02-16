defmodule Jido.AI.Plugins.TaskSupervisor do
  @moduledoc """
  Plugin that creates and manages a per-instance Task.Supervisor for Jido.AI agents.

  In Jido 2.0, each agent instance requires its own task supervisor to properly
  scope async operations (like LLM streaming and tool execution) to the agent's
  lifecycle.

  This plugin is automatically added to Jido.AI agents to handle supervisor creation
  and cleanup.

  ## Supervisor Storage

  The supervisor PID is stored in `agent.state.__task_supervisor_skill__` (the plugin's
  internal state) and is accessed by directives via `Directive.Helper.get_task_supervisor/1`.

  ## Lifecycle

  - **mount**: Creates a new anonymous Task.Supervisor
  - **Automatic cleanup**: The linked supervisor terminates when the agent stops

  ## Usage

  This plugin is automatically included when using `Jido.AI.Agent`. Manual
  inclusion is not typically needed.

  ## Implementation Notes

  This plugin has no actions - it only provides lifecycle hooks for supervisor
  management. The supervisor PID is stored in the plugin's state under the internal
  key `__task_supervisor_skill__`.
  """

  use Jido.Plugin,
    name: "ai_task_supervisor",
    description: "Manages per-instance task supervisor for async operations",
    category: "ai",
    tags: ["supervisor", "async", "lifecycle"],
    state_key: :__task_supervisor_skill__,
    actions: []

  require Logger

  @doc """
  Initialize plugin state when mounted to an agent.

  Creates and stores the Task.Supervisor PID.
  """
  @impl Jido.Plugin
  def mount(_agent, _config) do
    case start_supervisor() do
      {:ok, supervisor_pid} ->
        {:ok, %{supervisor: supervisor_pid}}

      {:error, reason} ->
        Logger.error("Failed to start Task.Supervisor", reason: reason)
        {:error, {:task_supervisor_failed, reason}}
    end
  end

  # Starts a new anonymous Task.Supervisor.
  defp start_supervisor do
    # Start the supervisor without a name (anonymous)
    # This ensures each agent instance gets its own supervisor
    case Task.Supervisor.start_link() do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end
end
