defmodule Kodo.Core.SessionTest do
  use ExUnit.Case, async: true

  alias Kodo.Core.Sessions.Session

  setup do
    session_id = "test_session_#{System.unique_integer()}"
    {:ok, session_pid} = Session.start_link(session_id)

    on_exit(fn ->
      if Process.alive?(session_pid) do
        GenServer.stop(session_pid)
      end
    end)

    {:ok, session_id: session_id, session_pid: session_pid}
  end

  describe "start_link/1" do
    test "starts a session with given ID" do
      session_id = "test_session_#{System.unique_integer()}"
      assert {:ok, pid} = Session.start_link(session_id)
      assert is_pid(pid)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  describe "eval/2" do
    test "evaluates simple expressions", %{session_pid: session_pid} do
      assert {:ok, 3} = Session.eval(session_pid, "1 + 2")
      assert {:ok, "hello"} = Session.eval(session_pid, "\"hello\"")
    end

    test "maintains variable bindings", %{session_pid: session_pid} do
      assert {:ok, 5} = Session.eval(session_pid, "x = 5")
      assert {:ok, 10} = Session.eval(session_pid, "x * 2")
    end

    test "returns error for invalid expressions", %{session_pid: session_pid} do
      assert {:error, _reason} = Session.eval(session_pid, "invalid_syntax +++")
    end

    test "handles complex expressions", %{session_pid: session_pid} do
      assert {:ok, [1, 2, 3]} = Session.eval(session_pid, "[1, 2, 3]")
      assert {:ok, %{a: 1}} = Session.eval(session_pid, "%{a: 1}")
    end
  end

  describe "history/1" do
    test "returns empty history initially", %{session_pid: session_pid} do
      assert [] = Session.history(session_pid)
    end

    test "tracks evaluation history", %{session_pid: session_pid} do
      Session.eval(session_pid, "1 + 1")
      Session.eval(session_pid, "2 + 2")

      history = Session.history(session_pid)
      assert length(history) == 2
      assert "1 + 1" in history
      assert "2 + 2" in history
    end

    test "maintains history order", %{session_pid: session_pid} do
      Session.eval(session_pid, "\"first\"")
      Session.eval(session_pid, "\"second\"")
      Session.eval(session_pid, "\"third\"")

      history = Session.history(session_pid)
      assert history == ["\"first\"", "\"second\"", "\"third\""]
    end
  end

  describe "env/1" do
    test "returns default environment", %{session_pid: session_pid} do
      env = Session.env(session_pid)
      assert is_map(env)
      assert Map.has_key?(env, "HOME")
      assert Map.has_key?(env, "PWD")
      assert Map.has_key?(env, "SHELL")
      assert env["SHELL"] == "kodo"
    end
  end

  describe "set_env/3" do
    test "sets environment variable", %{session_pid: session_pid} do
      assert :ok = Session.set_env(session_pid, "TEST_VAR", "test_value")

      env = Session.env(session_pid)
      assert env["TEST_VAR"] == "test_value"
    end

    test "overwrites existing environment variable", %{session_pid: session_pid} do
      Session.set_env(session_pid, "TEST_VAR", "old_value")
      Session.set_env(session_pid, "TEST_VAR", "new_value")

      env = Session.env(session_pid)
      assert env["TEST_VAR"] == "new_value"
    end
  end

  describe "get_env/2" do
    test "returns environment variable value", %{session_pid: session_pid} do
      Session.set_env(session_pid, "TEST_VAR", "test_value")
      assert {:ok, "test_value"} = Session.get_env(session_pid, "TEST_VAR")
    end

    test "returns error for non-existent variable", %{session_pid: session_pid} do
      assert :error = Session.get_env(session_pid, "NON_EXISTENT")
    end

    test "gets default environment variables", %{session_pid: session_pid} do
      assert {:ok, "kodo"} = Session.get_env(session_pid, "SHELL")
      assert {:ok, _home} = Session.get_env(session_pid, "HOME")
    end
  end

  describe "session state" do
    test "maintains independent state between sessions" do
      {:ok, session1} = Session.start_link("session1")
      {:ok, session2} = Session.start_link("session2")

      Session.eval(session1, "x = 1")
      Session.eval(session2, "x = 2")
      Session.set_env(session1, "VAR", "value1")
      Session.set_env(session2, "VAR", "value2")

      assert {:ok, 1} = Session.eval(session1, "x")
      assert {:ok, 2} = Session.eval(session2, "x")
      assert {:ok, "value1"} = Session.get_env(session1, "VAR")
      assert {:ok, "value2"} = Session.get_env(session2, "VAR")

      GenServer.stop(session1)
      GenServer.stop(session2)
    end
  end

  describe "error handling" do
    test "handles evaluation errors gracefully", %{session_pid: session_pid} do
      assert {:error, _} = Session.eval(session_pid, "raise \"test error\"")

      # Session should still be functional after error
      assert {:ok, 42} = Session.eval(session_pid, "42")
    end

    test "handles syntax errors", %{session_pid: session_pid} do
      assert {:error, _} = Session.eval(session_pid, "def invalid")

      # Session should still be functional after syntax error
      assert {:ok, "ok"} = Session.eval(session_pid, "\"ok\"")
    end
  end
end
