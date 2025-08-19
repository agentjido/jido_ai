defmodule Kodo.Execute do
  @moduledoc """
  Unified command execution interface for Kodo.

  This module provides the main entry point for executing commands, always 
  going through the JobManager to ensure consistent behavior across all
  transport types. Even foreground commands are treated as jobs that the
  shell waits on.
  """

  alias Kodo.Core.Jobs.JobManager
  alias Kodo.Core.Parsing.CommandParser

  @doc """
  Execute a command string synchronously.
  Returns {:ok, result} or {:error, reason}.
  """
  @spec execute_command(String.t(), pid() | String.t()) :: {:ok, term()} | {:error, term()}
  def execute_command(command_string, session) when is_binary(command_string) do
    session_id = get_session_id(session)
    instance = get_instance_from_session(session)

    # Try instance-specific job manager first, fall back to global for tests
    job_manager = case Registry.whereis_name({Kodo.InstanceRegistry, {:job_manager, instance}}) do
      :undefined -> 
        # Fall back to global job manager for tests
        case GenServer.whereis(JobManager) do
          nil -> {:error, :not_found}
          pid -> pid
        end
      pid -> 
        {:via, Registry, {Kodo.InstanceRegistry, {:job_manager, instance}}}
    end

    case job_manager do
      {:error, :not_found} ->
        {:error, :not_found}
      
      jm ->
        case CommandParser.parse(command_string) do
          {:ok, execution_plan} ->
            case JobManager.start_job(jm, execution_plan, command_string, session_id, false) do
              {:ok, job_id} ->
                # Wait for foreground job to complete
                case JobManager.wait_for_job(jm, job_id) do
                  {:ok, job} ->
                    if job.exit_status == 0 do
                      {:ok, ""}  # Success
                    else
                      {:error, "Command failed with exit status #{job.exit_status}"}
                    end
                  {:error, reason} ->
                    {:error, reason}
                end
              {:error, reason} ->
                {:error, reason}
            end
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Execute a command string in the background.
  Returns {:ok, job_id} or {:error, reason}.
  """
  @spec execute_command_bg(String.t(), pid() | String.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  def execute_command_bg(command_string, session) when is_binary(command_string) do
    session_id = get_session_id(session)
    instance = get_instance_from_session(session)

    job_manager = {:via, Registry, {Kodo.InstanceRegistry, {:job_manager, instance}}}

    case CommandParser.parse(command_string) do
      {:ok, execution_plan} ->
        JobManager.start_job(job_manager, execution_plan, command_string, session_id, true)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Kill a running job.
  """
  @spec kill_job(pos_integer(), pid() | String.t()) :: :ok | {:error, term()}
  def kill_job(job_id, session) do
    instance = get_instance_from_session(session)
    job_manager = {:via, Registry, {Kodo.InstanceRegistry, {:job_manager, instance}}}
    JobManager.kill_job(job_manager, job_id)
  end

  @doc """
  Move a background job to foreground.
  """
  @spec bring_to_foreground(pos_integer(), pid() | String.t()) :: {:ok, term()} | {:error, term()}
  def bring_to_foreground(job_id, session) do
    instance = get_instance_from_session(session)
    job_manager = {:via, Registry, {Kodo.InstanceRegistry, {:job_manager, instance}}}

    case JobManager.bring_to_foreground(job_manager, job_id) do
      :ok ->
        case JobManager.wait_for_job(job_manager, job_id) do
          {:ok, job} ->
            if job.exit_status == 0 do
              {:ok, ""}
            else
              {:error, "Command failed with exit status #{job.exit_status}"}
            end

          {:error, reason} ->
            {:error, reason}
        end

      error ->
        error
    end
  end

  @doc """
  Move a foreground job to background.
  """
  @spec send_to_background(pos_integer(), pid() | String.t()) :: :ok | {:error, term()}
  def send_to_background(job_id, session) do
    instance = get_instance_from_session(session)
    job_manager = {:via, Registry, {Kodo.InstanceRegistry, {:job_manager, instance}}}
    JobManager.send_to_background(job_manager, job_id)
  end

  @doc """
  List active jobs for a session.
  """
  @spec list_jobs(pid() | String.t() | nil) :: [Kodo.Core.Jobs.Job.t()]
  def list_jobs(session \\ nil) do
    if session do
      instance = get_instance_from_session(session)
      session_id = get_session_id(session)
      job_manager = {:via, Registry, {Kodo.InstanceRegistry, {:job_manager, instance}}}
      JobManager.list_jobs(job_manager, session_id)
    else
      # List all jobs across all instances - for now, just return empty
      # This would need to iterate across all instances
      []
    end
  end

  @doc """
  Get job details.
  """
  @spec get_job(pos_integer(), pid() | String.t()) ::
          {:ok, Kodo.Core.Jobs.Job.t()} | {:error, :not_found}
  def get_job(job_id, session) do
    instance = get_instance_from_session(session)
    job_manager = {:via, Registry, {Kodo.InstanceRegistry, {:job_manager, instance}}}
    JobManager.get_job(job_manager, job_id)
  end

  # Private helper functions

  defp get_session_id(session_pid) when is_pid(session_pid) do
    "session_#{:erlang.phash2(session_pid)}"
  end

  defp get_session_id(session_id) when is_binary(session_id) do
    session_id
  end

  defp get_session_id(session_name) when is_atom(session_name) do
    "session_#{session_name}"
  end

  # For now, hardcode to default instance
  # TODO: Get actual instance from session context
  defp get_instance_from_session(_session) do
    :default
  end
end
