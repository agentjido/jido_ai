defmodule Kodo.Commands.LsTest do
  use Kodo.Case, async: true

  alias Kodo.Commands.Ls

  describe "ls command" do
    setup context do
      setup_session_with_commands(context)
    end

    test "lists current directory contents", %{session_pid: session_pid} do
      # Create a temporary directory with some files
      tmp_dir = tmp_dir!()
      File.write!(Path.join(tmp_dir, "file1.txt"), "content")
      File.write!(Path.join(tmp_dir, "file2.txt"), "content")
      File.mkdir!(Path.join(tmp_dir, "subdir"))

      # Change to the temp directory
      assert {:ok, _} = exec_command(session_pid, "cd #{tmp_dir}")

      # List directory contents
      assert {:ok, output} = exec_command(session_pid, "ls")

      # Verify output contains our files
      assert output =~ "file1.txt"
      assert output =~ "file2.txt"
      assert output =~ "subdir"
    end

    test "handles empty directory", %{session_pid: session_pid} do
      tmp_dir = tmp_dir!()
      assert {:ok, _} = exec_command(session_pid, "cd #{tmp_dir}")
      assert {:ok, output} = exec_command(session_pid, "ls")
      assert String.trim(output) == ""
    end

    test "handles non-existent directory", %{session_pid: session_pid} do
      assert {:error, _reason} = exec_command(session_pid, "ls /non/existent/path")
    end
  end
end
