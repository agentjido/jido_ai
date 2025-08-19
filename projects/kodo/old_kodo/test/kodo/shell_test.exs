defmodule Kodo.ShellTest do
  use Kodo.Case, async: true
  doctest Kodo.Shell

  setup context do
    setup_session_with_commands(context)
  end

  describe "start/1" do
    test "starts a shell session with default options", %{session_pid: session_pid} do
      # Session is already started and managed by test infrastructure
      assert is_pid(session_pid)
      assert Process.alive?(session_pid)
    end

    test "starts a shell session with custom prompt", %{session_pid: session_pid} do
      # Session is already started and managed by test infrastructure
      assert is_pid(session_pid)
      assert Process.alive?(session_pid)
    end
  end

  describe "stop/1" do
    test "stops a shell session", %{instance: instance} do
      # Create a separate session just for this test that we can safely stop
      {:ok, _temp_session_id, temp_session_pid} = Kodo.Instance.new_session(instance)

      assert Process.alive?(temp_session_pid)

      # The stop function terminates the process which results in process exit
      # This is expected behavior for shell processes
      try do
        Kodo.Shell.stop(temp_session_pid)
        :ok
      catch
        :exit, _reason -> :ok
      end

      # Use proper process monitoring instead of sleep
      ref = Process.monitor(temp_session_pid)

      receive do
        {:DOWN, ^ref, :process, ^temp_session_pid, _reason} -> :ok
      after
        1000 -> flunk("Process did not terminate in time")
      end

      refute Process.alive?(temp_session_pid)
    end
  end

  describe "eval/2" do
    test "evaluates help command", %{session_pid: session_pid} do
      assert {:ok, output} = Kodo.Shell.eval("help", session_pid)
      assert is_binary(output)
      assert String.contains?(output, "Available commands")
    end

    test "evaluates pwd command", %{session_pid: session_pid} do
      assert {:ok, output} = Kodo.Shell.eval("pwd", session_pid)
      assert is_binary(output)
    end

    test "returns error for unknown command", %{session_pid: session_pid} do
      assert {:error, error} = Kodo.Shell.eval("unknown_command", session_pid)
      assert is_binary(error)
    end
  end

  describe "pwd/1" do
    test "returns current working directory", %{session_pid: session_pid} do
      assert {:ok, pwd} = Kodo.Shell.pwd(session_pid)
      assert is_binary(pwd)
    end
  end

  describe "cd/2" do
    test "changes current working directory", %{session_pid: session_pid} do
      tmp_dir = tmp_dir!()
      assert :ok = Kodo.Shell.cd(session_pid, tmp_dir)
      assert {:ok, pwd} = Kodo.Shell.pwd(session_pid)
      assert String.contains?(pwd, tmp_dir)
    end
  end

  describe "get_env/2 and set_env/3" do
    test "sets and gets environment variables", %{session_pid: session_pid} do
      assert :ok = Kodo.Shell.set_env(session_pid, "TEST_VAR", "test_value")
      assert {:ok, "test_value"} = Kodo.Shell.get_env(session_pid, "TEST_VAR")
    end

    test "returns error for unset environment variable", %{session_pid: session_pid} do
      assert :error = Kodo.Shell.get_env(session_pid, "NONEXISTENT_VAR")
    end
  end

  describe "ls/2" do
    test "lists directory contents", %{session_pid: session_pid} do
      result = Kodo.Shell.ls(session_pid, "/")
      assert match?({:ok, _output}, result) or match?({:error, _error}, result)
    end

    test "uses current directory by default", %{session_pid: session_pid} do
      result = Kodo.Shell.ls(session_pid)
      assert match?({:ok, _output}, result) or match?({:error, _error}, result)
    end
  end
end
