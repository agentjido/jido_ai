defmodule Kodo.Commands.CdTest do
  use Kodo.Case, async: true

  describe "cd command" do
    setup context do
      setup_session_with_commands(context)
    end

    test "changes to existing directory", %{session_pid: session_pid} do
      tmp_dir = tmp_dir!()

      assert {:ok, _} = exec_command(session_pid, "cd #{tmp_dir}")
      assert {:ok, output} = exec_command(session_pid, "pwd")
      assert String.contains?(output, tmp_dir)
    end

    test "handles non-existent directory", %{session_pid: session_pid} do
      assert {:error, _reason} = exec_command(session_pid, "cd /non/existent/path")
    end

    test "changes to parent directory", %{session_pid: session_pid} do
      # Get initial directory
      {:ok, initial_dir} = exec_command(session_pid, "pwd")
      initial_dir = String.trim(initial_dir)

      # Go to parent
      assert {:ok, _} = exec_command(session_pid, "cd ..")

      # Verify we moved up
      {:ok, parent_dir} = exec_command(session_pid, "pwd")
      parent_dir = String.trim(parent_dir)

      assert parent_dir != initial_dir
      assert String.starts_with?(initial_dir, parent_dir)
    end
  end
end
