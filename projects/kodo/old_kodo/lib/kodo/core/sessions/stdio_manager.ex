defmodule Kodo.Core.Sessions.StdioManager do
  @moduledoc """
  Manages stdio connections between commands in a pipeline.

  This module handles:
  - Creating pipes between commands in a pipeline
  - Setting up file redirections (>, <, >>, 2>, etc.)
  - Managing stdio streams for background and foreground processes
  """

  require Logger

  @type stream_spec :: :inherit | :pipe | {:file, String.t(), [atom()]}
  @type stdio_config :: %{
          stdin: stream_spec(),
          stdout: stream_spec(),
          stderr: stream_spec()
        }

  @doc """
  Creates stdio configuration for a pipeline of commands.

  Returns a list of stdio configs, one per command, with pipes
  connecting the output of each command to the input of the next.
  """
  @spec create_pipeline_connections([any()]) :: [stdio_config()]
  def create_pipeline_connections([]) do
    []
  end

  def create_pipeline_connections([_single_command]) do
    # Single command uses default stdio (inherit from shell)
    [%{stdin: :inherit, stdout: :inherit, stderr: :inherit}]
  end

  def create_pipeline_connections(commands) when length(commands) > 1 do
    # Create pipe connections between commands
    for {_command, index} <- Enum.with_index(commands) do
      stdin_spec = if index == 0, do: :inherit, else: :pipe
      stdout_spec = if index == length(commands) - 1, do: :inherit, else: :pipe

      %{
        stdin: stdin_spec,
        stdout: stdout_spec,
        # stderr is not piped by default
        stderr: :inherit
      }
    end
  end

  @doc """
  Applies redirections to a command's stdio configuration.

  Redirections can include:
  - Input redirection: "< file"
  - Output redirection: "> file", ">> file"  
  - Error redirection: "2> file", "2>> file"
  - Combined redirection: "&> file", "2>&1"
  """
  @spec setup_redirections(stdio_config(), [any()]) :: stdio_config()
  def setup_redirections(stdio_config, []) do
    stdio_config
  end

  def setup_redirections(stdio_config, redirections) do
    Enum.reduce(redirections, stdio_config, &apply_redirection/2)
  end

  @doc """
  Creates an actual Port or Task with the specified stdio configuration.

  This is where we actually spawn the process with the right stdio setup.
  """
  @spec spawn_with_stdio(String.t(), [String.t()], stdio_config(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def spawn_with_stdio(command, args, stdio_config, opts \\ []) do
    # Convert our stdio_config to Erlang port options
    port_opts = build_port_options(stdio_config, opts)

    try do
      # Use Port.open to start the external command
      port =
        Port.open(
          {:spawn_executable, find_executable(command)},
          [{:args, args} | port_opts]
        )

      {:ok, port}
    rescue
      error ->
        {:error, error}
    catch
      :exit, reason ->
        {:error, reason}
    end
  end

  @doc """
  Connects the output of one process to the input of another via pipes.

  This is used for pipeline connections where stdout of process A
  becomes stdin of process B.
  """
  @spec pipe_output_to_input(pid(), pid()) :: :ok | {:error, term()}
  def pipe_output_to_input(from_pid, to_pid) do
    # This is a simplified implementation
    # In a real shell, we'd need to handle the actual pipe file descriptors
    # For now, we'll just link the processes
    Process.link(from_pid)
    Process.link(to_pid)
    :ok
  end

  @doc """
  Creates a background process configuration that doesn't interfere
  with the shell's stdio.
  """
  @spec background_stdio_config() :: stdio_config()
  def background_stdio_config do
    %{
      stdin: {:file, "/dev/null", [:read]},
      stdout: {:file, "/dev/null", [:write]},
      stderr: {:file, "/dev/null", [:write]}
    }
  end

  @doc """
  Creates stdio configuration for capturing output (for testing or programmatic use).
  """
  @spec capture_stdio_config() :: stdio_config()
  def capture_stdio_config do
    %{
      stdin: :pipe,
      stdout: :pipe,
      stderr: :pipe
    }
  end

  # Private implementation functions

  defp apply_redirection({:input_redirect, filename}, stdio_config) do
    %{stdio_config | stdin: {:file, filename, [:read]}}
  end

  defp apply_redirection({:output_redirect, filename}, stdio_config) do
    %{stdio_config | stdout: {:file, filename, [:write]}}
  end

  defp apply_redirection({:append_redirect, filename}, stdio_config) do
    %{stdio_config | stdout: {:file, filename, [:write, :append]}}
  end

  defp apply_redirection({:error_redirect, filename}, stdio_config) do
    %{stdio_config | stderr: {:file, filename, [:write]}}
  end

  defp apply_redirection({:error_append_redirect, filename}, stdio_config) do
    %{stdio_config | stderr: {:file, filename, [:write, :append]}}
  end

  defp apply_redirection({:combined_redirect, filename}, stdio_config) do
    # &> redirects both stdout and stderr to file
    %{stdio_config | stdout: {:file, filename, [:write]}, stderr: {:file, filename, [:write]}}
  end

  defp apply_redirection({:stderr_to_stdout}, stdio_config) do
    # 2>&1 redirects stderr to whatever stdout is
    %{stdio_config | stderr: stdio_config.stdout}
  end

  defp apply_redirection(unknown_redirection, stdio_config) do
    Logger.warning("Unknown redirection: #{inspect(unknown_redirection)}")
    stdio_config
  end

  defp build_port_options(stdio_config, base_opts) do
    # Convert our stdio_config to Port options
    opts = [:binary, :exit_status | base_opts]

    # Add stdio options
    opts =
      case stdio_config.stdin do
        :inherit ->
          opts

        :pipe ->
          [:stdin | opts]

        {:file, _path, _file_opts} ->
          # For file input, we'll need to handle this differently
          # This is a simplified version
          opts
      end

    opts =
      case stdio_config.stdout do
        :inherit ->
          opts

        :pipe ->
          [:stdout | opts]

        {:file, _path, _file_opts} ->
          # File output needs special handling
          opts
      end

    case stdio_config.stderr do
      :inherit ->
        opts

      :pipe ->
        [:stderr | opts]

      {:file, _path, _file_opts} ->
        # File error output needs special handling
        opts
    end
  end

  defp find_executable(command) do
    # Simple executable finder - in a real implementation,
    # we'd search PATH and handle shell built-ins
    case System.find_executable(command) do
      nil ->
        # Try common paths
        common_paths = ["/bin", "/usr/bin", "/usr/local/bin"]

        Enum.find_value(common_paths, fn path ->
          full_path = Path.join(path, command)
          if File.exists?(full_path), do: full_path
        end) || command

      path ->
        path
    end
  end
end
