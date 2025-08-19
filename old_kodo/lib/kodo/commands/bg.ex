defmodule Kodo.Commands.Bg do
  @moduledoc """
  Send job to background command.
  """
  @behaviour Kodo.Ports.Command

  alias Kodo.Core.Jobs.{JobManager, Job}

  @impl true
  def name, do: "bg"

  @impl true
  def description, do: "Send job to background"

  @impl true
  def usage, do: "bg [job_id]"

  @impl true
  def meta, do: [:builtin]

  @impl true
  def execute(args, context) do
    job_manager = get_job_manager(context)

    case parse_job_id(args, context) do
      {:ok, job_id} ->
        case JobManager.send_to_background(job_manager, job_id) do
          :ok ->
            case JobManager.get_job(job_manager, job_id) do
              {:ok, job} ->
                {:ok, Job.format(job)}

              {:error, :not_found} ->
                {:error, "Job #{job_id} not found"}
            end

          {:error, :not_found} ->
            {:error, "Job #{job_id} not found"}

          {:error, :already_background} ->
            {:error, "Job #{job_id} is already in background"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions

  defp get_session_id(%{session_pid: session_pid}), do: "session_#{:erlang.phash2(session_pid)}"

  defp get_job_manager(%{job_manager: jm}) when jm != nil, do: jm

  defp get_job_manager(%{instance: instance}),
    do: {:via, Registry, {Kodo.InstanceRegistry, {:job_manager, instance}}}

  defp get_job_manager(_context) do
    # Ensure global JobManager is started before using it
    case GenServer.whereis(Kodo.Core.Jobs.JobManager) do
      nil -> {:ok, _} = Kodo.Core.Jobs.JobManager.start_link([])
      _ -> :ok
    end

    Kodo.Core.Jobs.JobManager
  end

  defp parse_job_id([], context) do
    # No job ID specified, find the most recent foreground job for this session
    session_id = get_session_id(context)
    job_manager = get_job_manager(context)
    jobs = JobManager.list_jobs(job_manager, session_id)

    foreground_jobs = Enum.filter(jobs, fn job -> not job.background? and Job.active?(job) end)

    case Enum.max_by(foreground_jobs, & &1.id, fn -> nil end) do
      nil -> {:error, "No foreground jobs available"}
      job -> {:ok, job.id}
    end
  end

  defp parse_job_id([job_id_str], _context) do
    case Integer.parse(job_id_str) do
      {job_id, ""} -> {:ok, job_id}
      _ -> {:error, "Invalid job ID: #{job_id_str}"}
    end
  end

  defp parse_job_id(_, _context) do
    {:error, "Usage: #{usage()}"}
  end
end
