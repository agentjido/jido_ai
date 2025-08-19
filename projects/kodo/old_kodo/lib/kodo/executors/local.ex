defmodule Kodo.Executors.Local do
  @moduledoc """
  Local process executor adapter using System.cmd/3 and Port.open/2.

  This is the default implementation that maintains compatibility with
  the existing ExternalExecutor behavior while providing the new port interface.
  """

  @behaviour Kodo.Ports.ProcessExecutor

  require Logger
  alias Kodo.Ports.ProcessExecutor

  @impl ProcessExecutor
  def execute(command, args, options \\ %{}) do
    opts = build_system_cmd_options(options)

    try do
      case System.cmd(command, args, opts) do
        {output, exit_code} ->
          {:ok, output, exit_code}
      end
    rescue
      e in [ErlangError] ->
        handle_erlang_error(e, command, args)

      e ->
        Logger.error("Unexpected error executing command",
          command: command,
          args: args,
          error: inspect(e),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        {:error, {:unexpected_error, Exception.message(e)}}
    end
  end

  @impl ProcessExecutor
  def execute_async(command, args, options \\ %{}) do
    opts = build_port_options(options)

    try do
      port =
        Port.open(
          {:spawn_executable, find_executable!(command)},
          [{:args, args} | opts]
        )

      {:ok, port}
    rescue
      e in [ErlangError] ->
        handle_erlang_error(e, command, args)

      e ->
        Logger.error("Unexpected error starting async command",
          command: command,
          args: args,
          error: inspect(e)
        )

        {:error, {:unexpected_error, Exception.message(e)}}
    end
  end

  @impl ProcessExecutor
  def wait_for(port, timeout \\ :infinity) when is_port(port) do
    receive do
      {^port, {:data, data}} ->
        # Continue collecting data
        wait_for_completion(port, [data], timeout)

      {^port, {:exit_status, exit_code}} ->
        {:ok, "", exit_code}

      {^port, :eof} ->
        {:ok, "", 0}
    after
      timeout ->
        Port.close(port)
        {:error, :timeout}
    end
  end

  @impl ProcessExecutor
  def get_status(port) when is_port(port) do
    case Port.info(port) do
      nil -> {:error, :not_found}
      _info -> {:running, port}
    end
  end

  @impl ProcessExecutor
  def kill(port, signal \\ :term) when is_port(port) do
    try do
      case signal do
        :kill -> Port.close(port)
        :term -> Port.close(port)
        _ -> Port.close(port)
      end

      :ok
    rescue
      # Port already closed, treat as success
      _ -> :ok
    end
  end

  @impl ProcessExecutor
  def can_execute?(command) do
    case System.find_executable(command) do
      nil -> false
      _path -> true
    end
  end

  @impl ProcessExecutor
  def info do
    %{
      type: :local,
      features: [:sync_execution, :async_execution, :timeout, :signal_handling],
      platform:
        case :os.type() do
          {:unix, _} -> :unix
          {:win32, _} -> :windows
        end,
      version: "1.0.0"
    }
  end

  # Private helper functions

  defp build_system_cmd_options(options) do
    base_opts = [
      stderr_to_stdout: Map.get(options, :stderr_to_stdout, true)
    ]

    base_opts
    |> maybe_add_working_dir(options)
    |> maybe_add_env(options)
  end

  defp build_port_options(options) do
    base_opts = [
      :stream,
      :binary,
      :exit_status,
      :use_stdio,
      :stderr_to_stdout
    ]

    base_opts
    |> maybe_add_working_dir_port(options)
    |> maybe_add_env_port(options)
  end

  defp maybe_add_working_dir(opts, %{working_dir: dir}) when is_binary(dir) do
    [{:cd, dir} | opts]
  end

  defp maybe_add_working_dir(opts, _), do: opts

  defp maybe_add_working_dir_port(opts, %{working_dir: dir}) when is_binary(dir) do
    [{:cd, dir} | opts]
  end

  defp maybe_add_working_dir_port(opts, _), do: opts

  defp maybe_add_env(opts, %{env: env}) when is_map(env) do
    env_list = Enum.map(env, fn {k, v} -> {to_string(k), to_string(v)} end)
    [{:env, env_list} | opts]
  end

  defp maybe_add_env(opts, _), do: opts

  defp maybe_add_env_port(opts, %{env: env}) when is_map(env) do
    env_list = Enum.map(env, fn {k, v} -> {to_string(k), to_string(v)} end)
    [{:env, env_list} | opts]
  end

  defp maybe_add_env_port(opts, _), do: opts

  defp find_executable!(command) do
    case System.find_executable(command) do
      nil -> raise ErlangError, original: :enoent
      path -> path
    end
  end

  defp handle_erlang_error(%ErlangError{original: :enoent}, command, _args) do
    {:error, {:command_not_found, command}}
  end

  defp handle_erlang_error(%ErlangError{original: reason}, command, args) do
    Logger.warning("Command execution failed",
      command: command,
      args: args,
      reason: reason
    )

    {:error, {:execution_failed, reason}}
  end

  defp wait_for_completion(port, acc_data, timeout) do
    receive do
      {^port, {:data, data}} ->
        wait_for_completion(port, [data | acc_data], timeout)

      {^port, {:exit_status, exit_code}} ->
        output = acc_data |> Enum.reverse() |> IO.iodata_to_binary()
        safe_close_port(port)
        {:ok, output, exit_code}

      {^port, :eof} ->
        output = acc_data |> Enum.reverse() |> IO.iodata_to_binary()
        safe_close_port(port)
        {:ok, output, 0}
    after
      timeout ->
        safe_close_port(port)
        {:error, :timeout}
    end
  end

  defp safe_close_port(port) do
    try do
      Port.close(port)
    rescue
      _ -> :ok
    end
  end
end
