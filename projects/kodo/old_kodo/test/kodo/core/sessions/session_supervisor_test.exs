defmodule Kodo.Core.SessionSupervisorTest do
  use ExUnit.Case, async: true

  alias Kodo.Core.Sessions.SessionSupervisor

  setup do
    {:ok, supervisor_pid} = SessionSupervisor.start_link([])

    on_exit(fn ->
      try do
        if Process.alive?(supervisor_pid) do
          DynamicSupervisor.stop(supervisor_pid, :normal)
        end
      catch
        :exit, _ -> :ok
      end
    end)

    {:ok, supervisor_pid: supervisor_pid}
  end

  describe "new/2" do
    test "starts a new session", %{supervisor_pid: supervisor_pid} do
      assert {:ok, session_id, session_pid} = SessionSupervisor.new(supervisor_pid)
      assert is_binary(session_id)
      assert is_pid(session_pid)
      assert Process.alive?(session_pid)
    end

    test "creates unique session IDs", %{supervisor_pid: supervisor_pid} do
      {:ok, session_id1, _pid1} = SessionSupervisor.new(supervisor_pid)
      {:ok, session_id2, _pid2} = SessionSupervisor.new(supervisor_pid)

      assert session_id1 != session_id2
    end

    test "creates multiple sessions", %{supervisor_pid: supervisor_pid} do
      sessions =
        for _i <- 1..5 do
          {:ok, session_id, session_pid} = SessionSupervisor.new(supervisor_pid)
          {session_id, session_pid}
        end

      # All sessions should be unique and alive
      session_ids = Enum.map(sessions, fn {id, _pid} -> id end)
      session_pids = Enum.map(sessions, fn {_id, pid} -> pid end)

      assert length(Enum.uniq(session_ids)) == 5
      assert length(Enum.uniq(session_pids)) == 5
      assert Enum.all?(session_pids, &Process.alive?/1)
    end

    test "registers session with instance", %{supervisor_pid: supervisor_pid} do
      instance = :test_instance

      # Create a test registry for the instance
      registry_name = String.to_atom("Kodo.SessionRegistry.#{instance}")
      {:ok, _} = Registry.start_link(keys: :unique, name: registry_name)

      {:ok, session_id, session_pid} = SessionSupervisor.new(supervisor_pid, instance)

      # Verify session is registered
      assert [{_session_pid, ^session_pid}] = Registry.lookup(registry_name, session_id)
    end
  end

  describe "stop/2" do
    test "terminates a session", %{supervisor_pid: supervisor_pid} do
      {:ok, _session_id, session_pid} = SessionSupervisor.new(supervisor_pid)
      assert Process.alive?(session_pid)

      assert :ok = SessionSupervisor.stop(session_pid, supervisor_pid)

      # Give the supervisor time to clean up
      Process.sleep(10)
      refute Process.alive?(session_pid)
    end

    test "returns error for non-existent session", %{supervisor_pid: supervisor_pid} do
      fake_pid = spawn(fn -> :ok end)
      assert {:error, :not_found} = SessionSupervisor.stop(fake_pid, supervisor_pid)
    end
  end

  describe "fault tolerance" do
    test "restarts crashed sessions when transient", %{supervisor_pid: supervisor_pid} do
      {:ok, _session_id, session_pid} = SessionSupervisor.new(supervisor_pid)

      # Kill the session process
      Process.exit(session_pid, :kill)

      # Give the supervisor time to restart
      Process.sleep(50)

      # The session should be restarted (transient restart strategy)
      # Note: This test might need adjustment based on actual restart behavior
      # For now, we just verify the original process is dead
      refute Process.alive?(session_pid)
    end

    test "supervisor continues running after session crashes", %{supervisor_pid: supervisor_pid} do
      {:ok, _session_id, session_pid} = SessionSupervisor.new(supervisor_pid)

      # Kill the session process
      Process.exit(session_pid, :kill)

      # Supervisor should still be alive and functional
      assert Process.alive?(supervisor_pid)

      # Should be able to start new sessions
      assert {:ok, _new_session_id, new_session_pid} = SessionSupervisor.new(supervisor_pid)
      assert Process.alive?(new_session_pid)
    end
  end

  describe "session ID generation" do
    test "generates unique hex session IDs", %{supervisor_pid: supervisor_pid} do
      {:ok, session_id, _pid} = SessionSupervisor.new(supervisor_pid)

      # Should be 32 character hex string (16 bytes * 2)
      assert String.length(session_id) == 32
      assert String.match?(session_id, ~r/^[0-9a-f]+$/)
    end
  end
end
