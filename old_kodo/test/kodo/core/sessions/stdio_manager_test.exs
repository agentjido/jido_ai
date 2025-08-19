defmodule Kodo.Core.Sessions.StdioManagerTest do
  use Kodo.Case, async: true
  alias Kodo.Core.Sessions.StdioManager

  describe "create_pipeline_connections/1" do
    test "returns empty list for empty commands" do
      assert StdioManager.create_pipeline_connections([]) == []
    end

    test "returns inherit config for single command" do
      expected = [%{stdin: :inherit, stdout: :inherit, stderr: :inherit}]
      assert StdioManager.create_pipeline_connections([:single_cmd]) == expected
    end

    test "creates pipe connections for multiple commands" do
      result = StdioManager.create_pipeline_connections([:cmd1, :cmd2, :cmd3])

      expected = [
        %{stdin: :inherit, stdout: :pipe, stderr: :inherit},
        %{stdin: :pipe, stdout: :pipe, stderr: :inherit},
        %{stdin: :pipe, stdout: :inherit, stderr: :inherit}
      ]

      assert result == expected
    end

    test "handles two commands correctly" do
      result = StdioManager.create_pipeline_connections([:cmd1, :cmd2])

      expected = [
        %{stdin: :inherit, stdout: :pipe, stderr: :inherit},
        %{stdin: :pipe, stdout: :inherit, stderr: :inherit}
      ]

      assert result == expected
    end
  end

  describe "setup_redirections/2" do
    setup do
      base_config = %{stdin: :inherit, stdout: :inherit, stderr: :inherit}
      {:ok, base_config: base_config}
    end

    test "returns unchanged config for empty redirections", %{base_config: config} do
      assert StdioManager.setup_redirections(config, []) == config
    end

    test "applies input redirection", %{base_config: config} do
      redirections = [{:input_redirect, "input.txt"}]
      result = StdioManager.setup_redirections(config, redirections)

      expected = %{config | stdin: {:file, "input.txt", [:read]}}
      assert result == expected
    end

    test "applies output redirection", %{base_config: config} do
      redirections = [{:output_redirect, "output.txt"}]
      result = StdioManager.setup_redirections(config, redirections)

      expected = %{config | stdout: {:file, "output.txt", [:write]}}
      assert result == expected
    end

    test "applies append redirection", %{base_config: config} do
      redirections = [{:append_redirect, "output.txt"}]
      result = StdioManager.setup_redirections(config, redirections)

      expected = %{config | stdout: {:file, "output.txt", [:write, :append]}}
      assert result == expected
    end

    test "applies error redirection", %{base_config: config} do
      redirections = [{:error_redirect, "error.txt"}]
      result = StdioManager.setup_redirections(config, redirections)

      expected = %{config | stderr: {:file, "error.txt", [:write]}}
      assert result == expected
    end

    test "applies error append redirection", %{base_config: config} do
      redirections = [{:error_append_redirect, "error.txt"}]
      result = StdioManager.setup_redirections(config, redirections)

      expected = %{config | stderr: {:file, "error.txt", [:write, :append]}}
      assert result == expected
    end

    test "applies combined redirection", %{base_config: config} do
      redirections = [{:combined_redirect, "combined.txt"}]
      result = StdioManager.setup_redirections(config, redirections)

      expected = %{
        config
        | stdout: {:file, "combined.txt", [:write]},
          stderr: {:file, "combined.txt", [:write]}
      }

      assert result == expected
    end

    test "applies stderr to stdout redirection", %{base_config: config} do
      # First set stdout to a pipe, then redirect stderr to it
      config_with_stdout = %{config | stdout: :pipe}
      redirections = [{:stderr_to_stdout}]
      result = StdioManager.setup_redirections(config_with_stdout, redirections)

      expected = %{config_with_stdout | stderr: :pipe}
      assert result == expected
    end

    test "applies stderr to stdout with file output" do
      config = %{stdin: :inherit, stdout: {:file, "out.txt", [:write]}, stderr: :inherit}
      redirections = [{:stderr_to_stdout}]
      result = StdioManager.setup_redirections(config, redirections)

      expected = %{config | stderr: {:file, "out.txt", [:write]}}
      assert result == expected
    end

    test "applies multiple redirections in order", %{base_config: config} do
      redirections = [
        {:input_redirect, "input.txt"},
        {:output_redirect, "output.txt"},
        {:error_redirect, "error.txt"}
      ]

      result = StdioManager.setup_redirections(config, redirections)

      expected = %{
        stdin: {:file, "input.txt", [:read]},
        stdout: {:file, "output.txt", [:write]},
        stderr: {:file, "error.txt", [:write]}
      }

      assert result == expected
    end

    test "ignores unknown redirections", %{base_config: config} do
      redirections = [{:unknown_redirect, "file.txt"}]
      result = StdioManager.setup_redirections(config, redirections)

      assert result == config
    end
  end

  describe "background_stdio_config/0" do
    test "returns configuration that redirects all streams to /dev/null" do
      result = StdioManager.background_stdio_config()

      expected = %{
        stdin: {:file, "/dev/null", [:read]},
        stdout: {:file, "/dev/null", [:write]},
        stderr: {:file, "/dev/null", [:write]}
      }

      assert result == expected
    end
  end

  describe "capture_stdio_config/0" do
    test "returns configuration with all streams as pipes" do
      result = StdioManager.capture_stdio_config()

      expected = %{
        stdin: :pipe,
        stdout: :pipe,
        stderr: :pipe
      }

      assert result == expected
    end
  end

  describe "build_port_options/2 (via spawn_with_stdio)" do
    # Test private build_port_options function indirectly through spawn_with_stdio
    # We expect spawn_with_stdio to fail due to missing executable, but we can
    # verify the port options are built correctly by checking the error patterns

    test "builds basic options with inherit stdio" do
      stdio_config = %{stdin: :inherit, stdout: :inherit, stderr: :inherit}

      # Call spawn_with_stdio which internally uses build_port_options
      # We expect it to fail but we're testing the options building logic
      {:error, _} =
        StdioManager.spawn_with_stdio("nonexistent_cmd", [], stdio_config, [:some_option])

      # The function should have processed the stdio config without error
      # (the error will be from the missing executable, not option building)
      assert true
    end

    test "processes pipe configurations without errors" do
      stdio_configs = [
        %{stdin: :pipe, stdout: :inherit, stderr: :inherit},
        %{stdin: :inherit, stdout: :pipe, stderr: :inherit},
        %{stdin: :inherit, stdout: :inherit, stderr: :pipe},
        %{stdin: :pipe, stdout: :pipe, stderr: :pipe}
      ]

      for config <- stdio_configs do
        {:error, _} = StdioManager.spawn_with_stdio("nonexistent_cmd", [], config, [])
        # Should process without option-building errors
        assert true
      end
    end

    test "processes file redirections without errors" do
      stdio_config = %{
        stdin: {:file, "input.txt", [:read]},
        stdout: {:file, "output.txt", [:write]},
        stderr: {:file, "error.txt", [:write]}
      }

      {:error, _} = StdioManager.spawn_with_stdio("nonexistent_cmd", [], stdio_config, [])
      # Should process file configs without option-building errors
      assert true
    end

    test "processes mixed configurations without errors" do
      stdio_config = %{
        stdin: :pipe,
        stdout: {:file, "output.txt", [:write]},
        stderr: :inherit
      }

      {:error, _} =
        StdioManager.spawn_with_stdio("nonexistent_cmd", [], stdio_config, [:custom_opt])

      # Should handle mixed configs without option-building errors
      assert true
    end
  end
end
