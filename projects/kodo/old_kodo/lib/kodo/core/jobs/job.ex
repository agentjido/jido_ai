defmodule Kodo.Core.Jobs.Job do
  @moduledoc """
  Represents a job in the shell - a command or pipeline that is being executed.

  Jobs can be running in the foreground or background, and can be controlled
  through job control commands like fg, bg, and kill.
  """

  defstruct [
    # Unique job identifier (integer)
    :id,
    # Process PID or Supervisor PID
    :pid,
    # :running | :stopped | :completed | :failed
    :status,
    # Original command string
    :command,
    # DateTime when job started
    :started_at,
    # DateTime when job completed (nil if still running)
    :completed_at,
    # Integer exit code (nil if still running)
    :exit_status,
    # Boolean - true if background job
    :background?,
    # Session ID that owns this job
    :session_id
  ]

  @type status :: :running | :stopped | :completed | :failed

  @type t :: %__MODULE__{
          id: pos_integer(),
          pid: pid() | nil,
          status: status(),
          command: String.t(),
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
          exit_status: integer() | nil,
          background?: boolean(),
          session_id: String.t()
        }

  @doc """
  Creates a new job with the given parameters.
  """
  @spec new(pos_integer(), String.t(), String.t(), boolean()) :: t()
  def new(id, command, session_id, background? \\ false) do
    %__MODULE__{
      id: id,
      command: command,
      session_id: session_id,
      background?: background?,
      status: :running,
      started_at: DateTime.utc_now()
    }
  end

  @doc """
  Updates the job with a new PID.
  """
  @spec set_pid(t(), pid()) :: t()
  def set_pid(%__MODULE__{} = job, pid) when is_pid(pid) do
    %{job | pid: pid}
  end

  @doc """
  Marks the job as completed with the given exit status.
  """
  @spec complete(t(), integer()) :: t()
  def complete(%__MODULE__{} = job, exit_status) when is_integer(exit_status) do
    %{
      job
      | status: if(exit_status == 0, do: :completed, else: :failed),
        exit_status: exit_status,
        completed_at: DateTime.utc_now()
    }
  end

  @doc """
  Marks the job as stopped (suspended).
  """
  @spec stop(t()) :: t()
  def stop(%__MODULE__{} = job) do
    %{job | status: :stopped}
  end

  @doc """
  Marks the job as running (resumed).
  """
  @spec resume(t()) :: t()
  def resume(%__MODULE__{} = job) do
    %{job | status: :running}
  end

  @doc """
  Returns true if the job is still active (running or stopped).
  """
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{status: status}) do
    status in [:running, :stopped]
  end

  @doc """
  Returns true if the job is finished (completed or failed).
  """
  @spec finished?(t()) :: boolean()
  def finished?(%__MODULE__{status: status}) do
    status in [:completed, :failed]
  end

  @doc """
  Returns a human-readable status string for the job.
  """
  @spec status_string(t()) :: String.t()
  def status_string(%__MODULE__{status: :running, background?: true}), do: "Running"
  def status_string(%__MODULE__{status: :running, background?: false}), do: "Foreground"
  def status_string(%__MODULE__{status: :stopped}), do: "Stopped"
  def status_string(%__MODULE__{status: :completed}), do: "Done"
  def status_string(%__MODULE__{status: :failed}), do: "Failed"

  @doc """
  Returns a formatted string representation of the job for display.
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = job) do
    status_indicator = if job.background?, do: "&", else: ""
    "[#{job.id}]#{status_indicator} #{status_string(job)}\t#{job.command}"
  end
end
