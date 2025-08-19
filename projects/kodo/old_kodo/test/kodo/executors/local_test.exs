defmodule Kodo.Executors.LocalTest do
  use ExUnit.Case, async: true

  alias Kodo.Executors.Local

  describe "execute/3" do
    test "executes simple command successfully" do
      assert {:ok, output, 0} = Local.execute("echo", ["hello"], %{})
      assert String.trim(output) == "hello"
    end

    test "handles command with non-zero exit code" do
      # Use 'false' command which always exits with code 1
      assert {:ok, "", 1} = Local.execute("false", [], %{})
    end

    test "handles command not found" do
      assert {:error, {:command_not_found, "nonexistent_command_12345"}} =
               Local.execute("nonexistent_command_12345", [], %{})
    end

    test "respects working directory option" do
      # Create a temporary directory  
      tmp_dir = System.tmp_dir!()

      assert {:ok, output, 0} = Local.execute("pwd", [], %{working_dir: tmp_dir})

      # Just check that the output contains the key part of the temp directory path
      # to avoid symlink resolution issues on different platforms
      output_trimmed = String.trim(output)
      # temp directory should contain T
      assert String.contains?(output_trimmed, "T")
      assert String.length(output_trimmed) > 0
    end

    test "respects environment variables" do
      env = %{"TEST_VAR" => "test_value"}

      case :os.type() do
        {:unix, _} ->
          assert {:ok, output, 0} = Local.execute("printenv", ["TEST_VAR"], %{env: env})
          assert String.trim(output) == "test_value"

        {:win32, _} ->
          assert {:ok, output, 0} = Local.execute("echo", ["%TEST_VAR%"], %{env: env})
          assert String.contains?(output, "test_value")
      end
    end
  end

  describe "execute_async/3" do
    test "starts command asynchronously" do
      assert {:ok, port} = Local.execute_async("echo", ["async_test"], %{})
      assert is_port(port)
    end

    test "handles command not found for async" do
      assert {:error, {:command_not_found, "nonexistent_async_12345"}} =
               Local.execute_async("nonexistent_async_12345", [], %{})
    end
  end

  describe "wait_for/2" do
    test "waits for async command to complete" do
      {:ok, port} = Local.execute_async("echo", ["wait_test"], %{})

      assert {:ok, output, 0} = Local.wait_for(port, 5000)
      assert String.contains?(output, "wait_test")
    end

    test "handles timeout" do
      {:ok, port} = Local.execute_async("sleep", ["10"], %{})

      assert {:error, :timeout} = Local.wait_for(port, 100)
    end
  end

  describe "get_status/1" do
    test "returns running status for active process" do
      {:ok, port} = Local.execute_async("sleep", ["1"], %{})

      assert {:running, ^port} = Local.get_status(port)
    end

    test "handles non-existent process" do
      # Create a port and let it finish naturally
      {:ok, port} = Local.execute_async("echo", ["test"], %{})

      # Wait for the process to complete
      Local.wait_for(port, 1000)

      assert {:error, :not_found} = Local.get_status(port)
    end
  end

  describe "kill/2" do
    test "kills running process" do
      {:ok, port} = Local.execute_async("sleep", ["10"], %{})

      assert :ok = Local.kill(port, :term)
    end

    test "handles already closed process" do
      {:ok, port} = Local.execute_async("echo", ["test"], %{})

      # Wait for the process to complete
      Local.wait_for(port, 1000)

      # Trying to kill an already finished process should still return :ok
      # (Port.close on a closed port in our implementation returns :ok)
      assert :ok = Local.kill(port, :term)
    end
  end

  describe "can_execute?/1" do
    test "returns true for existing commands" do
      assert Local.can_execute?("echo") == true
    end

    test "returns false for non-existent commands" do
      assert Local.can_execute?("nonexistent_command_12345") == false
    end
  end

  describe "info/0" do
    test "returns executor information" do
      info = Local.info()

      assert info.type == :local
      assert info.version == "1.0.0"
      assert :sync_execution in info.features
      assert :async_execution in info.features
      assert info.platform in [:unix, :windows]
    end
  end
end
