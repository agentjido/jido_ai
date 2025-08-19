defmodule Kodo.Ports.ProcessExecutorTest do
  use Kodo.Case, async: true

  alias Kodo.Ports.ProcessExecutor

  # Create a simple test executor for testing the helper functions
  defmodule TestExecutor do
    @behaviour Kodo.Ports.ProcessExecutor

    def execute("echo", ["hello"], _options) do
      {:ok, "hello\n", 0}
    end

    def execute("false", [], _options) do
      {:ok, "", 1}
    end

    def execute("timeout_cmd", [], %{timeout: timeout}) when timeout < 100 do
      {:error, :timeout}
    end

    def execute("error_cmd", [], _options) do
      {:error, :command_not_found}
    end

    def execute(_command, _args, _options) do
      {:ok, "default output", 0}
    end

    def execute_async(_command, _args, _options) do
      {:ok, self()}
    end

    def wait_for(_pid, _timeout) do
      {:ok, "async output", 0}
    end

    def get_status(_pid) do
      {:running, self()}
    end

    def kill(_pid, _signal) do
      :ok
    end

    def can_execute?("echo"), do: true
    def can_execute?("false"), do: true
    def can_execute?(_), do: false

    def info do
      %{
        type: :test,
        features: [:test_execution],
        platform: :test,
        version: "1.0.0"
      }
    end
  end

  describe "ProcessExecutor helper functions" do
    test "execute_for_output/4 returns only output on success" do
      assert {:ok, "hello\n"} =
               ProcessExecutor.execute_for_output(TestExecutor, "echo", ["hello"])
    end

    test "execute_for_output/4 returns error on command failure" do
      assert {:error, :command_not_found} =
               ProcessExecutor.execute_for_output(TestExecutor, "error_cmd", [])
    end

    test "execute_for_output/4 still returns output even with non-zero exit code" do
      assert {:ok, ""} = ProcessExecutor.execute_for_output(TestExecutor, "false", [])
    end

    test "execute_for_success/4 returns :ok for successful commands" do
      assert :ok = ProcessExecutor.execute_for_success(TestExecutor, "echo", ["hello"])
    end

    test "execute_for_success/4 returns error tuple for failed commands" do
      assert {:error, {"", 1}} = ProcessExecutor.execute_for_success(TestExecutor, "false", [])
    end

    test "execute_for_success/4 returns error for command not found" do
      assert {:error, :command_not_found} =
               ProcessExecutor.execute_for_success(TestExecutor, "error_cmd", [])
    end

    test "execute_with_timeout/5 passes timeout to options" do
      assert {:error, :timeout} =
               ProcessExecutor.execute_with_timeout(TestExecutor, "timeout_cmd", [], 50)
    end

    test "execute_with_timeout/5 works normally when no timeout" do
      assert {:ok, "hello\n", 0} =
               ProcessExecutor.execute_with_timeout(TestExecutor, "echo", ["hello"], 5000)
    end

    test "helper functions work with default options" do
      assert {:ok, "default output"} =
               ProcessExecutor.execute_for_output(TestExecutor, "unknown", [])

      assert :ok = ProcessExecutor.execute_for_success(TestExecutor, "unknown", [])
    end
  end

  describe "ProcessExecutor behaviour documentation" do
    test "behaviour defines all required callbacks" do
      assert function_exported?(TestExecutor, :execute, 3)
      assert function_exported?(TestExecutor, :execute_async, 3)
      assert function_exported?(TestExecutor, :wait_for, 2)
      assert function_exported?(TestExecutor, :get_status, 1)
      assert function_exported?(TestExecutor, :kill, 2)
      assert function_exported?(TestExecutor, :can_execute?, 1)
      assert function_exported?(TestExecutor, :info, 0)
    end

    test "test executor implements all behavior methods" do
      # Test basic execution
      assert {:ok, "hello\n", 0} = TestExecutor.execute("echo", ["hello"], %{})

      # Test async execution
      assert {:ok, pid} = TestExecutor.execute_async("test", [], %{})
      assert is_pid(pid)

      # Test wait_for
      assert {:ok, "async output", 0} = TestExecutor.wait_for(pid, 1000)

      # Test get_status
      assert {:running, _pid} = TestExecutor.get_status(pid)

      # Test kill
      assert :ok = TestExecutor.kill(pid, :term)

      # Test can_execute?
      assert TestExecutor.can_execute?("echo") == true
      assert TestExecutor.can_execute?("nonexistent") == false

      # Test info
      info = TestExecutor.info()
      assert is_map(info)
      assert info.type == :test
    end
  end
end
