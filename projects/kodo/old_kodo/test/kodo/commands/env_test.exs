defmodule Kodo.Commands.EnvTest do
  use Kodo.Case, async: true

  alias Kodo.Commands.Env

  describe "env command behaviour implementation" do
    test "implements Kodo.Ports.Command behaviour" do
      behaviours = Env.__info__(:attributes)[:behaviour] || []
      assert Kodo.Ports.Command in behaviours
    end

    test "has required callback functions" do
      assert Env.name() == "env"
      assert is_binary(Env.description())
      assert is_binary(Env.usage())
      assert Env.meta() == [:builtin]
      assert function_exported?(Env, :execute, 2)
    end
  end

  describe "env command execution" do
    setup context do
      setup_session_with_commands(context)
    end

    test "displays all environment variables with no arguments", %{session_pid: session_pid} do
      assert {:ok, output} = exec_command(session_pid, "env")

      # Output should be non-empty and contain key=value pairs
      assert String.length(output) > 0
      lines = String.split(String.trim(output), "\n")
      assert length(lines) > 0

      # Each line should be in KEY=VALUE format
      for line <- lines do
        assert String.contains?(line, "=")
      end
    end

    test "gets existing environment variable", %{session_pid: session_pid} do
      # Set a variable first
      assert {:ok, _} = exec_command(session_pid, "env TEST_VAR=hello")

      # Then get it
      assert {:ok, output} = exec_command(session_pid, "env TEST_VAR")
      assert String.trim(output) == "hello"
    end

    test "gets non-existent environment variable", %{session_pid: session_pid} do
      assert {:error, reason} = exec_command(session_pid, "env NON_EXISTENT_VAR")
      assert String.contains?(reason, "not found")
    end

    test "sets environment variable with value", %{session_pid: session_pid} do
      assert {:ok, output} = exec_command(session_pid, "env NEW_VAR=test_value")
      assert String.trim(output) == "NEW_VAR=test_value"

      # Verify it was set by getting it back
      assert {:ok, get_output} = exec_command(session_pid, "env NEW_VAR")
      assert String.trim(get_output) == "test_value"
    end

    test "sets environment variable with empty value", %{session_pid: session_pid} do
      assert {:ok, output} = exec_command(session_pid, "env EMPTY_VAR=")
      assert String.trim(output) == "EMPTY_VAR="

      # Verify it was set with empty value
      assert {:ok, get_output} = exec_command(session_pid, "env EMPTY_VAR")
      assert String.trim(get_output) == ""
    end

    test "sets environment variable with spaces in value", %{session_pid: session_pid} do
      assert {:ok, output} = exec_command(session_pid, "env \"SPACE_VAR=hello world\"")
      assert String.trim(output) == "SPACE_VAR=hello world"

      # Verify it was set correctly
      assert {:ok, get_output} = exec_command(session_pid, "env SPACE_VAR")
      assert String.trim(get_output) == "hello world"
    end

    test "sets environment variable with special characters", %{session_pid: session_pid} do
      # Test with safe special characters that don't need escaping
      special_value = "test_value-123"
      assert {:ok, output} = exec_command(session_pid, "env SPECIAL_VAR=#{special_value}")
      assert String.trim(output) == "SPECIAL_VAR=#{special_value}"

      # Verify it was set correctly
      assert {:ok, get_output} = exec_command(session_pid, "env SPECIAL_VAR")
      assert String.trim(get_output) == special_value
    end

    test "sets environment variable with equals sign in value", %{session_pid: session_pid} do
      # Value contains = sign
      assert {:ok, output} = exec_command(session_pid, "env EQUALS_VAR=key=value")
      assert String.trim(output) == "EQUALS_VAR=key=value"

      # Verify it was set correctly
      assert {:ok, get_output} = exec_command(session_pid, "env EQUALS_VAR")
      assert String.trim(get_output) == "key=value"
    end

    test "overwrites existing environment variable", %{session_pid: session_pid} do
      # Set initial value
      assert {:ok, _} = exec_command(session_pid, "env OVERWRITE_VAR=original")
      assert {:ok, first_get} = exec_command(session_pid, "env OVERWRITE_VAR")
      assert String.trim(first_get) == "original"

      # Overwrite with new value
      assert {:ok, _} = exec_command(session_pid, "env OVERWRITE_VAR=updated")
      assert {:ok, second_get} = exec_command(session_pid, "env OVERWRITE_VAR")
      assert String.trim(second_get) == "updated"
    end

    test "environment variables persist across commands in same session", %{
      session_pid: session_pid
    } do
      # Set a variable
      assert {:ok, _} = exec_command(session_pid, "env PERSIST_VAR=persistent")

      # Run another command
      assert {:ok, _} = exec_command(session_pid, "pwd")

      # Variable should still exist
      assert {:ok, output} = exec_command(session_pid, "env PERSIST_VAR")
      assert String.trim(output) == "persistent"
    end

    test "env command shows sorted environment variables", %{session_pid: session_pid} do
      # Set multiple variables
      assert {:ok, _} = exec_command(session_pid, "env ZEBRA=last")
      assert {:ok, _} = exec_command(session_pid, "env ALPHA=first")
      assert {:ok, _} = exec_command(session_pid, "env BETA=middle")

      # Get all env vars
      assert {:ok, output} = exec_command(session_pid, "env")
      lines = String.split(String.trim(output), "\n")

      # Find our test variables
      test_lines =
        Enum.filter(lines, fn line ->
          String.starts_with?(line, "ALPHA=") or
            String.starts_with?(line, "BETA=") or
            String.starts_with?(line, "ZEBRA=")
        end)

      # Should be sorted alphabetically
      assert length(test_lines) == 3
      assert Enum.at(test_lines, 0) |> String.starts_with?("ALPHA=")
      assert Enum.at(test_lines, 1) |> String.starts_with?("BETA=")
      assert Enum.at(test_lines, 2) |> String.starts_with?("ZEBRA=")
    end

    test "returns usage error for multiple arguments", %{session_pid: session_pid} do
      assert {:error, reason} = exec_command(session_pid, "env arg1 arg2")
      assert String.contains?(reason, "Usage:")
      assert String.contains?(reason, "env [NAME[=VALUE]]")
    end

    test "handles variable names with numbers and underscores", %{session_pid: session_pid} do
      assert {:ok, _} = exec_command(session_pid, "env VAR_123=number_test")
      assert {:ok, output} = exec_command(session_pid, "env VAR_123")
      assert String.trim(output) == "number_test"
    end

    test "handles very long variable values", %{session_pid: session_pid} do
      long_value = String.duplicate("A", 1000)
      assert {:ok, _} = exec_command(session_pid, "env LONG_VAR=#{long_value}")
      assert {:ok, output} = exec_command(session_pid, "env LONG_VAR")
      assert String.trim(output) == long_value
    end
  end
end
