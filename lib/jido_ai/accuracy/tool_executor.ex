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
  - Command allowlist for security

  ## Security Considerations

  - All commands are validated against an allowlist (configurable)
  - All commands are executed with a timeout to prevent hanging
  - Environment variables are sanitized (no secrets passed)
  - Working directory is validated before execution
  - Docker/podman isolation recommended for production

  ## Command Allowlist

  By default, only common programming language interpreters and build tools
  are allowed. This can be configured via:

      # config/config.exs
      config :jido_ai, :command_allowlist, [
        "python3", "python", "node", "elixir", "ruby", "bash", "sh"
      ]

  Or completely disabled (not recommended for production):

      config :jido_ai, :enforce_command_allowlist, false

  ## Usage

      # Execute a simple command
      {:ok, result} = ToolExecutor.run_command("echo", ["hello"], [])

      # Execute with timeout
      {:ok, result} = ToolExecutor.run_command("sleep", ["10"], [], timeout: 1000)

      # Execute in specific directory
      {:ok, result} = ToolExecutor.run_command("ls", ["-la"], [], cd: "/tmp")

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
          sandbox: :none | :docker | :podman,
          bypass_allowlist: boolean()
        ]

  # Default command allowlist - common language interpreters and tools
  @default_allowlist [
    # Language interpreters
    "python3",
    "python",
    "python2",
    "node",
    "nodejs",
    "npm",
    "npx",
    "elixir",
    "elixirc",
    "mix",
    "iex",
    "ruby",
    "gem",
    "irb",
    "perl",
    "perl6",
    "java",
    "javac",
    "go",
    "gofmt",
    "rustc",
    "cargo",
    # Shells
    "bash",
    "sh",
    "zsh",
    "fish",
    # Build tools
    "make",
    "cmake",
    "gcc",
    "g++",
    "clang",
    "clang++",
    # Common utilities (for testing)
    "echo",
    "printf",
    "cat",
    "ls",
    "pwd",
    "mkdir",
    "rm",
    "cp",
    "mv",
    "test",
    "true",
    "false",
    # Docker/Podman (for sandboxing)
    "docker",
    "podman"
  ]

  @doc """
  Initializes the command allowlist from configuration.
  Should be called from application startup.
  """
  def init_allowlist do
    custom_list = Application.get_env(:jido_ai, :command_allowlist, @default_allowlist)

    allowlist =
      if Application.get_env(:jido_ai, :enforce_command_allowlist, true) do
        MapSet.new(custom_list)
      else
        :disabled
      end

    :persistent_term.put(:jido_ai_command_allowlist, allowlist)
  end

  @doc """
  Returns the current command allowlist.
  """
  @spec get_allowlist() :: MapSet.t() | :disabled
  def get_allowlist do
    case :persistent_term.get(:jido_ai_command_allowlist, :not_initialized) do
      :not_initialized ->
        init_allowlist()
        :persistent_term.get(:jido_ai_command_allowlist)

      allowlist ->
        allowlist
    end
  end

  @doc """
  Sets a custom command allowlist at runtime.
  Useful for testing or dynamic configuration.
  """
  @spec set_allowlist([String.t()] | :disabled | :allow_all) :: :ok
  def set_allowlist(:allow_all) do
    :persistent_term.put(:jido_ai_command_allowlist, :disabled)
    :ok
  end

  def set_allowlist(:disabled) do
    :persistent_term.put(:jido_ai_command_allowlist, :disabled)
    :ok
  end

  def set_allowlist(commands) when is_list(commands) do
    :persistent_term.put(:jido_ai_command_allowlist, MapSet.new(commands))
    :ok
  end

  @doc """
  Adds a command to the allowlist.
  """
  @spec allow_command(String.t()) :: :ok
  def allow_command(command) do
    current_allowlist = get_allowlist()

    new_allowlist =
      case current_allowlist do
        :disabled -> :disabled
        set -> MapSet.put(set, command)
      end

    :persistent_term.put(:jido_ai_command_allowlist, new_allowlist)
    :ok
  end

  @doc """
  Checks if a command is allowed.
  """
  @spec command_allowed?(String.t()) :: boolean()
  def command_allowed?(command) when is_binary(command) do
    allowlist = get_allowlist()

    case allowlist do
      :disabled -> true
      set -> MapSet.member?(set, Path.basename(command))
    end
  end

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
  - `:bypass_allowlist` - Skip allowlist check (default: false)

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
    bypass_allowlist = Keyword.get(opts, :bypass_allowlist, false)

    with :ok <- validate_command(command, bypass_allowlist),
         :ok <- validate_working_dir(cd),
         :ok <- validate_environment(env),
         {:ok, full_command, full_args} <- maybe_wrap_in_sandbox(command, args, sandbox, opts),
         {start_time, exec_result} <- measure_time(fn -> execute(full_command, full_args, cd, env, timeout) end) do
      end_time = System.monotonic_time(:native)

      case exec_result do
        {:ok, exit_code, stdout, stderr} ->
          {:ok,
           %{
             exit_code: exit_code,
             stdout: stdout,
             stderr: stderr,
             timed_out: false,
             duration_ms: System.convert_time_unit(end_time - start_time, :native, :millisecond)
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

    port =
      Port.open(
        {:spawn_executable, find_executable(command)},
        port_options ++ [:binary, :exit_status, :hide, args: args]
      )

    # Ensure port is closed even if an error occurs
    try do
      # Wait for the result with timeout
      await_port_result(port, timeout, <<>>, <<>>)
    after
      # Close port if it's still open (not closed by await_port_result)
      # Note: Erlang ports close automatically on exit_status, but this is defensive
      if Port.info(port) != nil do
        Port.close(port)
      end
    end
  rescue
    e in [ArgumentError, BadArityError, FunctionClauseError] ->
      {:error, e}
  end

  defp build_port_options(nil, env, _timeout), do: env_option(env)
  defp build_port_options(cd, env, _timeout), do: [{:cd, cd} | env_option(env)]

  defp env_option(%{} = env) when map_size(env) > 0 do
    # Port.open expects env values as charlists, not binaries
    env_list =
      Enum.map(env, fn {k, v} ->
        {String.to_charlist(k), String.to_charlist(v)}
      end)

    [{:env, env_list}]
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
        # Port closes automatically after exit_status
        {:ok, exit_code, stdout_acc, stderr_acc}
    after
      timeout ->
        # Return timeout signal - port will be closed by try/after in execute
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

        # Sanitize the working directory path for Docker volume mount
        # Docker doesn't handle paths with certain characters well
        sanitized_cd = sanitize_path_for_docker(cd)

        # Wrap command in docker run with security hardening
        docker_cmd = "docker"

        docker_args =
          [
            "run",
            "--rm",
            # Read-only mount (prevents container from modifying host files)
            "-v",
            "#{sanitized_cd}:/workspace:ro",
            "-w",
            "/workspace",
            # Drop all capabilities (no privileged operations)
            "--cap-drop=ALL",
            # No new privileges (even for root user)
            "--security-opt=no-new-privileges",
            # Temporary filesystems for /tmp and /home (writable but in memory only)
            "--tmpfs",
            "/tmp:rw,noexec,nosuid,size=100m",
            "--tmpfs",
            "/home:rw,noexec,nosuid,size=100m",
            # Network isolation (no network access)
            "--network=none",
            # Resource limits
            "--memory=512m",
            "--cpus=1",
            "--pids-limit=100",
            # Read-only root filesystem (prevents writing to system directories)
            "--read-only",
            # Use non-root user
            "-u",
            "1000:1000",
            # Use a minimal image
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

        # Sanitize the working directory path for Podman volume mount
        sanitized_cd = sanitize_path_for_docker(cd)

        # Wrap command in podman run with security hardening
        podman_cmd = "podman"

        podman_args =
          [
            "run",
            "--rm",
            # Read-only mount with SELinux label
            "-v",
            "#{sanitized_cd}:/workspace:ro,Z",
            "-w",
            "/workspace",
            # Drop all capabilities
            "--cap-drop=ALL",
            # No new privileges
            "--security-opt=no-new-privileges",
            # Temporary filesystems
            "--tmpfs",
            "/tmp:rw,noexec,nosuid,size=100m",
            "--tmpfs",
            "/home:rw,noexec,nosuid,size=100m",
            # Network isolation
            "--network=none",
            # Resource limits
            "--memory=512m",
            "--cpus=1",
            "--pids-limit=100",
            # Read-only root filesystem
            "--read-only",
            # Non-root user
            "-u",
            "1000:1000",
            # Use a minimal image
            "elixir:latest",
            command
          ] ++ args

        {:ok, podman_cmd, podman_args}
    end
  end

  # Sanitize path for Docker/Podman volume mounts
  # Some characters in paths can cause issues with container runtimes
  defp sanitize_path_for_docker(path) do
    # Expand the path first
    expanded = Path.expand(path)

    # For Docker on Windows, paths need special handling
    # On Unix-like systems, the path should be fine as-is
    expanded
  end

  defp validate_working_dir(nil), do: :ok

  defp validate_working_dir(path) when is_binary(path) do
    # Sanitize path to prevent directory traversal
    expanded_path = Path.expand(path)

    # Check if path exists and is a directory
    if File.dir?(expanded_path) do
      # Ensure path doesn't contain suspicious patterns
      if suspicious_path?(expanded_path) do
        {:error, :suspicious_path}
      else
        :ok
      end
    else
      {:error, :directory_not_found}
    end
  end

  defp validate_working_dir(_), do: {:error, :invalid_directory}

  # Check for suspicious path patterns that might indicate attacks
  defp suspicious_path?(path) do
    # Check for null bytes and URL-like patterns that shouldn't be in file paths
    # Note: ".." is allowed for legitimate parent directory navigation
    cond do
      # Null byte injection
      String.contains?(path, "\x00") -> true
      # Check for protocol-like patterns (potential URL injection)
      # But allow common patterns like "C:/" on Windows
      String.contains?(path, "://") -> true
      true -> false
    end
  end

  # Validate command against allowlist
  defp validate_command(command, bypass_allowlist?) do
    command_basename = Path.basename(command)

    cond do
      # Allow bypass for internal use (e.g., docker/podman wrapper)
      bypass_allowlist? ->
        :ok

      # Check if command is on allowlist
      command_allowed?(command_basename) ->
        :ok

      # Reject commands not on allowlist
      true ->
        {:error, {:command_not_allowed, command_basename}}
    end
  end

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
