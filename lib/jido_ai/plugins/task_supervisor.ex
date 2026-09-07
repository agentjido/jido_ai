defmodule Jido.AI.Plugins.TaskSupervisor do
  @moduledoc """
  Compatibility helper for callers that own a task supervisor.

  Native AI requests use the core-owned Session runtime. The public AI Agent
  does not insert this Plugin. `mount/2` remains an explicit caller-owned helper;
  its returned PID must not be saved in v3 Agent state. A native Agent can use
  the Plugin child specification when it needs a separate task supervisor.
  """

  use Jido.Plugin

  def child_spec(_init), do: Supervisor.child_spec({Task.Supervisor, []}, id: __MODULE__)

  require Logger

  @doc """
  Initialize plugin state when mounted to an agent.

  Creates and stores the Task.Supervisor PID.
  """
  def mount(_agent, _config) do
    case start_supervisor() do
      {:ok, supervisor_pid} ->
        {:ok, %{supervisor: supervisor_pid}}

      {:error, reason} ->
        Logger.error("Failed to start Task.Supervisor", reason: reason)
        {:error, {:task_supervisor_failed, reason}}
    end
  end

  @doc false
  @spec on_checkpoint(term(), map()) :: :drop
  def on_checkpoint(_plugin_state, _context), do: :drop

  # Starts a new anonymous Task.Supervisor.
  defp start_supervisor do
    Task.Supervisor.start_link()
  end
end
