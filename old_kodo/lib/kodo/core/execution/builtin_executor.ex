defmodule Kodo.Core.Execution.BuiltinExecutor do
  @moduledoc """
  Executor for built-in Kodo commands registered in the CommandRegistry.
  """
  require Logger

  @spec execute(module(), Kodo.Ports.Command.args(), Kodo.Ports.Command.context()) ::
          Kodo.Ports.Command.result()
  def execute(module, args, context) do
    try do
      case module.execute(args, context) do
        {:ok, output, %{session_updates: updates}} ->
          # Apply session updates
          apply_session_updates(context.session_pid, updates)
          {:ok, output}

        result ->
          result
      end
    rescue
      e in [ArgumentError] ->
        message = "Invalid arguments: #{Exception.message(e)}"

        Kodo.Telemetry.error_event(:invalid_arguments, message, %{
          command: module.name(),
          args: args
        })

        {:error, message}

      e in [File.Error] ->
        message = "File operation failed: #{Exception.message(e)}"

        Kodo.Telemetry.error_event(:file_error, message, %{
          command: module.name(),
          args: args
        })

        {:error, message}

      e ->
        message = Exception.message(e)
        stacktrace = Exception.format_stacktrace(__STACKTRACE__)

        Logger.error("Builtin command execution failed",
          command: module.name(),
          args: args,
          error: inspect(e),
          stacktrace: stacktrace
        )

        Kodo.Telemetry.error_event(:command_error, message, %{
          command: module.name(),
          args: args,
          stacktrace: stacktrace
        })

        {:error, "Command failed: #{message}"}
    end
  end

  @spec can_execute?(String.t()) :: boolean()
  def can_execute?(cmd_name) do
    case Kodo.Core.Commands.CommandRegistry.get_command(cmd_name) do
      {:ok, module} -> :builtin in module.meta()
      :error -> false
    end
  end

  # Private helper to apply session updates
  defp apply_session_updates(session_pid, %{set_env: env_updates}) do
    Enum.each(env_updates, fn {name, value} ->
      Kodo.Core.Sessions.Session.set_env(session_pid, name, value)
    end)
  end

  defp apply_session_updates(_session_pid, _updates) do
    # Handle other types of updates in the future
    :ok
  end
end
