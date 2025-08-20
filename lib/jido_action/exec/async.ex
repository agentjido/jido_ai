defmodule Jido.Exec.Async do
  @moduledoc """
  Handles asynchronous execution of Actions using Task.Supervisor.

  This module provides the core async implementation for Jido.Exec, 
  managing task supervision, cleanup, and async lifecycle.
  """
  use Private
  use ExDbug, enabled: false

  alias Jido.Action.Error

  require Logger

  @default_timeout 5000

  # Helper functions to get configuration values with fallbacks
  defp get_default_timeout,
    do: Application.get_env(:jido_action, :default_timeout, @default_timeout)

  @type action :: module()
  @type params :: map()
  @type context :: map()
  @type run_opts :: [timeout: non_neg_integer()]
  @type async_ref :: %{ref: reference(), pid: pid()}

  # Execution result types
  @type exec_success :: {:ok, map()}
  @type exec_success_dir :: {:ok, map(), any()}
  @type exec_error :: {:error, Exception.t()}
  @type exec_error_dir :: {:error, Exception.t(), any()}

  @type exec_result ::
          exec_success
          | exec_success_dir
          | exec_error
          | exec_error_dir

  @doc """
  Starts an asynchronous Action execution.

  This function creates a supervised task that calls back to Jido.Exec.run/4 
  to ensure feature consistency across sync and async execution paths.

  ## Parameters

  - `action`: The module implementing the Action behavior.
  - `params`: A map of input parameters for the Action.
  - `context`: A map providing additional context for the Action execution.
  - `opts`: Options controlling the execution (same as Jido.Exec.run/4).

  ## Returns

  An `async_ref` map containing:
  - `:ref` - A unique reference for this async action.
  - `:pid` - The PID of the process executing the Action.
  """
  @spec start(action(), params(), context(), run_opts()) :: async_ref()
  def start(action, params \\ %{}, context \\ %{}, opts \\ []) do
    dbug("Starting async action", action: action, params: params, context: context, opts: opts)
    ref = make_ref()
    parent = self()

    # Start the task under the TaskSupervisor.
    # If the supervisor is not running, this will raise an error.
    {:ok, pid} =
      Task.Supervisor.start_child(Jido.Action.TaskSupervisor, fn ->
        result = Jido.Exec.run(action, params, context, opts)
        send(parent, {:action_async_result, ref, result})
        result
      end)

    # We monitor the newly created Task so we can handle :DOWN messages in `await`.
    Process.monitor(pid)

    dbug("Async action started", ref: ref, pid: pid)
    %{ref: ref, pid: pid}
  end

  @doc """
  Waits for the result of an asynchronous Action execution.

  ## Parameters

  - `async_ref`: The reference returned by `start/4`.
  - `timeout`: Maximum time (in ms) to wait for the result (default: 5000).

  ## Returns

  - `{:ok, result}` if the Action executes successfully.
  - `{:error, reason}` if an error occurs during execution or if the action times out.
  """
  @spec await(async_ref()) :: exec_result
  def await(async_ref), do: await(async_ref, get_default_timeout())

  @doc """
  Awaits the completion of an asynchronous Action with a custom timeout.

  ## Parameters

  - `async_ref`: The async reference returned by `start/4`.
  - `timeout`: Maximum time to wait in milliseconds.

  ## Returns

  - `{:ok, result}` if the Action completes successfully.
  - `{:error, reason}` if an error occurs or timeout is reached.
  """
  @spec await(async_ref(), timeout()) :: exec_result
  def await(%{ref: ref, pid: pid}, timeout) do
    dbug("Awaiting async action result", ref: ref, pid: pid, timeout: timeout)

    receive do
      {:action_async_result, ^ref, result} ->
        dbug("Received async result", result: result)
        result

      {:DOWN, _monitor_ref, :process, ^pid, :normal} ->
        dbug("Process completed normally")
        # Process completed normally, but we might still receive the result
        receive do
          {:action_async_result, ^ref, result} ->
            dbug("Received delayed result", result: result)
            result
        after
          100 ->
            dbug("No result received after normal completion")
            {:error, Error.execution_error("Process completed but result was not received")}
        end

      {:DOWN, _monitor_ref, :process, ^pid, reason} ->
        dbug("Process crashed", reason: reason)
        {:error, Error.execution_error("Server error in async action: #{inspect(reason)}")}
    after
      timeout ->
        dbug("Async action timed out", timeout: timeout)
        Process.exit(pid, :kill)

        receive do
          {:DOWN, _, :process, ^pid, _} -> :ok
        after
          0 -> :ok
        end

        {:error, Error.timeout_error("Async action timed out after #{timeout}ms")}
    end
  end

  @doc """
  Cancels a running asynchronous Action execution.

  ## Parameters

  - `async_ref`: The reference returned by `start/4`, or just the PID of the process to cancel.

  ## Returns

  - `:ok` if the cancellation was successful.
  - `{:error, reason}` if the cancellation failed or the input was invalid.
  """
  @spec cancel(async_ref() | pid()) :: :ok | exec_error
  def cancel(%{ref: _ref, pid: pid}), do: cancel(pid)
  def cancel(%{pid: pid}), do: cancel(pid)

  def cancel(pid) when is_pid(pid) do
    dbug("Cancelling action", pid: pid)
    Process.exit(pid, :shutdown)
    :ok
  end

  def cancel(_), do: {:error, Error.validation_error("Invalid async ref for cancellation")}
end
