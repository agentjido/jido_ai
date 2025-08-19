defmodule Kodo.Core.Execution.PipelineExecutor do
  @moduledoc """
  Executes command pipelines and handles complex execution plans.

  This module is responsible for:
  - Executing simple commands
  - Setting up and running pipelines with proper stdio connections
  - Handling control operators (&&, ||, ;)
  - Managing background execution (&)
  - Coordinating with JobManager for job lifecycle
  """

  require Logger

  alias Kodo.Core.Parsing.ExecutionPlan
  alias Kodo.Core.Jobs.{Job, JobManager}
  alias Kodo.Core.Sessions.StdioManager
  alias Kodo.Core.Execution.BuiltinExecutor
  alias Kodo.Core.Commands.CommandRegistry

  @doc """
  Executes an execution plan within the context of a job.

  This is the main entry point for executing parsed commands.
  Returns {:ok, exit_status} or {:error, reason}.
  """
  @spec exec(ExecutionPlan.t(), Job.t(), map()) :: {:ok, integer()} | {:error, term()}
  def exec(execution_plan, job, context \\ %{})

  def exec(%ExecutionPlan.Command{} = command, job, context) do
    exec_command(command, job, context)
  end

  def exec(%ExecutionPlan.Pipeline{commands: commands}, job, context) do
    exec_pipeline(commands, job, context)
  end

  def exec(%ExecutionPlan{pipelines: pipelines}, job, context) when length(pipelines) == 1 do
    [pipeline] = pipelines
    exec(pipeline, job, context)
  end

  def exec(%ExecutionPlan{} = plan, job, context) do
    # Complex execution plan with multiple pipelines and control operators
    exec_plan(plan, job, context)
  end

  def exec({:background, execution_plan}, job, context) do
    exec_bg(execution_plan, job, context)
  end

  def exec(unknown, _job, _context) do
    Logger.error("Unknown execution plan: #{inspect(unknown)}")
    {:error, {:unknown_execution_plan, unknown}}
  end

  # Legacy function names - DEPRECATED
  @deprecated "Use exec/3 instead"
  def execute(execution_plan, job, context \\ %{}) do
    exec(execution_plan, job, context)
  end

  @doc """
  Executes a single command (single process).
  """
  @spec exec_command(ExecutionPlan.Command.t(), Job.t(), map()) ::
          {:ok, integer()} | {:error, term()}
  def exec_command(%ExecutionPlan.Command{} = command, job, context) do
    # Determine stdio configuration
    stdio_config = determine_stdio_config(command, job, context)

    # Check if this is a built-in command
    case lookup_builtin_command(command.name, context) do
      {:ok, module} ->
        execute_builtin_command(module, command, job, context)

      :not_found ->
        execute_external_command(command, job, context, stdio_config)
    end
  end

  @doc """
  Executes a complex execution plan with multiple pipelines and control operators.
  """
  @spec exec_plan(ExecutionPlan.t(), Job.t(), map()) ::
          {:ok, integer()} | {:error, term()}
  def exec_plan(%ExecutionPlan{pipelines: pipelines}, job, context) do
    # For now, execute all pipelines sequentially
    # TODO: Handle control operators properly
    results =
      Enum.map(pipelines, fn pipeline ->
        exec(pipeline, job, context)
      end)

    # Return the result of the last pipeline
    case List.last(results) do
      {:ok, exit_status} -> {:ok, exit_status}
      {:error, reason} -> {:error, reason}
      nil -> {:ok, 0}
    end
  end

  @doc """
  Executes a pipeline of commands with proper stdio connections.
  """
  @spec exec_pipeline([ExecutionPlan.Command.t()], Job.t(), map()) ::
          {:ok, integer()} | {:error, term()}
  def exec_pipeline(commands, job, context) when length(commands) > 1 do
    Logger.debug("Executing pipeline with #{length(commands)} commands")

    # Create stdio configurations for all commands in the pipeline
    stdio_configs = StdioManager.create_pipeline_connections(commands)

    # Start all commands in the pipeline
    case start_pipeline_processes(commands, stdio_configs, job, context) do
      {:ok, processes} ->
        # Wait for all processes to complete and get the exit status of the last command
        wait_for_pipeline_completion(processes)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def exec_pipeline([single_command], job, context) do
    # Single command in a "pipeline" is just a single command
    exec_command(single_command, job, context)
  end

  def exec_pipeline([], _job, _context) do
    # Empty pipeline succeeds
    {:ok, 0}
  end

  @doc """
  Executes control operators between execution plans.
  """
  @spec exec_control_op(ExecutionPlan.t(), atom(), ExecutionPlan.t(), Job.t(), map()) ::
          {:ok, integer()} | {:error, term()}
  def exec_control_op(left, operator, right, job, context) do
    case exec(left, job, context) do
      {:ok, left_exit_status} ->
        case operator do
          # &&
          :and_then ->
            if left_exit_status == 0 do
              exec(right, job, context)
            else
              {:ok, left_exit_status}
            end

          # ||
          :or_else ->
            if left_exit_status != 0 do
              exec(right, job, context)
            else
              {:ok, left_exit_status}
            end

          # ;
          :sequence ->
            # Always execute right side regardless of left side result
            case exec(right, job, context) do
              {:ok, right_exit_status} -> {:ok, right_exit_status}
              error -> error
            end
        end

      {:error, reason} ->
        # If left side fails, handle based on operator
        case operator do
          # && stops on failure
          :and_then -> {:error, reason}
          # || continues on failure
          :or_else -> exec(right, job, context)
          # ; always continues
          :sequence -> exec(right, job, context)
        end
    end
  end

  @doc """
  Executes a command in the background.
  """
  @spec exec_bg(ExecutionPlan.t(), Job.t(), map()) ::
          {:ok, integer()} | {:error, term()}
  def exec_bg(execution_plan, job, context) do
    # For background execution, we spawn a separate process
    # and return immediately

    _parent = self()

    _task =
      Task.async(fn ->
        # Execute the plan in background
        result = exec(execution_plan, job, context)

        # Notify the job manager when complete
        case result do
          {:ok, exit_status} ->
            JobManager.job_completed(job.id, exit_status)
            exit_status

          {:error, _reason} ->
            JobManager.job_completed(job.id, 1)
            1
        end
      end)

    # Return immediately for background jobs
    {:ok, 0}
  end

  # Private implementation functions

  defp determine_stdio_config(command, job, _context) do
    base_config =
      if job.background? do
        StdioManager.background_stdio_config()
      else
        %{stdin: :inherit, stdout: :inherit, stderr: :inherit}
      end

    # Apply any redirections specified in the command
    StdioManager.setup_redirections(base_config, command.redirections || [])
  end

  defp lookup_builtin_command(command_name, context) do
    command_registry = Map.get(context, :command_registry, Kodo.Core.Commands.CommandRegistry)

    case CommandRegistry.get_command(command_registry, command_name) do
      {:ok, module} ->
        if :builtin in module.meta() do
          {:ok, module}
        else
          :not_found
        end

      :error ->
        :not_found
    end
  end

  defp execute_builtin_command(module, command, _job, context) do
    # Execute builtin command using BuiltinExecutor
    case BuiltinExecutor.execute(module, command.args, context) do
      {:ok, output} ->
        # Builtin commands that succeed return the output
        {:ok, output}

      {:error, reason} ->
        # Builtin commands that fail return the error
        {:error, reason}
    end
  end

  defp execute_external_command(command, _job, _context, stdio_config) do
    # Use StdioManager to spawn the external process
    case StdioManager.spawn_with_stdio(command.name, command.args, stdio_config) do
      {:ok, port} ->
        # Wait for the process to complete
        wait_for_process_completion(port)

      {:error, :enoent} ->
        {:error, {:command_not_found, command.name}}

      {:error, reason} ->
        {:error, {:spawn_failed, reason}}
    end
  end

  defp start_pipeline_processes(commands, stdio_configs, _job, _context) do
    # Start all processes in the pipeline
    results =
      for {command, stdio_config} <- Enum.zip(commands, stdio_configs) do
        case StdioManager.spawn_with_stdio(command.command, command.args, stdio_config) do
          {:ok, port} -> {:ok, port}
          {:error, reason} -> {:error, {command.command, reason}}
        end
      end

    # Check if all processes started successfully
    case Enum.find(results, fn result -> match?({:error, _}, result) end) do
      nil ->
        # All processes started successfully
        processes = Enum.map(results, fn {:ok, port} -> port end)
        {:ok, processes}

      {:error, reason} ->
        # Some process failed to start, clean up and return error
        cleanup_partial_pipeline(results)
        {:error, reason}
    end
  end

  defp cleanup_partial_pipeline(results) do
    # Clean up any processes that did start
    Enum.each(results, fn
      {:ok, port} ->
        try do
          Port.close(port)
        catch
          _, _ -> :ok
        end

      {:error, _} ->
        :ok
    end)
  end

  defp wait_for_pipeline_completion(processes) do
    # Wait for all processes to complete
    # The exit status of a pipeline is the exit status of the last command

    # This is a simplified implementation
    # In a real shell, we'd need to handle proper pipe coordination

    results =
      for process <- processes do
        wait_for_process_completion(process)
      end

    # Return the result of the last process
    case List.last(results) do
      {:ok, exit_status} -> {:ok, exit_status}
      {:error, reason} -> {:error, reason}
      # Empty pipeline
      nil -> {:ok, 0}
    end
  end

  defp wait_for_process_completion(port) when is_port(port) do
    receive do
      {^port, {:exit_status, status}} ->
        {:ok, status}

      {^port, {:data, _data}} ->
        # Ignore data output for now
        wait_for_process_completion(port)

      {:EXIT, ^port, :normal} ->
        {:ok, 0}

      {:EXIT, ^port, reason} ->
        {:error, reason}
    after
      # 30 second timeout
      30_000 ->
        Port.close(port)
        {:error, :timeout}
    end
  end

  defp wait_for_process_completion(pid) when is_pid(pid) do
    # For Task/GenServer processes
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} ->
        {:ok, 0}

      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:error, reason}
    after
      30_000 ->
        Process.exit(pid, :kill)
        {:error, :timeout}
    end
  end
end
