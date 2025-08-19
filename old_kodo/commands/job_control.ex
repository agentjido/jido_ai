defmodule Kodo.Commands.JobControl do
  @moduledoc """
  Built-in commands for job control operations.
  
  Provides commands for managing background jobs:
  - jobs: List active jobs
  - fg: Bring job to foreground
  - bg: Send job to background
  - kill: Terminate a job
  """

  alias Kodo.Core.{JobManager, Job}

  @doc """
  Lists all active jobs for the current session.
  
  Usage: jobs [-l]
  -l: Long format (shows more details)
  """
  def jobs(args, context) do
    session_id = get_session_id(context)
    long_format = Enum.member?(args, "-l")
    
    jobs = JobManager.list_jobs(session_id)
    
    if Enum.empty?(jobs) do
      {:ok, "No active jobs"}
    else
      output = format_jobs(jobs, long_format)
      {:ok, output}
    end
  end

  @doc """
  Brings a background job to the foreground.
  
  Usage: fg [job_id]
  If no job_id is specified, brings the most recent background job to foreground.
  """
  def fg(args, context) do
    case parse_job_id(args, context) do
      {:ok, job_id} ->
        case JobManager.bring_to_foreground(job_id) do
          :ok ->
            case JobManager.wait_for_job(job_id) do
              {:ok, %Job{exit_status: 0}} -> {:ok, ""}
              {:ok, %Job{exit_status: status}} -> {:error, "Job exited with status #{status}"}
              {:error, reason} -> {:error, "Failed to wait for job: #{reason}"}
            end
          
          {:error, :not_found} ->
            {:error, "Job #{job_id} not found"}
          
          {:error, :not_background} ->
            {:error, "Job #{job_id} is not a background job"}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends a job to the background.
  
  Usage: bg [job_id]
  If no job_id is specified, sends the most recent foreground job to background.
  """
  def bg(args, context) do
    case parse_job_id(args, context) do
      {:ok, job_id} ->
        case JobManager.send_to_background(job_id) do
          :ok ->
            case JobManager.get_job(job_id) do
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

  @doc """
  Terminates a job.
  
  Usage: kill [-SIGNAL] job_id
  -SIGNAL: Signal to send (default: TERM)
  """
  def kill(args, _context) do
    {signal, job_args} = parse_kill_args(args)
    
    case job_args do
      [job_id_str] ->
        case Integer.parse(job_id_str) do
          {job_id, ""} ->
            case JobManager.kill_job(job_id, signal) do
              :ok ->
                {:ok, "Job #{job_id} terminated"}
              
              {:error, :not_found} ->
                {:error, "Job #{job_id} not found"}
              
              {:error, :no_process} ->
                {:error, "Job #{job_id} has no associated process"}
              
              {:error, reason} ->
                {:error, "Failed to kill job: #{reason}"}
            end
          
          _ ->
            {:error, "Invalid job ID: #{job_id_str}"}
        end
      
      [] ->
        {:error, "Usage: kill [-SIGNAL] job_id"}
      
      _ ->
        {:error, "Usage: kill [-SIGNAL] job_id"}
    end
  end

  # Private helper functions

  defp get_session_id(%{session_id: session_id}), do: session_id
  defp get_session_id(%{session_pid: session_pid}), do: "session_#{:erlang.phash2(session_pid)}"
  defp get_session_id(_), do: nil

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

  defp parse_job_id([], context) do
    # No job ID specified, find the most recent job for this session
    session_id = get_session_id(context)
    jobs = JobManager.list_jobs(session_id)
    
    case Enum.max_by(jobs, & &1.id, fn -> nil end) do
      nil -> {:error, "No jobs available"}
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
    {:error, "Too many arguments"}
  end

  defp parse_kill_args(args) do
    case args do
      ["-" <> signal_str | rest] ->
        signal = parse_signal(signal_str)
        {signal, rest}
      
      args ->
        {:sigterm, args}
    end
  end

  defp parse_signal("TERM"), do: :sigterm
  defp parse_signal("KILL"), do: :sigkill
  defp parse_signal("INT"), do: :sigint
  defp parse_signal("HUP"), do: :sighup
  defp parse_signal("QUIT"), do: :sigquit
  defp parse_signal("USR1"), do: :sigusr1
  defp parse_signal("USR2"), do: :sigusr2
  defp parse_signal(unknown), do: unknown  # Pass through unknown signals
end
