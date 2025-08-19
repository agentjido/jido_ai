defmodule Kodo.Commands.Kill do
  @moduledoc """
  Terminate a job command.
  """
  @behaviour Kodo.Ports.Command

  alias Kodo.Core.Jobs.JobManager

  @impl true
  def name, do: "kill"

  @impl true
  def description, do: "Terminate a job"

  @impl true
  def usage, do: "kill [-SIGNAL] job_id"

  @impl true
  def meta, do: [:builtin]

  @impl true
  def execute(args, _context) do
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
        {:error, "Usage: #{usage()}"}

      _ ->
        {:error, "Usage: #{usage()}"}
    end
  end

  # Private helper functions

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
  # Pass through unknown signals
  defp parse_signal(unknown), do: unknown
end
