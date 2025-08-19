defmodule Kodo.Core.Jobs.JobManager do
  @moduledoc """
  GenServer that manages job lifecycle, tracking active jobs and providing
  job control operations like starting, stopping, and killing jobs.

  The JobManager maintains a registry of all active jobs and handles
  cleanup when jobs complete or are terminated.
  """

  use GenServer
  require Logger

  alias Kodo.Core.Jobs.Job

  # Client API

  @doc """
  Starts the JobManager GenServer.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    instance = Keyword.get(opts, :instance)
    GenServer.start_link(__MODULE__, instance, name: name)
  end

  @doc """
  Starts a new job with the given execution plan and session ID.
  Returns {:ok, job_id} or {:error, reason}.
  """
  @spec start_job(any(), String.t(), String.t(), boolean()) ::
          {:ok, pos_integer()} | {:error, term()}
  def start_job(execution_plan, command_string, session_id, background? \\ false) do
    GenServer.call(
      __MODULE__,
      {:start_job, execution_plan, command_string, session_id, background?}
    )
  end

  @spec start_job(GenServer.server(), any(), String.t(), String.t(), boolean()) ::
          {:ok, pos_integer()} | {:error, term()}
  def start_job(job_manager_pid, execution_plan, command_string, session_id, background?) do
    GenServer.call(
      job_manager_pid,
      {:start_job, execution_plan, command_string, session_id, background?}
    )
  end

  @doc """
  Stops a job by sending it a SIGTERM signal.
  """
  @spec stop_job(pos_integer()) :: :ok | {:error, :not_found}
  def stop_job(job_id) do
    GenServer.call(__MODULE__, {:stop_job, job_id})
  end

  @doc """
  Kills a job by sending it a signal (default SIGTERM).
  """
  @spec kill_job(pos_integer(), atom()) :: :ok | {:error, :not_found}
  def kill_job(job_id, signal \\ :sigterm) do
    GenServer.call(__MODULE__, {:kill_job, job_id, signal})
  end

  @doc """
  Gets a specific job by ID.
  """
  @spec get_job(pos_integer()) :: {:ok, Job.t()} | {:error, :not_found}
  def get_job(job_id) do
    GenServer.call(__MODULE__, {:get_job, job_id})
  end

  @spec get_job(GenServer.server(), pos_integer()) :: {:ok, Job.t()} | {:error, :not_found}
  def get_job(job_manager_pid, job_id) do
    GenServer.call(job_manager_pid, {:get_job, job_id})
  end

  @doc """
  Lists all jobs, optionally filtered by session ID.
  """
  @spec list_jobs(String.t() | nil) :: [Job.t()]
  def list_jobs(session_id \\ nil) do
    GenServer.call(__MODULE__, {:list_jobs, session_id})
  end

  @spec list_jobs(GenServer.server(), String.t() | nil) :: [Job.t()]
  def list_jobs(job_manager_pid, session_id) do
    GenServer.call(job_manager_pid, {:list_jobs, session_id})
  end

  @doc """
  Brings a background job to the foreground.
  """
  @spec bring_to_foreground(pos_integer()) :: :ok | {:error, :not_found | :not_background}
  def bring_to_foreground(job_id) do
    GenServer.call(__MODULE__, {:bring_to_foreground, job_id})
  end

  @spec bring_to_foreground(GenServer.server(), pos_integer()) ::
          :ok | {:error, :not_found | :not_background}
  def bring_to_foreground(job_manager_pid, job_id) do
    GenServer.call(job_manager_pid, {:bring_to_foreground, job_id})
  end

  @doc """
  Sends a job to the background.
  """
  @spec send_to_background(pos_integer()) :: :ok | {:error, :not_found | :already_background}
  def send_to_background(job_id) do
    GenServer.call(__MODULE__, {:send_to_background, job_id})
  end

  @spec send_to_background(GenServer.server(), pos_integer()) ::
          :ok | {:error, :not_found | :already_background}
  def send_to_background(job_manager_pid, job_id) do
    GenServer.call(job_manager_pid, {:send_to_background, job_id})
  end

  @doc """
  Waits for a job to complete, with optional timeout.
  """
  @spec wait_for_job(pos_integer(), timeout()) :: {:ok, Job.t()} | {:error, :timeout | :not_found}
  def wait_for_job(job_id, timeout \\ :infinity) do
    GenServer.call(__MODULE__, {:wait_for_job, job_id}, timeout)
  end

  @spec wait_for_job(GenServer.server(), pos_integer(), timeout()) ::
          {:ok, Job.t()} | {:error, :timeout | :not_found}
  def wait_for_job(job_manager_pid, job_id, timeout) do
    GenServer.call(job_manager_pid, {:wait_for_job, job_id}, timeout)
  end

  @doc """
  Notifies the JobManager that a job has completed.
  This is typically called by the PipelineExecutor.
  """
  @spec job_completed(pos_integer(), integer()) :: :ok
  def job_completed(job_id, exit_status) do
    GenServer.cast(__MODULE__, {:job_completed, job_id, exit_status})
  end

  @doc """
  Notifies the JobManager that a job has been stopped.
  """
  @spec job_stopped(pos_integer()) :: :ok
  def job_stopped(job_id) do
    GenServer.cast(__MODULE__, {:job_stopped, job_id})
  end

  @doc """
  Gets the next available job ID.
  """
  @spec next_job_id() :: pos_integer()
  def next_job_id do
    GenServer.call(__MODULE__, :next_job_id)
  end

  # Server Implementation

  @impl true
  def init(instance) do
    # Trap exits so we can handle job process exits
    Process.flag(:trap_exit, true)

    state = %{
      # Instance this job manager belongs to
      instance: instance,
      # job_id => Job.t()
      jobs: %{},
      # Next job ID to assign
      next_id: 1,
      # job_id => [pids waiting for completion]
      waiters: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call(
        {:start_job, execution_plan, command_string, session_id, background?},
        _from,
        state
      ) do
    job_id = state.next_id
    job = Job.new(job_id, command_string, session_id, background?)

    # Start the job execution (delegate to PipelineExecutor)
    {:ok, pid} = start_job_execution(execution_plan, job, state)
    updated_job = Job.set_pid(job, pid)
    new_state = %{state | jobs: Map.put(state.jobs, job_id, updated_job), next_id: job_id + 1}

    # Emit telemetry event
    :telemetry.execute([:kodo, :job, :started], %{count: 1}, %{
      job_id: job_id,
      command: command_string,
      background: background?
    })

    {:reply, {:ok, job_id}, new_state}
  end

  @impl true
  def handle_call({:stop_job, job_id}, _from, state) do
    case Map.get(state.jobs, job_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %Job{pid: nil} ->
        {:reply, {:error, :no_process}, state}

      %Job{pid: pid} = job ->
        # Send SIGTERM to the process
        case Process.exit(pid, :kill) do
          true ->
            updated_job = Job.stop(job)
            new_state = %{state | jobs: Map.put(state.jobs, job_id, updated_job)}
            {:reply, :ok, new_state}

          false ->
            {:reply, {:error, :process_not_found}, state}
        end
    end
  end

  @impl true
  def handle_call({:kill_job, job_id, signal}, _from, state) do
    case Map.get(state.jobs, job_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %Job{pid: nil} ->
        {:reply, {:error, :no_process}, state}

      %Job{pid: pid} ->
        # For now, we'll use Process.exit since we don't have OS process groups
        # In a real implementation, we'd send the actual signal to the process group
        exit_reason =
          case signal do
            :sigterm -> :kill
            :sigkill -> :killed
            :sigint -> :interrupt
            _ -> signal
          end

        case Process.exit(pid, exit_reason) do
          true -> {:reply, :ok, state}
          false -> {:reply, {:error, :process_not_found}, state}
        end
    end
  end

  @impl true
  def handle_call({:get_job, job_id}, _from, state) do
    case Map.get(state.jobs, job_id) do
      nil -> {:reply, {:error, :not_found}, state}
      job -> {:reply, {:ok, job}, state}
    end
  end

  @impl true
  def handle_call({:list_jobs, session_id}, _from, state) do
    jobs =
      case session_id do
        nil ->
          Map.values(state.jobs)

        session_id ->
          state.jobs
          |> Map.values()
          |> Enum.filter(fn job -> job.session_id == session_id end)
      end

    {:reply, jobs, state}
  end

  @impl true
  def handle_call({:bring_to_foreground, job_id}, _from, state) do
    case Map.get(state.jobs, job_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %Job{background?: false} ->
        {:reply, {:error, :not_background}, state}

      job ->
        updated_job = %{job | background?: false}
        new_state = %{state | jobs: Map.put(state.jobs, job_id, updated_job)}
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:send_to_background, job_id}, _from, state) do
    case Map.get(state.jobs, job_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %Job{background?: true} ->
        {:reply, {:error, :already_background}, state}

      job ->
        updated_job = %{job | background?: true}
        new_state = %{state | jobs: Map.put(state.jobs, job_id, updated_job)}
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:wait_for_job, job_id}, from, state) do
    case Map.get(state.jobs, job_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %Job{} = job ->
        if Job.finished?(job) do
          {:reply, {:ok, job}, state}
        else
          # Add the caller to the waiters list
          waiters = Map.get(state.waiters, job_id, [])
          new_waiters = Map.put(state.waiters, job_id, [from | waiters])
          new_state = %{state | waiters: new_waiters}
          {:noreply, new_state}
        end
    end
  end

  @impl true
  def handle_call(:next_job_id, _from, state) do
    {:reply, state.next_id, state}
  end

  # Test helper function for injecting PIDs during testing
  @impl true
  def handle_call({:test_set_job_pid, job_id, new_pid}, _from, state) do
    case Map.get(state.jobs, job_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      job ->
        updated_job = %{job | pid: new_pid}
        new_jobs = Map.put(state.jobs, job_id, updated_job)
        new_state = %{state | jobs: new_jobs}
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_cast({:job_completed, job_id, exit_status}, state) do
    case Map.get(state.jobs, job_id) do
      nil ->
        Logger.warning("Received completion for unknown job #{job_id}")
        {:noreply, state}

      job ->
        updated_job = Job.complete(job, exit_status)
        new_jobs = Map.put(state.jobs, job_id, updated_job)

        # Notify any waiters
        waiters = Map.get(state.waiters, job_id, [])

        Enum.each(waiters, fn from ->
          GenServer.reply(from, {:ok, updated_job})
        end)

        new_waiters = Map.delete(state.waiters, job_id)

        # Emit telemetry event
        :telemetry.execute([:kodo, :job, :completed], %{duration: duration_ms(job)}, %{
          job_id: job_id,
          exit_status: exit_status
        })

        # Clean up completed jobs after a delay (keep for job history)
        Process.send_after(self(), {:cleanup_job, job_id}, 30_000)

        new_state = %{state | jobs: new_jobs, waiters: new_waiters}
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:job_stopped, job_id}, state) do
    case Map.get(state.jobs, job_id) do
      nil ->
        Logger.warning("Received stop for unknown job #{job_id}")
        {:noreply, state}

      job ->
        updated_job = Job.stop(job)
        new_jobs = Map.put(state.jobs, job_id, updated_job)
        new_state = %{state | jobs: new_jobs}
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:link_process, pid}, state) do
    Process.link(pid)
    {:noreply, state}
  end

  @impl true
  def handle_info({:cleanup_job, job_id}, state) do
    case Map.get(state.jobs, job_id) do
      %Job{} = job when job.status in [:completed, :failed] ->
        new_jobs = Map.delete(state.jobs, job_id)
        new_state = %{state | jobs: new_jobs}
        {:noreply, new_state}

      _ ->
        # Job is still active or doesn't exist, don't clean up
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    handle_process_exit(pid, reason, state)
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    handle_process_exit(pid, reason, state)
  end

  @impl true
  def handle_info(msg, state) do
    # Handle any other messages we might receive
    Logger.debug("JobManager received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private helper functions

  defp start_job_execution(execution_plan, job, state) do
    # Use PipelineExecutor to execute the job
    task =
      Task.async(fn ->
        # Create a basic context for the job with instance info
        context = %{
          session_id: job.session_id,
          background?: job.background?,
          instance: state.instance,
          command_registry:
            {:via, Registry, {Kodo.InstanceRegistry, {:command_registry, state.instance}}}
        }

        case Kodo.Core.Execution.PipelineExecutor.exec(execution_plan, job, context) do
          {:ok, exit_status} -> exit_status
          {:error, _reason} -> 1
        end
      end)

    {:ok, task.pid}
  end

  defp handle_process_exit(pid, reason, state) do
    # Find the job associated with this PID
    job_entry = Enum.find(state.jobs, fn {_id, job} -> job.pid == pid end)

    case job_entry do
      {job_id, job} ->
        exit_status =
          case reason do
            :normal -> 0
            # SIGKILL
            :killed -> 128 + 9
            # SIGINT
            :interrupt -> 128 + 2
            _ -> 1
          end

        updated_job = Job.complete(job, exit_status)
        new_jobs = Map.put(state.jobs, job_id, updated_job)

        # Notify waiters
        waiters = Map.get(state.waiters, job_id, [])

        Enum.each(waiters, fn from ->
          GenServer.reply(from, {:ok, updated_job})
        end)

        new_waiters = Map.delete(state.waiters, job_id)

        # Emit telemetry
        :telemetry.execute([:kodo, :job, :completed], %{duration: duration_ms(job)}, %{
          job_id: job_id,
          exit_status: exit_status
        })

        new_state = %{state | jobs: new_jobs, waiters: new_waiters}
        {:noreply, new_state}

      nil ->
        # Unknown process died, ignore
        {:noreply, state}
    end
  end

  defp duration_ms(job) do
    if job.completed_at && job.started_at do
      DateTime.diff(job.completed_at, job.started_at, :millisecond)
    else
      0
    end
  end
end
