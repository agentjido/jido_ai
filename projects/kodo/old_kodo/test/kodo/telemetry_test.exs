defmodule Kodo.TelemetryTest do
  use ExUnit.Case, async: false

  alias Kodo.Telemetry

  describe "telemetry event emission" do
    setup do
      # Use Agent to collect telemetry events
      {:ok, events_agent} = Agent.start_link(fn -> [] end)

      # Attach handler to capture all Kodo telemetry events
      handler_id = "test-telemetry-handler-#{System.unique_integer()}"

      :telemetry.attach_many(
        handler_id,
        [
          [:kodo, :command, :execute],
          [:kodo, :session, :started],
          [:kodo, :session, :terminated],
          [:kodo, :filesystem, :read],
          [:kodo, :filesystem, :write],
          [:kodo, :error, :command_failed],
          [:kodo, :error, :not_found]
        ],
        fn event, measurements, metadata, config ->
          Agent.update(config, &[{event, measurements, metadata} | &1])
        end,
        events_agent
      )

      on_exit(fn ->
        try do
          :telemetry.detach(handler_id)
        catch
          _ -> :ok
        end

        if Process.alive?(events_agent) do
          Agent.stop(events_agent)
        end
      end)

      {:ok, events_agent: events_agent, handler_id: handler_id}
    end

    test "execute_command/2 emits correct event", %{events_agent: agent} do
      start_time = System.monotonic_time()

      Telemetry.execute_command("test_command", start_time)

      events = Agent.get(agent, & &1)
      assert length(events) == 1

      {event, measurements, metadata} = List.first(events)

      assert event == [:kodo, :command, :execute]
      assert Map.has_key?(measurements, :duration)
      assert measurements.duration >= 0
      assert metadata.command == "test_command"
    end

    test "session_event/3 emits correct event", %{events_agent: agent} do
      session_id = "test_session_123"

      Telemetry.session_event(:started, session_id)

      events = Agent.get(agent, & &1)
      assert length(events) == 1

      {event, measurements, metadata} = List.first(events)

      assert event == [:kodo, :session, :started]
      assert Map.has_key?(measurements, :timestamp)
      assert measurements.timestamp > 0
      assert metadata.session_id == session_id
    end

    test "session_event/3 with additional metadata", %{events_agent: agent} do
      session_id = "test_session_456"
      extra_metadata = %{user: "test_user", reason: "timeout"}

      Telemetry.session_event(:terminated, session_id, extra_metadata)

      events = Agent.get(agent, & &1)
      assert length(events) == 1

      {event, _measurements, metadata} = List.first(events)

      assert event == [:kodo, :session, :terminated]
      assert metadata.session_id == session_id
      assert metadata.user == "test_user"
      assert metadata.reason == "timeout"
    end

    test "filesystem_operation/4 emits correct event", %{events_agent: agent} do
      start_time = System.monotonic_time()
      path = "/test/path"

      Telemetry.filesystem_operation(:read, path, start_time)

      events = Agent.get(agent, & &1)
      assert length(events) == 1

      {event, measurements, metadata} = List.first(events)

      assert event == [:kodo, :filesystem, :read]
      assert Map.has_key?(measurements, :duration)
      assert measurements.duration >= 0
      assert metadata.path == path
    end

    test "filesystem_operation/4 with additional metadata", %{events_agent: agent} do
      start_time = System.monotonic_time()
      path = "/test/path"
      extra_metadata = %{size: 1024, type: "file"}

      Telemetry.filesystem_operation(:write, path, start_time, extra_metadata)

      events = Agent.get(agent, & &1)
      assert length(events) == 1

      {event, _measurements, metadata} = List.first(events)

      assert event == [:kodo, :filesystem, :write]
      assert metadata.path == path
      assert metadata.size == 1024
      assert metadata.type == "file"
    end

    test "error_event/3 emits correct event", %{events_agent: agent} do
      error_message = "Something went wrong"

      Telemetry.error_event(:command_failed, error_message)

      events = Agent.get(agent, & &1)
      assert length(events) == 1

      {event, measurements, metadata} = List.first(events)

      assert event == [:kodo, :error, :command_failed]
      assert Map.has_key?(measurements, :timestamp)
      assert measurements.timestamp > 0
      assert metadata.message == error_message
    end

    test "error_event/3 with additional metadata", %{events_agent: agent} do
      error_message = "Filesystem error"
      extra_metadata = %{path: "/invalid/path", code: 404}

      Telemetry.error_event(:not_found, error_message, extra_metadata)

      events = Agent.get(agent, & &1)
      assert length(events) == 1

      {event, _measurements, metadata} = List.first(events)

      assert event == [:kodo, :error, :not_found]
      assert metadata.message == error_message
      assert metadata.path == "/invalid/path"
      assert metadata.code == 404
    end
  end

  describe "attach_default_handlers/0" do
    test "registers all expected handlers" do
      # Clean up any existing handlers first
      for handler_id <- [
            "kodo-command-handler",
            "kodo-session-handler",
            "kodo-filesystem-handler",
            "kodo-error-handler"
          ] do
        try do
          :telemetry.detach(handler_id)
        catch
          _ -> :ok
        end
      end

      # Attach default handlers
      Telemetry.attach_default_handlers()

      # Get handlers after attaching
      final_handlers = :telemetry.list_handlers([])

      # Verify specific handlers are registered
      handler_ids = Enum.map(final_handlers, & &1.id)

      assert "kodo-command-handler" in handler_ids
      assert "kodo-session-handler" in handler_ids
      assert "kodo-filesystem-handler" in handler_ids
      assert "kodo-error-handler" in handler_ids

      # Clean up - detach handlers
      :telemetry.detach("kodo-command-handler")
      :telemetry.detach("kodo-session-handler")
      :telemetry.detach("kodo-filesystem-handler")
      :telemetry.detach("kodo-error-handler")
    end

    test "calling attach_default_handlers twice is idempotent or raises error" do
      # Clean up any existing handlers first
      for handler_id <- [
            "kodo-command-handler",
            "kodo-session-handler",
            "kodo-filesystem-handler",
            "kodo-error-handler"
          ] do
        try do
          :telemetry.detach(handler_id)
        catch
          _ -> :ok
        end
      end

      # First call should succeed
      Telemetry.attach_default_handlers()

      # Second call should either be idempotent or raise an error
      try do
        Telemetry.attach_default_handlers()
        # If no error, that's fine - it's idempotent
        :ok
      rescue
        _ ->
          # If error, that's also fine - duplicate prevention
          :ok
      end

      # Clean up
      :telemetry.detach("kodo-command-handler")
      :telemetry.detach("kodo-session-handler")
      :telemetry.detach("kodo-filesystem-handler")
      :telemetry.detach("kodo-error-handler")
    end
  end

  describe "default event handlers" do
    setup do
      # Set logger level to capture all messages for testing
      original_level = Logger.level()
      Logger.configure(level: :debug)

      on_exit(fn ->
        Logger.configure(level: original_level)
      end)

      :ok
    end

    test "handle_command_event/4 logs debug message" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          Telemetry.handle_command_event(
            [:kodo, :command, :execute],
            %{duration: 1000},
            %{command: "test_cmd"},
            nil
          )
        end)

      assert log =~ "Command executed"
    end

    test "handle_session_event/4 logs info message" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          Telemetry.handle_session_event(
            [:kodo, :session, :started],
            %{timestamp: 123_456_789},
            %{session_id: "session_123"},
            nil
          )
        end)

      assert log =~ "Session event"
    end

    test "handle_filesystem_event/4 logs debug message" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          Telemetry.handle_filesystem_event(
            [:kodo, :filesystem, :read],
            %{duration: 500},
            %{path: "/test/file"},
            nil
          )
        end)

      assert log =~ "Filesystem operation"
    end

    test "handle_error_event/4 logs warning message" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          Telemetry.handle_error_event(
            [:kodo, :error, :command_failed],
            %{timestamp: 987_654_321},
            %{message: "Command execution failed"},
            nil
          )
        end)

      assert log =~ "Error occurred"
    end
  end
end
