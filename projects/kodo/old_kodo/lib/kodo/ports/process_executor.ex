defmodule Kodo.Ports.ProcessExecutor do
  @moduledoc """
  Port definition for external process execution.

  This behavior abstracts the execution of external commands, allowing for
  different execution environments (local, containerized, remote, etc.)
  while maintaining a consistent interface.
  """

  @type command :: String.t()
  @type args :: [String.t()]
  @type env :: %{String.t() => String.t()}
  @type working_dir :: String.t()
  @type exit_code :: non_neg_integer()
  @type output :: String.t()
  @type process_id :: pid() | port() | any()
  @type signal :: :kill | :term | :int | atom()

  @type execution_options :: %{
          working_dir: working_dir(),
          env: env(),
          timeout: pos_integer() | :infinity,
          capture_output: boolean(),
          stderr_to_stdout: boolean()
        }

  @type execution_result ::
          {:ok, output(), exit_code()}
          | {:error, term()}

  @type async_result ::
          {:ok, process_id()}
          | {:error, term()}

  @type process_status ::
          {:running, process_id()}
          | {:finished, exit_code(), output()}
          | {:killed, signal()}
          | {:error, term()}

  @doc """
  Execute a command synchronously and return the result.

  ## Options
  - `:working_dir` - Directory to run the command in (default: current directory)
  - `:env` - Environment variables map (default: inherit current env)
  - `:timeout` - Maximum execution time in milliseconds (default: 30_000)
  - `:capture_output` - Whether to capture stdout/stderr (default: true)
  - `:stderr_to_stdout` - Whether to merge stderr into stdout (default: true)

  ## Examples

      iex> ProcessExecutor.execute("echo", ["hello"], %{})
      {:ok, "hello\\n", 0}
      
      iex> ProcessExecutor.execute("false", [], %{})
      {:ok, "", 1}
      
      iex> ProcessExecutor.execute("nonexistent", [], %{})
      {:error, :command_not_found}
  """
  @callback execute(command(), args(), execution_options()) :: execution_result()

  @doc """
  Execute a command asynchronously and return a process identifier.

  The process can be monitored, waited for, or killed using other callbacks.

  ## Examples

      iex> {:ok, pid} = ProcessExecutor.execute_async("sleep", ["5"], %{})
      iex> ProcessExecutor.get_status(pid)
      {:running, pid}
  """
  @callback execute_async(command(), args(), execution_options()) :: async_result()

  @doc """
  Wait for an asynchronously started process to complete.

  ## Examples

      iex> {:ok, pid} = ProcessExecutor.execute_async("echo", ["done"], %{})
      iex> ProcessExecutor.wait_for(pid)
      {:ok, "done\\n", 0}
      
      iex> ProcessExecutor.wait_for(pid, 1000)
      {:error, :timeout}
  """
  @callback wait_for(process_id(), timeout :: pos_integer() | :infinity) ::
              {:ok, output(), exit_code()} | {:error, term()}

  @doc """
  Get the current status of a process.

  ## Examples

      iex> {:ok, pid} = ProcessExecutor.execute_async("sleep", ["1"], %{})
      iex> ProcessExecutor.get_status(pid)
      {:running, pid}
      
      # After completion
      iex> ProcessExecutor.get_status(pid)
      {:finished, 0, ""}
  """
  @callback get_status(process_id()) :: process_status()

  @doc """
  Kill a running process with the specified signal.

  ## Examples

      iex> {:ok, pid} = ProcessExecutor.execute_async("sleep", ["10"], %{})
      iex> ProcessExecutor.kill(pid, :term)
      :ok
      
      iex> ProcessExecutor.kill(pid, :kill)
      :ok
  """
  @callback kill(process_id(), signal()) :: :ok | {:error, term()}

  @doc """
  Check if a command exists and can be executed.

  ## Examples

      iex> ProcessExecutor.can_execute?("echo")
      true
      
      iex> ProcessExecutor.can_execute?("nonexistent_command")
      false
  """
  @callback can_execute?(command()) :: boolean()

  @doc """
  Get information about the execution environment.

  Returns metadata about the executor implementation, such as:
  - Execution context (local, docker, ssh, etc.)
  - Available features and limitations
  - Version information

  ## Examples

      iex> ProcessExecutor.info()
      %{
        type: :local,
        features: [:async_execution, :signal_handling],
        platform: :unix,
        version: "1.0.0"
      }
  """
  @callback info() :: map()

  # Helper functions for common execution patterns

  @doc """
  Execute a command and return only the output, ignoring exit code.

  Returns `{:error, reason}` if the command fails to start or times out.
  """
  @spec execute_for_output(module(), command(), args(), execution_options()) ::
          {:ok, output()} | {:error, term()}
  def execute_for_output(executor, command, args, options \\ %{}) do
    case executor.execute(command, args, options) do
      {:ok, output, _exit_code} -> {:ok, output}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Execute a command and return success/failure based on exit code.

  Returns `:ok` if exit code is 0, `{:error, {output, exit_code}}` otherwise.
  """
  @spec execute_for_success(module(), command(), args(), execution_options()) ::
          :ok | {:error, {output(), exit_code()} | term()}
  def execute_for_success(executor, command, args, options \\ %{}) do
    case executor.execute(command, args, options) do
      {:ok, _output, 0} -> :ok
      {:ok, output, exit_code} -> {:error, {output, exit_code}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Execute a command with a timeout, returning `:timeout` if it exceeds the limit.
  """
  @spec execute_with_timeout(module(), command(), args(), pos_integer(), execution_options()) ::
          execution_result() | {:error, :timeout}
  def execute_with_timeout(executor, command, args, timeout_ms, options \\ %{}) do
    options_with_timeout = Map.put(options, :timeout, timeout_ms)
    executor.execute(command, args, options_with_timeout)
  end
end
