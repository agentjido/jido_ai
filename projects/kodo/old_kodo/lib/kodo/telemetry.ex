defmodule Kodo.Telemetry do
  @moduledoc """
  Telemetry events for Kodo shell operations.
  """

  require Logger

  @doc """
  Executes telemetry events for command execution.
  """
  def execute_command(command_name, start_time) do
    :telemetry.execute(
      [:kodo, :command, :execute],
      %{duration: System.monotonic_time() - start_time},
      %{command: command_name}
    )
  end

  @doc """
  Executes telemetry events for session lifecycle.
  """
  def session_event(event_type, session_id, metadata \\ %{}) do
    :telemetry.execute(
      [:kodo, :session, event_type],
      %{timestamp: System.system_time()},
      Map.merge(%{session_id: session_id}, metadata)
    )
  end

  @doc """
  Executes telemetry events for filesystem operations.
  """
  def filesystem_operation(operation, path, start_time, metadata \\ %{}) do
    :telemetry.execute(
      [:kodo, :filesystem, operation],
      %{duration: System.monotonic_time() - start_time},
      Map.merge(%{path: path}, metadata)
    )
  end

  @doc """
  Executes telemetry events for error tracking.
  """
  def error_event(error_type, error_message, metadata \\ %{}) do
    :telemetry.execute(
      [:kodo, :error, error_type],
      %{timestamp: System.system_time()},
      Map.merge(%{message: error_message}, metadata)
    )
  end

  @doc """
  Attaches default telemetry handlers for logging.
  """
  def attach_default_handlers do
    :telemetry.attach(
      "kodo-command-handler",
      [:kodo, :command, :execute],
      &__MODULE__.handle_command_event/4,
      nil
    )

    :telemetry.attach(
      "kodo-session-handler",
      [:kodo, :session, :*],
      &__MODULE__.handle_session_event/4,
      nil
    )

    :telemetry.attach(
      "kodo-filesystem-handler",
      [:kodo, :filesystem, :*],
      &__MODULE__.handle_filesystem_event/4,
      nil
    )

    :telemetry.attach(
      "kodo-error-handler",
      [:kodo, :error, :*],
      &__MODULE__.handle_error_event/4,
      nil
    )
  end

  # Event Handlers

  @doc false
  def handle_command_event([:kodo, :command, :execute], measurements, metadata, _config) do
    Logger.debug("Command executed",
      command: metadata.command,
      duration_native: measurements.duration
    )
  end

  @doc false
  def handle_session_event([:kodo, :session, event_type], measurements, metadata, _config) do
    Logger.info("Session event",
      event_type: event_type,
      session_id: metadata.session_id,
      timestamp: measurements.timestamp
    )
  end

  @doc false
  def handle_filesystem_event([:kodo, :filesystem, operation], measurements, metadata, _config) do
    Logger.debug("Filesystem operation",
      operation: operation,
      path: metadata.path,
      duration_native: measurements.duration
    )
  end

  @doc false
  def handle_error_event([:kodo, :error, error_type], measurements, metadata, _config) do
    Logger.warning("Error occurred",
      error_type: error_type,
      message: metadata.message,
      timestamp: measurements.timestamp
    )
  end
end
