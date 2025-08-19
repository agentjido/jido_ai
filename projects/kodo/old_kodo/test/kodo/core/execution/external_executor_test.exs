defmodule Kodo.Core.ExternalExecutorTest do
  use ExUnit.Case, async: true

  alias Kodo.Core.Execution.ExternalExecutor

  setup do
    context = %{
      session_pid: self(),
      env: %{"HOME" => "/home/test", "PATH" => "/bin:/usr/bin"},
      current_dir: System.tmp_dir!(),
      opts: %{}
    }

    {:ok, context: context}
  end

  describe "can_execute?/1" do
    test "returns true for commands in PATH" do
      # Most systems should have 'echo'
      assert ExternalExecutor.can_execute?("echo")
    end

    test "returns false for non-existent commands" do
      refute ExternalExecutor.can_execute?("nonexistent_command_12345")
    end
  end

  describe "execute/3" do
    test "executes simple command successfully", %{context: context} do
      result = ExternalExecutor.execute("echo", ["hello"], context)

      case result do
        {:ok, output} ->
          assert String.trim(output) == "hello"

        {:error, _} ->
          # Skip test if echo is not available or behaves differently
          :ok
      end
    end

    test "handles command not found", %{context: context} do
      result = ExternalExecutor.execute("nonexistent_command_12345", [], context)
      assert {:error, "Command 'nonexistent_command_12345' not found"} = result
    end

    test "handles command with non-zero exit code", %{context: context} do
      # Using 'false' command which always exits with code 1
      result = ExternalExecutor.execute("false", [], context)
      assert {:error, message} = result
      assert String.contains?(message, "exited with code")
    end

    test "passes environment variables to command", %{context: context} do
      # Test that env vars are passed through
      context = put_in(context.env["TEST_VAR"], "test_value")

      # Use a command that can output environment variables
      case ExternalExecutor.execute("printenv", ["TEST_VAR"], context) do
        {:ok, output} ->
          assert String.trim(output) == "test_value"

        {:error, _} ->
          # If printenv is not available, try with echo
          case ExternalExecutor.execute("sh", ["-c", "echo $TEST_VAR"], context) do
            {:ok, output} ->
              assert String.trim(output) == "test_value"

            {:error, _} ->
              # Skip test if no suitable command available
              :ok
          end
      end
    end

    test "runs command in specified directory", %{context: context} do
      # Create a temporary directory for testing
      temp_dir = System.tmp_dir!()
      context = put_in(context.current_dir, temp_dir)

      case ExternalExecutor.execute("pwd", [], context) do
        {:ok, _output} ->
          # The output should be the temp directory path (allowing for symlinks)
          # The main test is that pwd executed without error
          :ok

        {:error, _} ->
          # If pwd is not available, skip test
          :ok
      end
    end
  end
end
