defmodule Jido.AI.Accuracy.ToolExecutorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.ToolExecutor

  @moduletag :capture_log

  describe "run_command/3" do
    test "executes simple command successfully" do
      {:ok, result} = ToolExecutor.run_command("echo", ["hello"], bypass_allowlist: true)

      assert result.exit_code == 0
      assert String.contains?(result.stdout, "hello")
      assert result.timed_out == false
      assert is_number(result.duration_ms)
      assert result.duration_ms >= 0
    end

    test "captures command output" do
      # Test that stdout capture works correctly
      {_, result} = ToolExecutor.run_command("echo", ["test output"], bypass_allowlist: true)

      assert String.contains?(result.stdout, "test output")
      assert result.stderr == ""
    end

    test "handles non-zero exit codes" do
      {:ok, result} = ToolExecutor.run_command("false", [], bypass_allowlist: true)

      assert result.exit_code != 0
    end

    test "times out long-running commands" do
      # Sleep for 5 seconds but timeout after 100ms
      {:ok, result} = ToolExecutor.run_command("sleep", ["5"], timeout: 100, bypass_allowlist: true)

      assert result.timed_out == true
      assert result.exit_code == -1
    end

    test "allows custom timeout" do
      {:ok, result} = ToolExecutor.run_command("sleep", ["0.1"], timeout: 500, bypass_allowlist: true)

      assert result.exit_code == 0
      assert result.timed_out == false
    end

    test "returns error for invalid working directory" do
      {:error, :directory_not_found} =
        ToolExecutor.run_command("echo", ["test"], cd: "/nonexistent/directory/xyz123", bypass_allowlist: true)
    end

    test "executes in specified working directory" do
      tmp_dir = System.tmp_dir!()

      {:ok, result} =
        ToolExecutor.run_command("pwd", [], cd: tmp_dir, bypass_allowlist: true)

      assert String.contains?(result.stdout, tmp_dir)
    end

    test "handles multiple arguments" do
      {:ok, result} = ToolExecutor.run_command("echo", ["hello", "world", "!"], bypass_allowlist: true)

      assert String.contains?(result.stdout, "hello world !")
    end

    test "returns error for forbidden environment keys" do
      {:error, :forbidden_environment_key} =
        ToolExecutor.run_command("echo", ["test"], env: %{"PATH" => "/bin"}, bypass_allowlist: true)
    end

    test "allows safe environment variables" do
      {:ok, result} =
        ToolExecutor.run_command("sh", ["-c", "echo $TEST_VAR"], env: %{"TEST_VAR" => "test_value"}, bypass_allowlist: true)

      assert String.contains?(result.stdout, "test_value")
    end
  end

  describe "parse_exit_code/1" do
    test "returns :success for exit code 0" do
      assert ToolExecutor.parse_exit_code(0) == :success
    end

    test "returns :failure for non-zero exit codes" do
      assert ToolExecutor.parse_exit_code(1) == :failure
      assert ToolExecutor.parse_exit_code(2) == :failure
    end

    test "returns :timeout for -1" do
      assert ToolExecutor.parse_exit_code(-1) == :timeout
    end

    test "returns :command_not_found for 127" do
      assert ToolExecutor.parse_exit_code(127) == :command_not_found
    end

    test "returns :command_not_executable for 126" do
      assert ToolExecutor.parse_exit_code(126) == :command_not_executable
    end
  end

  describe "capture_output/1" do
    test "combines stdout and stderr" do
      result = %{
        stdout: "standard out",
        stderr: "standard error"
      }

      combined = ToolExecutor.capture_output(result)

      assert String.contains?(combined, "standard out")
      assert String.contains?(combined, "standard error")
    end

    test "handles empty stdout" do
      result = %{
        stdout: "",
        stderr: "error message"
      }

      combined = ToolExecutor.capture_output(result)

      assert combined == "error message"
    end

    test "handles empty stderr" do
      result = %{
        stdout: "output",
        stderr: ""
      }

      combined = ToolExecutor.capture_output(result)

      assert combined == "output"
    end

    test "handles nil values" do
      result = %{
        stdout: nil,
        stderr: nil
      }

      combined = ToolExecutor.capture_output(result)

      assert combined == ""
    end
  end

  describe "sandbox options" do
    @tag :sandbox
    test "returns error when docker not available for docker sandbox" do
      # This test assumes docker might not be available
      # Skip if docker is available
      case System.find_executable("docker") do
        nil ->
          {:error, :docker_not_available} =
            ToolExecutor.run_command("echo", ["test"], sandbox: :docker)

        _ ->
          :skip
      end
    end

    @tag :sandbox
    test "returns error when podman not available for podman sandbox" do
      case System.find_executable("podman") do
        nil ->
          {:error, :podman_not_available} =
            ToolExecutor.run_command("echo", ["test"], sandbox: :podman)

        _ ->
          :skip
      end
    end
  end

  describe "edge cases" do
    test "handles empty arguments" do
      {:ok, result} = ToolExecutor.run_command("echo", [])

      assert result.exit_code == 0
    end

    test "handles command with spaces in arguments" do
      {:ok, result} =
        ToolExecutor.run_command("echo", ["hello world", "foo bar"])

      assert String.contains?(result.stdout, "hello world")
      assert String.contains?(result.stdout, "foo bar")
    end

    test "handles very long output" do
      # Generate long output
      long_input = String.duplicate("x", 10_000)

      {:ok, result} =
        ToolExecutor.run_command("echo", [long_input])

      assert String.length(result.stdout) > 10_000
    end
  end
end
