defmodule Kodo.Case do
  @moduledoc """
  Centralized test case template providing isolated test environments.

  Each test gets its own Instance, Session, and CommandRegistry to ensure
  proper isolation and enable async test execution.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import Kodo.Case
    end
  end

  setup _tags do
    instance = unique_atom("instance")
    ensure_instance_manager_started()
    ensure_job_manager_started()

    {:ok, _pid} = Kodo.InstanceManager.start(instance)

    # Each test gets its own CommandRegistry for isolation
    cmd_reg_name = unique_atom("cmd_reg")
    {:ok, _} = start_supervised({Kodo.Core.Commands.CommandRegistry, name: cmd_reg_name})

    {:ok, session_id, session_pid} = Kodo.Instance.new_session(instance)

    on_exit(fn ->
      GenServer.stop(session_pid, :normal)
      Kodo.InstanceManager.stop(instance)
    end)

    {:ok,
     instance: instance,
     session_pid: session_pid,
     session_id: session_id,
     command_registry: cmd_reg_name,
     job_manager: Kodo.Core.Jobs.JobManager}
  end

  @doc "Generate unique atom names for test isolation"
  def unique_atom(prefix) do
    String.to_atom("#{prefix}_#{System.unique_integer([:positive, :monotonic])}")
  end

  @doc "Ensure InstanceManager is running (start if needed)"
  def ensure_instance_manager_started do
    case GenServer.whereis(Kodo.InstanceManager) do
      nil -> {:ok, _} = Kodo.InstanceManager.start_link([])
      _ -> :ok
    end
  end

  @doc "Ensure JobManager is running (start if needed)"
  def ensure_job_manager_started do
    case GenServer.whereis(Kodo.Core.Jobs.JobManager) do
      nil -> {:ok, _} = Kodo.Core.Jobs.JobManager.start_link([])
      _ -> :ok
    end
  end

  @doc "Register common built-in commands for testing"
  def register_basic_commands(registry) do
    for mod <- [
          Kodo.Commands.Help,
          Kodo.Commands.Cd,
          Kodo.Commands.Pwd,
          Kodo.Commands.Ls,
          Kodo.Commands.Env,
          Kodo.Commands.Jobs,
          Kodo.Commands.Fg,
          Kodo.Commands.Bg,
          Kodo.Commands.Kill,
          Kodo.Commands.Sleep
        ] do
      Kodo.Core.Commands.CommandRegistry.register_command(registry, mod)
    end
  end

  @doc "Create unique temporary directory for file system tests"
  def tmp_dir! do
    path = Path.join(System.tmp_dir!(), "kodo_tests/#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end

  @doc "Wait for process to terminate properly (replaces Process.sleep)"
  def wait_for_termination(pid, timeout \\ 1000) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc "Execute command in session and return result"
  def exec_command(session_pid, command_string) do
    Kodo.Execute.execute_command(command_string, session_pid)
  end

  @doc "Setup session with basic commands registered"
  def setup_session_with_commands(context) do
    register_basic_commands(context.command_registry)
    context
  end
end
