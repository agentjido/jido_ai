defmodule Kodo.Commands.Jobs do
  @moduledoc """
  List active jobs command.
  """
  @behaviour Kodo.Ports.Command

  alias Kodo.Core.Jobs.{JobManager, Job}

  @impl true
  def name, do: "jobs"

  @impl true
  def description, do: "List active jobs"

  @impl true
  def usage, do: "jobs [-l]"

  @impl true
  def meta, do: [:builtin, :pure]

  @impl true
  def execute(args, context) do
    session_id = get_session_id(context)
    long_format = Enum.member?(args, "-l")

    # Get the instance-specific JobManager
    job_manager = get_job_manager(context)
    jobs = JobManager.list_jobs(job_manager, session_id)

    if Enum.empty?(jobs) do
      {:ok, "No active jobs"}
    else
      output = format_jobs(jobs, long_format)
      {:ok, output}
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

  defp format_jobs(jobs, long_format) do
    if long_format do
      format_jobs_long(jobs)
    else
      format_jobs_short(jobs)
    end
  end

  defp format_jobs_short(jobs) do
    jobs
    |> Enum.map(&Job.format/1)
    |> Enum.join("\n")
  end

  defp format_jobs_long(jobs) do
    jobs
    |> Enum.map(&format_job_long/1)
    |> Enum.join("\n")
  end

  defp format_job_long(job) do
    status = Job.status_string(job)
    duration = format_duration(job.started_at, job.completed_at)

    "[#{job.id}] #{status}\t#{job.command}\t#{duration}"
  end

  defp format_duration(started_at, nil) do
    seconds = DateTime.diff(DateTime.utc_now(), started_at, :second)
    "#{seconds}s"
  end

  defp format_duration(started_at, completed_at) do
    seconds = DateTime.diff(completed_at, started_at, :second)
    "#{seconds}s"
  end
end
