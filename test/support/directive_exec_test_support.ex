defmodule Jido.AI.TestSupport.DirectiveExec do
  @moduledoc false

  import ExUnit.Assertions

  @spec start_task_supervisor!() :: pid()
  def start_task_supervisor! do
    {:ok, supervisor} = Task.Supervisor.start_link()
    supervisor
  end

  @spec stop_task_supervisor(pid()) :: :ok
  def stop_task_supervisor(supervisor) when is_pid(supervisor) do
    _ = GenServer.stop(supervisor, :normal)
    :ok
  catch
    :exit, _ -> :ok
  end

  @spec state_with_supervisor(pid(), map()) :: map()
  def state_with_supervisor(supervisor, extra \\ %{}) when is_pid(supervisor) and is_map(extra) do
    Map.merge(%{task_supervisor: supervisor}, extra)
  end

  @spec assert_signal_cast(String.t(), timeout()) :: Jido.Signal.t()
  def assert_signal_cast(type, timeout \\ 1_000) when is_binary(type) do
    assert_receive {:"$gen_cast", {:signal, %Jido.Signal{type: ^type} = signal}}, timeout
    signal
  end
end
