defmodule Kodo.Commands.PwdTest do
  use Kodo.Case, async: true

  describe "pwd command" do
    setup context do
      setup_session_with_commands(context)
    end

    test "shows current working directory", %{session_pid: session_pid} do
      assert {:ok, output} = exec_command(session_pid, "pwd")
      assert String.contains?(output, "/")
    end

    test "shows updated directory after cd", %{session_pid: session_pid} do
      tmp_dir = tmp_dir!()

      assert {:ok, _} = exec_command(session_pid, "cd #{tmp_dir}")
      assert {:ok, output} = exec_command(session_pid, "pwd")
      assert String.contains?(output, tmp_dir)
    end
  end
end
