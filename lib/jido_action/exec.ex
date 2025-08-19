defmodule Jido.Exec do
  @moduledoc """
  Exec provides a robust set of methods for executing Actions (`Jido.Action`).

  This module offers functionality to:
  - Run actions synchronously or asynchronously
  - Manage timeouts and retries
  - Cancel running actions
  - Normalize and validate input parameters and context
  - Emit telemetry events for monitoring and debugging

  Execs are defined as modules (Actions) that implement specific callbacks, allowing for
  a standardized way of defining and executing complex actions across a distributed system.

  ## Features

  - Synchronous and asynchronous action execution
  - Automatic retries with exponential backoff
  - Timeout handling for long-running actions
  - Parameter and context normalization
  - Comprehensive error handling and reporting
  - Telemetry integration for monitoring and tracing
  - Cancellation of running actions

  ## Usage

  Execs are executed using the `run/4` or `run_async/4` functions:

      Jido.Exec.run(MyAction, %{param1: "value"}, %{context_key: "context_value"})

  See `Jido.Action` for how to define an Action.

  For asynchronous execution:

      async_ref = Jido.Exec.run_async(MyAction, params, context)
      # ... do other work ...
      result = Jido.Exec.await(async_ref)

  """
  use Private
  use ExDbug, enabled: false

  import Jido.Action.Util, only: [cond_log: 3]

  alias Jido.Action.Error
  alias Jido.Instruction

  require Logger

  @default_timeout 5000
  @default_max_retries 1
  @default_initial_backoff 250

  # Helper functions to get configuration values with fallbacks
  defp get_default_timeout,
    do: Application.get_env(:jido_action, :default_timeout, @default_timeout)

  defp get_default_max_retries,
    do: Application.get_env(:jido_action, :default_max_retries, @default_max_retries)

  defp get_default_backoff,
    do: Application.get_env(:jido_action, :default_backoff, @default_initial_backoff)

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
  Executes a Action synchronously with the given parameters and context.

  ## Parameters

  - `action`: The module implementing the Action behavior.
  - `params`: A map of input parameters for the Action.
  - `context`: A map providing additional context for the Action execution.
  - `opts`: Options controlling the execution:
    - `:timeout` - Maximum time (in ms) allowed for the Action to complete (default: #{@default_timeout}, configurable via `:jido_action, :default_timeout`).
    - `:max_retries` - Maximum number of retry attempts (default: #{@default_max_retries}, configurable via `:jido_action, :default_max_retries`).
    - `:backoff` - Initial backoff time in milliseconds, doubles with each retry (default: #{@default_initial_backoff}, configurable via `:jido_action, :default_backoff`).
    - `:log_level` - Override the global Logger level for this specific action. Accepts #{inspect(Logger.levels())}.

  ## Action Metadata in Context

  The action's metadata (name, description, category, tags, version, etc.) is made available
  to the action's `run/2` function via the `context` parameter under the `:action_metadata` key.
  This allows actions to access their own metadata when needed.

  ## Returns

  - `{:ok, result}` if the Action executes successfully.
  - `{:error, reason}` if an error occurs during execution.

  ## Examples

      iex> Jido.Exec.run(MyAction, %{input: "value"}, %{user_id: 123})
      {:ok, %{result: "processed value"}}

      iex> Jido.Exec.run(MyAction, %{invalid: "input"}, %{}, timeout: 1000)
      {:error, %Jido.Action.Error{type: :validation_error, message: "Invalid input"}}

      iex> Jido.Exec.run(MyAction, %{input: "value"}, %{}, log_level: :debug)
      {:ok, %{result: "processed value"}}

      # Access action metadata in the action:
      # defmodule MyAction do
      #   use Jido.Action,
      #     name: "my_action",
      #     description: "Example action",
      #     vsn: "1.0.0"
      #
      #   def run(_params, context) do
      #     metadata = context.action_metadata
      #     {:ok, %{name: metadata.name, version: metadata.vsn}}
      #   end
      # end
  """
  @spec run(Instruction.t()) :: exec_result()
  @spec run(action(), params(), context(), run_opts()) :: exec_result()
  def run(%Instruction{} = instruction) do
    dbug("Running instruction", instruction: instruction)

    run(
      instruction.action,
      instruction.params,
      instruction.context,
      instruction.opts
    )
  end

  def run(action, params \\ %{}, context \\ %{}, opts \\ [])

  def run(action, params, context, opts) when is_atom(action) and is_list(opts) do
    dbug("Starting action run", action: action, params: params, context: context, opts: opts)
    log_level = Keyword.get(opts, :log_level, :info)

    with {:ok, normalized_params} <- normalize_params(params),
         {:ok, normalized_context} <- normalize_context(context),
         :ok <- validate_action(action),
         {:ok, validated_params} <- validate_params(action, normalized_params) do
      enhanced_context =
        Map.put(normalized_context, :action_metadata, action.__action_metadata__())

      dbug("Params and context normalized and validated",
        normalized_params: normalized_params,
        normalized_context: enhanced_context,
        validated_params: validated_params
      )

      cond_log(
        log_level,
        :notice,
        "Executing #{inspect(action)} with params: #{inspect(validated_params)} and context: #{inspect(enhanced_context)}"
      )

      do_run_with_retry(action, validated_params, enhanced_context, opts)
    else
      {:error, reason} ->
        dbug("Error in action setup", error: reason)
        cond_log(log_level, :debug, "Action Execution failed: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e in [FunctionClauseError, BadArityError, BadFunctionError] ->
      log_level = Keyword.get(opts, :log_level, :info)
      dbug("Function error in action", error: e)

      cond_log(
        log_level,
        :warning,
        "Function invocation error in action: #{extract_safe_error_message(e)}"
      )

      {:error, Error.validation_error("Invalid action module: #{extract_safe_error_message(e)}")}

    e ->
      log_level = Keyword.get(opts, :log_level, :info)
      dbug("Unexpected error in action", error: e)
      cond_log(log_level, :error, "Unexpected error in action: #{extract_safe_error_message(e)}")

      {:error,
       Error.internal_error("An unexpected error occurred: #{extract_safe_error_message(e)}")}
  catch
    kind, reason ->
      log_level = Keyword.get(opts, :log_level, :info)
      dbug("Caught error in action", kind: kind, reason: reason)

      cond_log(
        log_level,
        :warning,
        "Caught unexpected throw/exit in action: #{extract_safe_error_message(reason)}"
      )

      {:error, Error.internal_error("Caught #{kind}: #{inspect(reason)}")}
  end

  def run(action, _params, _context, _opts) do
    dbug("Invalid action type", action: action)
    {:error, Error.validation_error("Expected action to be a module, got: #{inspect(action)}")}
  end

  @doc """
  Executes a Action asynchronously with the given parameters and context.

  This function immediately returns a reference that can be used to await the result
  or cancel the action.

  **Note**: This approach integrates with OTP by spawning tasks under a `Task.Supervisor`.
  Make sure `{Task.Supervisor, name: Jido.Action.TaskSupervisor}` is part of your supervision tree.

  ## Parameters

  - `action`: The module implementing the Action behavior.
  - `params`: A map of input parameters for the Action.
  - `context`: A map providing additional context for the Action execution.
  - `opts`: Options controlling the execution (same as `run/4`).

  ## Returns

  An `async_ref` map containing:
  - `:ref` - A unique reference for this async action.
  - `:pid` - The PID of the process executing the Action.

  ## Examples

      iex> async_ref = Jido.Exec.run_async(MyAction, %{input: "value"}, %{user_id: 123})
      %{ref: #Reference<0.1234.5678>, pid: #PID<0.234.0>}

      iex> result = Jido.Exec.await(async_ref)
      {:ok, %{result: "processed value"}}
  """
  @spec run_async(action(), params(), context(), run_opts()) :: async_ref()
  def run_async(action, params \\ %{}, context \\ %{}, opts \\ []) do
    dbug("Starting async action", action: action, params: params, context: context, opts: opts)
    ref = make_ref()
    parent = self()

    # Start the task under the TaskSupervisor.
    # If the supervisor is not running, this will raise an error.
    {:ok, pid} =
      Task.Supervisor.start_child(Jido.Action.TaskSupervisor, fn ->
        result = run(action, params, context, opts)
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

  - `async_ref`: The reference returned by `run_async/4`.
  - `timeout`: Maximum time (in ms) to wait for the result (default: 5000).

  ## Returns

  - `{:ok, result}` if the Action executes successfully.
  - `{:error, reason}` if an error occurs during execution or if the action times out.

  ## Examples

      iex> async_ref = Jido.Exec.run_async(MyAction, %{input: "value"})
      iex> Jido.Exec.await(async_ref, 10_000)
      {:ok, %{result: "processed value"}}

      iex> async_ref = Jido.Exec.run_async(SlowAction, %{input: "value"})
      iex> Jido.Exec.await(async_ref, 100)
      {:error, %Jido.Action.Error{type: :timeout, message: "Async action timed out after 100ms"}}
  """
  @spec await(async_ref()) :: exec_result
  def await(async_ref), do: await(async_ref, get_default_timeout())

  @doc """
  Awaits the completion of an asynchronous Action with a custom timeout.

  ## Parameters

  - `async_ref`: The async reference returned by `run_async/4`.
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

  - `async_ref`: The reference returned by `run_async/4`, or just the PID of the process to cancel.

  ## Returns

  - `:ok` if the cancellation was successful.
  - `{:error, reason}` if the cancellation failed or the input was invalid.

  ## Examples

      iex> async_ref = Jido.Exec.run_async(LongRunningAction, %{input: "value"})
      iex> Jido.Exec.cancel(async_ref)
      :ok

      iex> Jido.Exec.cancel("invalid")
      {:error, %Jido.Action.Error{type: :invalid_async_ref, message: "Invalid async ref for cancellation"}}
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

  # Private functions are exposed to the test suite
  private do
    @spec normalize_params(params()) :: {:ok, map()} | {:error, Exception.t()}
    defp normalize_params(%_{} = error) when is_exception(error), do: {:error, error}
    defp normalize_params(params) when is_map(params), do: {:ok, params}
    defp normalize_params(params) when is_list(params), do: {:ok, Map.new(params)}
    defp normalize_params({:ok, params}) when is_map(params), do: {:ok, params}
    defp normalize_params({:ok, params}) when is_list(params), do: {:ok, Map.new(params)}
    defp normalize_params({:error, reason}), do: {:error, Error.validation_error(reason)}

    defp normalize_params(params),
      do: {:error, Error.validation_error("Invalid params type: #{inspect(params)}")}

    @spec normalize_context(context()) :: {:ok, map()} | {:error, Exception.t()}
    defp normalize_context(context) when is_map(context), do: {:ok, context}
    defp normalize_context(context) when is_list(context), do: {:ok, Map.new(context)}

    defp normalize_context(context),
      do: {:error, Error.validation_error("Invalid context type: #{inspect(context)}")}

    @spec validate_action(action()) :: :ok | {:error, Exception.t()}
    defp validate_action(action) do
      dbug("Validating action", action: action)

      case Code.ensure_compiled(action) do
        {:module, _} ->
          if function_exported?(action, :run, 2) do
            :ok
          else
            {:error,
             Error.validation_error(
               "Module #{inspect(action)} is not a valid action: missing run/2 function"
             )}
          end

        {:error, reason} ->
          {:error,
           Error.validation_error(
             "Failed to compile module #{inspect(action)}: #{inspect(reason)}"
           )}
      end
    end

    @spec validate_params(action(), map()) :: {:ok, map()} | {:error, Exception.t()}
    defp validate_params(action, params) do
      dbug("Validating params", action: action, params: params)

      if function_exported?(action, :validate_params, 1) do
        case action.validate_params(params) do
          {:ok, params} ->
            {:ok, params}

          {:error, reason} ->
            {:error, reason}

          _ ->
            {:error, Error.validation_error("Invalid return from action.validate_params/1")}
        end
      else
        {:error,
         Error.validation_error(
           "Module #{inspect(action)} is not a valid action: missing validate_params/1 function"
         )}
      end
    end

    @spec validate_output(action(), map(), run_opts()) :: {:ok, map()} | {:error, Exception.t()}
    defp validate_output(action, output, opts) do
      log_level = Keyword.get(opts, :log_level, :info)
      dbug("Validating output", action: action, output: output)

      if function_exported?(action, :validate_output, 1) do
        case action.validate_output(output) do
          {:ok, validated_output} ->
            cond_log(log_level, :debug, "Output validation succeeded for #{inspect(action)}")
            {:ok, validated_output}

          {:error, reason} ->
            cond_log(
              log_level,
              :debug,
              "Output validation failed for #{inspect(action)}: #{inspect(reason)}"
            )

            {:error, reason}

          _ ->
            cond_log(log_level, :debug, "Invalid return from action.validate_output/1")
            {:error, Error.validation_error("Invalid return from action.validate_output/1")}
        end
      else
        # If action doesn't have validate_output/1, skip output validation
        cond_log(
          log_level,
          :debug,
          "No output validation function found for #{inspect(action)}, skipping"
        )

        {:ok, output}
      end
    end

    @spec do_run_with_retry(action(), params(), context(), run_opts()) :: exec_result
    defp do_run_with_retry(action, params, context, opts) do
      max_retries = Keyword.get(opts, :max_retries, get_default_max_retries())
      backoff = Keyword.get(opts, :backoff, get_default_backoff())
      dbug("Starting run with retry", action: action, max_retries: max_retries, backoff: backoff)
      do_run_with_retry(action, params, context, opts, 0, max_retries, backoff)
    end

    @spec do_run_with_retry(
            action(),
            params(),
            context(),
            run_opts(),
            non_neg_integer(),
            non_neg_integer(),
            non_neg_integer()
          ) :: exec_result
    defp do_run_with_retry(action, params, context, opts, retry_count, max_retries, backoff) do
      dbug("Attempting run", action: action, retry_count: retry_count)

      case do_run(action, params, context, opts) do
        {:ok, result} ->
          dbug("Run succeeded", result: result)
          {:ok, result}

        {:ok, result, other} ->
          dbug("Run succeeded with additional info", result: result, other: other)
          {:ok, result, other}

        {:error, reason, other} ->
          dbug("Run failed with additional info", error: reason, other: other)

          maybe_retry(
            action,
            params,
            context,
            opts,
            retry_count,
            max_retries,
            backoff,
            {:error, reason, other}
          )

        {:error, reason} ->
          dbug("Run failed", error: reason)

          maybe_retry(
            action,
            params,
            context,
            opts,
            retry_count,
            max_retries,
            backoff,
            {:error, reason}
          )
      end
    end

    defp maybe_retry(action, params, context, opts, retry_count, max_retries, backoff, error) do
      if retry_count < max_retries do
        backoff = calculate_backoff(retry_count, backoff)

        cond_log(
          Keyword.get(opts, :log_level, :info),
          :info,
          "Retrying #{inspect(action)} (attempt #{retry_count + 1}/#{max_retries}) after #{backoff}ms backoff"
        )

        dbug("Retrying after backoff",
          action: action,
          retry_count: retry_count,
          max_retries: max_retries,
          backoff: backoff
        )

        :timer.sleep(backoff)

        do_run_with_retry(
          action,
          params,
          context,
          opts,
          retry_count + 1,
          max_retries,
          backoff
        )
      else
        dbug("Max retries reached", action: action, max_retries: max_retries)
        error
      end
    end

    @spec calculate_backoff(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
    defp calculate_backoff(retry_count, backoff) do
      (backoff * :math.pow(2, retry_count))
      |> round()
      |> min(30_000)
    end

    @spec do_run(action(), params(), context(), run_opts()) :: exec_result
    defp do_run(action, params, context, opts) do
      timeout = Keyword.get(opts, :timeout, get_default_timeout())
      telemetry = Keyword.get(opts, :telemetry, :full)
      dbug("Starting action execution", action: action, timeout: timeout, telemetry: telemetry)

      result =
        case telemetry do
          :silent ->
            execute_action_with_timeout(action, params, context, timeout)

          _ ->
            span_metadata = %{
              action: action,
              params: params,
              context: context
            }

            :telemetry.span(
              [:jido, :action],
              span_metadata,
              fn ->
                result = execute_action_with_timeout(action, params, context, timeout, opts)
                {result, %{}}
              end
            )
        end

      case result do
        {:ok, _result} = success ->
          dbug("Action succeeded", result: success)
          success

        {:ok, _result, _other} = success ->
          dbug("Action succeeded with additional info", result: success)
          success

        {:error, %Jido.Action.Error.TimeoutError{}} = timeout_err ->
          dbug("Action timed out", error: timeout_err)
          timeout_err

        {:error, error, other} ->
          dbug("Action failed with additional info", error: error, other: other)
          handle_action_error(action, params, context, {error, other}, opts)

        {:error, error} ->
          dbug("Action failed", error: error)
          handle_action_error(action, params, context, error, opts)
      end
    end

    @spec handle_action_error(
            action(),
            params(),
            context(),
            Exception.t() | {Exception.t(), any()},
            run_opts()
          ) :: exec_result
    defp handle_action_error(action, params, context, error_or_tuple, opts) do
      Logger.debug("Handle Action Error in handle_action_error: #{inspect(opts)}")
      dbug("Handling action error", action: action, error: error_or_tuple)

      # Extract error and directive if present
      {error, directive} =
        case error_or_tuple do
          {error, directive} -> {error, directive}
          error -> {error, nil}
        end

      if compensation_enabled?(action) do
        metadata = action.__action_metadata__()
        compensation_opts = metadata[:compensation] || []

        timeout =
          Keyword.get(opts, :timeout) ||
            case compensation_opts do
              opts when is_list(opts) -> Keyword.get(opts, :timeout, 5_000)
              %{timeout: timeout} -> timeout
              _ -> 5_000
            end

        dbug("Starting compensation", action: action, timeout: timeout)

        task =
          Task.async(fn ->
            action.on_error(params, error, context, [])
          end)

        case Task.yield(task, timeout) || Task.shutdown(task) do
          {:ok, result} ->
            dbug("Compensation completed", result: result)
            handle_compensation_result(result, error, directive)

          nil ->
            dbug("Compensation timed out", timeout: timeout)

            error_result =
              Error.execution_error(
                "Compensation timed out after #{timeout}ms for: #{inspect(error)}",
                %{
                  compensated: false,
                  compensation_error: "Compensation timed out after #{timeout}ms",
                  original_error: error
                }
              )

            if directive, do: {:error, error_result, directive}, else: {:error, error_result}
        end
      else
        dbug("Compensation not enabled", action: action)
        if directive, do: {:error, error, directive}, else: {:error, error}
      end
    end

    @spec handle_compensation_result(any(), Exception.t(), any()) :: exec_result
    defp handle_compensation_result(result, original_error, directive) do
      error_result =
        case result do
          {:ok, comp_result} ->
            # Extract fields that should be at the top level of the details
            {top_level_fields, remaining_fields} =
              Map.split(comp_result, [:test_value, :compensation_context])

            # Create the details map with the compensation result
            details =
              Map.merge(
                %{
                  compensated: true,
                  compensation_result: remaining_fields
                },
                top_level_fields
              )

            # Extract message from error struct properly using safe helper
            error_message = extract_safe_error_message(original_error)

            Error.execution_error(
              "Compensation completed for: #{error_message}",
              Map.put(details, :original_error, original_error)
            )

          {:error, comp_error} ->
            # Extract message from error struct properly using safe helper
            error_message = extract_safe_error_message(original_error)

            Error.execution_error(
              "Compensation failed for: #{error_message}",
              %{
                compensated: false,
                compensation_error: comp_error,
                original_error: original_error
              }
            )

          _ ->
            Error.execution_error(
              "Invalid compensation result for: #{inspect(original_error)}",
              %{
                compensated: false,
                compensation_error: "Invalid compensation result",
                original_error: original_error
              }
            )
        end

      if directive, do: {:error, error_result, directive}, else: {:error, error_result}
    end

    @spec compensation_enabled?(action()) :: boolean()
    defp compensation_enabled?(action) do
      metadata = action.__action_metadata__()
      compensation_opts = metadata[:compensation] || []

      enabled =
        case compensation_opts do
          opts when is_list(opts) -> Keyword.get(opts, :enabled, false)
          %{enabled: enabled} -> enabled
          _ -> false
        end

      enabled && function_exported?(action, :on_error, 4)
    end

    @spec execute_action_with_timeout(
            action(),
            params(),
            context(),
            non_neg_integer(),
            run_opts()
          ) :: exec_result
    defp execute_action_with_timeout(action, params, context, timeout, opts \\ [])

    defp execute_action_with_timeout(action, params, context, 0, opts) do
      execute_action(action, params, context, opts)
    end

    defp execute_action_with_timeout(action, params, context, timeout, opts)
         when is_integer(timeout) and timeout > 0 do
      parent = self()
      ref = make_ref()

      dbug("Starting action with timeout", action: action, timeout: timeout)

      # Create a temporary task group for this execution
      {:ok, task_group} =
        Task.Supervisor.start_child(
          Jido.Action.TaskSupervisor,
          fn ->
            Process.flag(:trap_exit, true)

            receive do
              {:shutdown} -> :ok
            end
          end
        )

      # Add task_group to context so Actions can use it
      enhanced_context = Map.put(context, :__task_group__, task_group)

      # Get the current process's group leader
      current_gl = Process.group_leader()

      {pid, monitor_ref} =
        spawn_monitor(fn ->
          # Use the parent's group leader to ensure IO is properly captured
          Process.group_leader(self(), current_gl)

          result =
            try do
              dbug("Executing action in task", action: action, pid: self())
              result = execute_action(action, params, enhanced_context, opts)
              dbug("Action execution completed", action: action, result: result)
              result
            catch
              kind, reason ->
                stacktrace = __STACKTRACE__
                dbug("Action execution caught error", action: action, kind: kind, reason: reason)

                {:error,
                 Error.execution_error(
                   "Caught #{kind}: #{inspect(reason)}",
                   %{kind: kind, reason: reason, action: action, stacktrace: stacktrace}
                 )}
            end

          send(parent, {:done, ref, result})
        end)

      result =
        receive do
          {:done, ^ref, result} ->
            dbug("Received action result", action: action, result: result)
            cleanup_task_group(task_group)
            Process.demonitor(monitor_ref, [:flush])
            result

          {:DOWN, ^monitor_ref, :process, ^pid, :killed} ->
            dbug("Task was killed", action: action)
            cleanup_task_group(task_group)
            {:error, Error.execution_error("Task was killed")}

          {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
            dbug("Task exited unexpectedly", action: action, reason: reason)
            cleanup_task_group(task_group)
            {:error, Error.execution_error("Task exited: #{inspect(reason)}")}
        after
          timeout ->
            dbug("Action timed out", action: action, timeout: timeout)
            cleanup_task_group(task_group)
            Process.exit(pid, :kill)

            receive do
              {:DOWN, ^monitor_ref, :process, ^pid, _} -> :ok
            after
              0 -> :ok
            end

            {:error,
             Error.timeout_error(
               "Action #{inspect(action)} timed out after #{timeout}ms. This could be due to:
1. The action is taking too long to complete (current timeout: #{timeout}ms)
2. The action is stuck in an infinite loop
3. The action's return value doesn't match the expected format ({:ok, map()} | {:ok, map(), directive} | {:error, reason})
4. An unexpected error occurred without proper error handling
5. The action may be using unsafe IO operations (IO.inspect, etc).

Debug info:
- Action module: #{inspect(action)}
- Params: #{inspect(params)}
- Context: #{inspect(Map.delete(context, :__task_group__))}",
               %{
                 timeout: timeout,
                 action: action,
                 params: params,
                 context: Map.delete(context, :__task_group__)
               }
             )}
        end

      result
    end

    defp execute_action_with_timeout(action, params, context, _timeout, opts) do
      execute_action_with_timeout(action, params, context, get_default_timeout(), opts)
    end

    defp cleanup_task_group(task_group) do
      send(task_group, {:shutdown})

      Process.exit(task_group, :kill)

      Task.Supervisor.children(Jido.Action.TaskSupervisor)
      |> Enum.filter(fn pid ->
        case Process.info(pid, :group_leader) do
          {:group_leader, ^task_group} -> true
          _ -> false
        end
      end)
      |> Enum.each(&Process.exit(&1, :kill))
    end

    @spec execute_action(action(), params(), context(), run_opts()) :: exec_result
    defp execute_action(action, params, context, opts) do
      log_level = Keyword.get(opts, :log_level, :info)
      dbug("Executing action", action: action, params: params, context: context)

      cond_log(
        log_level,
        :debug,
        "Starting execution of #{inspect(action)}, params: #{inspect(params)}, context: #{inspect(context)}"
      )

      case action.run(params, context) do
        {:ok, result, other} ->
          dbug("Action succeeded with additional info", result: result, other: other)

          case validate_output(action, result, opts) do
            {:ok, validated_result} ->
              cond_log(
                log_level,
                :debug,
                "Finished execution of #{inspect(action)}, result: #{inspect(validated_result)}, directive: #{inspect(other)}"
              )

              {:ok, validated_result, other}

            {:error, validation_error} ->
              dbug("Action output validation failed", error: validation_error)

              cond_log(
                log_level,
                :error,
                "Action #{inspect(action)} output validation failed: #{inspect(validation_error)}"
              )

              {:error, validation_error, other}
          end

        {:ok, result} ->
          dbug("Action succeeded", result: result)

          case validate_output(action, result, opts) do
            {:ok, validated_result} ->
              cond_log(
                log_level,
                :debug,
                "Finished execution of #{inspect(action)}, result: #{inspect(validated_result)}"
              )

              {:ok, validated_result}

            {:error, validation_error} ->
              dbug("Action output validation failed", error: validation_error)

              cond_log(
                log_level,
                :error,
                "Action #{inspect(action)} output validation failed: #{inspect(validation_error)}"
              )

              {:error, validation_error}
          end

        {:error, reason, other} ->
          dbug("Action failed with additional info", error: reason, other: other)
          cond_log(log_level, :error, "Action #{inspect(action)} failed: #{inspect(reason)}")
          {:error, reason, other}

        {:error, %_{} = error} when is_exception(error) ->
          dbug("Action failed with error struct", error: error)
          cond_log(log_level, :error, "Action #{inspect(action)} failed: #{inspect(error)}")
          {:error, error}

        {:error, reason} ->
          dbug("Action failed with reason", reason: reason)
          cond_log(log_level, :error, "Action #{inspect(action)} failed: #{inspect(reason)}")
          {:error, Error.execution_error(reason)}

        result ->
          dbug("Action returned unexpected result", result: result)

          case validate_output(action, result, opts) do
            {:ok, validated_result} ->
              cond_log(
                log_level,
                :debug,
                "Finished execution of #{inspect(action)}, result: #{inspect(validated_result)}"
              )

              {:ok, validated_result}

            {:error, validation_error} ->
              dbug("Action output validation failed", error: validation_error)

              cond_log(
                log_level,
                :error,
                "Action #{inspect(action)} output validation failed: #{inspect(validation_error)}"
              )

              {:error, validation_error}
          end
      end
    rescue
      e in RuntimeError ->
        dbug("Runtime error in action", error: e)
        stacktrace = __STACKTRACE__
        log_level = Keyword.get(opts, :log_level, :info)
        cond_log(log_level, :error, "Action #{inspect(action)} failed: #{inspect(e)}")

        {:error,
         Error.execution_error(
           "Server error in #{inspect(action)}: #{extract_safe_error_message(e)}",
           %{original_exception: e, action: action, stacktrace: stacktrace}
         )}

      e in ArgumentError ->
        dbug("Argument error in action", error: e)
        stacktrace = __STACKTRACE__
        log_level = Keyword.get(opts, :log_level, :info)
        cond_log(log_level, :error, "Action #{inspect(action)} failed: #{inspect(e)}")

        {:error,
         Error.execution_error(
           "Argument error in #{inspect(action)}: #{extract_safe_error_message(e)}",
           %{original_exception: e, action: action, stacktrace: stacktrace}
         )}

      e ->
        stacktrace = __STACKTRACE__
        log_level = Keyword.get(opts, :log_level, :info)
        cond_log(log_level, :error, "Action #{inspect(action)} failed: #{inspect(e)}")

        {:error,
         Error.execution_error(
           "An unexpected error occurred during execution of #{inspect(action)}: #{inspect(e)}",
           %{original_exception: e, action: action, stacktrace: stacktrace}
         )}
    end
  end

  # Private helper to safely extract error messages, handling nil and nested cases
  defp extract_safe_error_message(error) do
    case error do
      %{message: %{message: inner_message}} when is_binary(inner_message) ->
        inner_message

      %{message: nil} ->
        ""

      %{message: message} when is_binary(message) ->
        message

      %{message: message} when is_struct(message) ->
        if Map.has_key?(message, :message) and is_binary(message.message) do
          message.message
        else
          inspect(message)
        end

      _ ->
        inspect(error)
    end
  end
end
