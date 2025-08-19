defmodule Kodo.Commands.HelpTest do
  use Kodo.Case, async: true

  alias Kodo.Commands.Help

  describe "help command behaviour implementation" do
    test "implements Kodo.Ports.Command behaviour" do
      behaviours = Help.__info__(:attributes)[:behaviour] || []
      assert Kodo.Ports.Command in behaviours
    end

    test "has required callback functions" do
      assert Help.name() == "help"
      assert is_binary(Help.description())
      assert is_binary(Help.usage())
      assert Help.meta() == [:builtin, :pure]
      assert function_exported?(Help, :execute, 2)
    end

    test "is marked as pure command" do
      assert :pure in Help.meta()
    end
  end

  describe "help command execution" do
    setup context do
      setup_session_with_commands(context)
    end

    test "shows general help with no arguments", %{session_pid: session_pid} do
      assert {:ok, output} = exec_command(session_pid, "help")

      # Should contain header
      assert String.contains?(output, "Available commands:")

      # Should list basic commands that were registered
      assert String.contains?(output, "help")
      assert String.contains?(output, "cd")
      assert String.contains?(output, "pwd")
      assert String.contains?(output, "ls")
      assert String.contains?(output, "env")

      # Should be formatted with descriptions
      lines = String.split(String.trim(output), "\n")
      assert length(lines) > 1

      # Each command line should have proper formatting (name padded, followed by description)
      # Skip header
      command_lines = Enum.drop(lines, 1)

      for line <- command_lines do
        # Each line should have at least 10 characters for the padded command name
        assert String.length(line) >= 10
        # Should contain some description text after the command name
        assert String.match?(line, ~r/^\s*\w+\s+.+/)
      end
    end

    test "shows help for specific valid command", %{session_pid: session_pid} do
      assert {:ok, output} = exec_command(session_pid, "help cd")

      # Should contain command name and description
      assert String.contains?(output, "cd")
      assert String.contains?(output, "Change")

      # Should contain usage information
      assert String.contains?(output, "Usage:")

      # Should be formatted properly with name, description, and usage
      lines = String.split(String.trim(output), "\n")
      # name-description line, empty line, usage line
      assert length(lines) >= 3
    end

    test "shows help for help command itself", %{session_pid: session_pid} do
      assert {:ok, output} = exec_command(session_pid, "help help")

      assert String.contains?(output, "help")
      assert String.contains?(output, "Display help information")
      assert String.contains?(output, "Usage:")
      assert String.contains?(output, "help [command]")
    end

    test "shows help for env command", %{session_pid: session_pid} do
      assert {:ok, output} = exec_command(session_pid, "help env")

      assert String.contains?(output, "env")
      assert String.contains?(output, "environment")
      assert String.contains?(output, "Usage:")
    end

    test "shows help for pwd command", %{session_pid: session_pid} do
      assert {:ok, output} = exec_command(session_pid, "help pwd")

      assert String.contains?(output, "pwd")
      assert String.contains?(output, "working directory")
      assert String.contains?(output, "Usage:")
    end

    test "shows help for ls command", %{session_pid: session_pid} do
      assert {:ok, output} = exec_command(session_pid, "help ls")

      assert String.contains?(output, "ls")
      assert String.contains?(output, "Usage:")
    end

    test "handles invalid command name", %{session_pid: session_pid} do
      assert {:error, reason} = exec_command(session_pid, "help nonexistent")

      assert String.contains?(reason, "No help available")
      assert String.contains?(reason, "nonexistent")
      assert String.contains?(reason, "Command not found")
    end

    test "handles command name with special characters", %{session_pid: session_pid} do
      assert {:error, reason} = exec_command(session_pid, "help \"@#$%\"")

      assert String.contains?(reason, "No help available")
      assert String.contains?(reason, "@#$%")
      assert String.contains?(reason, "Command not found")
    end

    test "handles empty string as command name", %{session_pid: session_pid} do
      assert {:error, reason} = exec_command(session_pid, "help \"\"")

      assert String.contains?(reason, "No help available")
      assert String.contains?(reason, "Command not found")
    end

    test "returns usage error for multiple arguments", %{session_pid: session_pid} do
      assert {:error, reason} = exec_command(session_pid, "help cmd1 cmd2")

      assert String.contains?(reason, "Usage:")
      assert String.contains?(reason, "help [command]")
    end

    test "returns usage error for three or more arguments", %{session_pid: session_pid} do
      assert {:error, reason} = exec_command(session_pid, "help cmd1 cmd2 cmd3")

      assert String.contains?(reason, "Usage:")
      assert String.contains?(reason, "help [command]")
    end

    test "commands are listed in alphabetical order", %{session_pid: session_pid} do
      assert {:ok, output} = exec_command(session_pid, "help")

      lines = String.split(String.trim(output), "\n")
      # Skip "Available commands:" header
      command_lines = Enum.drop(lines, 1)

      # Extract command names (first word of each line, trimmed)
      command_names =
        command_lines
        |> Enum.map(fn line ->
          line
          |> String.trim()
          |> String.split(" ", parts: 2)
          |> List.first()
        end)
        |> Enum.filter(fn name -> name != nil and String.length(name) > 0 end)

      # Should be sorted alphabetically
      sorted_names = Enum.sort(command_names)
      assert command_names == sorted_names
    end

    test "help output formatting is consistent", %{session_pid: session_pid} do
      assert {:ok, output} = exec_command(session_pid, "help")

      lines = String.split(String.trim(output), "\n")
      # Skip header
      command_lines = Enum.drop(lines, 1)

      # Each command line should follow the same format: "  command_name    description"
      for line <- command_lines do
        # Should start with spaces for indentation
        assert String.starts_with?(line, "  ")

        # Should have command name followed by spaces, then description
        trimmed = String.trim_leading(line)
        parts = String.split(trimmed, ~r/\s+/, parts: 2)
        assert length(parts) == 2

        [command_name, description] = parts
        # Command name should not be empty
        assert String.length(command_name) > 0
        # Description should not be empty
        assert String.length(description) > 0
      end
    end

    test "specific command help includes all required sections", %{session_pid: session_pid} do
      assert {:ok, output} = exec_command(session_pid, "help cd")

      # Should have command name and description on first line
      lines = String.split(String.trim(output), "\n")
      assert length(lines) >= 3

      first_line = Enum.at(lines, 0)
      assert String.contains?(first_line, "cd")
      # separator between name and description
      assert String.contains?(first_line, "-")

      # Should have empty line separator
      assert Enum.at(lines, 1) == ""

      # Should have usage section
      usage_line = Enum.at(lines, 2)
      assert String.starts_with?(usage_line, "Usage:")
    end

    test "help works with case sensitivity", %{session_pid: session_pid} do
      # Lowercase should work
      assert {:ok, _output} = exec_command(session_pid, "help cd")

      # Uppercase should fail (commands are case sensitive)
      assert {:error, reason} = exec_command(session_pid, "help CD")
      assert String.contains?(reason, "No help available")
      assert String.contains?(reason, "CD")
    end
  end
end
