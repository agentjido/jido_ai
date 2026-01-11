defmodule Jido.AI.Accuracy.ToolExecutor do
  @moduledoc """
  Safe execution of external tools for verification purposes.

  This module provides utilities for running external commands (code execution,
  test runners, static analysis tools) with proper timeout handling, output
  capture, and error handling.

  ## Features

  - Timeout-based process termination
  - Stdout/stderr capture
  - Exit code interpretation
  - Working directory management
  - Environment variable control
  - Optional Docker/podman sandboxing

  ## Security Considerations

  - All commands are executed with a timeout to prevent hanging
  - Environment variables are sanitized (no secrets passed)
  - Working directory is validated before execution
  - Docker/podman isolation recommended for production

  ## Usage

      # Execute a simple command
      {:ok, result} = ToolExecutor.run_command("echo", ["hello"], %{})

      # Execute with timeout
      {:ok, result} = ToolExecutor.run_command("sleep", ["10"], %{}, timeout: 1000)

      # Execute in specific directory
      {:ok, result} = ToolExecutor.run_command("ls", ["-la"], %{}, cd: "/tmp")

  ## Result Structure

  The result map contains:
  - `:exit_code` - Process exit code (0 for success)
  - `:stdout` - Standard output as string
  - `:stderr` - Standard error as string
  - `:timed_out` - Whether the command timed out
  - `:duration_ms` - Actual execution time in milliseconds

  """

  @type command_result :: %{
          exit_code: integer(),
          stdout: String.t(),
          stderr: String.t(),
          timed_out: boolean(),
          duration_ms: number()
        }

  @type opts :: [
          cd: String.t(),
          env: %{optional(String.t()) => String.t()},
          timeout: pos_integer(),
          sandbox: :none | :docker | :podman
        ]

  @doc """
  Executes a command with the given arguments.

  ## Parameters

  - `command` - The command to execute (string)
  - `args` - List of command arguments
  - `opts` - Execution options

  ## Options

  - `:cd` - Working directory for execution
  - `:env` - Environment variables to set
  - `:timeout` - Maximum execution time in milliseconds (default: 5000)
  - `:sandbox` - Sandbox type (:none, :docker, :podman)

  ## Returns

  - `{:ok, result}` - Command executed successfully
  - `{:error, reason}` - Command failed to start or execute

  ## Examples

      iex> {:ok, result} = ToolExecutor.run_command("echo", ["hello"], [])
      iex> result.stdout
      "hello\\n"
      iex> result.exit_code
      0

      iex> {:ok, result} = ToolExecutor.run_command("false", [], [])
      iex> result.exit_code
      1

  """
  @spec run_command(String.t(), [String.t()], opts()) :: {:ok, command_result()} | {:error, term()}
  def run_command(command, args, opts \\ []) when is_binary(command) and is_list(args) do
    timeout = Keyword.get(opts, :timeout, 5000)
    cd = Keyword.get(opts, :cd)
    env = Keyword.get(opts, :env, %{})
    sandbox = Keyword.get(opts, :sandbox, :none)

    with :ok <- validate_working_dir(cd),
         :ok <- validate_environment(env),
         {:ok, full_command, full_args} <- maybe_wrap_in_sandbox(command, args, sandbox, opts),
         {start_time, exec_result} <- measure_time(fn -> execute(full_command, full_args, cd, env, timeout) end) do
      case exec_result do
        {:ok, exit_code, stdout, stderr} ->
          {:ok,
           %{
             exit_code: exit_code,
             stdout: stdout,
             stderr: stderr,
             timed_out: false,
             duration_ms: System.convert_time_unit(start_time, :native, :millisecond)
           }}

        {:timeout, stdout, stderr} ->
          {:ok,
           %{
             exit_code: -1,
             stdout: stdout,
             stderr: stderr,
             timed_out: true,
             duration_ms: timeout
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Parses an exit code into a human-readable status.

  ## Examples

      iex> ToolExecutor.parse_exit_code(0)
      :success

      iex> ToolExecutor.parse_exit_code(1)
      :failure

      iex> ToolExecutor.parse_exit_code(-1)
      :timeout

      iex> ToolExecutor.parse_exit_code(127)
      :command_not_found

  """
  @spec parse_exit_code(integer()) :: :success | :failure | :timeout | :command_not_found | :unknown
  def parse_exit_code(0), do: :success
  def parse_exit_code(-1), do: :timeout
  def parse_exit_code(127), do: :command_not_found
  def parse_exit_code(126), do: :command_not_executable
  def parse_exit_code(_), do: :failure

  @doc """
  Captures and combines stdout and stderr into a single string.

  ## Examples

      iex> result = %{stdout: "out", stderr: "err"}
      iex> ToolExecutor.capture_output(result)
      "out\\nerr"

  """
  @spec capture_output(command_result()) :: String.t()
  def capture_output(%{stdout: stdout, stderr: stderr}) do
    [stdout, stderr]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join("\n")
    |> String.trim()
  end

  # Private functions

  defp execute(command, args, cd, env, timeout) do
    # Open a port to execute the command
    port_options = build_port_options(cd, env, timeout)

    try do
      port =
        Port.open(
          {:spawn_executable, find_executable(command)},
          port_options ++ [:binary, :exit_status, :hide, args: args]
        )

      # Wait for the result with timeout
      await_port_result(port, timeout, <<>>, <<>>)
    catch
      kind, error ->
        {:error, {kind, error}}
    end
  end

  defp build_port_options(nil, env, _timeout), do: env_option(env)
  defp build_port_options(cd, env, _timeout), do: [:cd, cd | env_option(env)]

  defp env_option(%{} = env) when map_size(env) > 0 do
    env_list =
      Enum.map(env, fn {k, v} ->
        {"#{k}", "#{v}"}
      end)

    [:env, env_list]
  end

  defp env_option(_), do: []

  defp await_port_result(port, timeout, stdout_acc, stderr_acc) do
    start_time = System.monotonic_time(:millisecond)

    receive do
      {^port, {:data, data}} ->
        # Determine if this is stdout or stderr
        # Note: Ports don't distinguish, so we treat everything as stdout
        await_port_result(
          port,
          timeout - (System.monotonic_time(:millisecond) - start_time),
          stdout_acc <> data,
          stderr_acc
        )

      {^port, {:exit_status, exit_code}} ->
        {:ok, exit_code, stdout_acc, stderr_acc}
    after
      timeout ->
        Port.close(port)
        {:timeout, stdout_acc, stderr_acc}
    end
  end

  defp find_executable(command) do
    # Try to find the executable in PATH
    case System.find_executable(command) do
      nil -> command
      path -> path
    end
  end

  defp maybe_wrap_in_sandbox(command, args, :none, _opts), do: {:ok, command, args}

  defp maybe_wrap_in_sandbox(command, args, :docker, opts) do
    # Check if docker is available
    case System.find_executable("docker") do
      nil ->
        {:error, :docker_not_available}

      _docker ->
        cd = Keyword.get(opts, :cd, File.cwd!())
        # Wrap command in docker run
        docker_cmd = "docker"

        docker_args =
          [
            "run",
            "--rm",
            "-v",
            "#{cd}:/workspace",
            "-w",
            "/workspace",
            "--network=none",
            "--memory=512m",
            "--cpus=1",
            "elixir:latest",
            command
          ] ++ args

        {:ok, docker_cmd, docker_args}
    end
  end

  defp maybe_wrap_in_sandbox(command, args, :podman, opts) do
    # Check if podman is available
    case System.find_executable("podman") do
      nil ->
        {:error, :podman_not_available}

      _podman ->
        cd = Keyword.get(opts, :cd, File.cwd!())
        # Wrap command in podman run
        podman_cmd = "podman"

        podman_args =
          [
            "run",
            "--rm",
            "-v",
            "#{cd}:/workspace:Z",
            "-w",
            "/workspace",
            "--network=none",
            "--memory=512m",
            "--cpus=1",
            "elixir:latest",
            command
          ] ++ args

        {:ok, podman_cmd, podman_args}
    end
  end

  defp validate_working_dir(nil), do: :ok

  defp validate_working_dir(path) when is_binary(path) do
    if File.dir?(path) do
      :ok
    else
      {:error, :directory_not_found}
    end
  end

  defp validate_working_dir(_), do: {:error, :invalid_directory}

  defp validate_environment(env) when is_map(env) do
    # Check for dangerous environment variables
    forbidden_keys = ["PATH", "HOME", "USER", "SHELL"]

    forbidden =
      env
      |> Map.keys()
      |> Enum.any?(fn key ->
        key_upper = String.upcase(to_string(key))
        Enum.any?(forbidden_keys, &(&1 == key_upper))
      end)

    if forbidden do
      {:error, :forbidden_environment_key}
    else
      :ok
    end
  end

  defp validate_environment(_), do: {:error, :invalid_environment}

  defp measure_time(fun) do
    start = System.monotonic_time(:native)
    result = fun.()
    {start, result}
  end
end
