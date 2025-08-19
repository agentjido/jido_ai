defmodule Kodo.Core.Execution.ExternalExecutor do
  @moduledoc """
  Executor for external system commands using pluggable ProcessExecutor adapters.

  This module now delegates to a ProcessExecutor adapter, allowing for different
  execution environments (local, containerized, remote, etc.) while maintaining
  backward compatibility.
  """
  require Logger

  # Default process executor - can be configured
  @default_executor Kodo.Executors.Local

  @spec execute(String.t(), Kodo.Ports.Command.args(), Kodo.Ports.Command.context()) ::
          Kodo.Ports.Command.result()
  def execute(cmd_name, args, context) do
    executor = get_process_executor(context)

    execution_options = %{
      working_dir: context.current_dir,
      env: context.env,
      stderr_to_stdout: true,
      capture_output: true,
      timeout: 30_000
    }

    case executor.execute(cmd_name, args, execution_options) do
      {:ok, output, 0} ->
        # Command succeeded
        result = if is_binary(output), do: String.trim(output), else: ""
        {:ok, result}

      {:ok, output, exit_code} ->
        # Command failed
        error_msg = if is_binary(output), do: String.trim(output), else: "Command failed"
        message = "Command '#{cmd_name}' exited with code #{exit_code}: #{error_msg}"

        Kodo.Telemetry.error_event(:external_command_failed, message, %{
          command: cmd_name,
          args: args,
          exit_code: exit_code
        })

        {:error, message}

      {:error, {:command_not_found, _}} ->
        message = "Command '#{cmd_name}' not found"

        Kodo.Telemetry.error_event(:command_not_found, message, %{
          command: cmd_name,
          args: args
        })

        {:error, message}

      {:error, reason} ->
        message = "Failed to execute command '#{cmd_name}': #{inspect(reason)}"

        Kodo.Telemetry.error_event(:external_command_error, message, %{
          command: cmd_name,
          args: args,
          reason: reason
        })

        {:error, message}
    end
  end

  @spec can_execute?(String.t()) :: boolean()
  def can_execute?(cmd_name) do
    executor = get_process_executor()
    executor.can_execute?(cmd_name)
  end

  @doc """
  Execute a command asynchronously using the configured process executor.

  Returns a process identifier that can be used with other functions
  to monitor, wait for, or kill the process.
  """
  @spec execute_async(String.t(), Kodo.Ports.Command.args(), Kodo.Ports.Command.context()) ::
          {:ok, any()} | {:error, term()}
  def execute_async(cmd_name, args, context) do
    executor = get_process_executor(context)

    execution_options = %{
      working_dir: context.current_dir,
      env: context.env,
      stderr_to_stdout: true,
      capture_output: true
    }

    executor.execute_async(cmd_name, args, execution_options)
  end

  @doc """
  Wait for an asynchronously started process to complete.
  """
  @spec wait_for_process(any(), pos_integer()) ::
          {:ok, String.t(), non_neg_integer()} | {:error, term()}
  def wait_for_process(process_id, timeout \\ 30_000) do
    executor = get_process_executor()
    executor.wait_for(process_id, timeout)
  end

  @doc """
  Kill a running process.
  """
  @spec kill_process(any(), atom()) :: :ok | {:error, term()}
  def kill_process(process_id, signal \\ :term) do
    executor = get_process_executor()
    executor.kill(process_id, signal)
  end

  @doc """
  Get the status of a process.
  """
  @spec get_process_status(any()) :: any()
  def get_process_status(process_id) do
    executor = get_process_executor()
    executor.get_status(process_id)
  end

  # Private helper functions

  defp get_process_executor(context \\ %{}) do
    # Allow context to override the executor for testing or special cases
    Map.get(context, :process_executor, get_configured_executor())
  end

  defp get_configured_executor do
    # This could be made configurable via application environment
    Application.get_env(:kodo, :process_executor, @default_executor)
  end
end
